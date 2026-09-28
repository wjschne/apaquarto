-- Two things Word gets wrong about a .docx table of contents, and the lists
-- of figures and tables that go with it.
--
-- Word builds a TOC from a field: pandoc writes TOC \o "1-3" \h \z \u with
-- nothing cached inside it and the field marked dirty, so Word has to run the
-- field before the table shows anything at all. That is the prompt a reader
-- meets on opening the file. The field itself is pandoc's and is written after
-- every filter has run, so nothing here can reach it -- see the note in
-- _extension.yml. What is written here instead is a list of its own: each
-- entry is a link to the float it names, and carries a PAGEREF field for the
-- page it is on, which is what Word writes for its own table of figures. The
-- entry itself is there whether or not the field is ever run, so the list
-- reads even in a viewer that leaves fields alone.
--
-- The other thing is the TOC field's reach. apaquarto gives four headings of
-- its own the Heading 1 style -- the title, the author note, the abstract and
-- the impact statement -- and all four were listed in the table of contents,
-- along with any heading the writer marks {.unlisted}.
--
-- An outline level of 9 on such a paragraph is not enough, which Word settles
-- plainly: TOC \o builds from the built-in heading styles, so a Heading 1
-- paragraph is collected whatever outline level is set on it. The style has
-- to be one Word does not know, so these headings take apaquarto's own
-- ApaUnlistedHeading styles, which the reference document bases on the real
-- headings -- the same look, and a writer's own changes to Heading 1 follow
-- through -- and which carry the outline level of body text, which keeps them
-- out of \u as well.
--
-- The figure and table titles were listed too, for the same reason from the
-- other end: the FigureTitle style carried outline level 1. It carries body
-- text now, which is what the title of a float is.
--
-- Pandoc offers no way to ask for any of this on a header it writes itself,
-- and a custom-style div around one does not reach it, so the paragraph is
-- written here as word markup.

if FORMAT ~= "docx" then
  return
end

local utilsapa = require("utilsapa")

local figureword = "Figure"
local tableword = "Table"

-- toccolor, as six hex digits, or nil for the colour of the body text.
--
-- A run in these lists carries no character style -- pandoc's Hyperlink
-- style is never applied to markup written here -- so there is nothing to
-- colour but the run itself, and the colour goes straight into its rPr.
-- The entries take it and the heading above them does not, which is what
-- the other formats do: toccolor is the colour of a link in the list.
local kEntryColour = nil

-- How many levels of heading the contents lists, which is quarto's toc-depth.
local kTocDepth = 3

local function read_meta(meta)
  if meta.language then
    if meta.language["crossref-fig-title"] then
      figureword = utilsapa.stringify(meta.language["crossref-fig-title"])
    end
    if meta.language["crossref-tbl-title"] then
      tableword = utilsapa.stringify(meta.language["crossref-tbl-title"])
    end
  end
  kEntryColour = utilsapa.colour_hex(meta["toccolor"])
  kTocDepth = utilsapa.toc_depth(meta, 3)
end

local function xml_escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Inlines as word runs. A heading carries little more than words and the odd
-- bold or italic, and anything else is written as the text it stringifies to.
local function runs(inlines, bold, italic, colour)
  local out = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local properties = {}
      if bold then properties[#properties + 1] = "<w:b/>" end
      if italic then properties[#properties + 1] = "<w:i/>" end
      if colour then
        properties[#properties + 1] = [[<w:color w:val="]] .. colour .. [["/>]]
      end
      local rpr = ""
      if #properties > 0 then
        rpr = "<w:rPr>" .. table.concat(properties) .. "</w:rPr>"
      end
      out[#out + 1] = "<w:r>" .. rpr .. [[<w:t xml:space="preserve">]]
        .. xml_escape(inline.text) .. "</w:t></w:r>"
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      out[#out + 1] = [[<w:r><w:t xml:space="preserve"> </w:t></w:r>]]
    elseif inline.t == "Strong" then
      out[#out + 1] = runs(inline.content, true, italic, colour)
    elseif inline.t == "Emph" then
      out[#out + 1] = runs(inline.content, bold, true, colour)
    elseif inline.content then
      out[#out + 1] = runs(inline.content, bold, italic, colour)
    else
      out[#out + 1] = "<w:r>" .. [[<w:t xml:space="preserve">]]
        .. xml_escape(pandoc.utils.stringify(inline)) .. "</w:t></w:r>"
    end
  end
  return table.concat(out)
end

-- The name pandoc gives a heading's bookmark, which is not always the
-- identifier. Word will not take a bookmark name longer than 40 characters,
-- so pandoc hashes a longer identifier and writes the sha1 with its first
-- character replaced by an X. A link here has to ask for the same name or it
-- points at nothing: the heading "Tables and Figures Spanning Two Columns in
-- Journal Mode" is 55 characters as an identifier, and every entry for it led
-- nowhere until this.
local function bookmark_name(identifier)
  if #identifier <= 40 then return identifier end
  return "X" .. pandoc.utils.sha1(identifier):sub(2)
end

-- Bookmark ids of our own, well clear of the ones pandoc hands out.
local bookmark = 90000

-- A heading the table of contents passes over: apaquarto's own heading style,
-- which looks like the real one and is not a heading as far as Word's field
-- is concerned.
local function unlisted_heading(header)
  local level = header.level
  if level < 1 then level = 1 end
  if level > 9 then level = 9 end

  local before, after = "", ""
  if header.identifier ~= "" then
    bookmark = bookmark + 1
    before = [[<w:bookmarkStart w:id="]] .. bookmark .. [[" w:name="]]
      .. xml_escape(bookmark_name(header.identifier)) .. [["/>]]
    after = [[<w:bookmarkEnd w:id="]] .. bookmark .. [["/>]]
  end

  return pandoc.RawBlock("openxml", before ..
    "<w:p><w:pPr><w:pStyle w:val=\"ApaUnlistedHeading" .. level .. "\"/></w:pPr>" ..
    runs(header.content, false, false) .. "</w:p>" .. after)
end

-- Every figure and table in the document, in the order they appear, as the
-- number apacaption.lua gave them, the caption that followed it and the
-- identifier a reader can be sent to.
--
-- A float inside a float is not descended into: the panels of a multipanel
-- figure are floats in their own right and carry labels of their own, and a
-- list of figures wants the figure, not each of its panels.
local function float_entry(div)
  local title, caption
  div:walk {
    Div = function(d)
      if d.classes:includes("FigureTitle") and not title then
        title = pandoc.utils.stringify(d)
      elseif d.classes:includes("Caption") and not caption then
        caption = d.content[1] and d.content[1].content or pandoc.Inlines({})
      end
    end
  }
  if not title then return nil end
  return { title = title, caption = caption, id = div.identifier }
end

local function scan(blocks, figures, tables)
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      local id = block.identifier
      if id:match("^fig%-") or id:match("^tbl%-") then
        local entry = float_entry(block)
        if entry then
          if id:match("^tbl%-") then tables:insert(entry) else figures:insert(entry) end
        end
      else
        scan(block.content, figures, tables)
      end
    elseif block.t == "BlockQuote" then
      scan(block.content, figures, tables)
    end
  end
end

local function collect_floats(blocks)
  local figures, tables = pandoc.List({}), pandoc.List({})
  scan(blocks, figures, tables)
  return figures, tables
end

-- A right tab with a dotted leader, at the width of the text block, so that
-- the page number sits against the right margin. Letter paper with the inch
-- margins apaquarto asks for is 6.5in, or 9360 twentieths of a point, and
-- that is the fallback; the real width is read from the reference document,
-- since a tab stop beyond the margin puts the number on a line of its own
-- and looks for all the world like a field that has not been updated.
--
-- Read after docxreferencedoc.lua has run, which is where papersize reaches
-- the reference document.
local kTabPosition = 9360

local function measure_text_width()
  local refdoc = PANDOC_WRITER_OPTIONS.reference_doc
  if not refdoc then return end
  local f = io.open(refdoc, "rb")
  if not f then return end
  local data = f:read("a")
  f:close()
  local ok, archive = pcall(pandoc.zip.Archive, data)
  if not ok then return end
  for _, entry in ipairs(archive.entries) do
    if entry.path == "word/document.xml" then
      local xml = entry:contents()
      local width = tonumber(xml:match('<w:pgSz[^>]-w:w="(%d+)"'))
      local left = tonumber(xml:match('<w:pgMar[^>]-w:left="(%d+)"'))
      local right = tonumber(xml:match('<w:pgMar[^>]-w:right="(%d+)"'))
      if width and left and right then
        local measure = width - left - right
        if measure > 0 then kTabPosition = measure end
      end
      return
    end
  end
end

-- One line of the list: what the float is called, a leader, and the page it
-- is on.
--
-- The page number has to be a field. Nothing else in the file knows where
-- Word will break the pages, and PAGEREF is what Word writes for its own
-- table of figures. Nothing is cached inside it: a number cached here would
-- be a guess, and a wrong page number is worse than none.
--
-- The field is not marked dirty, and that is deliberate. Word updates a
-- dirty field while it is loading the document, before it has laid the pages
-- out, so every PAGEREF answers 1 -- and the 1 then stays, because the field
-- is no longer dirty. Marking them dirty bought a prompt on opening and a
-- column of 1s. Left alone, the entry and its link are there from the start
-- and the numbers arrive the moment anything makes Word paginate and update:
-- select all and press F9, or print, or export to pdf.
--
-- Checked in Word on example.qmd, all 35 of them: dirty gives 1 1 1 1 1 on
-- opening, and so does updateFields in settings.xml; without it they are
-- empty, and after a repagination and an update they are 8 8 8 9 9.
local function entry_paragraph(entry)
  local body = runs(pandoc.Inlines({ pandoc.Str(entry.title) }), false, false, kEntryColour)
  if entry.caption and #entry.caption > 0 then
    body = body
      .. runs(pandoc.Inlines({ pandoc.Str("."), pandoc.Space() }), false, false, kEntryColour)
      .. runs(entry.caption, false, false, kEntryColour)
  end

  local id = entry.id or ""
  if id == "" then
    return pandoc.RawBlock("openxml", "<w:p>" .. body .. "</w:p>")
  end

  local anchor = xml_escape(bookmark_name(id))
  return pandoc.RawBlock("openxml", table.concat({
    "<w:p><w:pPr><w:tabs>",
    [[<w:tab w:val="right" w:leader="dot" w:pos="]] .. kTabPosition .. [["/>]],
    "</w:tabs></w:pPr>",
    [[<w:hyperlink w:anchor="]] .. anchor .. [[">]], body, "</w:hyperlink>",
    "<w:r><w:tab/></w:r>",
    [[<w:r><w:fldChar w:fldCharType="begin"/></w:r>]],
    [[<w:r><w:instrText xml:space="preserve"> PAGEREF ]] .. anchor
      .. [[ \h </w:instrText></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="separate"/></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="end"/></w:r>]],
    "</w:p>",
  }))
end

-- The headings the contents should carry: everything down to level three
-- that is not one of the headings marked unlisted. Collected here rather than
-- left to Word's own field, which takes the built-in heading styles and so
-- takes the title page, the author note and the rest along with them.
local function collect_headings(blocks)
  local out = pandoc.List({})
  pandoc.Blocks(blocks):walk {
    Header = function(h)
      if h.level > kTocDepth then return nil end
      if h.classes:includes("unlisted") then return nil end
      out:insert({ level = h.level, content = h.content, id = h.identifier })
    end
  }
  return out
end

-- One line of the contents: the heading, indented by its level, a leader, and
-- the page. The same shape as a line of the list of figures, and for the same
-- reason -- the page number is a field, since nothing here knows where Word
-- will break the pages.
local function heading_paragraph(entry)
  local indent = (entry.level - 1) * 360      -- quarter of an inch a level
  local properties = "<w:tabs>"
    .. [[<w:tab w:val="right" w:leader="dot" w:pos="]] .. kTabPosition .. [["/>]]
    .. "</w:tabs>"
  if indent > 0 then
    properties = [[<w:ind w:left="]] .. indent .. [["/>]] .. properties
  end

  local body = runs(entry.content, false, false, kEntryColour)
  local id = entry.id or ""
  if id == "" then
    return pandoc.RawBlock("openxml",
      "<w:p><w:pPr>" .. properties .. "</w:pPr>" .. body .. "</w:p>")
  end

  local anchor = xml_escape(bookmark_name(id))
  return pandoc.RawBlock("openxml", table.concat({
    "<w:p><w:pPr>", properties, "</w:pPr>",
    [[<w:hyperlink w:anchor="]] .. anchor .. [[">]], body, "</w:hyperlink>",
    "<w:r><w:tab/></w:r>",
    [[<w:r><w:fldChar w:fldCharType="begin"/></w:r>]],
    [[<w:r><w:instrText xml:space="preserve"> PAGEREF ]] .. anchor
      .. [[ \h </w:instrText></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="separate"/></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="end"/></w:r>]],
    "</w:p>",
  }))
end

local function build_contents(headings)
  local out = pandoc.List({})
  out:insert(unlisted_heading(
    pandoc.Header(1, pandoc.Inlines({ pandoc.Str("Table of Contents") }),
      pandoc.Attr("", { "unlisted" }))))
  for _, entry in ipairs(headings) do
    out:insert(heading_paragraph(entry))
  end
  return out
end

-- Each list stands on a page of its own and the body starts on the page
-- after the last of them, which is how typst sets them: there, every outline
-- is followed by a #pagebreak(). The break goes after each list rather than
-- before it, so that the one the front matter already leaves after the
-- supplemental materials is the one that opens the first list, and no blank
-- page falls between them.
local function page_break()
  return pandoc.RawBlock("openxml",
    [[<w:p><w:r><w:br w:type="page"/></w:r></w:p>]])
end

-- The list: a heading Word will not collect, then one line for each float.
local function build_list(title, entries)
  local out = pandoc.List({})
  out:insert(unlisted_heading(
    pandoc.Header(1, pandoc.Inlines({ pandoc.Str(title) }), pandoc.Attr("", { "unlisted" }))))
  for _, entry in ipairs(entries) do
    out:insert(entry_paragraph(entry))
  end
  return out
end

-- Said once, after a render that carries any of the three lists. The page
-- numbers in them are fields and Word leaves a field empty until it has
-- laid the pages out, so a reader opening the file finds the entries and
-- their links but no numbers until something makes Word update them. There
-- is no way to fill them in from here -- see the note on the page number
-- above -- so the next best thing is to say so plainly at the end of the
-- render, where whoever asked for the list is looking.
-- Kept to 80 columns a line: this goes to a terminal, and a paragraph that
-- wraps where the window happens to end is harder to read than one that
-- breaks where it was written to.
local function say_how_to_update()
  quarto.log.output(
    "apaquarto: this .docx has a list of contents, figures or tables. Word\n" ..
    "fills in their page numbers only once it has paginated, so they are blank\n" ..
    "until you ask for them: open the file, select all with ctrl+a (cmd+a on a\n" ..
    "mac) and press F9. Printing or exporting to pdf does it too.")
end

return {
  { Meta = read_meta },
  {
    Pandoc = function(doc)
      measure_text_width()
      local figures, tables = collect_floats(doc.blocks)
      local headings = collect_headings(doc.blocks)

      local out = pandoc.List({})
      local listed = false
      for _, block in ipairs(doc.blocks) do
        if block.t == "Div" and block.classes:includes("list-of-contents") then
          out:extend(build_contents(headings))
          listed = true
          out:insert(page_break())
        elseif block.t == "Div" and block.classes:includes("list-of-figures") then
          out:extend(build_list("List of Figures", figures))
          listed = true
          out:insert(page_break())
        elseif block.t == "Div" and block.classes:includes("list-of-tables") then
          out:extend(build_list("List of Tables", tables))
          out:insert(page_break())
          listed = true
        elseif block.t == "Header" and block.classes:includes("unlisted") then
          out:insert(unlisted_heading(block))
        else
          out:insert(block)
        end
      end

      if listed then say_how_to_update() end

      doc.blocks = out
      return doc
    end
  }
}

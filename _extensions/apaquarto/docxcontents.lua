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

local function get_language(meta)
  if meta.language then
    if meta.language["crossref-fig-title"] then
      figureword = utilsapa.stringify(meta.language["crossref-fig-title"])
    end
    if meta.language["crossref-tbl-title"] then
      tableword = utilsapa.stringify(meta.language["crossref-tbl-title"])
    end
  end
end

local function xml_escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Inlines as word runs. A heading carries little more than words and the odd
-- bold or italic, and anything else is written as the text it stringifies to.
local function runs(inlines, bold, italic)
  local out = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local properties = {}
      if bold then properties[#properties + 1] = "<w:b/>" end
      if italic then properties[#properties + 1] = "<w:i/>" end
      local rpr = ""
      if #properties > 0 then
        rpr = "<w:rPr>" .. table.concat(properties) .. "</w:rPr>"
      end
      out[#out + 1] = "<w:r>" .. rpr .. [[<w:t xml:space="preserve">]]
        .. xml_escape(inline.text) .. "</w:t></w:r>"
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      out[#out + 1] = [[<w:r><w:t xml:space="preserve"> </w:t></w:r>]]
    elseif inline.t == "Strong" then
      out[#out + 1] = runs(inline.content, true, italic)
    elseif inline.t == "Emph" then
      out[#out + 1] = runs(inline.content, bold, true)
    elseif inline.content then
      out[#out + 1] = runs(inline.content, bold, italic)
    else
      out[#out + 1] = "<w:r>" .. [[<w:t xml:space="preserve">]]
        .. xml_escape(pandoc.utils.stringify(inline)) .. "</w:t></w:r>"
    end
  end
  return table.concat(out)
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
      .. xml_escape(header.identifier) .. [["/>]]
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

-- A right tab with a dotted leader, at the width of the text block. Letter
-- paper with the inch margins apaquarto asks for is 6.5in, which is 9360
-- twentieths of a point; another paper size shifts the dots, not the number,
-- which Word sets against the right margin either way.
local kTabPosition = 9360

-- One line of the list: what the float is called, a leader, and the page it
-- is on.
--
-- The page number has to be a field. Nothing else in the file knows where
-- Word will break the pages, and PAGEREF is what Word writes for its own
-- table of figures. It is marked dirty so that Word fills it in when the
-- document is opened, and nothing is cached inside it -- a number cached here
-- would be a guess, and a wrong page number is worse than none. A reader
-- whose Word does not run the field still sees the entry and its link; only
-- the number after the dots is missing.
local function entry_paragraph(entry)
  local body = runs(pandoc.Inlines({ pandoc.Str(entry.title) }), true, false)
  if entry.caption and #entry.caption > 0 then
    body = body
      .. runs(pandoc.Inlines({ pandoc.Str("."), pandoc.Space() }), false, false)
      .. runs(entry.caption, false, false)
  end

  local id = entry.id or ""
  if id == "" then
    return pandoc.RawBlock("openxml", "<w:p>" .. body .. "</w:p>")
  end

  local anchor = xml_escape(id)
  return pandoc.RawBlock("openxml", table.concat({
    "<w:p><w:pPr><w:tabs>",
    [[<w:tab w:val="right" w:leader="dot" w:pos="]] .. kTabPosition .. [["/>]],
    "</w:tabs></w:pPr>",
    [[<w:hyperlink w:anchor="]] .. anchor .. [[">]], body, "</w:hyperlink>",
    "<w:r><w:tab/></w:r>",
    [[<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>]],
    [[<w:r><w:instrText xml:space="preserve"> PAGEREF ]] .. anchor
      .. [[ \h </w:instrText></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="separate"/></w:r>]],
    [[<w:r><w:fldChar w:fldCharType="end"/></w:r>]],
    "</w:p>",
  }))
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

return {
  { Meta = get_language },
  {
    Pandoc = function(doc)
      local figures, tables = collect_floats(doc.blocks)

      local out = pandoc.List({})
      for _, block in ipairs(doc.blocks) do
        if block.t == "Div" and block.classes:includes("list-of-figures") then
          out:extend(build_list("List of Figures", figures))
        elseif block.t == "Div" and block.classes:includes("list-of-tables") then
          out:extend(build_list("List of Tables", tables))
        elseif block.t == "Header" and block.classes:includes("unlisted") then
          out:insert(unlisted_heading(block))
        else
          out:insert(block)
        end
      end

      doc.blocks = out
      return doc
    end
  }
}

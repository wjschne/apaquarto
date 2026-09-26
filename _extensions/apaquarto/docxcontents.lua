-- Two things Word gets wrong about a .docx table of contents, and the lists
-- of figures and tables that go with it.
--
-- Word builds a TOC from a field: pandoc writes TOC \o "1-3" \h \z \u with
-- nothing cached inside it and the field marked dirty, so Word has to run the
-- field before the table shows anything at all. That is the prompt a reader
-- meets on opening the file. The field itself is pandoc's and is written after
-- every filter has run, so nothing here can reach it -- see the note in
-- _extension.yml. What is written here instead needs no field and no update:
-- ordinary paragraphs, each a link to the float it names, which Word shows the
-- moment the document opens.
--
-- The other thing is the TOC field's reach. It collects every paragraph whose
-- outline level is 1 to 3, which is every Heading 1 to 3 in the document, and
-- apaquarto gives four of its own headings that style: the title, the author
-- note, the abstract and the impact statement. All four were listed in the
-- table of contents, none of them belong there, and a heading the writer marks
-- {.unlisted} was listed too. Such a heading is written out here as word markup
-- of its own, keeping the Heading style it had so that it looks the same, and
-- carrying an outline level of 9 -- body text -- so the field passes over it.
-- Pandoc offers no way to ask for that on a header it writes itself, and a
-- custom-style div around one does not reach it.

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

-- A heading the table of contents should pass over: the Heading style it had,
-- so that it looks the same, and the outline level of body text.
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
    "<w:p><w:pPr><w:pStyle w:val=\"Heading" .. level .. "\"/>" ..
    "<w:outlineLvl w:val=\"9\"/></w:pPr>" ..
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

-- The list itself: a heading Word will not collect, then one paragraph for
-- each entry. No field, so there is nothing for Word to update and nothing to
-- ask the reader about. Page numbers are left out rather than guessed: a
-- filter cannot know where Word will break the pages.
local function build_list(title, entries)
  local out = pandoc.List({})
  out:insert(unlisted_heading(
    pandoc.Header(1, pandoc.Inlines({ pandoc.Str(title) }), pandoc.Attr("", { "unlisted" }))))
  for _, entry in ipairs(entries) do
    local line = pandoc.Inlines({})
    line:extend({ pandoc.Strong(pandoc.Inlines({ pandoc.Str(entry.title) })) })
    if entry.caption and #entry.caption > 0 then
      line:extend({ pandoc.Str("."), pandoc.Space() })
      line:extend(entry.caption)
    end
    -- The whole entry is a link to the float, which is what a reader expects
    -- of a list like this and is the nearest thing to a page number that does
    -- not need a field.
    if entry.id and entry.id ~= "" then
      line = pandoc.Inlines({ pandoc.Link(line, "#" .. entry.id) })
    end
    out:insert(pandoc.Para(line))
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

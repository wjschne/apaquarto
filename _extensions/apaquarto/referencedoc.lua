-- The reference document a .docx is written against, read and written in one
-- place.
--
-- Pandoc reads PANDOC_WRITER_OPTIONS.reference_doc when it writes the output,
-- after every filter has run, so what apaquarto changes about a .docx's
-- fonts, page, running head and link colours it changes in that file.
-- docxreferencedoc.lua is the one filter that writes it, once a render, with
-- everything that render asks for; the others only read it.
--
-- Not a filter. Loaded with require("referencedoc").

local M = {}

-- The reference document as a zip archive, and its path; nil and a reason
-- when there is none or it cannot be read.
function M.read()
  local path = PANDOC_WRITER_OPTIONS.reference_doc
  if not path then return nil, "no reference document" end
  local f = io.open(path, "rb")
  if not f then return nil, "could not read " .. path end
  local data = f:read("a")
  f:close()
  local ok, archive = pcall(pandoc.zip.Archive, data)
  if not ok then return nil, "could not read " .. path .. " as a docx file" end
  return archive, path
end

-- The contents of one part of the reference document, such as
-- "word/document.xml", or nil.
function M.part(name)
  local archive = M.read()
  if not archive then return nil end
  for _, entry in ipairs(archive.entries) do
    if entry.path == name then return entry:contents() end
  end
  return nil
end

-- Writes the archive back over the reference document. False when the file
-- could not be written.
function M.write(archive)
  local path = PANDOC_WRITER_OPTIONS.reference_doc
  if not path then return false end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(archive:bytestring())
  f:close()
  return true
end

-- Link colours -----------------------------------------------------------
--
-- The character style each colour field gives a link, written into
-- word/styles.xml by docxreferencedoc.lua and handed to the links by
-- docxlinkcolor.lua.
M.link_styles = {
  linkcolor = "ApaLinkColor",
  urlcolor  = "ApaUrlColor",
  citecolor = "ApaCiteColor",
  filecolor = "ApaFileColor",
}

-- field -> six hex digits, for the colour fields a document names.
function M.link_colours(meta)
  local utilsapa = require("utilsapa")
  local wanted = {}
  for field, _ in pairs(M.link_styles) do
    wanted[field] = utilsapa.colour_hex(meta[field])
  end
  return wanted
end

local marker_open = "<!-- apaquarto-link-styles -->"
local marker_close = "<!-- /apaquarto-link-styles -->"

local function strip_link_styles(xml)
  return (xml:gsub("<!%-%- apaquarto%-link%-styles %-%->.-<!%-%- /apaquarto%-link%-styles %-%->", ""))
end

local function style_xml(id, hex)
  return table.concat({
    '<w:style w:type="character" w:customStyle="1" w:styleId="', id, '">',
    '<w:name w:val="', id, '"/>',
    '<w:basedOn w:val="Hyperlink"/>',
    '<w:rPr><w:color w:val="', hex, '"/></w:rPr>',
    "</w:style>",
  })
end

-- word/styles.xml with a link style for each colour asked for. The styles are
-- added between markers and the marked block is taken out again first, so a
-- document that asks for no colour leaves the file as it shipped. Each is
-- based on Hyperlink, so a writer's own changes to it still come through.
function M.patch_link_styles(xml, wanted)
  local stripped = strip_link_styles(xml)
  local added = {}
  for field, id in pairs(M.link_styles) do
    if wanted[field] then added[#added + 1] = style_xml(id, wanted[field]) end
  end
  if #added == 0 then return stripped end
  table.sort(added)
  -- At the end, where the other styles are. A w:styles element has its
  -- docDefaults and its latentStyles before any w:style, and word calls a
  -- file that puts one of them first unreadable.
  local closing = "</w:styles>"
  local first = stripped:find(closing, 1, true)
  if not first then return stripped end
  return stripped:sub(1, first - 1) .. marker_open .. table.concat(added)
    .. marker_close .. stripped:sub(first)
end

-- The dash attribution under a block quotation --------------------------
--
-- The QuoteAttribution paragraph style apaquote.lua gives an attribution:
-- Block Text, so that it keeps the quotation's indents, set against the
-- right one with no first-line indent. Written between markers, and only for
-- a document that has an attribution, so the reference document is left as
-- it shipped otherwise. A reference document with a QuoteAttribution style of
-- its own keeps that one.
local attribution_open = "<!-- apaquarto-quote-attribution -->"
local attribution_close = "<!-- /apaquarto-quote-attribution -->"

local kAttributionStyle = table.concat({
  '<w:style w:type="paragraph" w:customStyle="1" w:styleId="QuoteAttribution">',
  '<w:name w:val="QuoteAttribution"/>',
  '<w:basedOn w:val="BlockText"/>',
  '<w:pPr><w:jc w:val="right"/><w:ind w:firstLine="0"/></w:pPr>',
  "</w:style>",
})

function M.patch_attribution_style(xml, wanted)
  local stripped = xml:gsub(
    "<!%-%- apaquarto%-quote%-attribution %-%->.-<!%-%- /apaquarto%-quote%-attribution %-%->", "")
  if not wanted or stripped:find('w:styleId="QuoteAttribution"', 1, true) then
    return stripped
  end
  local first = stripped:find("</w:styles>", 1, true)
  if not first then return stripped end
  return stripped:sub(1, first - 1) .. attribution_open .. kAttributionStyle
    .. attribution_close .. stripped:sub(first)
end

return M

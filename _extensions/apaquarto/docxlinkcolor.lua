-- The colour a link takes in .docx.
--
-- Every link pandoc writes carries the reference document's Hyperlink
-- character style, and that is the only thing saying what colour it is. A
-- document that asks for linkcolor, urlcolor, citecolor or filecolor is
-- asking for four colours from one style, so four styles are written into the
-- reference document instead -- each based on Hyperlink, so a writer's own
-- changes to it still come through -- and each link is given the one that
-- suits it.
--
-- A style is only reached by a run inside the link: pandoc ignores
-- custom-style on a Link but honours it on a Span within one, where the
-- rStyle it writes takes the place of Hyperlink.
--
-- toccolor is not here. The lists of contents, figures and tables are built
-- by docxcontents.lua out of word markup of its own, whose runs carry no
-- style at all, so the colour is written straight into them there.
--
-- The styles are added to the reference document between markers and the
-- marked block is taken out again at the start of every render, so a document
-- that asks for no colour leaves the file as it shipped.

if FORMAT ~= "docx" then
  return
end

local utilsapa = require("utilsapa")

-- Which field a link's target asks for. The same reading latex makes:
-- anything with a scheme leaves the document, a citation points at the
-- bibliography quarto writes, another anchor is a cross reference or a link
-- to a heading, and what is left is a path to a file.
local function field_for(target)
  if target:match("^#ref%-") then return "citecolor" end
  if target:match("^#") then return "linkcolor" end
  if target:match("^%a[%w+.-]*:") then return "urlcolor" end
  return "filecolor"
end

local styles = {
  linkcolor = "ApaLinkColor",
  urlcolor  = "ApaUrlColor",
  citecolor = "ApaCiteColor",
  filecolor = "ApaFileColor",
}

-- field -> six hex digits, for the fields this document actually named
local wanted = {}

function Meta(meta)
  for field, _ in pairs(styles) do
    wanted[field] = utilsapa.colour_hex(meta[field])
  end
end

function Link(link)
  local field = field_for(link.target)
  if not wanted[field] then return nil end
  local span = pandoc.Span(link.content,
    pandoc.Attr("", {}, { ["custom-style"] = styles[field] }))
  link.content = pandoc.Inlines({ span })
  return link
end

-- Writing the styles into the reference document ---------------------------

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

local function patch_styles(xml)
  local stripped = strip_link_styles(xml)
  local added = {}
  for field, id in pairs(styles) do
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

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

function Pandoc(doc)
  local refdoc = PANDOC_WRITER_OPTIONS.reference_doc
  if not refdoc then return nil end

  local data = read_file(refdoc)
  if not data then return nil end
  local ok, archive = pcall(pandoc.zip.Archive, data)
  if not ok then return nil end

  local changed = false
  local entries = {}
  for _, entry in ipairs(archive.entries) do
    if entry.path == "word/styles.xml" then
      local xml = entry:contents()
      local patched = patch_styles(xml)
      if patched ~= xml then
        changed = true
        entries[#entries + 1] = pandoc.zip.Entry(entry.path, patched, entry.modtime)
      else
        entries[#entries + 1] = entry
      end
    else
      entries[#entries + 1] = entry
    end
  end
  if not changed then return nil end

  archive.entries = entries
  local f = io.open(refdoc, "wb")
  if not f then
    quarto.log.warning("Could not write reference document " .. refdoc ..
      ", so the link colours were not applied.")
    return nil
  end
  f:write(archive:bytestring())
  f:close()
  return nil
end

return {
  { Meta = Meta },
  { Link = Link, Pandoc = Pandoc },
}

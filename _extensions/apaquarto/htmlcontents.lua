-- The table of contents in .html, which list-of-contents asks for in every
-- format.
--
-- There is no field to fill in and no page to number here, so an entry is
-- the heading and a link to it, nested a level at a time. Quarto's own
-- toc: true puts a contents in the margin and leaves the body alone; this
-- one is part of the document, in the place the other formats put it, and
-- the two can be asked for together.

if FORMAT ~= "html" then
  return
end

local utilsapa = require("utilsapa")

-- Everything down to level three that is not one of the headings apaquarto
-- marks unlisted -- the title, the author note, the abstract, the impact
-- statement -- and not one the writer marked so either.
local depth = 3
-- The heading of the contents, in the document's language
local contents_title = "Table of Contents"

local function collect_headings(blocks)
  return utilsapa.contents_headings(blocks, depth)
end

-- The entries as a nested list: each heading is a link to itself, and a
-- deeper heading goes in a list inside the entry above it.
local function build(headings, index, level)
  local items = pandoc.List({})
  while index <= #headings do
    local h = headings[index]
    if h.level < level then break end
    if h.level > level then
      local nested, next_index = build(headings, index, h.level)
      if #items > 0 and #nested.content > 0 then
        items[#items]:insert(nested)
      end
      index = next_index
    else
      local label = h.content
      if h.identifier ~= "" then
        label = pandoc.Inlines({ pandoc.Link(h.content, "#" .. h.identifier) })
      end
      items:insert(pandoc.Blocks({ pandoc.Plain(label) }))
      index = index + 1
    end
  end
  return pandoc.BulletList(items), index
end

-- The heading and the list together, in a div of their own so that toccolor
-- has something to name.
local function contents_blocks(headings)
  local out = pandoc.List({})
  out:insert(pandoc.Header(1, pandoc.Inlines({ pandoc.Str(contents_title) }),
    pandoc.Attr("apaquarto-contents", { "unlisted", "unnumbered" })))
  if #headings > 0 then
    local list = build(headings, 1, headings[1].level)
    out:insert(list)
  end
  return pandoc.List({
    pandoc.Div(out, pandoc.Attr("", { "apaquarto-contents" })) })
end

function Pandoc(doc)
  depth = utilsapa.toc_depth(doc.meta, 3)
  contents_title = utilsapa.lang(doc.meta, "toc-title-document", contents_title)
  local headings = collect_headings(doc.blocks)
  local out = pandoc.List({})
  local found = false
  for _, block in ipairs(doc.blocks) do
    if block.t == "Div" and block.classes:includes("list-of-contents") then
      out:extend(contents_blocks(headings))
      found = true
    else
      out:insert(block)
    end
  end
  if not found then return nil end
  doc.blocks = out
  return doc
end

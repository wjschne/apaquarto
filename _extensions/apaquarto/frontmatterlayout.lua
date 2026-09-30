-- The shape of the front matter in the formats that lay it out for themselves:
-- a journal article in typst and in the .pdf, and a typst document.
--
-- frontmatter.lua builds the front matter once, as the same blocks for every
-- format: the title, the byline, the author note, the abstract and the rest.
-- A manuscript prints them one after another. A journal article sets the
-- title, byline and abstract across both columns and the author note at the
-- foot of the first, and a typst document runs them on as one flow. What that
-- takes is read here, for typst/formattypst.lua and for frontmatter.lua's
-- latex journal layout, so that the two read the front matter the same way
-- and differ only in the markup they wrap it in.
--
-- Loaded with require("frontmatterlayout"); a module, not a filter.

local List = require 'pandoc.List'

local M = {}

-- The class of the div frontmatter.lua hands the typst front matter over in,
-- for typst/formattypst.lua to lay out and take away.
M.kFrontMatterClass = "apa-frontmatter"

-- Whether a block is spacing the manuscript title page uses: its blank lines
-- and its page breaks, which a continuous layout drops.
--
-- The blank lines are line breaks written straight into the list of blocks.
-- Read before frontmatter.lua has returned they are the line breaks
-- themselves; read after, pandoc has put each into a Plain of its own, and
-- that is what they are here.
function M.is_spacing(block)
  if block.t == "LineBreak" or block.t == "SoftBreak" then return true end
  if block.t == "Plain" and #block.content > 0 then
    for _, inline in ipairs(block.content) do
      if inline.t ~= "LineBreak" and inline.t ~= "SoftBreak" then return false end
    end
    return true
  end
  return block.t == "RawBlock" and block.format == "typst" and
    block.text:find("#pagebreak", 1, true) ~= nil
end

-- The list markers frontmatter.lua writes (list-of-contents, list-of-figures,
-- list-of-tables), taken out of the front matter and returned beside what is
-- left. A journal article sets its lists in the body rather than in the
-- masthead, where they would be swept into one part or another of it.
function M.take_list_markers(blocks)
  local kept, lists = List:new {}, List:new {}
  for _, block in ipairs(blocks) do
    if block.t == "Div" and (block.classes:includes("list-of-contents")
        or block.classes:includes("list-of-figures")
        or block.classes:includes("list-of-tables")) then
      lists:insert(block)
    else
      kept:insert(block)
    end
  end
  return kept, lists
end

-- Journal mode: the front matter split into the parts a journal sets apart.
-- "front" is the title and authors; "narrow" is everything from the abstract
-- on -- abstract, impact statement, keywords -- set smaller and narrower;
-- "notes" is the author note, which goes to the foot of the first column; and
-- "tail" is a table of contents or list already written as raw typst, too
-- large for the masthead, which flows in the body instead.
function M.split_journal(blocks)
  local front = List:new {}
  local narrow = List:new {}
  local notes = List:new {}
  local tail = List:new {}
  local in_notes = false
  local in_narrow = false
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.identifier == "author-note" then
      -- The note sits alone at the foot of the column under a rule, the way
      -- apa7 sets it, so it needs no heading to introduce it.
      in_notes = true
      in_narrow = false
    elseif block.t == "Header" and block.identifier == "abstract" then
      -- apa7 prints no heading above the abstract in journal mode; the small
      -- narrow block is what marks it out.
      in_notes = false
      in_narrow = true
    elseif block.t == "Header" and block.identifier == "impact" then
      -- The impact statement does keep its heading. Everything from here to
      -- the author note belongs in the narrow block, including the keywords
      -- line that trails the abstract.
      in_notes = false
      in_narrow = true
      narrow:insert(block)
    elseif block.t == "Header" and block.identifier == "firstheader" then
      -- The masthead already carries the title; do not repeat it.
    elseif block.t == "RawBlock" and block.format == "typst" and
        (block.text:find("#outline", 1, true) ~= nil or
         block.text:find("#show outline", 1, true) ~= nil) then
      tail:insert(block)
    elseif M.is_spacing(block) then
      -- No manuscript spacing in journal mode.
    elseif in_notes then
      notes:insert(block)
    elseif in_narrow then
      narrow:insert(block)
    else
      front:insert(block)
    end
  end
  return front, narrow, notes, tail
end

-- The ORCID icon carries a width in millimetres, which next to the author
-- note's smaller text is taller than the text itself and opens up every line
-- it sits on. Sizing it to the cap height, about 0.8em, keeps it level with
-- the capitals beside it and leaves the line height alone. The height must be
-- written as a literal dimension, since Pandoc parses this attribute rather
-- than passing it through. Dropping the width keeps the icon square.
function M.fit_orcid(blocks)
  return pandoc.Blocks(blocks):walk {
    Image = function(img)
      if img.identifier == "orcid" then
        img.attributes.width = nil
        img.attributes.height = "0.8em"
        return img
      end
    end
  }
end

-- Whether a paragraph is an ORCID line: one holding the ORCID icon, which is
-- an image in typst and the raw \orcidlink command in latex, where
-- frontmatter.lua writes the mark rather than an svg that would need
-- converting.
local function has_orcid(block)
  local found = false
  block:walk {
    Image = function(img)
      if img.identifier == "orcid" then found = true end
    end,
    RawInline = function(ri)
      if ri.format == "latex" and ri.text:find("\\orcidlink{", 1, true) then
        found = true
      end
    end
  }
  return found
end

-- The ORCID lines of the author note, each a short name-and-link paragraph,
-- set off between open and close, which the format writes: justified they
-- stretch across the column, and indented the names fall out of line.
function M.set_off_orcid(blocks, open, close)
  local out = List:new {}
  local inside = false
  for _, block in ipairs(blocks) do
    local orcid = block.t == "Para" and has_orcid(block)
    if orcid and not inside then
      out:insert(open)
      inside = true
    elseif inside and not orcid then
      out:insert(close)
      inside = false
    end
    out:insert(block)
  end
  if inside then out:insert(close) end
  return out
end

-- The impact statement set in a box between open and close, which the format
-- writes. The statement arrives as its heading followed by one or more divs;
-- the keywords line after it is a paragraph, which closes the box.
function M.box_impact(blocks, open, close)
  local out = List:new {}
  local i = 1
  while i <= #blocks do
    local block = blocks[i]
    if block.t == "Header" and block.identifier == "impact" then
      out:insert(open)
      out:insert(block)
      i = i + 1
      while i <= #blocks and blocks[i].t == "Div" do
        out:insert(blocks[i])
        i = i + 1
      end
      out:insert(close)
    else
      out:insert(block)
      i = i + 1
    end
  end
  return out
end

return M

-- What goes in a dissertation's table of contents.
--
-- The Graduate School asks for three stretches, in this order and all at the
-- left margin:
--
--   the front matter, in capitals --- the abstract, the dedication, the
--   acknowledgments and the lists, but never the copyright page and never
--   the contents itself;
--
--   the chapters, under a column label reading CHAPTER, each with its arabic
--   number and its title in capitals, and under each chapter as many levels
--   of subheading as the writer asks for, each indented half an inch from
--   the one above it and never more than three deep;
--
--   the back matter, in capitals --- the references, and the appendices,
--   each lettered in the order it is mentioned.
--
-- This file works out what the entries are. How they are set, with their
-- leader dots and their page numbers, is each format's own business and is
-- in thesisfrontmatter.lua.

local M = {}

local utilsapa = require("utilsapa")
local stringify = utilsapa.stringify

-- Three levels of subheading is what the handbook allows, so four counting
-- the chapter itself.
M.max_depth = 4

local function upper(inlines)
  return pandoc.Inlines(inlines):walk {
    Str = function(s) return pandoc.Str(pandoc.text.upper(s.text)) end
  }
end

-- An appendix is a level-one heading that crossrefprefix.lua has marked, by
-- the apx identifier a writer gives it or by the title it wrote onto it.
local function is_appendix(header)
  if header.identifier and header.identifier:find("^apx%-") then return true end
  return header.attributes ~= nil
    and header.attributes.appendixtitle ~= nil
end

-- The references heading is the level-one heading that stands over the div
-- citeproc fills. Quarto calls that div refs, and the heading above it is
-- whatever the writer called it.
local function references_identifier(blocks)
  local last_header = nil
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level == 1 then
      last_header = block.identifier
    elseif block.t == "Div" and block.identifier == "refs" then
      return last_header
    end
  end
  return nil
end

local function listed(header)
  if header.classes:includes("unlisted") then return false end
  if header.classes:includes("title") then return false end
  return true
end

-- The entries the body asks for: the chapters and what is under them, then
-- the references and the appendices.
--
-- depth says how far down to go. One lists the chapters and nothing else,
-- which is what the handbook asks for unless a writer says otherwise; four
-- is the deepest it allows.
function M.body_entries(blocks, depth, words)
  depth = math.max(1, math.min(M.max_depth, depth or 1))
  local refs = references_identifier(blocks)

  local chapters = pandoc.List({})
  local back = pandoc.List({})
  local appendices = pandoc.List({})
  local chapter_number = 0
  local in_back = false

  for _, block in ipairs(blocks) do
    if block.t == "Header" and listed(block) then
      local identifier = block.identifier
      if identifier == "" then identifier = nil end

      if block.level == 1 and identifier ~= nil and identifier == refs then
        in_back = true
        back:insert({ kind = "entry", indent = 0,
          text = upper(block.content), target = identifier })
      elseif block.level == 1 and is_appendix(block) then
        in_back = true
        appendices:insert({ kind = "entry", indent = 0,
          letter = true, text = upper(block.content), target = identifier })
      elseif not in_back then
        if block.level == 1 and identifier == nil then
          -- A level-one heading with no identifier of its own is not a
          -- chapter. crossrefprefix.lua writes one of these over each
          -- appendix, reading "Appendix A", and listing it as a chapter put
          -- the appendices in the middle of the chapters and threw the
          -- numbering out.
          identifier = nil
        elseif block.level == 1 then
          chapter_number = chapter_number + 1
          chapters:insert({ kind = "entry", indent = 0,
            number = tostring(chapter_number) .. ".",
            text = upper(block.content), target = identifier })
        elseif block.level <= depth then
          chapters:insert({ kind = "entry", indent = block.level - 1,
            text = pandoc.Inlines(block.content), target = identifier })
        end
      end
    end
  end

  local out = pandoc.List({})
  if #chapters > 0 then
    out:insert({ kind = "label", indent = 0, text = words.chapter })
    out:extend(chapters)
  end
  out:extend(back)
  if #appendices > 0 then
    -- The heading over them, pointing at the first, and then each one
    -- lettered in the order it is mentioned.
    out:insert({ kind = "entry", indent = 0, text = words.appendices,
      target = appendices[1].target })
    for i, appendix in ipairs(appendices) do
      appendix.number = string.char(string.byte("A") + i - 1) .. "."
      appendix.letter = nil
      out:insert(appendix)
    end
  end
  return out
end

-- How deep a document asks its contents to go.
function M.depth(meta)
  local thesis = meta.thesis
  if thesis == nil or thesis["contents-depth"] == nil then return 1 end
  local written = tonumber(stringify(thesis["contents-depth"]))
  if written == nil then return 1 end
  return math.max(1, math.min(M.max_depth, math.floor(written)))
end

return M

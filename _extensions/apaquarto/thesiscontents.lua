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

M.upper = utilsapa.upper

-- An appendix is a level-one heading that crossrefprefix.lua has marked, by
-- the apx identifier a writer gives it or by the title it wrote onto it.
function M.is_appendix(header)
  if header.identifier and header.identifier:find("^apx%-") then return true end
  return header.attributes ~= nil
    and header.attributes.appendixtitle ~= nil
end

-- The references heading is the level-one heading that stands over the div
-- citeproc fills. Quarto calls that div refs, and the heading above it is
-- whatever the writer called it.
function M.references_identifier(blocks)
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

function M.listed(header)
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
  local refs = M.references_identifier(blocks)

  local chapters = pandoc.List({})
  local back = pandoc.List({})
  local appendices = pandoc.List({})
  local chapter_number = 0
  local in_back = false

  for _, block in ipairs(blocks) do
    if block.t == "Header" and M.listed(block) then
      local identifier = block.identifier
      if identifier == "" then identifier = nil end

      if block.level == 1 and identifier ~= nil and identifier == refs then
        in_back = true
        back:insert({ kind = "entry", indent = 0,
          text = M.upper(block.content), target = identifier })
      elseif block.level == 1 and M.is_appendix(block) then
        in_back = true
        appendices:insert({ kind = "entry", indent = 0,
          letter = true, text = M.upper(block.content), target = identifier })
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
            text = M.upper(block.content), target = identifier })
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
    -- The word over them, set like the CHAPTER above the chapters: a column
    -- label rather than an entry, so it carries no leader and no page. The
    -- appendices themselves follow, each lettered in the order it is
    -- mentioned.
    out:insert({ kind = "label", indent = 0, text = words.appendices })
    for i, appendix in ipairs(appendices) do
      appendix.number = string.char(string.byte("A") + i - 1) .. "."
      appendix.letter = nil
      out:insert(appendix)
    end
  end
  return out
end

-- What each level-one heading of the body is, and for a chapter what number
-- it carries.
--
-- A dissertation's body is a run of major divisions, and the handbook says
-- each of them begins a page of its own: every chapter, the sources section,
-- and every appendix. What they are is worked out once here, so that the
-- CHAPTER written over a heading, the number beside it in the contents and
-- the page it begins on cannot disagree with one another.
--
--   chapter        a heading that is none of the others, and is numbered
--   references     the heading over the div citeproc fills
--   appendix       a heading a writer gave an apx identifier
--   appendixlabel  the "Appendix A" crossrefprefix.lua writes over one
--
-- The first division is not given a break: the front matter has just ended a
-- page, and a second break would leave a blank one between them.
function M.divisions(blocks)
  local refs = M.references_identifier(blocks)
  local out = {}
  local number = 0
  local in_back = false
  local previous = nil
  local first = true

  for index, block in ipairs(blocks) do
    if block.t == "Header" and block.level == 1 and M.listed(block) then
      local identifier = block.identifier
      if identifier == "" then identifier = nil end

      local kind
      if identifier ~= nil and identifier == refs then
        kind, in_back = "references", true
      elseif M.is_appendix(block) then
        kind, in_back = "appendix", true
      elseif identifier == nil then
        kind = "appendixlabel"
      elseif not in_back then
        kind = "chapter"
        number = number + 1
      else
        kind = "other"
      end

      -- Every major division opens a page. An appendix that the label above
      -- it already opened one for does not open a second.
      local opens = kind == "chapter" or kind == "references"
        or kind == "appendixlabel"
        or (kind == "appendix" and previous ~= "appendixlabel")

      -- apafloatstoend.lua writes the break before an appendix, in every
      -- format that has pages, so this one does not: a second would leave a
      -- blank page before each of them.
      local mine = kind ~= "appendix" and kind ~= "appendixlabel"

      out[index] = {
        kind = kind,
        number = kind == "chapter" and number or nil,
        page = opens and not first,
        others_break = not mine,
      }
      if opens then first = false end
      previous = kind
    end
  end
  return out
end

-- Where thesisfloats.lua leaves what it noted down.
M.field = "apathesis-floats"

-- The floats thesisfloats.lua noted down while they could still be read,
-- grouped by what they are called: Table, Figure, and whatever else the
-- document declared for itself.
--
-- The order the kinds come back in is the order a dissertation lists them:
-- tables first, then figures, then the rest as they were declared.
function M.float_kinds(meta)
  local noted = meta[M.field]
  local kinds, order = {}, pandoc.List({})
  if noted == nil then return order, kinds end

  for _, float in ipairs(noted) do
    local kind = stringify(float.kind)
    if kinds[kind] == nil then
      kinds[kind] = pandoc.List({})
      order:insert(kind)
    end
    kinds[kind]:insert({
      kind = "entry",
      indent = 0,
      number = stringify(float.number) ~= ""
        and (stringify(float.number) .. ".") or nil,
      text = pandoc.Inlines(float.caption or {}),
      target = stringify(float.id),
    })
  end

  -- Tables, then figures, then whatever else in the order it was first
  -- seen. The order a kind was seen in is kept so that the sort settles the
  -- same way every time: lua's own is not a stable one.
  local seen = {}
  for index, kind in ipairs(order) do seen[kind] = index end
  table.sort(order, function(a, b)
    local rank = { Table = 1, Figure = 2 }
    local ra, rb = rank[a] or 3, rank[b] or 3
    if ra ~= rb then return ra < rb end
    return seen[a] < seen[b]
  end)
  return order, kinds
end

-- How deep a dissertation's contents goes, which is quarto's toc-depth like
-- every other contents apaquarto builds. Three levels of subheading is as
-- deep as the handbook allows, so four counting the chapter, and that is
-- where this stops whatever is asked for.
function M.depth(meta)
  return math.min(M.max_depth, utilsapa.toc_depth(meta, 3))
end

return M

-- Make apa-twocolumn figures and tables span both page columns in Typst
-- journal mode. This runs after notes are attached, so the note can be placed
-- in the same full-width wrapper as the float.

if FORMAT ~= "typst" then
  return
end

local stringify = pandoc.utils.stringify

local function attributes(el)
  local ok, attrs = pcall(function() return el.attributes end)
  if ok and attrs then
    return attrs
  end

  ok, attrs = pcall(function()
    if el.attr then
      return el.attr.attributes
    end
  end)
  if ok then
    return attrs
  end
end

local function is_journal_mode(meta)
  return meta.documentmode and stringify(meta.documentmode) == "jou"
end

local function attr_true(el, name)
  local attrs = attributes(el)
  if not (attrs and attrs[name]) then
    return false
  end

  local value = attrs[name]
  local normalized = stringify(value):lower():gsub("[^%a]", "")
  return value == true or tostring(value) == "true" or normalized == "true"
end

local function marker_id(block)
  if block.t == "RawBlock" and block.format == "typst" then
    return block.text:match("^// apaquarto%-wide%-float:([%w%-%_%.:]+)%s*$")
  end
end

local function wants_two_columns(block)
  if attr_true(block, "apa-twocolumn") then
    return true
  end

  local found = false
  block:walk {
    Div = function(el)
      if attr_true(el, "apa-twocolumn") then
        found = true
      end
    end,
    Figure = function(el)
      if attr_true(el, "apa-twocolumn") then
        found = true
      end
    end,
    Image = function(el)
      if attr_true(el, "apa-twocolumn") then
        found = true
      end
    end,
    Table = function(el)
      if attr_true(el, "apa-twocolumn") then
        found = true
      end
    end,
  }

  return found
end

local function is_figure_note(block)
  if block.t ~= "Div" then
    return false
  end

  local found = block.classes and block.classes:includes("FigureNote")
  block:walk {
    Div = function(div)
      if div.classes and div.classes:includes("FigureNote") then
        found = true
      end
    end,
  }

  return found
end

function Pandoc(doc)
  if not is_journal_mode(doc.meta) then
    return doc
  end

  local blocks = pandoc.List()
  local pending_marker = nil
  local i = 1
  while i <= #doc.blocks do
    local block = doc.blocks[i]
    local marked_id = marker_id(block)

    if marked_id then
      pending_marker = marked_id
    elseif pending_marker or wants_two_columns(block) then
      blocks:insert(pandoc.RawBlock("typst", '#place(top, scope: "parent", float: true, clearance: 1.5em)['))
      blocks:insert(block)
      pending_marker = nil

      -- A figure's note is a sibling block that apanote.lua left after the
      -- float, so it has to come inside the wrapper too. A table's note is
      -- already inside the float, put there by formattypst.lua.
      if i < #doc.blocks and is_figure_note(doc.blocks[i + 1]) then
        blocks:insert(doc.blocks[i + 1])
        i = i + 1
      end

      blocks:insert(pandoc.RawBlock("typst", "]"))
    else
      blocks:insert(block)
    end

    i = i + 1
  end

  return pandoc.Pandoc(blocks, doc.meta)
end

-- Mark apa-twocolumn floats before Quarto realizes markdown tables and fenced
-- figures. The Typst post-render wrapper consumes the marker after the float
-- has become ordinary rendered Typst blocks.

if FORMAT ~= "typst" then
  return
end

local utilsapa = require("utilsapa")

-- Wide spanning only exists in the two-column journal layout, so only the jou
-- mode needs these markers. Gating here keeps marker comments out of the Typst
-- generated for the one-column modes (man/doc/stu).
local function is_journal_mode(meta)
  return utilsapa.mode(meta) == "jou"
end

local function identifier(el)
  local ok, id = pcall(function() return el.identifier end)
  if ok and id then
    return id
  end

  ok, id = pcall(function()
    if el.attr then
      return el.attr.identifier
    end
  end)
  if ok then
    return id
  end
end

local function attr_true(el)
  return utilsapa.attr_true(el, "apa-twocolumn")
end

local function marker(id)
  return pandoc.RawBlock("typst", "// apaquarto-wide-float:" .. id)
end

local function marked_id(block)
  local block_id = identifier(block)
  if block.t ~= "CodeBlock" and attr_true(block) and block_id and block_id ~= "" then
    return block_id
  end

  local id = nil

  block:walk {
    Div = function(el)
      local el_id = identifier(el)
      if not id and attr_true(el) and el_id and el_id ~= "" then
        id = el_id
      end
    end,
    Figure = function(el)
      local el_id = identifier(el)
      if not id and attr_true(el) and el_id and el_id ~= "" then
        id = el_id
      end
    end,
    Image = function(el)
      local el_id = identifier(el)
      if not id and attr_true(el) and el_id and el_id ~= "" then
        id = el_id
      end
    end,
    Table = function(el)
      local el_id = identifier(el)
      if not id and attr_true(el) and el_id and el_id ~= "" then
        id = el_id
      end
    end,
  }

  return id
end

function Pandoc(doc)
  if not is_journal_mode(doc.meta) then
    return doc
  end

  local blocks = pandoc.List()

  for _, block in ipairs(doc.blocks) do
    local id = marked_id(block)
    if id then
      blocks:insert(marker(id))
    end
    blocks:insert(block)
  end

  return pandoc.Pandoc(blocks, doc.meta)
end

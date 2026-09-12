local beginapanote = "Note"
local utilsapa = require("utilsapa")

local function getnote(m)
  if m.language and m.language["figure-table-note"] then
    beginapanote = pandoc.utils.stringify(m.language["figure-table-note"])
  end
end

-- The grid the float is asking for, as a list of rows of relative cell
-- widths. layout-ncol and layout-nrow are spelled out into such a list;
-- an explicit layout is taken as given, a flat one read as a single row.
-- Returns nil when the float asks for no grid at all, in which case quarto
-- stacks the sub-figures at full width and a note needs no help.
local function layout_rows(float, ncells)
  local explicit = float.attributes["layout"]
  if explicit then
    local ok, decoded = pcall(quarto.json.decode, explicit)
    if not ok or type(decoded) ~= "table" or #decoded == 0 then
      return nil
    end
    if type(decoded[1]) ~= "table" then
      decoded = { decoded }
    end
    -- Quarto keeps laying cells out past the end of a short matrix by
    -- repeating its last row; do the same, so the count below is right.
    local counted = 0
    for _, row in ipairs(decoded) do counted = counted + #row end
    local last = decoded[#decoded]
    while counted < ncells and #last > 0 do
      local copy = {}
      for i, w in ipairs(last) do copy[i] = w end
      decoded[#decoded + 1] = copy
      counted = counted + #copy
    end
    return decoded
  end

  local ncol = tonumber(float.attributes["layout-ncol"])
  if not ncol then
    local nrow = tonumber(float.attributes["layout-nrow"])
    if nrow and nrow > 0 then
      ncol = math.ceil(ncells / nrow)
    end
  end
  if not ncol or ncol < 1 then
    return nil
  end

  local rows = {}
  local placed = 0
  while placed < ncells do
    local row = {}
    for _ = 1, ncol do row[#row + 1] = 1 end
    rows[#rows + 1] = row
    placed = placed + ncol
  end
  return rows
end

local function rows_to_attribute(rows)
  local out = {}
  for _, row in ipairs(rows) do
    local cells = {}
    for _, w in ipairs(row) do
      cells[#cells + 1] = string.format("%.10g", w)
    end
    out[#out + 1] = "[" .. table.concat(cells, ",") .. "]"
  end
  return "[" .. table.concat(out, ",") .. "]"
end

-- A note that belongs to the whole figure becomes one more cell of the
-- layout, and a cell is only as wide as its row allows: in a two column
-- figure the note would wrap inside half the width. Give it a row of its own
-- instead. The grid the float asked for is written out as an explicit layout
-- with a full-width row added at the end, and a row the sub-figures leave
-- half empty is padded with a blank cell, so every panel keeps the width it
-- had.
local function note_gets_its_own_row(float)
  -- Quarto's latex and html writers lay a float out from an explicit layout
  -- matrix. Its typst writer reads layout-ncol and falls back to a single
  -- column for anything it is given as a matrix, and its docx writer has
  -- not been checked, so those keep the grid they asked for and the note
  -- keeps the column width it had.
  if not (FORMAT == "latex" or FORMAT == "html") then
    return
  end

  local npanels = #float.content
  local rows = layout_rows(float, npanels)
  if not rows then
    return
  end

  local slots = 0
  for _, row in ipairs(rows) do slots = slots + #row end
  for _ = npanels + 1, slots do
    float.content:insert(pandoc.Div({}))
  end

  rows[#rows + 1] = { 1 }
  float.attributes["layout"] = rows_to_attribute(rows)
  float.attributes["layout-ncol"] = nil
  float.attributes["layout-nrow"] = nil
end

local mynote = function(float)
    if float.attributes["disable-apaquarto-processing"] then
    if not (float.attributes["disable-apaquarto-processing"] == "false") then
      return float
    end
  end
  
  if float.attributes.hassubfigs then
    
    if float.attributes['apa-note'] then
      prefix = pandoc.Para({ pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."), pandoc.Space() })
      apanotedivs = utilsapa.make_note(float.attributes['apa-note'], prefix)

      note_gets_its_own_row(float)
      float.content:extend({ apanotedivs })

      return float
    end
  end
end

return {
  { Meta = getnote },
  { FloatRefTarget = mynote }
}
local beginapanote = "Note"
local utilsapa = require("utilsapa")

local panelword = "Panel"
local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function getnote(m)
  if m.language and m.language["figure-table-note"] then
    beginapanote = pandoc.utils.stringify(m.language["figure-table-note"])
  end
  if m.language and m.language["figure-panel"] then
    panelword = pandoc.utils.stringify(m.language["figure-panel"])
  end
end

-- APA labels the panels of a figure Panel A, Panel B, and describes them in
-- the note. Quarto labels a panel that was given a label of its own "(A)" and
-- leaves a panel without one unlabelled, so both are relabelled here.
--
-- Typst does none of this: formattypst.lua builds that layout itself and
-- labels the panels as it goes.

-- How many panels each figure has had, so that each gets the next letter.
local panelcounts = {}

local function panel_label(index)
  local letter = letters:sub(index, index)
  if letter == "" then letter = tostring(index) end
  return pandoc.Inlines({
    pandoc.Strong(pandoc.Str(panelword .. " " .. letter))
  })
end

-- The caption a panel should be given: its label, then whatever it already
-- said, on the same line.
-- A caption as inlines. Quarto hands one over as a single Block for the usual
-- one line caption, and as Blocks or Inlines elsewhere.
local function caption_inlines(caption)
  if not caption then return nil end
  local kind = pandoc.utils.type(caption)
  local inlines
  if kind == "Inlines" then
    inlines = caption
  elseif kind == "Block" then
    inlines = caption.content
  elseif kind == "Blocks" then
    local ok, converted = pcall(pandoc.utils.blocks_to_inlines, caption)
    inlines = ok and converted or nil
  end
  if not inlines or #inlines == 0 then return nil end
  return inlines
end

local function labelled_caption(label, caption)
  local inlines = label
  local existing = caption_inlines(caption)
  if existing then
    inlines:insert(pandoc.Str("."))
    inlines:insert(pandoc.Space())
    inlines:extend(existing)
  end
  return pandoc.Blocks({ pandoc.Plain(inlines) })
end

-- A panel that was given a label of its own, which quarto counts as a float.
local function label_subfloat(float)
  if FORMAT == "typst" then return nil end
  local parent = tostring(float.parent_id)
  local index = (panelcounts[parent] or 0) + 1
  panelcounts[parent] = index

  float.caption_long = labelled_caption(panel_label(index), float.caption_long)
  -- Quarto puts "(A)" in front of a panel it has an order for. The reference
  -- to the panel is numbered elsewhere and still reads Figure 1B.
  float.order = nil
  return float
end

-- The apa-note of the image a figure holds, when the figure has none of its
-- own. A panel written as `![Caption](x.png){apa-note="..."}` puts the note
-- there and nowhere else.
local function image_note(fig)
  if fig.attributes and fig.attributes["apa-note"] then
    return fig.attributes["apa-note"]
  end
  local found = nil
  fig:walk {
    Image = function(img)
      if found == nil and img.attributes and img.attributes["apa-note"] then
        found = img.attributes["apa-note"]
      end
    end
  }
  return found
end

-- A panel written as a plain code chunk, which arrives as a pandoc figure
-- inside the parent rather than as a float of its own. Quarto gives these no
-- label at all.
local function label_figures(float)
  if FORMAT == "typst" then return end
  local index = 0
  float.content = float.content:walk {
    Figure = function(fig)
      index = index + 1
      -- The caption is changed in place rather than made afresh with
      -- pandoc.Caption, which pandoc grew only in the version quarto 1.7
      -- carries; every figure already has a caption to write into, empty or
      -- not, so this works whatever pandoc is underneath.
      local long = fig.caption and fig.caption.long
      if fig.caption then
        fig.caption.long = labelled_caption(panel_label(index), long)
      else
        fig.caption = { long = labelled_caption(panel_label(index), long) }
      end

      -- A panel written as a markdown image keeps its note on the image
      -- itself, where nothing downstream looks for it: apanote.lua writes the
      -- note of a div, and a code chunk gives it one to write while a bare
      -- image does not. The note is lifted onto a div around the figure, which
      -- is the shape the rest of apaquarto already knows how to read. One
      -- block still stands for one panel, so the grid is unchanged.
      local note = image_note(fig)
      if note then
        return pandoc.Div(pandoc.Blocks({ fig }), pandoc.Attr("", {},
          { ["apa-note"] = note }))
      end
      return fig
    end
  }
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
  -- Quarto's latex, html and docx writers lay a float out from an explicit
  -- layout matrix. Its typst writer reads layout-ncol and falls back to a
  -- single column for anything it is given as a matrix, so typst keeps the
  -- grid it asked for; formattypst.lua builds that one itself anyway.
  --
  -- .docx needs the explicit matrix rather than merely tolerating it. Word has
  -- no way of putting panels side by side except a table, and quarto fills
  -- that table with as many cells as the layout asked for: under layout-ncol
  -- the note appended after the panels was a block too many and was dropped,
  -- so a figure whose panels carried labels of their own lost the note
  -- belonging to the whole figure. A figure whose panels are plain code chunks
  -- kept its note, which is why example.qmd never showed this.
  if FORMAT == "typst" then
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

-- Whether the float is laid out in panels rather than holding a single image.
--
-- crossrefprefix.lua sets hassubfigs when the panels carry labels of their own,
-- which is how a layout used to be recognised here. A layout whose panels are
-- plain code chunks, with a fig-cap but no label, never gets that mark, and its
-- note was going nowhere: the note belongs to the whole float rather than to
-- any one panel, and apanote.lua cannot write it either, because a laid-out
-- float does not reach post-render as a div for it to find. The layout
-- attributes say what hassubfigs does not, so they are read as well.
local function is_laid_out(float)
  local a = float.attributes
  if not a then return false end
  return a.hassubfigs ~= nil
    or a["layout"] ~= nil
    or a["layout-ncol"] ~= nil
    or a["layout-nrow"] ~= nil
end

local mynote = function(float)
  -- A panel of a laid-out figure, relabelled the APA way.
  if float.parent_id then
    return label_subfloat(float)
  end

    if float.attributes["disable-apaquarto-processing"] then
    if not (float.attributes["disable-apaquarto-processing"] == "false") then
      return float
    end
  end

  if is_laid_out(float) then
    label_figures(float)

    -- Typst builds no grid here. formattypst.lua writes the grid itself, so
    -- that the note can follow it at the full width and the panels can carry
    -- APA panel labels, and it writes the note along with it.
    if FORMAT == "typst" then
      return
    end

    if float.attributes['apa-note'] then
      prefix = pandoc.Para({ pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."), pandoc.Space() })
      apanotedivs = utilsapa.make_note(float.attributes['apa-note'], prefix)

      -- Say that the note has been written, so that a format which also writes
      -- notes of its own -- typst does, in formattypst.lua -- leaves this one
      -- alone rather than printing it a second time. The apa-note attribute
      -- stays where it is, since apafloat.lua reads it afterwards to tell a
      -- float that has a note from one that has none.
      --
      -- The note goes inside the float for every format. Returning it beside
      -- the float instead costs the float the caption and label quarto
      -- registered for it, in .docx as well as in typst.
      float.attributes["apa-note-written"] = "true"

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
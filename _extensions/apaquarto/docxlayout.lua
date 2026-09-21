-- Sets a multipanel figure the APA way in .docx.
--
-- Word has no way of putting things side by side except a table, so quarto
-- lays a figure of panels out as one. That leaves four things wrong for APA,
-- all of them fixed here:
--
--   * The figure's number and title are written after the table rather than
--     above it, which is where APA puts them.
--   * The table takes the reference document's Table style, whose bottom rule
--     is the one APA tables want and no figure does, so a black line is drawn
--     under every panel and under the note.
--   * The note of the whole figure ends up in a table of its own, which is
--     what gives it a rule of its own, and its paragraphs come out in Word's
--     Compact style rather than FigureNote.
--   * A panel's own note is set flush left like the figure's note, where APA
--     centres it under the panel it belongs to. This one is asked for below
--     but does not yet arrive: pandoc's docx writer gives every paragraph in a
--     table cell the Compact style and ignores the custom-style of a div
--     around it, so the SubPanelNote style never reaches the page. The request
--     is left in place for when that changes; until then a panel's note is set
--     like the rest of the cell.
--
-- This runs after apacaption.lua, which is what makes the number and title,
-- and after apaafternote.lua, so that the float is in its final shape.

if FORMAT ~= "docx" then
  return
end

-- A table style with no rules, defined in docxreferencedoc.lua. Naming a style
-- that a reference document does not define is harmless: word then draws the
-- table with no style at all, which is also without rules.
local kLayoutTableStyle = "FigureLayout"
local kPanelNoteStyle = "SubPanelNote"
local kNoteStyle = "FigureNote"

local function is_note(block)
  return block.t == "Div" and block.classes:includes("FigureNote")
end

-- Whether a table holds nothing but the note of the whole figure, which is
-- what floatwithsubfigure.lua's full width row comes to once quarto has laid
-- it out. Such a table is unwrapped: the note reads better as an ordinary
-- paragraph, and out of the table it keeps its own style and loses the rule.
local function note_only_table(block)
  if block.t ~= "Table" then return nil end
  local notes = pandoc.List({})
  local other = false
  block:walk {
    Div = function(div)
      if is_note(div) then
        notes:insert(div)
      end
    end,
    Figure = function() other = true end,
    Image = function() other = true end,
  }
  if other or #notes == 0 then return nil end
  -- The walk sees the same note twice, once for the cell's div and once for
  -- the note inside it, so only the outermost of each is kept.
  local seen = {}
  local kept = pandoc.List({})
  for _, note in ipairs(notes) do
    local text = pandoc.utils.stringify(note)
    if not seen[text] then
      seen[text] = true
      kept:insert(note)
    end
  end
  return kept
end

-- The style word gives a figure's caption. Naming it in raw ooxml below keeps
-- the caption looking as it did when pandoc was writing it.
local kCaptionStyle = "ImageCaption"

local function xml_escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Inlines as word runs. Only the marking a caption is likely to carry is
-- understood; anything else is written as its text, which is what pandoc's own
-- stringify would give.
local function runs(inlines, bold, italic)
  local out = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local properties = {}
      if bold then properties[#properties + 1] = "<w:b/>" end
      if italic then properties[#properties + 1] = "<w:i/>" end
      local rpr = ""
      if #properties > 0 then
        rpr = "<w:rPr>" .. table.concat(properties) .. "</w:rPr>"
      end
      out[#out + 1] = "<w:r>" .. rpr .. '<w:t xml:space="preserve">'
        .. xml_escape(inline.text) .. "</w:t></w:r>"
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      out[#out + 1] = '<w:r><w:t xml:space="preserve"> </w:t></w:r>'
    elseif inline.t == "Strong" then
      out[#out + 1] = runs(inline.content, true, italic)
    elseif inline.t == "Emph" then
      out[#out + 1] = runs(inline.content, bold, true)
    elseif inline.content then
      out[#out + 1] = runs(inline.content, bold, italic)
    else
      out[#out + 1] = "<w:r>" .. '<w:t xml:space="preserve">'
        .. xml_escape(pandoc.utils.stringify(inline)) .. "</w:t></w:r>"
    end
  end
  return table.concat(out)
end

local function caption_paragraph(inlines)
  return pandoc.RawBlock("openxml",
    '<w:p><w:pPr><w:pStyle w:val="' .. kCaptionStyle .. '"/></w:pPr>'
    .. runs(inlines, false, false) .. "</w:p>")
end

-- A panel's caption, moved above the panel.
--
-- Pandoc writes a figure's caption after the picture and offers no way to ask
-- for it above, which is where APA puts it and where every other format has
-- it. So the caption is taken off the figure and written out in front of it as
-- word markup of its own, naming the style pandoc would have given it. Raw
-- markup rather than a div, because pandoc gives every paragraph in a table
-- cell the Compact style and pays no attention to the custom-style of a div
-- around it.
local function captions_above(block)
  return block:walk {
    Figure = function(figure)
      local caption = figure.caption and figure.caption.long
      if not caption or #caption == 0 then return nil end
      local ok, inlines = pcall(pandoc.utils.blocks_to_inlines, caption)
      if not ok or not inlines or #inlines == 0 then return nil end
      figure.caption.long = pandoc.Blocks({})
      return { caption_paragraph(inlines), figure }
    end
  }
end

-- A panel's own note, centred under the panel rather than flush left.
local function style_panel_notes(block)
  return block:walk {
    Div = function(div)
      if is_note(div) then
        div.attributes["custom-style"] = kPanelNoteStyle
        return div
      end
    end
  }
end

-- Quarto lays the panels of a figure out as a table, a cell to each panel,
-- which is the only way word has of putting things side by side. It writes
-- one such table for the whole figure when the panels are plain code chunks,
-- and one table for each panel when every panel carries a label of its own:
-- a row of as many cells as the layout asked for, with the panel in the
-- first and the rest empty. Word then sets each table under the one before
-- it, so labelled panels came out in a column where unlabelled ones came out
-- in a row.
--
-- The tables are put back together here. Every cell that holds something is
-- taken in order and dealt out into rows the width the layout asked for,
-- which leaves a figure whose panels were already in one table exactly as it
-- was and gives the labelled figure the same shape.
local function cell_is_empty(cell)
  local blocks = pandoc.Blocks(cell.contents)
  local found = false
  blocks:walk {
    Image = function() found = true end,
    Figure = function() found = true end,
    RawBlock = function() found = true end,
  }
  if found then return false end
  return (pandoc.utils.stringify(blocks):gsub("%s", "")) == ""
end

local function merge_layout_tables(tables)
  if #tables < 2 then return tables end
  local first = tables[1]
  local ncol = #first.colspecs
  if ncol < 2 then return tables end

  local cells = pandoc.List({})
  for _, tb in ipairs(tables) do
    -- Tables of different widths are not rows of one layout, so they are
    -- left alone rather than forced together.
    if #tb.colspecs ~= ncol or #tb.bodies == 0 then return tables end
    for _, row in ipairs(tb.bodies[1].body) do
      for _, cell in ipairs(row.cells) do
        if not cell_is_empty(cell) then cells:insert(cell) end
      end
    end
  end
  if #cells < 2 then return tables end

  local rows = pandoc.List({})
  local i = 1
  while i <= #cells do
    local rowcells = pandoc.List({})
    for j = i, math.min(i + ncol - 1, #cells) do
      rowcells:insert(cells[j])
    end
    while #rowcells < ncol do
      rowcells:insert(pandoc.Cell(pandoc.Blocks({})))
    end
    rows:insert(pandoc.Row(rowcells))
    i = i + ncol
  end

  first.bodies[1].body = rows
  return pandoc.List({ first })
end

-- Two tables with nothing between them are one table to word, so quarto puts
-- an empty paragraph between the panel tables. It has to be stepped over to
-- see that the tables belong together, and it goes when they are merged: one
-- table needs no separator. Anything that would actually show on the page
-- ends the run instead.
local function is_separator(block)
  if block.t ~= "RawBlock" then return false end
  if block.format ~= "openxml" then return false end
  return not (block.text:find("<w:t", 1, true)
    or block.text:find("<w:drawing", 1, true))
end

local function merge_adjacent_tables(blocks)
  local out = pandoc.List({})
  local run = pandoc.List({})      -- the tables of the run, in order
  local buffer = pandoc.List({})   -- the run as it stands, separators and all

  local function flush()
    if #run > 1 then
      local merged = merge_layout_tables(run)
      if #merged == 1 then
        out:insert(merged[1])
        run = pandoc.List({})
        buffer = pandoc.List({})
        return
      end
    end
    -- Nothing merged, so the run is put back exactly as it came.
    for _, block in ipairs(buffer) do out:insert(block) end
    run = pandoc.List({})
    buffer = pandoc.List({})
  end

  for _, block in ipairs(blocks) do
    if block.t == "Table" and not note_only_table(block) then
      run:insert(block)
      buffer:insert(block)
    elseif is_separator(block) and #run > 0 then
      buffer:insert(block)
    else
      flush()
      out:insert(block)
    end
  end
  flush()
  return out
end

local function rebuild(float)
  local titles = pandoc.List({})
  local body = pandoc.List({})
  local notes = pandoc.List({})
  local laid_out = false

  for _, block in ipairs(merge_adjacent_tables(float.content)) do
    if block.t == "Div" and (block.classes:includes("FigureTitle")
        or block.classes:includes("Caption")) then
      titles:insert(block)
    else
      local note_table = note_only_table(block)
      if note_table then
        laid_out = true
        for _, note in ipairs(note_table) do
          note.attributes["custom-style"] = kNoteStyle
          notes:insert(note)
        end
      elseif block.t == "Table" then
        laid_out = true
        local table_block = captions_above(style_panel_notes(block))
        table_block.attr = table_block.attr or pandoc.Attr()
        table_block.attr.attributes["custom-style"] = kLayoutTableStyle
        body:insert(table_block)
      else
        body:insert(block)
      end
    end
  end

  if not laid_out then return nil end

  local out = pandoc.List({})
  out:extend(titles)
  out:extend(body)
  out:extend(notes)
  float.content = out
  return float
end

return {
  {
    Div = function(div)
      if div.classes:includes("FigureWithNote")
          or div.classes:includes("FigureWithoutNote") then
        return rebuild(div)
      end
    end
  }
}

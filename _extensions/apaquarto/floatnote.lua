-- Writes the apa-note of a float inside the float, for .html and .docx.
--
-- A float's note belongs with the float: under its content, inside it, where
-- it moves with the float when floatsintext sends the float to the end and
-- where nothing can come between the two. floatlatex.lua and
-- typst/formattypst.lua write it there for the .pdf and typst, and this does
-- the same for the other two formats, from the same reading of the float
-- (floatrecord.lua). A float laid out in panels is floatwithsubfigure.lua's,
-- which has written the note of the whole figure by the time this runs; the
-- note of each panel is written here, inside the panel, in the SubPanelNote
-- style that centres it under the panel it belongs to.
--
-- The float is marked as having its note (utilsapa.note_mark), so that
-- apanote.lua, which runs after the float has been rendered, does not write
-- it again. apanote.lua is left the notes that only it can see: those of a
-- figure brought in with {{< embed >}}, which embednote.lua recovers after
-- rendering, and those of a div that is not a float.
--
-- It runs at post-quarto, the last point at which a float can still be read
-- as a float.

if FORMAT ~= "html" and FORMAT ~= "docx" then
  return
end

local utilsapa = require("utilsapa")
local floatrecord = require("floatrecord")

local noteword = "Note"
-- The notes of markdown tables as they were written, by identifier
local tablenotes = {}

local function meta(m)
  noteword = utilsapa.lang(m, "figure-table-note", noteword)
  tablenotes = utilsapa.table_notes(m)
end

-- A panel's note: a FigureNote made into a SubPanelNote, which apa.css and
-- the reference document define as FigureNote centred. APA sets the note of
-- the whole figure flush left under the figure and a panel's note centred
-- under its panel.
local function panel_note(text)
  return floatrecord.note_blocks(text, noteword):walk {
    Div = function(div)
      if not div.classes:includes("FigureNote") then return nil end
      div.classes = div.classes:map(function(class)
        if class == "FigureNote" then return "SubPanelNote" end
        return class
      end)
      div.attributes["custom-style"] = "SubPanelNote"
      return div
    end
  }
end

-- A panel given a label of its own is a float in its own right, and its note
-- goes inside it.
local function write_panel_float(float)
  if utilsapa.note_is_written(float) then return nil end
  local note = floatrecord.note_text(float, tablenotes)
  if not note then return nil end
  local content = pandoc.Blocks({})
  content:extend(floatrecord.as_blocks(float.content))
  content:insert(panel_note(note))
  float.content = content
  float.attributes[utilsapa.note_written] = utilsapa.note_mark()
  return float
end

-- A panel written as a plain code chunk, or as a markdown image, is a div
-- carrying its note (floatwithsubfigure.lua lifts an image's note onto a div
-- around it). The note goes inside that div, so that one block still stands
-- for one panel and the grid is left as it was.
local function write_panel_divs(float)
  local touched = false
  float.content = float.content:walk {
    Div = function(div)
      local note = div.attributes and div.attributes["apa-note"]
      if not note or note == "" then return nil end
      if floatrecord.float_behind(div) or utilsapa.note_is_written(div) then
        return nil
      end
      div.content:insert(panel_note(note))
      div.attributes[utilsapa.note_written] = utilsapa.note_mark()
      touched = true
      return div
    end
  }
  if touched then return float end
end

local function write_note(float)
  if float.parent_id then return write_panel_float(float) end

  -- floatwithsubfigure.lua has written the layout of a float of panels out
  -- as an explicit matrix for these two formats, so the matrix is read.
  local record = floatrecord.read(float,
    { tablenotes = tablenotes, read_matrix = true })
  if record.columns then return write_panel_divs(float) end

  -- A float this filter has been over before
  if float.attributes and float.attributes[utilsapa.note_written] then
    return nil
  end
  if not record.note then return nil end

  local content = pandoc.Blocks({})
  content:extend(record.content)
  content:insert(floatrecord.note_blocks(record.note, noteword))
  float.content = content
  float.attributes[utilsapa.note_written] = utilsapa.note_mark()
  return float
end

-- Gives a float the note of the code cell it came from, and takes it off the
-- cell.
--
-- A figure made by a code chunk carries its apa-note on the cell div quarto
-- wraps the chunk's output in, not on the float itself (a table made by a
-- chunk carries it on both). The note is copied down to the float here, in a
-- pass of its own, so that it is there by the time write_note reads it, and
-- taken off the cell, where apanote.lua would find it and write it a second
-- time. Only a cell holding one float is given this: a cell holding several
-- leaves no way to tell whose note it is, and is left for apanote.lua as
-- before. A div holding no float is never touched, whatever its note says.
local function push_cell_note(div)
  local note = div.attributes and div.attributes["apa-note"]
  if not note or note == "" then return nil end
  local floats = {}
  div.content:walk {
    Div = function(child)
      local float = floatrecord.float_behind(child)
      if float then floats[#floats + 1] = float end
    end
  }
  if #floats ~= 1 or not floats[1].attributes then return nil end
  -- A float laid out in panels has been through floatwithsubfigure.lua
  -- already, which read no note off the cell, so the cell's note is left for
  -- apanote.lua to write as before.
  if floatrecord.columns(floats[1], true) then return nil end
  local float = floats[1]
  if not float.attributes["apa-note"] then
    float.attributes["apa-note"] = note
  end
  -- The float writes the note now; the cell keeps a different note of its
  -- own, should it have one.
  if float.attributes["apa-note"] == note then
    div.attributes["apa-note"] = nil
    return div
  end
  return nil
end

return {
  { Meta = meta },
  { Div = push_cell_note },
  { FloatRefTarget = write_note },
}

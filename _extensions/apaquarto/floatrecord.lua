-- What a float is, read once for the filters that write one out.
--
-- A float reaches post-quarto as a FloatRefTarget, and each format that sets
-- it the APA way -- floatlatex.lua for the .pdf, typst/formattypst.lua for
-- typst -- has to take it apart the same way first: its caption as inlines,
-- its content as blocks, its note, and, for a figure laid out in panels, the
-- same four things for every panel. That reading is done here, so that the
-- writers differ only in what they write.
--
-- Loaded with require("floatrecord"); it is a module, not a filter, and is
-- not listed in _extension.yml.
--
--   local floatrecord = require("floatrecord")
--   local record = floatrecord.read(float, { tablenotes = notes })
--   record.caption, record.content, record.note, record.columns,
--   record.panels[i].caption, .content, .identifier, .note, .block

local utilsapa = require("utilsapa")

local M = {}

-- Inlines from a caption, which quarto hands over as a single Block for the
-- ordinary one-line caption and as Blocks or Inlines elsewhere; nil when it
-- is empty.
function M.caption_inlines(caption)
  if not caption then return nil end
  local kind = pandoc.utils.type(caption)
  local inlines
  if kind == "Inlines" then
    inlines = caption
  elseif kind == "Block" then
    if caption.content then
      inlines = caption.content
    else
      local ok, converted = pcall(pandoc.utils.blocks_to_inlines, { caption })
      inlines = ok and converted or nil
    end
  elseif kind == "Blocks" then
    local ok, converted = pcall(pandoc.utils.blocks_to_inlines, caption)
    inlines = ok and converted or nil
  end
  if not inlines or #inlines == 0 then return nil end
  return inlines
end

-- Anything a float or figure holds, as Blocks. A float holding one image has
-- a single block for its content; one holding panels has a list of them.
function M.as_blocks(content)
  if content == nil then return pandoc.Blocks({}) end
  if pandoc.utils.type(content) == "Blocks" then return content end
  return pandoc.Blocks({ content })
end

-- The float a div is standing in for. A float is a custom node, and a walk of
-- the document sees only the div carrying its id. A panel that was given a
-- label of its own arrives this way; one written as a plain code chunk arrives
-- as a pandoc figure instead, which figure_inside finds.
function M.float_behind(block)
  if block.t ~= "Div" then return nil end
  local id = block.attributes and block.attributes["__quarto_custom_id"]
  if not id then return nil end
  local ok, float = pcall(function()
    return quarto._quarto.ast.custom_node_data[tostring(id)]
  end)
  if not ok then return nil end
  return float
end

-- The first pandoc Figure inside a block, which is what a panel is once quarto
-- has laid the cell out.
function M.figure_inside(block)
  -- A panel written as a markdown image is the figure, rather than holding
  -- one, and a walk of it visits its children and never itself. Without this
  -- such a panel kept the caption typst or latex writes under a figure of its
  -- own instead of taking the caption up beside its panel label.
  if block.t == "Figure" then return block end
  local found = nil
  block:walk {
    Figure = function(fig)
      if not found then found = fig end
    end
  }
  return found
end

-- Whether a block holds the note of a whole figure: a FigureNote div, which
-- utilsapa.make_note always wraps in a div of its own.
function M.is_figure_note(block)
  local found = false
  block:walk {
    Div = function(d)
      if d.classes:includes("FigureNote") then found = true end
    end
  }
  return found
end

-- The number of columns a float of panels is asking for, or nil if it holds
-- one thing.
--
-- floatwithsubfigure.lua writes the layout of a latex float out as an explicit
-- matrix, so that the figure's note can have a row to itself, and a writer
-- that is given one reads it first (read_matrix). Typst is not: quarto's typst
-- writer drops a figure handed a matrix, so there only layout-ncol and
-- layout-nrow count.
function M.columns(float, read_matrix)
  local a = float.attributes
  if not a then return nil end
  if read_matrix and a["layout"] then
    local ok, rows = pcall(quarto.json.decode, a["layout"])
    if ok and type(rows) == "table" and #rows > 0 then
      local first = rows[1]
      if type(first) == "table" and #first > 0 then return #first end
      return #rows
    end
  end
  local ncol = tonumber(a["layout-ncol"])
  if not ncol then
    local nrow = tonumber(a["layout-nrow"])
    if nrow and nrow > 0 then
      ncol = math.ceil(#float.content / nrow)
    end
  end
  if not ncol or ncol < 1 then return nil end
  return ncol
end

-- The note text of a float: the markdown table's note as the writer typed it,
-- when there is one, and otherwise the apa-note attribute. nil when there is
-- none.
function M.note_text(float, tablenotes)
  local attributes = float.attributes or {}
  local note = (tablenotes and tablenotes[float.identifier])
    or attributes["apa-note"]
  if note == nil or note == "" then return nil end
  return note
end

-- A note's blocks, opening with the word for it in italics: "Note. ...".
function M.note_blocks(text, noteword)
  local prefix = pandoc.Para({
    pandoc.Emph(pandoc.Str(noteword)), pandoc.Str("."), pandoc.Space() })
  return utilsapa.make_note(text, prefix)
end

-- One panel of a laid-out figure: its caption, what it holds, its identifier
-- and its own note.
--
-- A panel given a label of its own is a float, and all four come from the
-- float behind the div. A panel written as a plain code chunk, or as a
-- markdown image, is a pandoc figure, and the note is on the block around it.
-- A panel written as a markdown image carries its note on the image, which is
-- where it is looked for last.
function M.panel(block)
  local p = { block = block }
  local sub = M.float_behind(block)
  if sub then
    p.caption = M.caption_inlines(sub.caption_long)
    p.content = sub.content
    p.identifier = sub.identifier
    p.note = sub.attributes and sub.attributes["apa-note"]
  else
    local figure = M.figure_inside(block)
    if figure then
      p.caption = M.caption_inlines(figure.caption and figure.caption.long)
      p.content = figure.content
      p.identifier = figure.identifier
    end
  end
  if p.note == nil or p.note == "" then
    p.note = block.attributes and block.attributes["apa-note"]
  end
  if p.note == nil or p.note == "" then
    p.note = nil
    M.as_blocks(p.content):walk {
      Image = function(img)
        if p.note == nil and img.attributes and img.attributes["apa-note"]
            and img.attributes["apa-note"] ~= "" then
          p.note = img.attributes["apa-note"]
        end
      end
    }
  end
  return p
end

-- Everything above, for one float.
--
-- options.tablenotes: the notes of markdown tables, from utilsapa.table_notes.
-- options.read_matrix: whether an explicit layout matrix counts; see columns.
function M.read(float, options)
  options = options or {}
  local record = {
    float = float,
    identifier = float.identifier,
    kind = float.type,
    caption = M.caption_inlines(float.caption_long),
    content = M.as_blocks(float.content),
    note = M.note_text(float, options.tablenotes),
    columns = M.columns(float, options.read_matrix),
  }
  if record.columns then
    record.panels = pandoc.List({})
    for _, block in ipairs(record.content) do
      record.panels:insert(M.panel(block))
    end
  end
  return record
end

return M

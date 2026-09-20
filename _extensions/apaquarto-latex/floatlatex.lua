-- Sets figures and tables the APA way, in plain LaTeX.
--
-- Quarto's latex writer builds a float itself, as a figure or table
-- environment with a \caption under it. APA wants something else: the number
-- on its own line in bold, the title under it in italics, both above the
-- figure, and the note below. So the float is taken apart here and written
-- back out in that order, using the commands apalatex.tex defines.
--
-- This is the plain latex format's counterpart to apafloatlatex.lua, which
-- does the same job for apaquarto-pdf but has to talk the apa7 class round
-- first. Here there is no class to argue with and the whole of it is the
-- handful of blocks below.
--
-- It runs at post-quarto, which is the last point at which a float is still a
-- FloatRefTarget that can be read. By post-render the writer has already made
-- its own figure out of it, which is why apanote.lua, which works on divs,
-- never sees a float in latex and why the note needs writing here.

local utilsapa = require("utilsapa")

local figureword = "Figure"
local tableword = "Table"
local noteword = "Note"
local floatsintext = true
local mode = "man"

local function meta(m)
  if m.documentmode then mode = utilsapa.stringify(m.documentmode) end
  if m.language then
    if m.language["crossref-fig-title"] then
      figureword = utilsapa.stringify(m.language["crossref-fig-title"])
    end
    if m.language["crossref-tbl-title"] then
      tableword = utilsapa.stringify(m.language["crossref-tbl-title"])
    end
    if m.language["figure-table-note"] then
      noteword = utilsapa.stringify(m.language["figure-table-note"])
    end
  end
  if m.floatsintext ~= nil then
    floatsintext = utilsapa.stringify(m.floatsintext) ~= "false"
  end
end

local function raw(text)
  return pandoc.RawBlock("latex", text)
end

-- One paragraph passing some inlines to a latex command, so that whatever
-- markup the title carries survives being wrapped. The braces are inlines
-- rather than blocks of their own, which keeps the argument on one paragraph:
-- a blank line inside a command argument is a paragraph break, and latex will
-- not have one there.
local function command(name, inlines)
  local out = pandoc.List({ pandoc.RawInline("latex", "\\" .. name .. "{") })
  out:extend(inlines)
  out:insert(pandoc.RawInline("latex", "}"))
  return pandoc.Para(out)
end

-- The float's number. apaquarto works one out that accounts for appendices
-- and leaves it as an attribute; quarto's own count stands in when it has not.
local function number(float)
  local attributes = float.attributes or {}
  local given = attributes.fignum or attributes.tblnum
  if given and given ~= "" then return tostring(given) end
  if type(float.order) == "table" and float.order.order then
    return tostring(float.order.order)
  end
  return nil
end

-- "Figure 1", or "Figure A1" in an appendix, where apaquarto leaves the letter
-- in a prefix attribute.
local function label_inlines(float)
  local word = (float.type == "Table") and tableword or figureword
  local n = number(float)
  if not n then return pandoc.Inlines({ pandoc.Str(word) }) end
  local prefix = (float.attributes or {}).prefix or ""
  return pandoc.Inlines({ pandoc.Str(word .. " " .. prefix .. n) })
end

-- The title of the float. Quarto hands this over as a single Block for the
-- ordinary one-line caption, and as Blocks or Inlines elsewhere, so all three
-- are taken.
local function caption_inlines(float)
  local caption = float.caption_long
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

-- \label on its own refers to whatever counter was last stepped, which for a
-- float written without \caption is the wrong one, and every reference to it
-- comes out as ??. The counter is set to the number the float is being given
-- and then stepped, so that the anchor a reference jumps to is the float's own.
--
-- What the reference prints is set by hand afterwards. \refstepcounter leaves
-- \@currentlabel reading the bare count, which is right for a float in the
-- body and wrong for one in an appendix: apaquarto numbers those B1, B2 and
-- begins again at each appendix, so the title above the table read "Table B1"
-- while every reference to it in the text read "Table 1". The number the
-- reader sees is written into \@currentlabel, so that the two agree.
local function label_blocks(float)
  if not float.identifier or float.identifier == "" then
    return pandoc.List({})
  end
  local counter = (float.type == "Table") and "table" or "figure"
  local out = pandoc.List({})
  local n = number(float)
  if n and n:match("^%d+$") then
    out:insert(raw("\\setcounter{" .. counter .. "}{" .. (tonumber(n) - 1) .. "}"))
  end
  local tex = "\\refstepcounter{" .. counter .. "}%\n"
  if n then
    local shown = ((float.attributes or {}).prefix or "") .. n
    tex = tex .. "\\makeatletter\\def\\@currentlabel{" .. shown
      .. "}\\makeatother%\n"
  end
  out:insert(raw(tex .. "\\label{" .. float.identifier .. "}"))
  return out
end

-- The note, as the same blocks every other format gets, so that a note reads
-- the same whichever way the document is written out.
-- Every note this filter has written, so that the div around the float can be
-- told not to write it again.
local written_notes = {}

local function note_blocks(float)
  local attributes = float.attributes or {}
  -- floatwithsubfigure.lua writes the note of a float laid out in panels, and
  -- marks the float when it has, so that it is not written twice.
  if attributes["apa-note-written"] then return nil end
  local note = attributes["apa-note"]
  if not note or note == "" then return nil end
  written_notes[note] = true
  local prefix = pandoc.Para({
    pandoc.Emph(pandoc.Str(noteword)), pandoc.Str("."), pandoc.Space() })
  return utilsapa.make_note(note, prefix)
end

-- Takes the apa-note off the cell a float came from, once the note has been
-- written into the float above.
--
-- A float made by a code chunk sits inside the cell div quarto builds for that
-- chunk, and the chunk's apa-note is set on both. This filter writes the note
-- inside the float, which is where APA wants it and where floatsintext can
-- carry it; apanote.lua, which runs later and reads divs, then found the
-- attribute still on the cell and wrote the note a second time underneath the
-- whole table. Only the note this filter has actually written is taken off, so
-- a note on a div holding no float is left for apanote.lua as before.
--
-- The float is inside the div, so it has already been through processfloat by
-- the time the div is reached.
local function clear_written_note(div)
  local note = div.attributes and div.attributes["apa-note"]
  if note and written_notes[note] then
    div.attributes["apa-note"] = nil
    return div
  end
end

-- ---------------------------------------------------------------------------
-- Figures laid out in panels
--
-- Quarto lays a float of panels out itself for its own pdf format, but what it
-- builds is a figure environment for every panel, which inside this format's
-- figure would be a figure inside a figure: latex sets those one under the
-- other whatever the layout asked for. So the row of panels is built here, out
-- of minipages, and each panel is taken down to its picture so that no second
-- figure environment is made.

local panelword = "Panel"
local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- The number of columns the float is asking for, or nil if it holds one thing.
--
-- floatwithsubfigure.lua has already been over the float and, for latex, has
-- written the layout out as an explicit matrix of rows so that the figure's
-- note can have a row to itself. So the matrix is read first and the plainer
-- layout-ncol only when there is none.
local function panel_columns(float)
  local a = float.attributes or {}
  local explicit = a["layout"]
  if explicit then
    local ok, rows = pcall(quarto.json.decode, explicit)
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

-- Whether a block is the note of the whole figure, which floatwithsubfigure.lua
-- put among the panels for the formats that lay a float out from a matrix. Here
-- the grid is built by hand, so the note is taken back out of it and set under
-- the grid at the full width.
local function is_figure_note(block)
  local found = false
  block:walk {
    Div = function(d)
      if d.classes:includes("FigureNote") then found = true end
    end
  }
  return found
end

-- Whether a block holds nothing at all, which is what the padding cell added
-- to fill out a short row comes to.
local function is_empty(block)
  return pandoc.utils.stringify(block) == "" and not is_figure_note(block)
end

-- The float a div is standing in for. A float is a custom node, and a walk of
-- the document sees only the div carrying its id. A panel that was given a
-- label of its own arrives this way; one written as a plain code chunk arrives
-- as a pandoc figure instead, which figure_inside finds.
local function float_behind(block)
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
local function figure_inside(block)
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

local function figure_caption(figure)
  local caption = figure.caption and figure.caption.long
  if not caption then return nil end
  local ok, inlines = pcall(pandoc.utils.blocks_to_inlines, caption)
  if not ok or not inlines or #inlines == 0 then return nil end
  return inlines
end

-- One panel, written out as latex.
--
-- The panel goes inside a minipage, and the minipages of a row have to follow
-- one another with nothing between them: a blank line is a paragraph break to
-- latex, and pandoc leaves one between every pair of blocks it writes. So the
-- row is assembled as a single piece of latex here, with each panel's blocks
-- written out by pandoc as they are reached.
--
-- The panel's caption already carries its APA label, put there by
-- floatwithsubfigure.lua, so none is added here.
local function panel_latex(block, width, parentnumber, letter)
  local out = {}
  out[#out + 1] = string.format("\\begin{apapanel}{%.4f}%%", width)

  -- A panel arrives either as a float of its own, when it was given a label,
  -- or as a pandoc figure, when it was written as a plain code chunk. Either
  -- way it is taken down to its picture: left as a float it would be written
  -- as a figure environment of its own, and latex sets a figure inside a
  -- figure one under the other whatever the layout asked for.
  local body = pandoc.List({})
  local caption, content, identifier, note
  local sub = float_behind(block)
  if sub then
    caption = caption_inlines(sub)
    content = sub.content
    identifier = sub.identifier
    note = sub.attributes and sub.attributes["apa-note"]
  else
    local figure = figure_inside(block)
    if figure then
      caption = figure_caption(figure)
      content = figure.content
      identifier = figure.identifier
    end
    note = block.attributes and block.attributes["apa-note"]
  end

  -- The caption already carries its APA panel label, put there by
  -- floatwithsubfigure.lua, so none is added here. It is followed by the same
  -- blank line that separates a figure's own title from its picture: set hard
  -- against the panel, as it was, the label read as part of the picture.
  if caption then
    body:insert(pandoc.Para(caption))
    body:insert(pandoc.RawBlock("latex", "\\apafigureskip"))
  end

  if content == nil then
    body:insert(block)
  elseif pandoc.utils.type(content) == "Blocks" then
    body:extend(content)
  else
    body:insert(content)
  end

  -- A reference to a panel should read like the panel's own number, 1B and so
  -- on. The label is not attached to any counter here, so the text it stands
  -- for is set by hand before it is written.
  if identifier and identifier ~= "" then
    local shown = (parentnumber or "") .. (letter or "")
    body:insert(pandoc.RawBlock("latex",
      "\\makeatletter\\def\\@currentlabel{" .. shown .. "}\\makeatother%\n"
      .. "\\label{" .. identifier .. "}"))
  end

  if note and note ~= "" then
    local prefix = pandoc.Para({
      pandoc.Emph(pandoc.Str(noteword)), pandoc.Str("."), pandoc.Space() })
    body:insert(pandoc.RawBlock("latex", "\\begin{apapanelnote}"))
    body:insert(utilsapa.make_note(note, prefix))
    body:insert(pandoc.RawBlock("latex", "\\end{apapanelnote}"))
  end

  local ok, written = pcall(pandoc.write, pandoc.Pandoc(body), "latex")
  out[#out + 1] = ok and written or ""
  out[#out + 1] = "\\end{apapanel}%"
  return table.concat(out, "\n")
end

-- Every panel, in rows of ncol minipages, and then the note of the whole
-- figure under them.
local function panel_grid(float, ncol)
  local parentnumber = number(float)
  local notes = pandoc.List({})
  local pieces = {}
  local width = 0.98 / ncol
  local index = 0
  for _, block in ipairs(float.content) do
    if is_figure_note(block) then
      notes:insert(block)
    elseif not is_empty(block) then
      index = index + 1
      if index > 1 then
        if (index - 1) % ncol == 0 then
          pieces[#pieces + 1] = "\\par\\bigskip"
        else
          pieces[#pieces + 1] = "\\hfill"
        end
      end
      pieces[#pieces + 1] = panel_latex(block, width, parentnumber,
        letters:sub(index, index))
    end
  end
  local blocks = pandoc.List({
    raw(table.concat(pieces, "\n") .. "\n\\par")
  })
  return blocks, notes
end

-- ---------------------------------------------------------------------------
-- Chunk options on the cell div
--
-- A float written as a markdown image carries apa-twocolumn on the image, and
-- quarto hands the attribute on to the float it builds around it. A float
-- written as a code chunk carries it somewhere else: on the cell div quarto
-- wraps the chunk's output in. The float inside that div never saw it, so a
-- figure asked to span both columns of a journal article was set inside one
-- column like any other.
--
-- The attribute is copied down to the float here, in a pass of its own, so
-- that it is already there by the time processfloat reads it. A table written
-- as a chunk needs none of this -- quarto puts the cell's attributes on the
-- table float itself -- and one that already carries the attribute is left
-- alone, so nothing is overwritten.
--
-- The note comes with it. A spanning float is the one kind this format does
-- not set in place: latex will only put it at the top of a page, so a note
-- left behind on the div would sit in the column under a figure that had gone
-- elsewhere. Inside the float it travels with the figure, which is where the
-- note of a table already is.
local function push_cell_attributes(div)
  local a = div.attributes
  if not a then return nil end
  local span = a["apa-twocolumn"]
  if not span or span == "" then return nil end

  local moved = false
  div.content:walk {
    Div = function(child)
      local float = float_behind(child)
      if not float or not float.attributes then return nil end
      if not float.attributes["apa-twocolumn"] then
        float.attributes["apa-twocolumn"] = span
        moved = true
      end
      if a["apa-note"] and not float.attributes["apa-note"] then
        float.attributes["apa-note"] = a["apa-note"]
      end
    end
  }
  if moved then return div end
end

-- The identifier quarto leaves on a markdown table.
--
-- The float carries it too, and this format writes the label itself, from the
-- number the reader sees. Pandoc's latex writer turns an identified table into
-- a longtable that opens with a \caption and a \label of its own: the
-- caption is empty, apacaption.lua having lifted the title out of it long
-- before, but \caption still steps the table counter and sets an empty
-- caption line above the rules, and the second \label makes the identifier
-- multiply defined, so a reference to it could resolve to either. The one on
-- the table is taken off and the float's own is left.
local function strip_table_identifier(blocks)
  return blocks:walk {
    Table = function(tb)
      if tb.identifier and tb.identifier ~= "" then
        tb.identifier = ""
        return tb
      end
    end
  }
end

local function processfloat(float)
  -- A panel of a laid-out figure. It is left as it is so that the figure it
  -- belongs to can take it apart and put it in the grid; written out here it
  -- would become a figure environment of its own.
  if float.parent_id then return nil end

  local istable = float.type == "Table"
  local environment = istable and "table" or "figure"

  -- A float asking to span both columns of a journal article gets the starred
  -- environment, which latex sets across the page instead of inside a column.
  -- Nothing else can hold a table wider than a column, and a longtable, which
  -- is what such a table would otherwise be, cannot be set in two columns at
  -- all.
  if mode == "jou" then
    local span = (float.attributes or {})["apa-twocolumn"]
    if span and utilsapa.stringify(span) ~= "false" then
      environment = environment .. "*"
    end
  end
  -- floatsintext asks for the float to stay where it was written, which is
  -- what the H placement means; otherwise latex is left to place it.
  --
  -- A float spanning both columns is the exception. Latex will only set one at
  -- the top of a page or on a page of its own, and given [H] it silently drops
  -- the float: the table was simply missing from the output, which is the
  -- disappearance example.qmd warns about.
  local placement = floatsintext and "[H]" or "[htbp]"
  if environment:find("%*$") then
    placement = "[tbp]"
  end

  local blocks = pandoc.List({
    raw("\\begin{" .. environment .. "}" .. placement),
  })

  blocks:extend(label_blocks(float))
  blocks:insert(command("apafloattitle", label_inlines(float)))

  local caption = caption_inlines(float)
  if caption then
    blocks:insert(command("apafloatcaption", caption))
    if not istable then
      blocks:insert(raw("\\apafigureskip"))
    end
  end

  local ncol = panel_columns(float)
  local panelnotes = nil
  if ncol then
    local grid, notes = panel_grid(float, ncol)
    blocks:extend(grid)
    panelnotes = notes
  elseif float.content then
    if pandoc.utils.type(float.content) == "Blocks" then
      blocks:extend(strip_table_identifier(float.content))
    else
      blocks:extend(strip_table_identifier(pandoc.Blocks({ float.content })))
    end
  end

  local note = note_blocks(float)
  if note then
    -- A table's note sits under the rule that closes the table, and needs
    -- the rule cleared. A figure's note follows the picture and does not.
    if istable then blocks:insert(raw("\\apatablenoteskip")) end
    blocks:insert(note)
  elseif panelnotes then
    -- The note floatwithsubfigure.lua already made, set under the whole grid.
    -- It is a FigureNote div, which formatlatex.lua puts in an apafloatnote of
    -- its own, so none is asked for here.
    blocks:extend(panelnotes)
  end

  blocks:insert(raw("\\end{" .. environment .. "}"))
  return pandoc.Div(blocks)
end

return {
  { Meta = meta },
  -- Before the floats are written, so that a chunk's apa-twocolumn has
  -- reached the float by the time processfloat asks for it.
  { Div = push_cell_attributes },
  { FloatRefTarget = processfloat, Div = clear_written_note },
}

-- Sets figures and tables the APA way, in plain LaTeX.
--
-- Quarto's latex writer builds a float itself, as a figure or table
-- environment with a \caption under it. APA wants something else: the number
-- on its own line in bold, the title under it in italics, both above the
-- figure, and the note below. So the float is taken apart here and written
-- back out in that order, using the commands apalatex.tex defines.
--
-- It runs at post-quarto, which is the last point at which a float is still a
-- FloatRefTarget that can be read. By post-render the writer has already made
-- its own figure out of it, which is why apanote.lua, which works on divs,
-- never sees a float in latex and why the note needs writing here.

-- These two filters are the whole of the pdf format, and they are in the
-- shared chain so that their place in it is fixed. Nothing here has
-- anything to say about .html, .docx or typst.
if FORMAT ~= "latex" then
  return
end
local utilsapa = require("utilsapa")
local floatrecord = require("floatrecord")

local figureword = "Figure"
local tableword = "Table"
local noteword = "Note"
-- The notes of markdown tables as they were written, by identifier
local tablenotes = {}
local floatsintext = true
local mode = "man"

-- A float a document declared for itself, under crossref.custom: what it is
-- called against the latex environment quarto builds for it. An Illustration
-- is the one apaquarto ships. Such a float is set the way a figure is, but it
-- carries its own name and counts in a sequence of its own, so neither can be
-- taken from the figure.
local customfloats = {}

local function meta(m)
  if m.crossref and m.crossref.custom then
    for _, entry in ipairs(m.crossref.custom) do
      local name = entry["reference-prefix"]
        and utilsapa.stringify(entry["reference-prefix"])
      local env = entry["latex-env"] and utilsapa.stringify(entry["latex-env"])
      if name and env then customfloats[name] = env end
    end
  end
  mode = utilsapa.mode(m)
  tablenotes = utilsapa.table_notes(m)
  figureword = utilsapa.lang(m, "crossref-fig-title", figureword)
  tableword = utilsapa.lang(m, "crossref-tbl-title", tableword)
  noteword = utilsapa.lang(m, "figure-table-note", noteword)
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
  local given = attributes.fignum or attributes.tblnum or attributes.floatnum
  if given and given ~= "" then return tostring(given) end
  if type(float.order) == "table" and float.order.order then
    return tostring(float.order.order)
  end
  return nil
end

-- "Figure 1", or "Figure A1" in an appendix, where apaquarto leaves the letter
-- in a prefix attribute.
local function label_inlines(float)
  local word = figureword
  if float.type == "Table" then
    word = tableword
  elseif float.type and float.type ~= "" and float.type ~= "Figure" then
    word = tostring(float.type)
  end
  local n = number(float)
  if not n then return pandoc.Inlines({ pandoc.Str(word) }) end
  local prefix = (float.attributes or {}).prefix or ""
  return pandoc.Inlines({ pandoc.Str(word .. " " .. prefix .. n) })
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
  if float.type and customfloats[float.type] then
    counter = customfloats[float.type]
  end
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

-- The attribute the div a float is written into carries, holding the note
-- written into it, so that the cell the float came from can be told not to
-- write it again. It is not the float's identifier, which would give pandoc
-- a second \label to write.
local kWrittenNote = "apa-written-note"

local function note_blocks(record)
  local attributes = record.float.attributes or {}
  -- floatwithsubfigure.lua writes the note of a float laid out in panels, and
  -- marks the float when it has, so that it is not written twice.
  if attributes["apa-note-written"] then return nil end
  if not record.note then return nil end
  return floatrecord.note_blocks(record.note, noteword)
end

-- Takes the apa-note off the cell a float came from, once the note has been
-- written into the float above.
--
-- A float made by a code chunk sits inside the cell div quarto builds for that
-- chunk, and the chunk's apa-note is set on both. This filter writes the note
-- inside the float, which is where APA wants it and where floatsintext can
-- carry it; apanote.lua, which runs later and reads divs, then found the
-- attribute still on the cell and wrote the note a second time underneath the
-- whole table. Only a note written into a float inside this div is taken off,
-- so a note on a div holding no float is left for apanote.lua as before,
-- whatever it says.
--
-- The float is inside the div, so it has already been through processfloat by
-- the time the div is reached.
local function clear_written_note(div)
  local note = div.attributes and div.attributes["apa-note"]
  if not note then return nil end
  local written = false
  div.content:walk {
    Div = function(child)
      local inner = child.attributes and child.attributes[kWrittenNote]
      if inner == note then written = true end
      -- The note of a markdown table is written as it was typed, and the
      -- cell carries the flattened copy; the float carries both.
      if child.attributes and child.attributes["apa-note-flat"] == note then
        written = true
      end
    end
  }
  if written then
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

-- The number of columns comes from floatrecord.columns, which reads first the
-- explicit matrix floatwithsubfigure.lua has written for latex, so that the
-- figure's note can have a row to itself.

-- Whether a block is the note of the whole figure, which floatwithsubfigure.lua
-- put among the panels for the formats that lay a float out from a matrix. Here
-- the grid is built by hand, so the note is taken back out of it and set under
-- the grid at the full width.
local is_figure_note = floatrecord.is_figure_note

-- Whether a block holds nothing at all, which is what the padding cell added
-- to fill out a short row comes to.
local function is_empty(block)
  return pandoc.utils.stringify(block) == "" and not is_figure_note(block)
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
local function panel_latex(panel, width, parentnumber, letter)
  local out = {}
  out[#out + 1] = string.format("\\begin{apapanel}{%.4f}%%", width)

  -- A panel arrives either as a float of its own, when it was given a label,
  -- or as a pandoc figure, when it was written as a plain code chunk. Either
  -- way it is taken down to its picture: left as a float it would be written
  -- as a figure environment of its own, and latex sets a figure inside a
  -- figure one under the other whatever the layout asked for.
  local body = pandoc.List({})
  local block = panel.block
  local caption, content, identifier, note =
    panel.caption, panel.content, panel.identifier, panel.note

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
    body:insert(pandoc.RawBlock("latex", "\\begin{apapanelnote}"))
    body:insert(floatrecord.note_blocks(note, noteword))
    body:insert(pandoc.RawBlock("latex", "\\end{apapanelnote}"))
  end

  local ok, written = pcall(pandoc.write, pandoc.Pandoc(body), "latex")
  out[#out + 1] = ok and written or ""
  out[#out + 1] = "\\end{apapanel}%"
  return table.concat(out, "\n")
end

-- Every panel, in rows of ncol minipages, and then the note of the whole
-- figure under them.
local function panel_grid(record)
  local ncol = record.columns
  local parentnumber = number(record.float)
  local notes = pandoc.List({})
  local pieces = {}
  local width = 0.98 / ncol
  local index = 0
  for _, panel in ipairs(record.panels) do
    local block = panel.block
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
      pieces[#pieces + 1] = panel_latex(panel, width, parentnumber,
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
--
-- Every chunk's note comes down too, not only a spanning one's. Left on the
-- cell, apanote.lua wrote it after \end{figure}: outside the float, so a
-- figure that floats left it behind in the text, and one set [H] in place
-- could still be parted from it by a page break, the figure ending one page
-- and its note beginning the next (tests/layout-chunk-note.qmd). It is copied
-- only into a cell holding one float, so that a chunk drawing several figures
-- keeps its one note under them all, and only to that float, not to the
-- panels inside it, which have notes of their own.
local function cell_floats(blocks)
  local found = {}
  local function look(list)
    for _, block in ipairs(list) do
      local float = floatrecord.float_behind(block)
      if float then
        found[#found + 1] = float
      elseif block.t == "Div" then
        look(block.content)
      end
    end
  end
  look(blocks)
  return found
end

local function push_cell_attributes(div)
  local a = div.attributes
  if not a then return nil end
  local span = a["apa-twocolumn"]
  if span == "" then span = nil end
  local note = a["apa-note"]
  if not span and not note then return nil end

  local floats = cell_floats(div.content)
  local changed = false
  for _, float in ipairs(floats) do
    float.attributes = float.attributes or {}
    if span and not float.attributes["apa-twocolumn"] then
      float.attributes["apa-twocolumn"] = span
      changed = true
    end
    if note and #floats == 1 and not float.attributes["apa-note"] then
      float.attributes["apa-note"] = note
      changed = true
    end
  end
  if changed then return div end
end

-- The identifier quarto leaves on a markdown table.
--
-- The float carries it too, and this format writes the label itself, from the
-- number the reader sees. Pandoc's latex writer turns an identified table into
-- a longtable that opens with a \caption and a \label of its own: the
-- caption is empty, quarto having moved the title onto the float, but
-- \caption still steps the table counter and sets an empty
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

-- Whether a table in the text flow is short enough to be kept whole.
--
-- A longtable may break after any row, and a short one was broken where it
-- happened to fall: the four-row table in example.qmd set its title, head and
-- first row at the foot of one page and the other three under a repeated head
-- on the next. A short table is set as a tabular instead, one box, and moved
-- whole to the next page with its title when it does not fit
-- (tests/layout-table-whole.qmd).
--
-- Only a table pandoc writes is counted, a markdown or knitr::kable one,
-- since its rows are there to count; a table a package writes in latex of
-- its own (flextable, kableExtra) is left as it was. Fifteen rows, double
-- spaced, with the title, caption and head, come to about three quarters of
-- a page; a table longer than that is better broken over pages than pushed
-- whole to the next one.
local short_table_rows = 15

-- Whether a float holds one table pandoc writes, and how many rows it has.
local function native_table(content)
  local tables, rows, raw_table = 0, 0, false
  pandoc.Blocks(floatrecord.as_blocks(content)):walk {
    Table = function(tbl)
      tables = tables + 1
      rows = rows + #tbl.head.rows + #tbl.foot.rows
      for _, body in ipairs(tbl.bodies) do
        rows = rows + #body.head + #body.body
      end
    end,
    RawBlock = function(block)
      if block.format:match("latex") or block.format:match("tex") then
        raw_table = true
      end
    end,
  }
  return tables == 1 and not raw_table, rows
end

local function short_table(content)
  local native, rows = native_table(content)
  return native and rows <= short_table_rows
end

local function processfloat(float)
  -- A panel of a laid-out figure. It is left as it is so that the figure it
  -- belongs to can take it apart and put it in the grid; written out here it
  -- would become a figure environment of its own.
  if float.parent_id then return nil end

  local record = floatrecord.read(float,
    { tablenotes = tablenotes, read_matrix = true })
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

  -- A table is set in the text flow rather than in a float, which is where
  -- apa7 sets one too.
  --
  -- A float is a single box, and a table longer than a page cannot break out
  -- of it: latex sets what fits and drops the rest without a word. The long
  -- table in tests/longtable-pagebreak.qmd came out sixty lines short that
  -- way. In the flow a longtable breaks over pages as it is built to, and its
  -- \endlastfoot is emitted, which inside a float it never is -- the missing
  -- rule at the foot of a table, and the missing note row of a flextable, came
  -- from the same place.
  --
  -- Journal mode keeps the float. A longtable cannot run in two columns at
  -- all, so a table there is set as a tabular, which is one box again; and a
  -- table asking to span both columns needs a float to span with.
  --
  -- A figure asked to stay where it was written (floatsintext, the [H] it
  -- would otherwise get) is set in the flow as well. An [H] float is one box
  -- that cannot break, and its note is inside it since #169: a figure and note
  -- together taller than the page had the end of the note set past the foot
  -- of the page and cut off (#171). In the flow the title, caption and
  -- picture are kept together and with the start of the note, and a long note
  -- runs on to the next page. A figure left to float keeps its float, and
  -- its note inside it, since the two move together.
  local floated = mode == "jou" or (not istable and not floatsintext)
  local inflow_figure = (not floated) and (not istable)
  -- A short table is kept whole: see short_table above.
  local short = (not floated) and istable and short_table(record.content)
  -- A table pandoc writes, in the flow, takes the table spacing.
  local spaced = (not floated) and istable and native_table(record.content)

  local blocks = pandoc.List({})
  if floated then
    blocks:insert(raw("\\begin{" .. environment .. "}" .. placement))
  else
    -- The space a float would have left around itself, and the group a float
    -- would have been. Without it whatever a table package declares ahead of
    -- its tabular is never ended: the bare \centering kableExtra writes set
    -- every paragraph after the table centred.
    --
    -- The space is a blank line of the text's own spacing, above and below,
    -- for a figure as for a table: "If text appears on the same page as a
    -- table or figure, add a double-spaced blank line between the text and
    -- the table or figure" (APA). typst sets the same (floatspace in
    -- typst-template.typ; tests/layout-float-space.qmd).
    blocks:insert(raw("\\par\\addvspace{\\baselineskip}\\begingroup"))
    if istable then
      -- A table is set flush left, as APA sets one and as .docx and .html
      -- do; longtable centres one by default, between \LTleft and \LTright
      -- of \fill. A table package that asks for its own placement, as
      -- flextable's [c] does, still gets it. And no \LTpost, the 12pt
      -- longtable leaves under a table: the note under it is spaced by
      -- \apatablenoteskip alone, and the space after the whole float by the
      -- \addvspace below. With both, a note stood a line and a half under
      -- the table's last row (tests/layout-float-space.qmd).
      --
      -- Nor the half em of \apatablenotegap, which a journal's table needs
      -- and this one does not: the note is the next line under the table,
      -- its capitals 15.5pt under the rule, as in typst. Its baseline stands
      -- a line under the rule, which leaves half a point more, taken back
      -- here (tests/layout-table-rules.qmd).
      blocks:insert(raw("\\setlength{\\LTleft}{0pt}\\setlength{\\LTright}{\\fill}\\setlength{\\LTpost}{0pt}\\setlength{\\apatablenotegap}{-0.5pt}"))
      -- The space between the caption and the table's top rule, as typst
      -- leaves it: 15.75pt from the caption's baseline to the rule, measured
      -- in the ink of both (tests/layout-table-rules.qmd). longtable's own
      -- is \bigskipamount, 12pt that could stretch or shrink by 4 with the
      -- page.
      blocks:insert(raw("\\setlength{\\LTpre}{16pt}"))
      -- A short table is set as a tabular, one box that cannot break, with
      -- no indent before it, as journal mode sets every table.
      if short then
        blocks:insert(raw("\\apalongtableastabular\\setlength{\\parindent}{0pt}"))
      end
    end
    if inflow_figure then
      -- A float sets its contents without a paragraph indent, and a figure's
      -- picture is a paragraph of its own; in the flow it would be indented.
      blocks:insert(raw("\\setlength{\\parindent}{0pt}"))
      -- The panels of a figure with sub-figures are labelled with
      -- \subcaption, by quarto when the figure has no layout, which stops
      -- the render outside a float. This says the group is a figure.
      blocks:insert(raw("\\captionsetup{type=figure}"))
    end
    -- The title and caption, kept with the start of the table, or with the
    -- picture and the start of the note: see \apatablekeep in apalatex.tex.
    blocks:insert(raw("\\apatablekeep"))
  end

  blocks:extend(label_blocks(float))
  blocks:insert(command("apafloattitle", label_inlines(float)))

  local caption = record.caption
  if caption then
    blocks:insert(command("apafloatcaption", caption))
    if not istable then
      blocks:insert(raw("\\apafigureskip"))
    end
  end

  -- The line this float puts in the list of figures or the list of tables:
  -- "Figure 1. The Figure Caption", which is the line .docx and typst give.
  -- Written whether or not the document asks for such a list -- latex keeps
  -- these in a file of its own and prints nothing unless \\listoffigures or
  -- \\listoftables is there to read them back.
  local entry = pandoc.List({})
  entry:extend(label_inlines(float))
  if caption then
    entry:insert(pandoc.Str("."))
    entry:insert(pandoc.Space())
    entry:extend(caption)
  end
  local listfile = istable and "lot" or "lof"
  local listkind = istable and "table" or "figure"
  local addline = pandoc.List({ pandoc.RawInline("latex",
    "\\addcontentsline{" .. listfile .. "}{" .. listkind .. "}{") })
  addline:extend(entry)
  addline:insert(pandoc.RawInline("latex", "}"))
  blocks:insert(pandoc.Plain(addline))
  -- A short table's box holds the table as well, and ends after it.
  if not floated and istable and not short then
    blocks:insert(raw("\\apatablekeepend"))
  end

  -- The table spaced from the caption's baseline, not from the foot of its
  -- last line: TeX puts a table under the depth of the line above it, so a
  -- caption whose last line had a p or a g in it stood 2pt further off the
  -- table than one that had none (tests/layout-table-rules.qmd).
  if not floated and istable then
    blocks:insert(raw("\\par\\ifdim\\prevdepth>0pt\\vskip-\\prevdepth\\prevdepth=0pt\\fi"))
  end

  -- The space longtable leaves above a table, \LTpre, which a tabular does
  -- not: a short table stands under its caption as a long one does. Less
  -- \lineskip, the point TeX puts between a line and a box as tall as a
  -- tabular, which a longtable's first row, a rule, is not given.
  if short then
    blocks:insert(raw("\\par\\vspace{\\dimexpr\\LTpre-\\lineskip\\relax}"))
  end

  local panelnotes = nil
  if record.columns then
    local grid, notes = panel_grid(record)
    blocks:extend(grid)
    panelnotes = notes
  else
    -- Its rows at the table spacing, double unless table-spacing asks for
    -- less, in a group of their own so that the note under the table keeps
    -- the body's (\apatablespacing in apalatex.tex).
    if spaced then blocks:insert(raw("\\begingroup\\apatablespacing")) end
    blocks:extend(strip_table_identifier(record.content))
    if spaced then blocks:insert(raw("\\par\\endgroup")) end
  end

  local note = note_blocks(record)
  if short then
    -- A tabular is one box on a line of its own, hanging below that line
    -- by most of its height, and the line under it is spaced from that
    -- depth: the note came within a point or two of the rule. Measured from
    -- the rule instead, as it is under a longtable, the note is the next
    -- line under the table.
    blocks:insert(raw("\\par\\prevdepth=0pt"))
  end
  if inflow_figure or short then
    -- The box ends with the picture, or with a short table. With a note to
    -- follow, it asks for room for the note's first two lines as well, and
    -- no break is allowed between the picture or table and the note.
    if note or panelnotes then
      blocks:insert(raw("\\apafigurekeepend"))
    else
      blocks:insert(raw("\\apakeepend{0pt}"))
    end
  end
  local out = pandoc.Div({})
  if note then
    out.attributes[kWrittenNote] = record.note
    if (float.attributes or {})["apa-note"] then
      out.attributes["apa-note-flat"] = float.attributes["apa-note"]
    end
  end
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

  if floated then
    blocks:insert(raw("\\end{" .. environment .. "}"))
  else
    blocks:insert(raw("\\par\\endgroup\\addvspace{\\baselineskip}"))
  end
  out.content = blocks
  return out
end

return {
  { Meta = meta },
  -- Before the floats are written, so that a chunk's apa-twocolumn has
  -- reached the float by the time processfloat asks for it.
  { Div = push_cell_attributes },
  { FloatRefTarget = processfloat, Div = clear_written_note },
}

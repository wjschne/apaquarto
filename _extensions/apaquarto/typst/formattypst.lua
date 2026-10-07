if FORMAT ~='typst' then
  return
end

-- The modules this filter loads, utilsapa.lua and floatrecord.lua, are in the
-- folder above this one, and require looks only in this filter's own folder.
-- utilsapa was found all the same, because an earlier filter had already
-- loaded it; floatrecord is loaded by no filter before this one in typst. So
-- the folder above is put on the search path, and neither is left to depend
-- on what ran first.
package.path = quarto.utils.resolve_path("../?.lua") .. ";" .. package.path

-- mainfont and monofont can be one font or a comma-separated stack of fonts
-- (the way the html format sets them). Typst takes a list of font families
-- and uses the first one that can render each glyph, so a stack becomes a
-- list for the template. Css generic families mean nothing to typst, so
-- they are dropped.
local generic_families = {
  ["cursive"] = true,
  ["emoji"] = true,
  ["fantasy"] = true,
  ["math"] = true,
  ["monospace"] = true,
  ["sans-serif"] = true,
  ["serif"] = true,
  ["system-ui"] = true,
  ["ui-monospace"] = true,
  ["ui-rounded"] = true,
  ["ui-sans-serif"] = true,
  ["ui-serif"] = true
}

-- Typst prints a warning for every font family it cannot find, even when a
-- later font in the list covers the text, and it offers no way to ask which
-- fonts are installed or to silence the warning. So the default font is
-- picked by platform instead of being listed as a fallback chain: macos
-- ships Times, windows ships Times New Roman. Other systems get the fonts
-- that are metric-compatible with Times New Roman, any of which may be
-- missing, so set mainfont there to name a font that is installed.
local platform_mainfont = {
  darwin = "Times",
  mingw32 = "Times New Roman"
}

local function default_mainfont()
  return platform_mainfont[pandoc.system.os] or
    "Times New Roman, Liberation Serif, Nimbus Roman"
end

local trim = require("utilsapa").trim

local function fontlist(value)
  local fonts = pandoc.List({})
  for font in pandoc.utils.stringify(value):gmatch("[^,]+") do
    font = trim(font)
    font = font:match('^"(.*)"$') or font:match("^'(.*)'$") or font
    -- the name is written into a typst string
    font = font:gsub('[\\"]', "")
    if font ~= "" and not generic_families[font:lower()] then
      fonts:insert(pandoc.MetaString(font))
    end
  end

  if #fonts == 0 then
    return nil
  end
  return pandoc.MetaList(fonts)
end

local utilsapa = require("utilsapa")
local floatrecord = require("floatrecord")
local typstfrontmatter = require("typstfrontmatter")

-- The body first-line indent differs by mode, and the template names each one.
-- A block that suspends the indent (references, a note) has to put back the
-- one belonging to this document rather than the manuscript default, and in
-- journal mode has to put back the all: true form as well, so the expression
-- is built once here.
local bodyindent = "apaparindent(firstlineindent)"
local hangingindent = "0.5in"

-- Whether the reference list takes a dissertation's line spacing: single
-- spaced within an entry and a double space between one entry and the next.
-- The template's thesisreferences is what sets it.
local thesisrefs = false

-- Numbered lines, which APA wants on a manuscript sent out for review.
--
-- apa7 draws them with lineno and leaves that package's own look alone: a
-- number half the size of the body, right aligned, ten points clear of the
-- text block, in the margin beside every line. Journal mode is the one it
-- changes, moving the number to five points so that it still has room beside
-- a column. Those are the three things matched here -- the size, the
-- alignment and the distance -- with the size written in em so that it
-- follows the body of whichever mode is being set.
--
-- The face is matched as nearly as typst allows: linenumberfont in the
-- template is the one sans typst bundles, so the numbers are sans wherever the
-- paper is set and no render has to warn about a family that is not there.
-- linenumber-font names another.
-- The font list a writer named in linenumber-font, as a typst array, or nil
-- when they named none. One name or several; several are tried in turn, which
-- is worth doing only for families the writer knows the machine has, since
-- typst warns once for every name it cannot find.
local function asked_for_number_font(meta)
  local value = meta["linenumber-font"]
  if value == nil then return nil end

  local names = {}
  local kind = pandoc.utils.type(value)
  if kind == "List" then
    for _, item in ipairs(value) do
      local name = pandoc.utils.stringify(item)
      if name ~= "" then names[#names + 1] = name end
    end
  else
    local name = pandoc.utils.stringify(value)
    if name ~= "" then names[1] = name end
  end
  if #names == 0 then return nil end

  for i, name in ipairs(names) do
    -- A quotation mark or a backslash in a font name would close or
    -- escape the typst string it is about to be written into. Neither
    -- belongs in one, so they are dropped rather than escaped.
    names[i] = '"' .. name:gsub('[\\"]', '') .. '"'
  end
  -- A one-name array keeps the trailing comma typst wants to tell an array
  -- from a parenthesised value.
  return "(" .. table.concat(names, ", ") .. ",)"
end

local function line_numbering(meta)
  if not utilsapa.flag(meta, "numbered-lines") then return nil end
  local mode = utilsapa.mode(meta)
  local clearance = (mode == "jou") and "5pt" or "10pt"
  local font = asked_for_number_font(meta) or "linenumberfont"
  return pandoc.RawBlock("typst",
    "#set par.line(numbering: n => text(size: 0.5em, font: " .. font .. ")[#n], " ..
    "number-align: right, number-clearance: " .. clearance .. ")")
end

local function set_body_indent(meta)
  local mode = utilsapa.mode(meta)
  if mode == "jou" then
    bodyindent = "apaparindent(joufirstlineindent, all: true)"
    hangingindent = "joufirstlineindent"
  elseif mode == "doc" then
    bodyindent = "apaparindent(docfirstlineindent)"
    hangingindent = "docfirstlineindent"
  elseif mode == "thesis" then
    thesisrefs = true
  end
end

-- Word for "note", and the notes markdowntable.lua recovered from markdown
-- table captions, keyed by table identifier
local noteword = "Note"
local tablenotes = {}

-- table-spacing as the word for it, read in the Meta pass below
local tablespacing = "double"

-- typst's word for a cell's horizontal alignment, its own or its column's.
local typst_align = {
  AlignLeft = "left", AlignRight = "right", AlignCenter = "center",
}

-- The cells of a table's head set at the foot of their row, as the .pdf
-- sets them and as APA's tables do: a heading that wraps to a second line
-- has its neighbours level with that line, on the rule, rather than with its
-- first. The body's cells stay at the top of theirs. pandoc gives the table
-- an align of its own, which a second could not join, so each head cell's
-- content is aligned instead, keeping its column's horizontal alignment.
local function bottom_align_head(tbl)
  for _, row in ipairs(tbl.head.rows) do
    local column = 1
    for _, cell in ipairs(row.cells) do
      local alignment = cell.alignment
      if alignment == "AlignDefault" and tbl.colspecs[column] then
        alignment = tbl.colspecs[column][1]
      end
      local horizontal = typst_align[alignment] or "start"
      local contents = pandoc.Blocks({
        pandoc.RawBlock("typst", "#align(bottom + " .. horizontal .. ")[")
      })
      contents:extend(cell.contents)
      contents:insert(pandoc.RawBlock("typst", "]"))
      cell.contents = contents
      column = column + cell.col_span
    end
  end
end

-- A table pandoc writes, given its padding and rules (apatablecells in the
-- template) by its count of rows and of head rows: typst tells a cell only
-- its own column and row, and the rules go under the head, wherever that
-- ends, and under the last row. A table that asks for its own inset or
-- stroke keeps it.
local function rule_table(tbl)
  bottom_align_head(tbl)
  local head = #tbl.head.rows
  local rows = head + #tbl.foot.rows
  for _, body in ipairs(tbl.bodies) do
    rows = rows + #body.head + #body.body
  end
  local cells = string.format('apatablecells("%s", %d, %d)', tablespacing,
    rows, head)
  local attributes = tbl.attr.attributes
  if attributes["typst:inset"] == nil then
    attributes["typst:inset"] = cells .. ".inset"
  end
  if attributes["typst:stroke"] == nil then
    attributes["typst:stroke"] = cells .. ".stroke"
  end
  return tbl
end

-- Table floats whose note a surrounding div already carries. apanote.lua
-- makes the note for those divs later, so making it here as well would print
-- it twice. A table from a code chunk with apa-twocolumn is the usual case.
local divnotes = {}

-- Whether apanote.lua is going to write this float's note, which is the one
-- case where writing it here as well would print it twice.
--
-- A note written on an image --- ![caption](x.png){#fig-a apa-note="..."} ---
-- is carried by the image and by the float around it alike. apanote.lua lifts
-- such a note off the image and writes it after the div, so this stands down
-- for those. An image given alt text is the exception: quarto writes it
-- straight to typst markup before apanote.lua runs, so there is no image left
-- to lift from and the note has to be written here.
--
-- A note written on the float itself --- ::: {#fig-a apa-note="..."} --- sits
-- on no image at all, so apanote.lua has nothing to lift and here is the only
-- place it can be written. That is the shape a table takes, and the shape an
-- Illustration, or any other kind of float a document declares for itself
-- under crossref.custom, is usually written in.
local function note_on_image(float)
  local lifted = false
  float.content:walk {
    Image = function(img)
      if img.attributes and img.attributes["apa-note"]
          and not img.attributes["fig-alt"] then
        lifted = true
      end
    end
  }
  return lifted
end

-- ---------------------------------------------------------------------------
-- Figures laid out in panels
--
-- Quarto builds the grid for such a figure out of everything the float holds,
-- one cell per block, so a note left inside it is one more cell and only as
-- wide as a column: in a two column figure it wraps inside half the width.
-- There is no way to widen it from outside. An explicit layout matrix, which
-- is how latex and html are given a full width row, is not something quarto's
-- typst writer reads -- handed one, it drops the figure. A note returned
-- alongside the float loses the label and typst stops with "label <fig-x>
-- does not exist in the document". And grid.cell(colspan:) is honoured only as
-- a direct child of the grid, which is not where quarto puts a cell's content.
--
-- So the grid is written out here instead, and the layout attributes taken off
-- the float so that quarto does not build a second one around it. The note
-- then follows the grid inside the figure, at the full width, with the label
-- still on the figure it belongs to.
--
-- Writing the grid means labelling the panels too, since quarto's "(a)" and
-- "(b)" come from the layout it is no longer building. They are labelled the
-- APA way, Panel A and Panel B, above each panel.
local panelword = "Panel"
local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- A float of panels is read by floatrecord, which counts the columns from
-- layout-ncol and layout-nrow only: quarto's typst writer drops a figure
-- handed an explicit layout matrix, so none is read here.

-- One panel of the grid: its label, then the picture.
--
-- Whatever a panel arrived as, it is written out as plain content. Left alone
-- it would be set as a numbered figure of its own -- which is what quarto
-- suppresses while it is building the layout, and no longer does once the
-- layout is being built here. The panel is labelled the APA way instead, with
-- its own caption following the label on the same line.
local function panel_cell(panel, index)
  local letter = letters:sub(index, index)
  if letter == "" then letter = tostring(index) end
  local label = pandoc.Inlines({
    pandoc.Strong(pandoc.Str(panelword .. " " .. letter))
  })

  local block = panel.block
  local caption, content, identifier, note =
    panel.caption, panel.content, panel.identifier, panel.note

  if caption then
    label:insert(pandoc.Str("."))
    label:insert(pandoc.Space())
    label:extend(caption)
  end

  local blocks = pandoc.Blocks({ pandoc.Para(label) })
  if content == nil then
    blocks:insert(block)
  elseif pandoc.utils.type(content) == "Blocks" then
    blocks:extend(content)
  else
    blocks:insert(content)
  end
  -- The panel keeps its own label, so that a cross-reference to it still finds
  -- something to point at.
  if identifier and identifier ~= "" then
    blocks:insert(pandoc.RawBlock("typst", "<" .. identifier .. ">"))
  end

  -- A note of the panel's own, which sits centred under the panel it belongs
  -- to rather than flush left like the note of the whole figure. floatrecord
  -- has found it wherever it was written: on the float behind a panel given a
  -- label of its own, on the block of a plain code chunk, or on the image of a
  -- panel written as a markdown image.
  --
  -- Taken off the image now that it has been read. apanote.lua lifts the note
  -- of an image onto the div around it, which for a panel is the scaffold
  -- quarto wraps the whole grid in, and the note would then be written a
  -- second time after the figure rather than under its panel.
  blocks = blocks:walk {
    Image = function(img)
      if img.attributes and img.attributes["apa-note"] then
        img.attributes["apa-note"] = nil
        return img
      end
    end
  }
  if note and note ~= "" then
    blocks:insert(pandoc.RawBlock("typst", "#align(center)["))
    blocks:insert(floatrecord.note_blocks(note, noteword))
    blocks:insert(pandoc.RawBlock("typst", "]"))
  end

  return blocks
end

-- The body of a float, the picture, table or grid of panels, in a block that
-- cannot break. The template lets the float itself break, so that a note too
-- long for the rest of the page runs on to the next one rather than off the
-- foot of it (#171); what may not be parted is held together here instead.
-- Followed by a note, the block stays on the page with the note's first line.
local function keep_body(blocks, before_note)
  local out = pandoc.Blocks({
    pandoc.RawBlock("typst", "#block(breakable: false"
      .. (before_note and ", ..apasticky" or "") .. ")[")
  })
  out:extend(floatrecord.as_blocks(blocks))
  out:insert(pandoc.RawBlock("typst", "]"))
  return out
end

-- The whole figure: the grid of panels, then the note under it at full width.
-- The panels are already plain blocks by the time this runs, each one having
-- been through panel_cell below.
local function laid_out_float(record)
  local float = record.float
  local grid = pandoc.Blocks({
    pandoc.RawBlock("typst", "#grid(columns: " .. record.columns .. ", gutter: 2em,")
  })
  for index, panel in ipairs(record.panels) do
    grid:insert(pandoc.RawBlock("typst", "["))
    grid:extend(panel_cell(panel, index))
    grid:insert(pandoc.RawBlock("typst", "],"))
  end
  grid:insert(pandoc.RawBlock("typst", ")"))
  local content = keep_body(grid, record.note ~= nil)

  if record.note then
    content:insert(pandoc.RawBlock("typst", "#align(left)["))
    content:insert(floatrecord.note_blocks(record.note, noteword))
    content:insert(pandoc.RawBlock("typst", "]"))
  end

  float.content = content
  -- Quarto builds no grid of its own for a float that asks for no layout.
  float.attributes["layout-ncol"] = nil
  float.attributes["layout-nrow"] = nil
  float.attributes["layout"] = nil
  return float
end

-- The note is written inside the float however it was given, so that the
-- figure's show rule, an unbreakable block, holds the two together. A note
-- written after the float, as apanote.lua writes one, could be parted from it
-- by a page break: the figure ended one page and its note began the next
-- (tests/layout-chunk-note.qmd). A note on an image is taken off the image
-- once it is written here, so that apanote.lua finds nothing to lift; the
-- note of a code chunk is brought down from the cell by mark_cell_notes below.
local function floatnote(record)
  if divnotes[record.identifier] then
    return nil
  end
  if not record.note then
    return nil
  end
  if note_on_image(record.float) then
    record.float.content = record.float.content:walk {
      Image = function(img)
        if img.attributes and img.attributes["apa-note"] then
          img.attributes["apa-note"] = nil
          return img
        end
      end
    }
    -- A float holding one image has that one block for its content.
    record.content = floatrecord.as_blocks(record.float.content)
  end
  return floatrecord.note_blocks(record.note, noteword)
end

-- The floats a cell holds, not counting the panels inside one of them.
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

-- A code chunk's apa-note is set on the cell quarto wraps the chunk's output
-- in, not on the float inside it, so apanote.lua wrote it after the cell,
-- outside the figure. A cell holding one float hands its note down to that
-- float and is marked as written, so that the note is written inside the
-- float, once. A cell drawing several figures keeps its one note under them
-- all, written by apanote.lua as before, and none of its floats writes it.
local function mark_cell_notes(div)
  local note = div.attributes["apa-note"]
  if not note or div.attributes[utilsapa.note_written] == utilsapa.note_mark() then
    return nil
  end
  local floats = cell_floats(div.content)
  -- A float carrying a note of its own that says something else keeps both,
  -- the way they were written before (tests/note-sources.qmd).
  local own = #floats == 1 and floats[1].attributes
    and floats[1].attributes["apa-note"]
  if #floats == 1 and (not own or own == note) then
    local float = floats[1]
    float.attributes = float.attributes or {}
    float.attributes["apa-note"] = note
    div.attributes[utilsapa.note_written] = utilsapa.note_mark()
    return div
  end
  for _, float in ipairs(floats) do
    if float.identifier then
      divnotes[float.identifier] = true
    end
  end
end

return {
  {
    -- Give the template mainfont and monofont as a list of font families
    Meta = function(meta)
      for _, key in ipairs({"mainfont", "monofont"}) do
        if meta[key] then
          meta[key] = fontlist(meta[key])
        end
      end
      -- the template's own default is a fallback chain, which warns
      if not meta.mainfont then
        meta.mainfont = fontlist(pandoc.MetaString(default_mainfont()))
      end
      noteword = utilsapa.lang(meta, "figure-table-note", noteword)
      panelword = utilsapa.lang(meta, "figure-panel", panelword)
      set_body_indent(meta)
      -- table-spacing, read once and handed to the template as the word for
      -- it: single, onehalf or double.
      tablespacing = utilsapa.table_spacing(meta)
      meta["apa-table-spacing"] = tablespacing
      if meta["apa-table-notes"] then
        tablenotes = utilsapa.table_notes(meta)
      end
      return meta
    end
  },
  -- The front matter, laid out for the document's mode, before the passes
  -- below read it as the blocks typst is given.
  { Pandoc = typstfrontmatter.lay_out },
  { Table = rule_table },
  {
    -- A note on a div around a float: brought down into the float when the div
    -- holds just the one, and otherwise left to apanote.lua, with the floats
    -- inside standing down so that it is not written twice. A float is a
    -- custom node, which a walk sees only as the div standing in for it, so
    -- the float is looked up by the id that div carries.
    Div = mark_cell_notes
  },
  {
    -- Put the note below the float's content. It goes inside the float, as it
    -- does in latex, because returning the float alongside the note loses the
    -- label quarto registers for cross-references. The template centres the
    -- body of a figure, so the note is aligned left for itself.
    FloatRefTarget = function(float)
      -- A panel of a laid-out figure. It is left as it is so that the figure
      -- it belongs to can take it apart and put it in the grid; given a note
      -- here, that note would be written outside the grid.
      if float.parent_id then return nil end

      local record = floatrecord.read(float, { tablenotes = tablenotes })
      if record.columns then
        return laid_out_float(record)
      end

      local note = floatnote(record)
      local content = keep_body(record.content, note ~= nil)
      if note then
        content:insert(pandoc.RawBlock("typst", "#align(left)["))
        content:insert(note)
        content:insert(pandoc.RawBlock("typst", "]"))
      end
      float.content = content
      return float
    end
  },
  {
    -- Replace LaTeX logo
    Math = function(eq)
      if eq.mathtype == "InlineMath" then
        if eq.text == "\\LaTeX" then
          return pandoc.Str("LaTeX")
        end
        if eq.text == "\\TeX" then
          return pandoc.Str("TeX")
        end
      end
    end
  },
  { 
      Div = function(div)
      -- Center author and affiliation
      if div.classes:includes("Author") then
        return {pandoc.RawBlock('typst', "#set align(center)"), div, pandoc.RawBlock('typst', "#set align(left)")}
      end
      
      -- Hanging indent on refs
      if div.identifier == "refs" then
        -- A dissertation's list is wrapped in thesisreferences, which holds
        -- the line spacing as well, and the indent goes inside that wrapper:
        -- everything set there stops with the list, so nothing has to be put
        -- back after it.
        if thesisrefs then
          return {pandoc.RawBlock("typst", "#thesisreferences[#set par(first-line-indent: 0in, hanging-indent: " .. hangingindent .. ")"), div, pandoc.RawBlock("typst", "]") }
        end
        return {pandoc.RawBlock("typst", "#set par(first-line-indent: 0in, hanging-indent: " .. hangingindent .. ")"), div, pandoc.RawBlock("typst","#set par(first-line-indent: " .. bodyindent .. ", hanging-indent: 0in)") }
      end
      
      if div.classes:includes("NoIndent") then
        return {pandoc.RawBlock('typst', "#set par(first-line-indent: 0mm)"), div, pandoc.RawBlock('typst', "#set par(first-line-indent: " .. bodyindent .. ")")}
      end

      -- The dash attribution under a block quotation (apaquote.lua): against
      -- the quotation's right edge, with no first-line indent. Both are set
      -- inside a content block of their own, so nothing has to be put back
      -- after, and the div's paragraphs go in it bare rather than in the
      -- block pandoc writes a div as: a block (and an align is one) is set
      -- off by the quotation's space around blocks, which put more air above
      -- the attribution than between the lines of the quotation.
      if div.classes:includes("quote-attribution") then
        local out = pandoc.List({ pandoc.RawBlock("typst",
          "#[#set align(right)\n#set par(first-line-indent: 0pt)") })
        out:extend(div.content)
        out:insert(pandoc.RawBlock("typst", "]"))
        return out
      end
    end
  } ,
  {
    Pandoc = function (doc)
      -- The line-number rule goes at the head of the body, so that it reaches
      -- every line of the document as lineno does in apa7.
      local numbering = line_numbering(doc.meta)
      if numbering then doc.blocks:insert(1, numbering) end

      -- typst aggressively wants to make first paragraphs after something not indented. 
      -- APA style wants almost all paragraphs to be indented.
      -- This function inserts a blank  paragraph and then negative vertical space
      -- before any first paragraph. Hoping that typst will fix this and that this function
      -- becomes unnecessary.
      -- The first-paragraph indent fix is for the manuscript body; in journal
      -- mode it would land inside the masthead and author note, so skip it.
      local journalmode = utilsapa.mode(doc.meta) == "jou"

      for i = #doc.blocks, 1, -1 do
        if i > 1 and not journalmode and doc.blocks[i].t == "Para" and doc.blocks[i-1].t ~= "Para" then
          if doc.blocks[i-1].t == "Header" and doc.blocks[i-1].level > 3 then
            --Do nothing
          else
            doc.blocks:insert(i, pandoc.RawBlock("typst",
              -- The spacer is a paragraph, so numbered-lines counts it as
              -- a line: its number came out beside the number of the real
              -- first line, five points apart, where the reader expects
              -- one. It is a trick of the layout rather than a line of the
              -- document, so it is not numbered. A set rule inside a
              -- content block reaches no further than the block, so the
              -- rest of the document keeps its numbering and a document
              -- that asked for none is unaffected.
              "#[#set par.line(numbering: none)\n" ..
              "#par()[#text(size:0.5em)[#h(0.0em)]]]\n" ..
              -- Taken back by the paragraph spacing the spacer brought with
              -- it, whatever the mode sets that to: a fixed 18pt took the
              -- first paragraph after a heading too close in any mode whose
              -- spacing was not 18pt.
              "#context v(-par.spacing)"))
          end
        end       
        -- Count appendices, by the heading crossrefprefix.lua marks as
        -- opening one
        if doc.blocks[i].t == "Header" and doc.blocks[i].level == 1
            and doc.blocks[i].classes:includes("apa-appendix") then
          doc.blocks:insert(i+1, pandoc.RawBlock("typst", "#counter(figure.where(kind: \"quarto-float-fig\")).update(0)\n#counter(figure.where(kind: \"quarto-float-tbl\")).update(0)\n#appendixcounter.step()"))
        end
      end
      return doc
    end
  }
}
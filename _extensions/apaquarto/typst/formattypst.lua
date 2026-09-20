if FORMAT ~='typst' then
  return
end

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

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

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

-- The body first-line indent differs by mode, and the template names each one.
-- A block that suspends the indent (references, a note) has to put back the
-- one belonging to this document rather than the manuscript default, and in
-- journal mode has to put back the all: true form as well, so the expression
-- is built once here.
local bodyindent = "apaparindent(firstlineindent)"
local hangingindent = "0.5in"

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
  if meta["numbered-lines"] == nil then return nil end
  if pandoc.utils.stringify(meta["numbered-lines"]) == "false" then return nil end
  local mode = meta.documentmode and
    pandoc.utils.stringify(meta.documentmode) or "man"
  local clearance = (mode == "jou") and "5pt" or "10pt"
  local font = asked_for_number_font(meta) or "linenumberfont"
  return pandoc.RawBlock("typst",
    "#set par.line(numbering: n => text(size: 0.5em, font: " .. font .. ")[#n], " ..
    "number-align: right, number-clearance: " .. clearance .. ")")
end

local function set_body_indent(meta)
  local mode = meta.documentmode and pandoc.utils.stringify(meta.documentmode) or "man"
  if mode == "jou" then
    bodyindent = "apaparindent(joufirstlineindent, all: true)"
    hangingindent = "joufirstlineindent"
  elseif mode == "doc" then
    bodyindent = "apaparindent(docfirstlineindent)"
    hangingindent = "docfirstlineindent"
  end
end

-- Word for "note", and the notes apatablenote.lua recovered from markdown
-- table captions, keyed by table identifier
local noteword = "Note"
local tablenotes = {}

-- Table floats whose note a surrounding div already carries. apanote.lua
-- makes the note for those divs later, so making it here as well would print
-- it twice. A table from a code chunk with apa-twocolumn is the usual case.
local divnotes = {}

-- An image with alt text is written straight to typst markup before
-- apanote.lua runs, so there is no image left for it to take the note from
-- and the note is lost. Those figures are handled here instead.
local function has_alt(float)
  local alt = false
  float.content:walk {
    Image = function(img)
      if img.attributes["fig-alt"] then
        alt = true
      end
    end
  }
  return alt
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

-- The number of columns a float of panels is asking for, or nil if it is not
-- laid out in panels at all.
local function panel_columns(float)
  local a = float.attributes
  if not a then return nil end
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

-- A float's caption, which quarto hands over as a single Block for the usual
-- one line caption and as Blocks or Inlines elsewhere.
local function caption_inlines(float)
  local caption = float.caption_long
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

-- The float a div is standing in for. A float is a custom node, and a walk of
-- the document sees only the div carrying its id.
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

-- The first pandoc Figure inside a block, which is how a panel written as a
-- plain code chunk arrives: a cell div wrapping an output div wrapping the
-- figure. A panel that was given a label of its own is a float instead, and
-- float_behind finds that one.
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

-- One panel of the grid: its label, then the picture.
--
-- Whatever a panel arrived as, it is written out as plain content. Left alone
-- it would be set as a numbered figure of its own -- which is what quarto
-- suppresses while it is building the layout, and no longer does once the
-- layout is being built here. The panel is labelled the APA way instead, with
-- its own caption following the label on the same line.
local function panel_cell(block, index)
  local letter = letters:sub(index, index)
  if letter == "" then letter = tostring(index) end
  local label = pandoc.Inlines({
    pandoc.Strong(pandoc.Str(panelword .. " " .. letter))
  })

  local caption, content, identifier, note
  local float = float_behind(block)
  if float then
    caption = caption_inlines(float)
    content = float.content
    identifier = float.identifier
    note = float.attributes and float.attributes["apa-note"]
  else
    local figure = figure_inside(block)
    if figure then
      caption = figure.caption and figure.caption.long
      if caption then
        local ok, inlines = pcall(pandoc.utils.blocks_to_inlines, caption)
        caption = ok and inlines or nil
        if caption and #caption == 0 then caption = nil end
      end
      content = figure.content
      identifier = figure.identifier
    end
  end

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
  -- to rather than flush left like the note of the whole figure. A panel given
  -- a label of its own carries the note on the float behind it, read above; a
  -- panel written as a plain code chunk carries it on the block itself; and a
  -- panel written as a markdown image carries it on the image, which is the
  -- only place it is ever written.
  if note == nil or note == "" then
    note = block.attributes and block.attributes["apa-note"]
  end
  if note == nil or note == "" then
    blocks:walk {
      Image = function(img)
        if (note == nil or note == "") and img.attributes
            and img.attributes["apa-note"] then
          note = img.attributes["apa-note"]
        end
      end
    }
  end
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
    local prefix = pandoc.Para({
      pandoc.Emph(pandoc.Str(noteword)), pandoc.Str("."), pandoc.Space() })
    blocks:insert(pandoc.RawBlock("typst", "#align(center)["))
    blocks:insert(utilsapa.make_note(note, prefix))
    blocks:insert(pandoc.RawBlock("typst", "]"))
  end

  return blocks
end

-- The whole figure: the grid of panels, then the note under it at full width.
-- The panels are already plain blocks by the time this runs, each one having
-- been through panel_cell below.
local function laid_out_float(float, ncol)
  local content = pandoc.Blocks({
    pandoc.RawBlock("typst", "#grid(columns: " .. ncol .. ", gutter: 2em,")
  })
  local index = 0
  for _, panel in ipairs(float.content) do
    index = index + 1
    content:insert(pandoc.RawBlock("typst", "["))
    content:extend(panel_cell(panel, index))
    content:insert(pandoc.RawBlock("typst", "],"))
  end
  content:insert(pandoc.RawBlock("typst", ")"))

  if float.attributes["apa-note"] then
    local prefix = pandoc.Para({
      pandoc.Emph(pandoc.Str(noteword)), pandoc.Str("."), pandoc.Space() })
    content:insert(pandoc.RawBlock("typst", "#align(left)["))
    content:insert(utilsapa.make_note(float.attributes["apa-note"], prefix))
    content:insert(pandoc.RawBlock("typst", "]"))
  end

  float.content = content
  -- Quarto builds no grid of its own for a float that asks for no layout.
  float.attributes["layout-ncol"] = nil
  float.attributes["layout-nrow"] = nil
  float.attributes["layout"] = nil
  return float
end

local function floatnote(float)
  if divnotes[float.identifier] then
    return nil
  end
  if float.type ~= "Table" and not (float.type == "Figure" and has_alt(float)) then
    return nil
  end
  local note = tablenotes[float.identifier] or float.attributes["apa-note"]
  if not note then
    return nil
  end
  local prefix = pandoc.Para({
    pandoc.Emph(pandoc.Str(noteword)),
    pandoc.Str("."),
    pandoc.Space()
  })
  return utilsapa.make_note(note, prefix)
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
      if meta.language and meta.language["figure-table-note"] then
        noteword = pandoc.utils.stringify(meta.language["figure-table-note"])
      end
      if meta.language and meta.language["figure-panel"] then
        panelword = pandoc.utils.stringify(meta.language["figure-panel"])
      end
      set_body_indent(meta)
      if meta["apa-table-notes"] then
        for id, note in pairs(meta["apa-table-notes"]) do
          tablenotes[id] = pandoc.utils.stringify(note)
        end
      end
      return meta
    end
  },
  {
    -- Find the tables whose note is already on a surrounding div. A float is
    -- a custom node, which a walk sees only as the div standing in for it, so
    -- the float is looked up by the id that div carries.
    Div = function(div)
      if div.attributes["apa-note"] then
        div.content:walk {
          Div = function(d)
            local id = d.attributes and d.attributes["__quarto_custom_id"]
            if id then
              local float = quarto._quarto.ast.custom_node_data[tostring(id)]
              if float and float.identifier then
                divnotes[float.identifier] = true
              end
            end
          end
        }
      end
    end
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

      -- floatwithsubfigure.lua writes the note of a float laid out in panels
      -- for the other formats, and marks the float when it has. Writing it
      -- again here would print it twice.
      if float.attributes and float.attributes["apa-note-written"] then
        return nil
      end

      local ncol = panel_columns(float)
      if ncol then
        return laid_out_float(float, ncol)
      end

      local note = floatnote(float)
      if not note then return nil end
      -- A float holding one image has a single block for its content; one
      -- holding a layout of panels has a list of them. The list has to be
      -- opened out rather than put inside the new list, since a list is not
      -- itself a block and pandoc will not take one where a block belongs.
      local content = pandoc.Blocks({})
      if pandoc.utils.type(float.content) == "Blocks" then
        content:extend(float.content)
      else
        content:insert(float.content)
      end
      content:insert(pandoc.RawBlock("typst", "#align(left)["))
      content:insert(note)
      content:insert(pandoc.RawBlock("typst", "]"))
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
        return {pandoc.RawBlock("typst", "#set par(first-line-indent: 0in, hanging-indent: " .. hangingindent .. ")"), div, pandoc.RawBlock("typst","#set par(first-line-indent: " .. bodyindent .. ", hanging-indent: 0in)") }
      end
      
      if div.classes:includes("NoIndent") then
        return {pandoc.RawBlock('typst', "#set par(first-line-indent: 0mm)"), div, pandoc.RawBlock('typst', "#set par(first-line-indent: " .. bodyindent .. ")")}
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
      local appendixword = "Appendix"
      if doc.meta.language and doc.meta.language["crossref-apx-prefix"] then
        appendixword = pandoc.utils.stringify(doc.meta.language["crossref-apx-prefix"])
      end
      -- The first-paragraph indent fix is for the manuscript body; in journal
      -- mode it would land inside the masthead and author note, so skip it.
      local journalmode = doc.meta.documentmode and
        pandoc.utils.stringify(doc.meta.documentmode) == "jou"

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
              "#v(apafirstparshift)"))
          end
        end       
        -- Count appendices
        if doc.blocks[i].t == "Header" and doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == appendixword then
          doc.blocks:insert(i+1, pandoc.RawBlock("typst", "#counter(figure.where(kind: \"quarto-float-fig\")).update(0)\n#counter(figure.where(kind: \"quarto-float-tbl\")).update(0)\n#appendixcounter.step()"))
        end
      end
      return doc
    end
  }
}
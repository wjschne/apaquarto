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

-- Quarto drops the apa-note of a table when it renders the float, and the
-- note of a figure with alt text goes the same way, so both are made here
-- while the float still carries the note. A figure without alt text keeps its
-- image, and apanote.lua makes the note for it later.
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
      local note = floatnote(float)
      if note then
        float.content = pandoc.Blocks({
          float.content,
          pandoc.RawBlock("typst", "#align(left)["),
          note,
          pandoc.RawBlock("typst", "]")
        })
      end
      if note then
        return float
      end
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
            doc.blocks:insert(i, pandoc.RawBlock("typst", "#par()[#text(size:0.5em)[#h(0.0em)]]\n#v(apafirstparshift)"))
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
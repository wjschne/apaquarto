--- Sets the docx fonts and page size from the mainfont, monofont and
--- papersize YAML options.
---
--- Nearly every style in apaquarto.docx asks for the theme font
--- (w:asciiTheme="minorHAnsi" and friends), so mainfont is set in the
--- reference document's theme (word/theme/theme1.xml).
---
--- A Word theme has no monospace font, so monofont is set in
--- word/styles.xml instead. The syntax highlighting styles (NormalTok,
--- KeywordTok, and the rest) name their font explicitly, and the
--- SourceCode and VerbatimChar styles are given the font as well so that
--- code blocks without highlighting and inline code match. Those two
--- styles inherit the theme font when monofont is not set, which is why
--- inline code is in the main font by default.
---
--- The page size is the w:pgSz of the section properties in
--- word/document.xml. Pandoc ignores papersize when it writes docx, and it
--- takes both the page size and the margins from the reference document,
--- so papersize is set there too. Setting it before pandoc writes also
--- means images given a percentage width are scaled to the new text width.
---
--- numbered-lines is set in those same section properties, as their
--- w:lnNumType. It belongs there because a section's line numbering, its
--- page size and the headerReference that carries the running head are all
--- properties of one section: adding a <w:sectPr> of its own to the body to
--- carry the line numbering, as apaquarto once did, splits the document into
--- a section with no header and takes the running head away (issue #104).
---
--- The running head is held in a content control in word/header2.xml, bound
--- to the document's description, which frontmatter.lua sets to the short
--- title. Word fills such a control in from its binding when it opens the
--- file, but a viewer that does not resolve data bindings shows the control's
--- placeholder instead, so the running head came out as "[Comments]" or as
--- nothing at all. The text is written into the control as well, which leaves
--- the binding in place for Word and gives every other viewer something to
--- show.
---
--- Pandoc reads the reference document when it writes the output, which
--- happens after all filters have run, so patching the reference document
--- here is picked up by the writer.
---
--- The fonts, page size, line numbering and running-head control the
--- reference document shipped with are recorded in xml comments the first
--- time it is patched, so that a later render without mainfont, monofont,
--- papersize or numbered-lines restores them, and so that every render
--- rewrites the shipped running-head control rather than its own last
--- attempt at one.

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

local theme_path = "word/theme/theme1.xml"
local styles_path = "word/styles.xml"
local document_path = "word/document.xml"
local header_pattern = "^word/header%d*%.xml$"

--- Styles that hold code but take their font from the theme by default
local code_styles = {
  SourceCode = true,
  VerbatimChar = true
}

--- Page sizes as width, height and the paper code word writes, in twips
--- (a twentieth of a point, so 1440 to the inch)
local paper_sizes = {
  a3 = {16838, 23811, 8},
  a4 = {11906, 16838, 9},
  a5 = {8391, 11906, 11},
  b5 = {9978, 14173, 13},
  executive = {10440, 15120, 7},
  legal = {12240, 20160, 5},
  letter = {12240, 15840, 1},
  tabloid = {15840, 24480, 3}
}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--- mainfont and monofont can be a stack of fonts (the html format sets
--- "Times, Times New Roman, serif"). Word wants a single font, and the
--- font name goes into xml attributes, so drop anything needing escapes.
local function clean_font(value)
  if not value then return "" end
  local font = trim(trim(pandoc.utils.stringify(value)):match("^[^,]*") or "")
  font = font:match('^"(.*)"$') or font:match("^'(.*)'$") or font
  return (font:gsub('[<>&"]', ""))
end

local function marker_pattern(key)
  return "<!%-%-%s*apaquarto%-original%-" .. key .. ":%s*(.-)%s*%-%->"
end

local function get_marker(xml, key)
  return xml:match(marker_pattern(key))
end

local function strip_marker(xml, key)
  return (xml:gsub(marker_pattern(key), ""))
end

local function make_marker(key, value)
  return "<!-- apaquarto-original-" .. key .. ": " .. value .. " -->"
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("a")
  f:close()
  return data
end

local function write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

--- Set the typeface of the <a:latin/> element in majorFont and minorFont
local function set_latin_typeface(scheme, font)
  return (scheme:gsub('(<a:latin[^>]-typeface=")[^"]*(")', function(before, after)
    return before .. font .. after
  end))
end

local function patch_theme(theme, mainfont)
  local first, last = theme:find("<a:fontScheme.-</a:fontScheme>")
  if not first then return nil end
  local scheme = theme:sub(first, last)
  local opentag = scheme:match("^<a:fontScheme[^>]*>")
  if not opentag then return nil end

  --- The font the reference document shipped with
  local original = get_marker(scheme, "mainfont") or
    scheme:match('<a:majorFont>.-<a:latin[^>]-typeface="([^"]*)"') or ""
  local font = mainfont ~= "" and mainfont or original

  local body = strip_marker(scheme:sub(#opentag + 1), "mainfont")
  local marker = font ~= original and make_marker("mainfont", original) or ""
  local newscheme = opentag .. marker .. set_latin_typeface(body, font)

  return theme:sub(1, first - 1) .. newscheme .. theme:sub(last + 1)
end

local function each_style(styles)
  return styles:gmatch("<w:style%s.-</w:style>")
end

local function find_style(styles, id)
  for style in each_style(styles) do
    if style:match('w:styleId="([^"]*)"') == id then return style end
  end
end

local function style_font(style)
  if not style then return nil end
  return style:match('<w:rFonts[^>]-w:ascii="([^"]*)"')
end

--- Rename a font wherever a style names it explicitly
local function rename_font(style, from, to)
  if from == "" or from == to then return style end
  return (style:gsub("<w:rFonts[^>]*>", function(rfonts)
    return (rfonts:gsub('(=")([^"]*)(")', function(before, value, after)
      if value == from then return before .. to .. after end
    end))
  end))
end

--- Give a style an explicit font, or remove the one it has when font is ""
local function set_style_font(style, font)
  local rfonts = '<w:rFonts w:ascii="' .. font .. '" w:hAnsi="' .. font .. '"/>'
  local first, last = style:find("<w:rPr>.-</w:rPr>")
  if first then
    local body = style:sub(first, last):match("^<w:rPr>(.-)</w:rPr>$")
    body = (body:gsub("<w:rFonts[^>]*>", ""))
    if font ~= "" then body = rfonts .. body end
    local rpr = body ~= "" and "<w:rPr>" .. body .. "</w:rPr>" or ""
    return style:sub(1, first - 1) .. rpr .. style:sub(last + 1)
  end
  if font == "" then return style end
  --- w:rPr comes after w:pPr in a style
  local rpr = "<w:rPr>" .. rfonts .. "</w:rPr>"
  local ppr = style:find("</w:pPr>", 1, true)
  if ppr then
    return style:sub(1, ppr + 7) .. rpr .. style:sub(ppr + 8)
  end
  local closetag = "</w:style>"
  return style:sub(1, #style - #closetag) .. rpr .. closetag
end

local function patch_styles(styles, monofont)
  --- The fonts the reference document shipped with. The highlighting
  --- styles and the code styles are recorded separately because the code
  --- styles have no font of their own by default.
  local current = style_font(find_style(styles, "NormalTok")) or ""
  local original_mono = get_marker(styles, "monofont") or current
  local original_code = get_marker(styles, "codefont") or
    style_font(find_style(styles, "VerbatimChar")) or ""

  local mono = monofont ~= "" and monofont or original_mono
  local code = monofont ~= "" and monofont or original_code

  styles = strip_marker(strip_marker(styles, "monofont"), "codefont")
  local first, last = styles:find("<w:styles%s[^>]*>")
  if not first then return nil end

  local newstyles = styles:gsub("<w:style%s.-</w:style>", function(style)
    local id = style:match('w:styleId="([^"]*)"') or ""
    if code_styles[id] then
      return set_style_font(style, code)
    elseif id:match("Tok$") then
      return rename_font(style, current, mono)
    end
  end)

  local markers = ""
  if mono ~= original_mono or code ~= original_code then
    markers = make_marker("monofont", original_mono) ..
      make_marker("codefont", original_code)
  end

  return newstyles:sub(1, last) .. markers .. newstyles:sub(last + 1)
end

--- papersize is written in several ways: a4, A4, a4paper, letter, us-letter
local function paper_key(papersize)
  local name = papersize:lower():gsub("[^%a%d]", "")
  name = name:gsub("^us", "")
  name = name:gsub("paper$", "")
  return name
end

--- Word numbers every line of the section, counting by one and running on
--- across pages, which is what APA asks for.
local line_numbering = '<w:lnNumType w:countBy="1" w:restart="continuous"/>'

--- w:lnNumType sits between w:pgMar and w:cols in a w:sectPr, where the
--- schema's order for section properties puts it.
local function set_line_numbers(document, linenumbers)
  local stripped = strip_marker(document, "linenumbers")

  --- The line numbering the reference document shipped with, as its element
  local original = get_marker(document, "linenumbers") or
    stripped:match("<w:lnNumType[^>]*>") or ""
  stripped = (stripped:gsub("<w:lnNumType[^>]*>", ""))

  local wanted = linenumbers and line_numbering or original
  local marker = wanted ~= original and make_marker("linenumbers", original) or ""

  local first, last = stripped:find("<w:pgMar[^>]*>")
  if not first then first, last = stripped:find("<w:pgSz[^>]*>") end
  if not first then return nil end

  return stripped:sub(1, last) .. marker .. wanted .. stripped:sub(last + 1)
end

local function patch_document(document, papersize, linenumbers)
  local stripped = strip_marker(document, "papersize")
  local first, last = stripped:find("<w:pgSz[^>]*>")
  if not first then return nil end

  --- The page size the reference document shipped with, as its attributes
  local original = get_marker(document, "papersize") or
    stripped:sub(first, last):match("^<w:pgSz%s+(.-)%s*/?>$") or ""
  local attributes = original

  if papersize ~= "" then
    local size = paper_sizes[paper_key(papersize)]
    if not size then
      quarto.log.warning("The docx format has no page size named " ..
        papersize .. ", so the reference document's page size was kept.")
    else
      local width, height, code = size[1], size[2], size[3]
      local landscape = original:match('w:orient="landscape"')
      if landscape then
        width, height = height, width
      end
      attributes = string.format('w:w="%d" w:h="%d" w:code="%d"', width, height, code)
      if landscape then
        attributes = attributes .. ' w:orient="landscape"'
      end
    end
  end

  local marker = attributes ~= original and make_marker("papersize", original) or ""
  local patched = stripped:sub(1, first - 1) .. marker ..
    "<w:pgSz " .. attributes .. "/>" .. stripped:sub(last + 1)

  return set_line_numbers(patched, linenumbers) or patched
end

local function escape_xml(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--- The running-head control is the one bound to the description of the
--- document, which its w:dataBinding names in the dublin core namespace.
local binding_field = "ns0:description"

--- Where that control begins and ends. Content controls can hold other
--- content controls, so the closing tag is found by counting the tags in
--- between rather than by taking the first one.
local function find_running_head(header)
  local from = 1
  while true do
    local first = header:find("<w:sdt[%s>]", from)
    if not first then return nil end
    local depth, at, last = 0, first, nil
    while true do
      local s, e, tag = header:find("<(/?w:sdt)[%s>]", at)
      if not s then break end
      depth = depth + (tag == "w:sdt" and 1 or -1)
      at = e
      if depth == 0 then last = header:find(">", e, true) break end
    end
    if not last then return nil end
    if header:sub(first, last):find(binding_field, 1, true) then
      return first, last
    end
    from = last + 1
  end
end

--- Put the running head inside the control, in place of the placeholder it
--- shows until something fills it in. The w:dataBinding is left alone, so
--- word still keeps the control and the document's description in step.
local function fill_running_head(sdt, runninghead)
  local filled = (sdt:gsub("<w:showingPlcHdr%s*/>", ""))
  local _, opened = filled:find("<w:sdtContent[^>]*>")
  local closed = opened and filled:find("</w:sdtContent>", opened, true)
  if not closed then return nil end

  local run = "<w:r><w:t xml:space=\"preserve\">" ..
    escape_xml(runninghead) .. "</w:t></w:r>"
  return filled:sub(1, opened) .. run .. filled:sub(closed)
end

local function patch_header(header, runninghead)
  --- A document with no description at all is one this filter knows nothing
  --- about, so its header is left as its reference document wrote it.
  if not runninghead then return nil end

  local stripped = strip_marker(header, "runninghead")
  local first, last = find_running_head(stripped)
  if not first then return nil end

  --- The control as the reference document shipped it, so that each render
  --- rewrites that rather than the text the render before it left behind
  local original = get_marker(header, "runninghead") or stripped:sub(first, last)

  --- A suppressed short title empties the control rather than putting the
  --- placeholder back: an empty header is what suppressing it asks for, and
  --- the placeholder is exactly the "[Comments]" a reader should never see.
  local wanted = fill_running_head(original, runninghead) or original

  local marker = wanted ~= original and make_marker("runninghead", original) or ""
  return stripped:sub(1, first - 1) .. marker .. wanted .. stripped:sub(last + 1)
end

function Pandoc(doc)
  local refdoc = PANDOC_WRITER_OPTIONS.reference_doc
  if not refdoc then return nil end

  local mainfont = clean_font(doc.meta.mainfont)
  local monofont = clean_font(doc.meta.monofont)
  local papersize = doc.meta.papersize and
    trim(pandoc.utils.stringify(doc.meta.papersize)) or ""
  local linenumbers = doc.meta["numbered-lines"] ~= nil and
    pandoc.utils.stringify(doc.meta["numbered-lines"]) == "true"
  --- frontmatter.lua has already put the short title, upper cased, in the
  --- description, or a single space when the short title is suppressed. nil
  --- rather than "" when there is no description at all, which tells
  --- patch_header to leave the header alone.
  local runninghead = doc.meta.description ~= nil and
    trim(pandoc.utils.stringify(doc.meta.description)) or nil

  local data = read_file(refdoc)
  if not data then
    quarto.log.warning("Could not read reference document " .. refdoc ..
      ", so mainfont, monofont, papersize and numbered-lines were not applied.")
    return nil
  end

  local ok, archive = pcall(pandoc.zip.Archive, data)
  if not ok then
    quarto.log.warning("Could not read reference document " .. refdoc ..
      " as a docx file, so mainfont, monofont, papersize and numbered-lines" ..
      " were not applied.")
    return nil
  end

  local changed = false
  local newentries = {}
  for _, entry in ipairs(archive.entries) do
    local xml, patched
    if entry.path == theme_path then
      xml = entry:contents()
      patched = patch_theme(xml, mainfont)
      if not patched then
        quarto.log.warning("Reference document " .. refdoc ..
          " has no theme fonts, mainfont was not applied.")
      end
    elseif entry.path == styles_path then
      xml = entry:contents()
      patched = patch_styles(xml, monofont)
      if not patched then
        quarto.log.warning("Reference document " .. refdoc ..
          " has no styles, monofont was not applied.")
      end
    elseif entry.path == document_path then
      xml = entry:contents()
      patched = patch_document(xml, papersize, linenumbers)
      if not patched then
        quarto.log.warning("Reference document " .. refdoc ..
          " has no page size, so papersize and numbered-lines were not applied.")
      end
    elseif entry.path:match(header_pattern) then
      --- Only the header holding the running-head control is changed; the
      --- others have no such control and patch_header leaves them alone.
      xml = entry:contents()
      patched = patch_header(xml, runninghead)
    end
    if patched and patched ~= xml then
      changed = true
      newentries[#newentries + 1] = pandoc.zip.Entry(entry.path, patched, entry.modtime)
    else
      newentries[#newentries + 1] = entry
    end
  end
  if not changed then return nil end

  archive.entries = newentries
  if not write_file(refdoc, archive:bytestring()) then
    quarto.log.warning("Could not write reference document " .. refdoc ..
      ", so mainfont, monofont, papersize and numbered-lines were not applied.")
  end

  return nil
end

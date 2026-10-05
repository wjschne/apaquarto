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
--- The link colours are written here too: a character style for each of
--- linkcolor, urlcolor, citecolor and filecolor, which docxlinkcolor.lua
--- hands to the links themselves.
---
--- Pandoc reads the reference document when it writes the output, which
--- happens after all filters have run, so patching the reference document
--- here is picked up by the writer. This is the one filter that writes it,
--- once a render, with everything the render asks for; see referencedoc.lua.
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
local footer_pattern = "^word/footer%d*%.xml$"
local rels_path = "word/_rels/document.xml.rels"

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

local utilsapa = require("utilsapa")
local referencedoc = require("referencedoc")
local trim = utilsapa.trim

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

--- The paragraph properties a dissertation's styles take. The Graduate School
--- sets the body double spaced, which is what Normal carries, but a block
--- quotation, a note and the entries of the reference list single spaced, with
--- a double space between one entry and the next and the whole of a quotation
--- half an inch in from both margins. A line of twelve point Times is 13.8
--- points deep in word, so the 276 twips under a paragraph are the second line
--- that makes the gap between two of them a double space.
---
--- A block quotation is given those 276 twips as well. Word hangs the extra
--- half of a double-spaced line below the line rather than above it, so a
--- single-spaced paragraph leaves nothing under its last line, and the
--- paragraph after a quotation would otherwise sit a single space from it
--- while the paragraph before it sits a double space away.
---
--- Each style's properties are written out in full rather than added to what
--- the reference document ships, so that they read as the handbook's rule
--- rather than as a difference from it, and so that a document that brings a
--- reference document of its own still gets them. What was there before is
--- kept in a marker, and every other mode puts it back.
local single_spaced = '<w:spacing w:after="276" w:line="240" w:lineRule="auto"/>'
local thesis_properties = {
  BlockText = single_spaced .. '<w:ind w:left="720" w:right="720" w:firstLine="0"/>',
  NextBlockText = single_spaced .. '<w:ind w:firstLine="720"/>',
  Bibliography = single_spaced .. '<w:ind w:left="720" w:hanging="720"/>',
  --- A numbered note, whose first line the handbook asks to be indented half
  --- an inch. Its turned lines run to the margin.
  FootnoteText = single_spaced .. '<w:ind w:firstLine="720"/>'
}

--- Give a style the paragraph properties it is to carry, or take away the ones
--- it has when properties is nil, and say what it had.
local function set_style_properties(style, properties)
  local first, last = style:find("<w:pPr>.-</w:pPr>")
  local original = first and
    style:sub(first, last):match("^<w:pPr>(.-)</w:pPr>$") or ""
  local ppr = properties and "<w:pPr>" .. properties .. "</w:pPr>" or ""
  if first then
    return style:sub(1, first - 1) .. ppr .. style:sub(last + 1), original
  end
  if ppr == "" then return style, original end
  --- w:pPr comes before w:rPr in a style
  local rpr = style:find("<w:rPr>", 1, true)
  if rpr then
    return style:sub(1, rpr - 1) .. ppr .. style:sub(rpr), original
  end
  local closetag = "</w:style>"
  return style:sub(1, #style - #closetag) .. ppr .. closetag, original
end

local function patch_styles(styles, monofont, thesis)
  --- The fonts the reference document shipped with. The highlighting
  --- styles and the code styles are recorded separately because the code
  --- styles have no font of their own by default.
  local current = style_font(find_style(styles, "NormalTok")) or ""
  local original_mono = get_marker(styles, "monofont") or current
  local original_code = get_marker(styles, "codefont") or
    style_font(find_style(styles, "VerbatimChar")) or ""

  local mono = monofont ~= "" and monofont or original_mono
  local code = monofont ~= "" and monofont or original_code

  --- The properties those styles had before any render changed them. An empty
  --- marker is a style that carried none, which is what every mode but thesis
  --- puts back.
  local original_properties = {}
  for id in pairs(thesis_properties) do
    original_properties[id] = get_marker(styles, "ppr" .. id)
    styles = strip_marker(styles, "ppr" .. id)
  end

  styles = strip_marker(strip_marker(styles, "monofont"), "codefont")
  local first, last = styles:find("<w:styles%s[^>]*>")
  if not first then return nil end

  local property_markers = {}
  local newstyles = styles:gsub("<w:style%s.-</w:style>", function(style)
    local id = style:match('w:styleId="([^"]*)"') or ""
    if thesis_properties[id] then
      local _, had = set_style_properties(style, nil)
      local original = original_properties[id] or had
      local wanted = thesis and thesis_properties[id]
        or (original ~= "" and original or nil)
      --- The marker is written whenever the style is not left as it shipped,
      --- and not only when this render is the one that changes it: a second
      --- thesis render finds the properties already set and would otherwise
      --- drop the marker that says what it replaced.
      if (wanted or "") ~= original then
        property_markers[#property_markers + 1] =
          make_marker("ppr" .. id, original)
      end
      if (wanted or "") == had then return nil end
      return (set_style_properties(style, wanted))
    end
    if code_styles[id] then
      return set_style_font(style, code)
    elseif id:match("Tok$") then
      return rename_font(style, current, mono)
    end
  end)

  local markers = table.concat(property_markers)
  if mono ~= original_mono or code ~= original_code then
    markers = markers .. make_marker("monofont", original_mono) ..
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

--- The margins, which live in the same section properties as the page size
--- and which pandoc takes from the reference document just as it does the
--- size. documentmode: thesis asks for the ones the Graduate School's
--- handbook sets, and a document can ask for its own with margin; a side
--- neither names keeps whatever the reference document shipped with.
local function set_margins(document, margins)
  local stripped = strip_marker(document, "margins")
  local first, last = stripped:find("<w:pgMar[^>]*>")
  if not first then return document end

  --- The margins the reference document shipped with, as its attributes
  local original = get_marker(document, "margins") or
    stripped:sub(first, last):match("^<w:pgMar%s+(.-)%s*/?>$") or ""

  local attributes = original
  if margins then
    for _, side in ipairs({ "top", "right", "bottom", "left" }) do
      if margins[side] then
        local twips = math.floor(margins[side] * 1440 + 0.5)
        local name = "w:" .. side
        if attributes:find(name .. '="', 1, true) then
          attributes = attributes:gsub(name .. '="[^"]*"', name .. '="' .. twips .. '"')
        else
          attributes = attributes .. " " .. name .. '="' .. twips .. '"'
        end
      end
    end
  end

  local marker = attributes ~= original and make_marker("margins", original) or ""
  return stripped:sub(1, first - 1) .. marker ..
    "<w:pgMar " .. attributes .. "/>" .. stripped:sub(last + 1)
end

--- How the pages of the body are numbered.
---
--- A dissertation numbers its front matter in lower-case roman and starts
--- again at 1 for the first page of the body, so the body is a section of its
--- own with a w:pgNumType saying so. The title page's own section is written
--- by thesisfrontmatter.lua, at the end of the page it builds; this is the
--- section that holds everything after it.
---
--- w:pgNumType belongs after w:lnNumType and before w:cols in the order the
--- schema sets for section properties.
---
--- An earlier version of this left the running head off the title page with a
--- w:titlePg here. The title page has a section of its own now and carries no
--- header reference at all, so the element is taken out wherever a render of
--- that version left one behind.
local function set_page_numbering(document, numbering)
  local stripped = strip_marker(document, "pagenumbering")
  stripped = (stripped:gsub("<w:titlePg%s*/>", ""))

  local original = get_marker(document, "pagenumbering") or
    stripped:match("<w:pgNumType[^>]*>") or ""
  stripped = (stripped:gsub("<w:pgNumType[^>]*>", ""))

  local wanted = numbering or original
  local marker = wanted ~= original and make_marker("pagenumbering", original) or ""

  local at = stripped:find("<w:cols", 1, true)
    or stripped:find("</w:sectPr>", 1, true)
  if not at then return stripped end
  return stripped:sub(1, at - 1) .. marker .. wanted .. stripped:sub(at)
end

--- The running head, which a dissertation does not have.
---
--- The Graduate School asks for the page number and nothing else, so in
--- thesis mode the section names no header at all and word draws none.
---
--- The references are taken out as one stretch and the marker goes in where
--- they stood, holding exactly what was there. Putting them back is then
--- putting that stretch back in its own place, so that a reference document
--- which has been through thesis mode and out again holds what it held
--- before, in the order it held it, rather than the same references
--- rearranged.
local function set_header_references(document, strip)
  --- Whatever a render left behind, back where it came from
  local restored = (document:gsub(marker_pattern("headers"),
    function(text) return text end))
  if not strip then return restored end

  local first = restored:find("<w:headerReference", 1, true)
  if not first then return restored end
  --- To the end of the last of them, which takes in any footer reference
  --- standing between two header references. Those come back untouched.
  local last = first
  while true do
    local from, to = restored:find("<w:headerReference[^>]*/>", last)
    if not from then break end
    last = to + 1
  end
  local span = restored:sub(first, last - 1)
  if span == "" then return restored end
  return restored:sub(1, first - 1) .. make_marker("headers", span)
    .. restored:sub(last)
end

--- The page number at the centre of the foot, which is where the
--- dissertations Temple publishes put it. Word needs a field in a footer to
--- show one, and the reference document's footers are empty, so the field is
--- written into the one the section names as its default.
local footer_page_number = table.concat({
  '<w:p><w:pPr><w:pStyle w:val="Footer"/><w:jc w:val="center"/></w:pPr>',
  '<w:r><w:fldChar w:fldCharType="begin"/></w:r>',
  '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>',
  '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
  '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>',
})

--- What the footer held before is kept in a marker, so that every other mode
--- gets it back. A marker is an xml comment and an xml comment cannot hold a
--- double hyphen, so a footer with one in it is left alone and said so.
local function patch_footer(footer, wanted)
  local _, open = footer:find("<w:ftr[^>]*>")
  local close = footer:find("</w:ftr>", 1, true)
  if not open or not close then return nil end

  local original = get_marker(footer, "footer")
  if original == nil then
    if not wanted then return nil end
    original = footer:sub(open + 1, close - 1)
    if original:find("--", 1, true) then
      quarto.log.warning("The reference document's footer cannot be replaced " ..
        "with a page number, so the pages are not numbered at the foot.")
      return nil
    end
  end

  local body = original
  if wanted then
    body = make_marker("footer", original) .. footer_page_number
  end
  return footer:sub(1, open) .. body .. footer:sub(close)
end

--- Which footer the section calls its default, as a path in the archive.
local function default_footer_path(document, rels)
  local id = document:match('<w:footerReference w:type="default" r:id="([^"]+)"')
  if not id then return nil end
  for element in rels:gmatch("<Relationship[^>]*>") do
    if element:match('Id="' .. id .. '"') then
      local target = element:match('Target="([^"]+)"')
      if target then return "word/" .. (target:gsub("^/", "")) end
    end
  end
  return nil
end

local function patch_document(document, papersize, linenumbers, margins, numbering)
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

  patched = set_margins(patched, margins)
  patched = set_page_numbering(patched, numbering)
  patched = set_header_references(patched, numbering ~= nil)
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
  if not PANDOC_WRITER_OPTIONS.reference_doc then return nil end

  local mainfont = clean_font(doc.meta.mainfont)
  local monofont = clean_font(doc.meta.monofont)
  local papersize = doc.meta.papersize and
    trim(pandoc.utils.stringify(doc.meta.papersize)) or ""
  local linenumbers = utilsapa.flag(doc.meta, "numbered-lines")
  --- A dissertation is bound at the left and wants a wider margin there, and
  --- its title page carries no running head. Both belong to the section, and
  --- the section is the reference document's.
  local thesis = utilsapa.mode(doc.meta) == "thesis"
  --- A document's own margin field is laid over that, side by side, so a
  --- side it does not name keeps the mode's margin, or the reference
  --- document's in every mode but thesis.
  local margins = nil
  if thesis then
    margins = utilsapa.thesis_body_margins(doc.meta, true)
  else
    margins = utilsapa.margin_sides(doc.meta.margin, true)
  end
  --- The body of a dissertation begins again at 1, in arabic; the front
  --- matter before it is in lower-case roman, which the title page's own
  --- section sets.
  local numbering = thesis and '<w:pgNumType w:fmt="decimal" w:start="1"/>'
    or nil
  --- frontmatter.lua has already put the short title, upper cased, in the
  --- description, or a single space when the short title is suppressed. nil
  --- rather than "" when there is no description at all, which tells
  --- patch_header to leave the header alone.
  local runninghead = doc.meta.description ~= nil and
    trim(pandoc.utils.stringify(doc.meta.description)) or nil
  --- A student paper carries the page number and nothing else. APA seventh
  --- edition drops the running head from student work, and the control is
  --- emptied rather than left out so that the number beside it stays.
  --- Issue #166.
  if utilsapa.mode(doc.meta) == "stu" then
    runninghead = ""
  end

  --- The colour each of linkcolor, urlcolor, citecolor and filecolor asks
  --- for, which become character styles in word/styles.xml.
  local linkcolours = referencedoc.link_colours(doc.meta)

  local archive, refdoc = referencedoc.read()
  if not archive then
    quarto.log.warning("Reference document: " .. refdoc ..
      ", so mainfont, monofont, papersize, numbered-lines and the link" ..
      " colours were not applied.")
    return nil
  end

  --- Which footer the page number goes in. Every footer is looked at, not
  --- just that one, so that a footer an earlier render wrote a number into is
  --- put back when the mode changes.
  local footer_path = nil
  do
    local docxml, relsxml
    for _, entry in ipairs(archive.entries) do
      if entry.path == document_path then docxml = entry:contents() end
      if entry.path == rels_path then relsxml = entry:contents() end
    end
    if thesis and docxml and relsxml then
      footer_path = default_footer_path(docxml, relsxml)
    end
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
      patched = patch_styles(xml, monofont, thesis)
      if not patched then
        quarto.log.warning("Reference document " .. refdoc ..
          " has no styles, monofont and the link colours were not applied.")
      else
        patched = referencedoc.patch_link_styles(patched, linkcolours)
        --- The style a quotation's dash attribution takes, for a document
        --- that has one (apaquote.lua).
        patched = referencedoc.patch_attribution_style(patched,
          utilsapa.flag(doc.meta, "apa-quote-attribution"))
      end
    elseif entry.path == document_path then
      xml = entry:contents()
      patched = patch_document(xml, papersize, linenumbers, margins, numbering)
      if not patched then
        quarto.log.warning("Reference document " .. refdoc ..
          " has no page size, so papersize and numbered-lines were not applied.")
      end
    elseif entry.path:match(header_pattern) then
      --- Only the header holding the running-head control is changed; the
      --- others have no such control and patch_header leaves them alone.
      xml = entry:contents()
      patched = patch_header(xml, runninghead)
    elseif entry.path:match(footer_pattern) then
      xml = entry:contents()
      patched = patch_footer(xml, entry.path == footer_path)
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
  if not referencedoc.write(archive) then
    quarto.log.warning("Could not write reference document " .. refdoc ..
      ", so mainfont, monofont, papersize, numbered-lines and the link" ..
      " colours were not applied.")
  end

  return nil
end

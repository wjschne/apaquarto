-- The front matter of a dissertation, set in Word's own markup. See
-- thesispages.lua for the pages it is handed.

local thesispages = require("thesispages")
local utilsapa = require("utilsapa")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
local contents_colour = thesispages.contents_colour
local raw = pandoc.RawBlock

-- Written as word markup so that the spacing is exact and the pages still
-- read as ordinary paragraphs a writer can edit in word.

local xml_escape = utilsapa.xml_escape
local docx_runs = utilsapa.docx_runs

-- Word measures a space before a paragraph in twentieths of a point.
local function twips(points)
  return math.floor(points * 20 + 0.5)
end

-- Which footers the document's own section names, taken from the reference
-- document. A section that names none inherits none, and a page with no
-- footer carries no number, so the sections written here have to name the
-- same ones the body's section does for the front matter to be numbered at
-- all. The title page still comes out unnumbered: w:titlePg sends the first
-- page of its section to the "first" footer, which is empty.
local function reference_footers()
  local xml = require("referencedoc").part("word/document.xml")
  local sect = xml and xml:match("<w:sectPr.-</w:sectPr>")
  if not sect then return "" end
  local found = {}
  for element in sect:gmatch("<w:footerReference[^>]*/>") do
    found[#found + 1] = element
  end
  return table.concat(found)
end

local kInch = 1440

-- The section properties a front-matter page ends with. Word keeps a
-- section's properties in the last paragraph of that section, so an empty
-- paragraph both ends the page and carries them.
--
-- The order of the properties is the schema's: the footer references, then
-- pgSz, pgMar, pgNumType, cols, titlePg.
local function docx_section(page, footers, start)
  local numbering = '<w:pgNumType w:fmt="lowerRoman"'
    .. (start and ' w:start="1"' or "") .. "/>"
  return table.concat({
    "<w:p><w:pPr><w:sectPr>",
    footers,
    '<w:pgSz w:w="12240" w:h="15840" w:code="1"/>',
    string.format(
      '<w:pgMar w:top="%d" w:right="%d" w:bottom="%d" w:left="%d"'
      .. ' w:header="720" w:footer="720" w:gutter="0"/>',
      page.margins.top * kInch, page.margins.right * kInch,
      page.margins.bottom * kInch, page.margins.left * kInch),
    numbering,
    '<w:cols w:space="720"/>',
    page.numbered and "" or "<w:titlePg/>",
    "</w:sectPr></w:pPr></w:p>",
  })
end

-- Word will not tell anything the page it is on except through a field, so
-- an entry carries a PAGEREF just as the lists of figures and tables do. It
-- is not marked dirty: word runs a dirty field while it is loading, before
-- it has laid the pages out, and every answer comes back 1 and stays there.
-- The number arrives the moment anything makes word paginate --- select all
-- and press F9, or print, or export to pdf --- which is what the notice
-- docxcontents.lua prints is about.
--
-- A bookmark name longer than forty characters is not one word will take, so
-- pandoc hashes it, and a link here has to ask for the same name.
local bookmark_name = utilsapa.docx_bookmark_name

local next_bookmark = 8000
local function bookmark_id(same)
  if not same then next_bookmark = next_bookmark + 1 end
  return next_bookmark
end

local function docx_contents_line(entry, measure, colour)
  local indent = twips(entry.indent * kSubheadingStep * 72)
  local hanging = entry.number and twips(kNumberColumn * 72) or 0
  local tab = twips(measure * 72) - indent

  local properties = string.format(
    --- A title of two or more lines is single spaced, and the 276 twips
    --- ahead of an entry are the second line that leaves a double space
    --- between it and whatever it follows --- the entry before it, or the
    --- column heading the list opens under.
    '<w:spacing w:before="276" w:after="0" w:line="240" w:lineRule="auto"/>'
    .. '<w:ind w:left="%d" w:hanging="%d"/>', indent + hanging, hanging)
  if entry.kind ~= "label" then
    properties = properties .. "<w:tabs>"
      .. (entry.number and string.format(
        '<w:tab w:val="left" w:pos="%d"/>', indent + hanging) or "")
      .. string.format(
        '<w:tab w:val="right" w:leader="dot" w:pos="%d"/>', tab)
      .. "</w:tabs>"
  end

  local body = docx_runs(entry.text, false, false, colour)
  if entry.number then
    body = docx_runs(pandoc.Inlines({ pandoc.Str(entry.number) }), false,
      false, colour) .. "<w:r><w:tab/></w:r>" .. body
  end

  if entry.kind == "label" or entry.target == nil then
    return "<w:p><w:pPr>" .. properties .. "</w:pPr>" .. body .. "</w:p>"
  end

  local anchor = xml_escape(bookmark_name(entry.target))
  return table.concat({
    "<w:p><w:pPr>", properties, "</w:pPr>",
    '<w:hyperlink w:anchor="', anchor, '">', body, "</w:hyperlink>",
    "<w:r><w:tab/></w:r>",
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>',
    '<w:r><w:instrText xml:space="preserve"> PAGEREF ', anchor,
    ' \\h </w:instrText></w:r>',
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>',
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>',
    "</w:p>",
  })
end

local function render_docx(pages, meta)
  local out = pandoc.List({})
  local footers = reference_footers()
  local pending_anchor = ""

  for index, page in ipairs(pages) do
    local pending = 0
    -- A bookmark waiting for the next paragraph to mark.
    local function anchors()
      local held = pending_anchor
      pending_anchor = ""
      return held
    end
    local function properties(extra, double)
      local spacing = string.format(
        '<w:spacing w:before="%d" w:after="0" w:line="%d" w:lineRule="auto"/>',
        twips(pending), double and 480 or 240)
      pending = 0
      return "<w:pPr>" .. spacing .. (extra or "") .. "</w:pPr>"
    end

    for _, item in ipairs(page.items) do
      if item.kind == "gap" then
        pending = pending + item.points
      elseif item.kind == "rule" then
        -- A rule is a paragraph with a border under it, which is how word
        -- draws one. The indents narrow the paragraph to the rule's width.
        local inset = twips((page.measure - item.width) / 2 * 72)
        local extra = '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="0"'
          .. ' w:color="auto"/></w:pBdr>'
          .. string.format('<w:ind w:left="%d" w:right="%d"/>', inset, inset)
        out:insert(raw("openxml",
          "<w:p>" .. properties(extra) .. anchors() .. "</w:p>"))
      elseif item.kind == "para" then
        local runs = pandoc.List({})
        for i, line in ipairs(item.lines) do
          if i > 1 then runs:insert("<w:r><w:br/></w:r>") end
          runs:insert(docx_runs(line, item.bold, false))
        end
        local extra = string.format('<w:jc w:val="%s"/>',
          item.align == "center" and "center"
            or item.align == "right" and "right" or "left")
        if item.indent then
          extra = extra .. string.format('<w:ind w:left="%d"/>',
            twips(item.indent * 72))
        end
        out:insert(raw("openxml",
          "<w:p>" .. properties(extra, item.double) .. anchors()
          .. table.concat(runs) .. "</w:p>"))
      elseif item.kind == "anchor" then
        -- Held back rather than set in a paragraph of its own: an empty
        -- paragraph is a blank line, and the heading under it came out a
        -- line further down the page than the other formats put it. A
        -- bookmark may stand inside the paragraph it marks, between the
        -- properties and the runs, so that is where it goes.
        pending_anchor = pending_anchor .. string.format(
          '<w:bookmarkStart w:id="%d" w:name="%s"/>'
          .. '<w:bookmarkEnd w:id="%d"/>',
          bookmark_id(), item.name, bookmark_id(true))
      elseif item.kind == "columns" then
        local tab = twips(page.measure * 72)
        local extra = "<w:tabs>"
          .. string.format('<w:tab w:val="right" w:pos="%d"/>', tab)
          .. "</w:tabs>"
        out:insert(raw("openxml", table.concat({
          "<w:p>", properties(extra), anchors(),
          docx_runs(item.left, false, false),
          "<w:r><w:tab/></w:r>",
          docx_runs(item.right, false, false),
          "</w:p>",
        })))
      elseif item.kind == "contents" then
        for _, entry in ipairs(item.entries) do
          out:insert(raw("openxml",
            docx_contents_line(entry, page.measure, contents_colour(meta))))
        end
      elseif item.kind == "blocks" then
        -- Prose word sets for itself. A gap standing before it is carried by
        -- an empty paragraph, since the blocks are not ours to give
        -- properties to.
        if pending > 0 then
          out:insert(raw("openxml", "<w:p>" .. properties() .. "</w:p>"))
        end
        -- Flush left, with no first line indented: an abstract begins at the
        -- margin. The reference document has the style for it already ---
        -- it is the one apaquarto gives the first paragraph of an APA
        -- abstract --- and a div carrying a custom style hands it to every
        -- paragraph inside.
        out:insert(pandoc.Div(item.blocks,
          pandoc.Attr("", {}, { ["custom-style"] = "AbstractFirstParagraph" })))
      end
    end
    out:insert(raw("openxml", docx_section(page, footers, index == 1)))
  end
  return out
end

return { render = render_docx }

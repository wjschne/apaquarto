-- The front matter of a dissertation, set in Word's own markup. See
-- thesispages.lua for the pages it is handed.

local thesispages = require("thesispages")
local utilsapa = require("utilsapa")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
local kPageColumn = thesispages.page_column
local kLabelLead = thesispages.label_lead
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
-- pgSz, pgMar, pgNumType, cols, vAlign, titlePg.
--
-- A page whose block stands in the middle of it is a section centred down
-- the page. Word centres the empty paragraph that carries the properties
-- along with the rest, so that paragraph is given next to no height, or the
-- block would stand half a line above the middle.
local function docx_section(page, footers, start, centred)
  local numbering = '<w:pgNumType w:fmt="lowerRoman"'
    .. (start and ' w:start="1"' or "") .. "/>"
  return table.concat({
    "<w:p><w:pPr>",
    centred and '<w:spacing w:before="0" w:after="0" w:line="20"'
      .. ' w:lineRule="exact"/>' or "",
    "<w:sectPr>",
    footers,
    '<w:pgSz w:w="12240" w:h="15840" w:code="1"/>',
    string.format(
      '<w:pgMar w:top="%d" w:right="%d" w:bottom="%d" w:left="%d"'
      .. ' w:header="720" w:footer="720" w:gutter="0"/>',
      page.margins.top * kInch, page.margins.right * kInch,
      page.margins.bottom * kInch, page.margins.left * kInch),
    numbering,
    '<w:cols w:space="720"/>',
    centred and '<w:vAlign w:val="center"/>' or "",
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
  -- A tab stop is measured from the margin, not from the indent, so the
  -- right tab sits at the full measure however deep the entry is indented.
  -- The words stop the page column short of it, at the right indent, and
  -- word lets a tab stop stand past that indent, so the dots and the number
  -- still run out to the margin.
  local tab = twips(measure * 72)
  local right = twips(kPageColumn * 72)

  -- tabs come before spacing and ind in a paragraph's properties
  local properties = ""
  if entry.kind ~= "label" then
    properties = "<w:tabs>"
      .. (entry.number and string.format(
        '<w:tab w:val="left" w:pos="%d"/>', indent + hanging) or "")
      .. string.format(
        '<w:tab w:val="right" w:leader="dot" w:pos="%d"/>', tab)
      .. "</w:tabs>"
  end
  properties = properties .. string.format(
    --- A title of two or more lines is single spaced, and the 276 twips
    --- ahead of an entry are the second line that leaves a double space
    --- between it and whatever it follows --- the entry before it, or the
    --- column heading the list opens under. A label has its lead on top.
    '<w:spacing w:before="%d" w:after="0" w:line="240" w:lineRule="auto"/>'
    .. '<w:ind w:left="%d" w:right="%d" w:hanging="%d"/>',
    276 + (entry.kind == "label" and twips(kLabelLead) or 0),
    indent + hanging, right, hanging)

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

-- Lines centred down the page with a rule under one of them as wide as the
-- widest. A paragraph's border runs from indent to indent whatever is in it,
-- and nothing here can measure the lines, so they are a table of two rows
-- that fits itself to what it holds: the lines over the rule in one, those
-- under it in the other, and the rule the border between, 0.5pt (w:sz is in
-- eighths of a point). The cells have no margins at the sides, so the lines
-- are set as the paragraphs around them would be, and 3pt at the rule, which
-- keeps it clear of the lines. The half line of space is the space before
-- the paragraph after it: half of the 276 twips a single line of 12pt Times
-- takes in word.
local function docx_notice(item)
  local cell_margins = '<w:tblCellMar><w:top w:w="0" w:type="dxa"/>'
    .. '<w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/>'
    .. '<w:right w:w="0" w:type="dxa"/></w:tblCellMar>'
  local function paragraph(lines, before)
    local runs = pandoc.List({})
    for i, line in ipairs(lines) do
      if i > 1 then runs:insert("<w:r><w:br/></w:r>") end
      runs:insert(docx_runs(line, false, false))
    end
    return table.concat({
      "<w:p><w:pPr>",
      string.format('<w:spacing w:before="%d" w:after="0" w:line="240"'
        .. ' w:lineRule="auto"/>', before),
      '<w:ind w:left="0" w:right="0" w:firstLine="0"/><w:jc w:val="center"/>',
      "</w:pPr>", table.concat(runs), "</w:p>",
    })
  end
  -- A cell of one or two paragraphs, with 3pt between it and the rule on
  -- the side the rule is.
  local function cell(groups, rule)
    local paragraphs = pandoc.List({})
    for i, lines in ipairs(groups) do
      if #lines > 0 then
        paragraphs:insert(paragraph(lines, i > 1 and 138 or 0))
      end
    end
    return table.concat({
      '<w:tr><w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>',
      rule == "below" and '<w:tcBorders><w:bottom w:val="single" w:sz="4"'
        .. ' w:space="0" w:color="auto"/></w:tcBorders>' or "",
      rule == "below" and '<w:tcMar><w:bottom w:w="60" w:type="dxa"/></w:tcMar>'
        or rule == "above" and '<w:tcMar><w:top w:w="60" w:type="dxa"/></w:tcMar>'
        or "",
      "</w:tcPr>", table.concat(paragraphs), "</w:tc></w:tr>",
    })
  end
  local first, second, below = pandoc.List({}), pandoc.List({}),
    pandoc.List({})
  for i, line in ipairs(item.lines) do
    local into = i <= item.space_after and first
      or i <= item.rule_after and second or below
    into:insert(line)
  end
  return table.concat({
    "<w:tbl><w:tblPr>",
    '<w:tblW w:w="0" w:type="auto"/><w:jc w:val="center"/>',
    -- No borders of its own, whatever table style the reference document
    -- makes the default, so that the rule is the only line drawn.
    '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/>',
    '<w:bottom w:val="nil"/><w:right w:val="nil"/>',
    '<w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders>',
    '<w:tblLayout w:type="autofit"/>', cell_margins,
    "</w:tblPr><w:tblGrid><w:gridCol/></w:tblGrid>",
    cell({ first, second }, #below > 0 and "below" or nil),
    #below > 0 and cell({ below }, "above") or "",
    "</w:tbl>",
  })
end

-- The title page as the .pdf sets it. latex adds the line spacing to a gap
-- written between two lines; word puts a gap above a paragraph and the top
-- of its line, and the baseline lies the line's ascent below that. What each
-- gap needs on top, by what stands before and after it, measured off both.
-- Only the title page is set this way; the pages after it were matched to
-- the .pdf on their own terms.
local kTitleSpace = {
  ["top>para"] = 31,
  ["para>rule"] = 8.5,
  ["rule>para"] = 3,
  ["para>para"] = 0.7,
}
-- And its single spacing the .pdf's 14.5pt: 252 is 1.05 of word's 13.8pt.
local kTitleLine = 252

local function title_space(before, after)
  return kTitleSpace[before .. ">" .. after] or 0
end

-- A frame as wide as the page's measure, on its bottom margin. Paragraphs
-- one after another with the same frame are one frame, so the lines after a
-- fill stand together with the last of them on the margin.
local function docx_frame(page)
  return string.format('<w:framePr w:w="%d" w:wrap="around"'
    .. ' w:vAnchor="margin" w:hAnchor="margin" w:x="0" w:yAlign="bottom"/>',
    twips(page.measure * 72))
end

local function render_docx(pages, meta)
  local out = pandoc.List({})
  local footers = reference_footers()
  local pending_anchor = ""

  for index, page in ipairs(pages) do
    local pending = 0
    local centred = false
    -- After a fill, the paragraphs that follow are a frame on the foot of
    -- the page (docx_frame).
    local framed = false
    -- The title page's single spacing is the .pdf's 14.5pt (kTitleSpace).
    local single = page.first and kTitleLine or 240
    -- A bookmark waiting for the next paragraph to mark.
    local function anchors()
      local held = pending_anchor
      pending_anchor = ""
      return held
    end
    -- exact, when given, is the height of each line in twips, whatever is in
    -- it. The frame, when there is one, comes first: the schema puts it
    -- ahead of the spacing.
    local function properties(extra, double, exact)
      local line = exact
        and string.format('w:line="%d" w:lineRule="exact"', exact)
        or string.format('w:line="%d" w:lineRule="auto"',
          double and 480 or single)
      local spacing = string.format(
        '<w:spacing w:before="%d" w:after="0" %s/>', twips(pending), line)
      pending = 0
      return "<w:pPr>" .. (framed and docx_frame(page) or "") .. spacing
        .. (extra or "") .. "</w:pPr>"
    end

    for i, item in ipairs(page.items) do
      if item.kind == "gap" then
        local points = item.points
        if page.first then
          local before = page.items[i - 1]
          local after = page.items[i + 1]
          points = points + title_space(before and before.kind or "top",
            after and after.kind or "end")
        end
        pending = pending + points
      elseif item.kind == "fill" then
        -- word has no space that grows to fill a page, so what follows is
        -- set in a frame on the bottom margin instead, and the frame keeps
        -- none of the space above it.
        framed = true
        pending = 0
      elseif item.kind == "rule" then
        -- A rule is a paragraph with a border under it, which is how word
        -- draws one. The indents narrow the paragraph to the rule's width.
        -- Its one line is next to nothing high, so that the border stands
        -- where the space above it ends: on a line of its own height it
        -- stood a line lower, and the words between two rules sat nearer the
        -- upper one than the lower.
        local inset = twips((page.measure - item.width) / 2 * 72)
        local extra = '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="0"'
          .. ' w:color="auto"/></w:pBdr>'
          .. string.format('<w:ind w:left="%d" w:right="%d"/>', inset, inset)
        out:insert(raw("openxml",
          "<w:p>" .. properties(extra, false, 20) .. anchors() .. "</w:p>"))
      elseif item.kind == "para" then
        local jc = string.format('<w:jc w:val="%s"/>',
          item.align == "center" and "center"
            or item.align == "right" and "right" or "left")
        if item.hanging then
          -- A paragraph a line, each turning under itself.
          local hang = twips(item.hanging * 72)
          local extra = jc .. string.format('<w:ind w:left="%d" w:hanging="%d"/>',
            twips((item.indent or 0) * 72) + hang, hang)
          for _, line in ipairs(item.lines) do
            out:insert(raw("openxml",
              "<w:p>" .. properties(extra, item.double) .. anchors()
              .. docx_runs(line, item.bold, false) .. "</w:p>"))
          end
        else
          local runs = pandoc.List({})
          for i, line in ipairs(item.lines) do
            if i > 1 then runs:insert("<w:r><w:br/></w:r>") end
            runs:insert(docx_runs(line, item.bold, false))
          end
          local extra = jc
          if item.indent then
            extra = extra .. string.format('<w:ind w:left="%d"/>',
              twips(item.indent * 72))
          end
          out:insert(raw("openxml",
            "<w:p>" .. properties(extra, item.double) .. anchors()
            .. table.concat(runs) .. "</w:p>"))
        end
      elseif item.kind == "notice" then
        out:insert(raw("openxml", docx_notice(item)))
        centred = true
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
    out:insert(raw("openxml",
      docx_section(page, footers, index == 1, centred)))
  end
  return out
end

return { render = render_docx }

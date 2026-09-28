-- The front matter of a Temple University dissertation or thesis.
--
-- documentmode: thesis is APA manuscript mode with a front matter of its
-- own. Two pages of it are built so far:
--
--   i   the title page --- the title in capitals in an inverted pyramid,
--       three centred blocks under it saying what the work is, what degree
--       it answers to and who wrote it, each set off by a rule, and the
--       examining committee flush left at the foot
--   ii  the copyright page
--
-- and the numbering that holds them together: the front matter in lower-case
-- roman, the title page counted as i but carrying no number, and the body
-- beginning again at 1 in arabic. There is no running head anywhere; the
-- number sits at the centre of the foot, which is where the dissertations
-- Temple publishes put it.
--
-- The pages are built here for all four formats rather than left to each of
-- them. The lines of the title have to be worked out once --- see
-- thesistitle.lua, and a .docx can measure nothing while it is being written
-- --- so the same lines and the same spacing go to every format.

local utilsapa = require("utilsapa")
local thesistitle = require("thesistitle")
local stringify = utilsapa.stringify

-- The margins the handbook asks for, which every page but the first takes.
local kMargins = utilsapa.thesis_margins
-- The title page is set on 1" all round, which is what the dissertations
-- Temple publishes do and what the Graduate School's template draws: the
-- block of the page stands at the centre of the paper rather than at the
-- centre of a text block pushed right by the binding margin. So the title is
-- broken against the measure the title page has, not the one the body has.
local kTitleMargins = utilsapa.thesis_title_margins
local kMeasureInches = utilsapa.thesis_title_measure()
local kBodyMeasureInches = utilsapa.thesis_measure()
local kTitleSize = 12
-- The measure in thousandths of an em of the title's own size, which is what
-- thesistitle measures a word in.
local kMeasure = kMeasureInches * 72 / kTitleSize * 1000

-- The rule under each block: the width the Graduate School's template draws.
local kRuleWidth = 5.5
local kRuleSpace = 21        -- points above and below each rule
local kTitleDrop = 70        -- points from the top margin down to the title
local kCommitteeDrop = 70    -- points from the last block down to the committee
local kLineSpace = 13.8      -- a single-spaced line of 12pt Times
local kDoubleSpace = 27.6    -- and a double-spaced one
-- Where the copyright notice sits: far enough down the page to read as a
-- page of its own rather than as a heading, which is where the Graduate
-- School's template puts it.
local kCopyrightDrop = 289

local function language(meta, key, fallback)
  if meta.language and meta.language[key] then
    return stringify(meta.language[key])
  end
  return fallback
end

-- A field of the thesis block, as inlines, or nil when it was not written.
local function field(thesis, key)
  if thesis == nil or thesis[key] == nil then return nil end
  local value = thesis[key]
  if stringify(value) == "false" then return nil end
  if value.t == "MetaInlines" then return pandoc.Inlines(value) end
  return pandoc.Inlines({ pandoc.Str(stringify(value)) })
end

local function text(str)
  return pandoc.Inlines({ pandoc.Str(str) })
end

-- "Mentor's Name, Advisory Chair, TU Department": whichever of the three the
-- entry carries, in that order, separated by commas.
local function committee_line(member)
  local parts = pandoc.List({})
  for _, key in ipairs({ "name", "role", "affiliation" }) do
    local value = field(member, key)
    if value and #value > 0 then parts:insert(value) end
  end
  local out = pandoc.Inlines({})
  for i, part in ipairs(parts) do
    if i > 1 then
      out:insert(pandoc.Str(","))
      out:insert(pandoc.Space())
    end
    out:extend(part)
  end
  return out
end

-- The author, as the title page names them: one writer, written out.
local function author_inlines(meta)
  local byauthor = meta["by-author"]
  if byauthor and byauthor[1] then
    local name = byauthor[1].name
    if name then
      if name.literal then return pandoc.Inlines(name.literal) end
      return text(stringify(name))
    end
  end
  if meta.apaauthor and meta.apaauthor[1] and meta.apaauthor[1].name then
    return text(stringify(meta.apaauthor[1].name))
  end
  return nil
end

-- The lines of the title: the writer's own where they broke it themselves,
-- and an inverted pyramid where they did not.
local function title_lines(meta)
  local title = meta.apatitledisplay or meta.title
  if title == nil then return pandoc.List({}) end
  local inlines = thesistitle.upper(pandoc.Inlines(title))
  local written = thesistitle.written_lines(inlines)
  if written then return written end
  return thesistitle.pyramid(inlines, kMeasure)
end

-- Collecting what goes on a page -------------------------------------------
--
-- A page is a list of things to set: a gap of so many points, a rule, or a
-- paragraph of one or more lines, centred or flush left. Every format is
-- handed the same list.

local function collector()
  local items = pandoc.List({})
  return items, {
    gap = function(points)
      items:insert({ kind = "gap", points = points })
    end,
    rule = function()
      items:insert({ kind = "rule" })
    end,
    para = function(align, lines, bold, double)
      local kept = pandoc.List({})
      for _, line in ipairs(lines) do
        if line and #line > 0 then kept:insert(line) end
      end
      if #kept > 0 then
        items:insert({ kind = "para", align = align, lines = kept,
          bold = bold, double = double })
      end
      return #kept > 0
    end,
  }
end

local function title_page(meta)
  local thesis = meta.thesis
  local items, add = collector()

  add.gap(kTitleDrop)
  add.para("center", title_lines(meta), true)

  -- What the work is: "A Dissertation / Submitted to / the Temple University
  -- Graduate Board".
  local kind = field(thesis, "type") or text("Dissertation")
  local what = pandoc.Inlines({
    pandoc.Str(language(meta, "thesis-article", "A")), pandoc.Space() })
  what:extend(kind)
  add.gap(kRuleSpace)
  add.rule()
  add.gap(kRuleSpace)
  add.para("center", {
    what,
    text(language(meta, "thesis-submitted-to", "Submitted to")),
    field(thesis, "submitted-to")
      or text("the Temple University Graduate Board"),
  })

  -- What degree it answers to.
  local degree = field(thesis, "degree")
  if degree then
    add.gap(kRuleSpace)
    add.rule()
    add.gap(kRuleSpace)
    add.para("center", {
      text(language(meta, "thesis-fulfillment", "In Partial Fulfillment")),
      text(language(meta, "thesis-requirements",
        "of the Requirements for the Degree")),
      degree,
    })
  end

  -- Who wrote it, and when they take the degree.
  local author = author_inlines(meta)
  if author then
    add.gap(kRuleSpace)
    add.rule()
    add.gap(kRuleSpace)
    add.para("center", {
      text(language(meta, "thesis-by", "by")),
      author,
      field(thesis, "date"),
    })
  end

  -- The examining committee, flush left at the foot of the page.
  local committee = thesis and thesis.committee
  if committee and #committee > 0 then
    local lines = pandoc.List({})
    for _, member in ipairs(committee) do
      lines:insert(committee_line(member))
    end
    add.gap(kCommitteeDrop)
    add.para("left", { text(language(meta, "thesis-committee",
      "Examining Committee Members:")) })
    add.gap(kLineSpace)
    add.para("left", lines)
  end

  return items
end

-- The year the work is copyrighted, which is the year it is submitted. Taken
-- from copyright where it is written and from the diploma date where it is
-- not, since that is the year either way. copyright: false leaves the page
-- out altogether.
local function copyright_year(thesis)
  if thesis == nil then return nil end
  if thesis.copyright ~= nil then
    local written = stringify(thesis.copyright)
    if written == "false" then return nil end
    if written ~= "" and written ~= "true" then return written end
  end
  local date = thesis.date and stringify(thesis.date) or ""
  return date:match("(%d%d%d%d)")
end

local function copyright_page(meta)
  local thesis = meta.thesis
  local year = copyright_year(thesis)
  local author = author_inlines(meta)
  if year == nil or author == nil then return nil end

  local items, add = collector()
  local notice = pandoc.Inlines({
    pandoc.Str("\u{00A9}"), pandoc.Space(),
    pandoc.Str(language(meta, "thesis-copyright", "Copyright")), pandoc.Space(),
    pandoc.Str(year), pandoc.Space(),
    pandoc.Str(language(meta, "thesis-copyright-by", "by")), pandoc.Space(),
  })
  notice:extend(author)

  add.gap(kCopyrightDrop)
  add.para("center", {
    notice,
    text(language(meta, "thesis-rights-reserved", "All Rights Reserved")),
  }, false, true)
  return items
end

-- The front matter, page by page. Each page says what margins it is set on
-- and whether it carries its number; the numbering itself is lower-case
-- roman throughout, and the body that follows begins again at 1 in arabic.
local function build_pages(meta)
  local pages = pandoc.List({})
  local title = title_page(meta)
  if #title > 0 then
    pages:insert({
      margins = kTitleMargins,
      measure = kMeasureInches,
      numbered = false,
      first = true,
      items = title,
    })
  end
  local copyright = copyright_page(meta)
  if copyright then
    pages:insert({
      margins = kMargins,
      measure = kBodyMeasureInches,
      numbered = true,
      items = copyright,
    })
  end
  return pages
end

-- Renderers ------------------------------------------------------------------

local function written(inlines, format)
  local out = pandoc.write(
    pandoc.Pandoc({ pandoc.Plain(inlines) }), format)
  return (out:gsub("%s+$", ""))
end

local function raw(format, s)
  return pandoc.RawBlock(format, s)
end

-- latex. setspace is loaded by apalatex.tex, so the pages can be set single
-- spaced inside a group and leave the body's spacing alone. geometry's
-- \newgeometry sets a page's own margins and \restoregeometry gives the body
-- back the ones the document asked for.
local function render_latex(pages)
  local out = pandoc.List({})
  -- No running head, the page number at the centre of the foot, and the
  -- front matter numbered in lower-case roman. The title page is page i and
  -- is counted, which is why the numbering starts before it.
  out:insert(raw("latex", "\\apathesishead\\pagenumbering{roman}"))
  out:insert(raw("latex", "\\begingroup\\linespread{1}\\selectfont"))

  local geometry = nil
  for _, page in ipairs(pages) do
    local wanted = string.format(
      "\\newgeometry{left=%.2fin,right=%.2fin,top=%.2fin,bottom=%.2fin}",
      page.margins.left, page.margins.right,
      page.margins.top, page.margins.bottom)
    if wanted ~= geometry then
      out:insert(raw("latex", wanted))
      -- Asking for the single spacing again, because a change of geometry
      -- puts the line spacing back to the document's. Without this the front
      -- matter came out double spaced however it was asked not to, and the
      -- title page ran onto a second page.
      out:insert(raw("latex", "\\linespread{1}\\selectfont"))
      geometry = wanted
    end
    if not page.numbered then
      out:insert(raw("latex", "\\thispagestyle{empty}"))
    end
    for _, item in ipairs(page.items) do
      if item.kind == "gap" then
        out:insert(raw("latex",
          string.format("\\vspace*{%.1fpt}", item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("latex", string.format(
          "{\\centering\\noindent\\rule{%.2fin}{0.5pt}\\par}", kRuleWidth)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "latex"))
        end
        local separator = item.double
          and string.format("\\\\[%.1fpt]\n", kDoubleSpace - kLineSpace)
          or "\\\\\n"
        local body = table.concat(lines, separator)
        if item.bold then body = "\\bfseries " .. body end
        local align = item.align == "center" and "\\centering"
          or "\\raggedright\\noindent"
        out:insert(raw("latex", "{" .. align .. "\n" .. body .. "\\par}"))
      end
    end
    out:insert(raw("latex", "\\clearpage"))
  end

  -- The body begins again at 1, in arabic, which is what \pagenumbering does
  -- to the counter as well as to the shape of the numeral.
  out:insert(raw("latex",
    "\\endgroup\\restoregeometry\\pagenumbering{arabic}"))
  return out
end

-- typst. #page with a body sets those pages on their own: their own margins,
-- and for the title page no footer at all, which is what leaves it
-- unnumbered. What comes after begins a new page, so no page break has to be
-- written.
local function render_typst(pages)
  local out = pandoc.List({})
  for _, page in ipairs(pages) do
    out:insert(raw("typst", string.format(
      "#page(margin: (left: %.2fin, right: %.2fin, top: %.2fin, bottom: %.2fin)%s)[\n",
      page.margins.left, page.margins.right,
      page.margins.top, page.margins.bottom,
      page.numbered and "" or ", header: none, footer: none, numbering: none")))
    out:insert(raw("typst",
      "#[\n#set par(first-line-indent: 0pt, justify: false)\n"
      -- The page carries its own spacing, in the gaps written between the
      -- blocks, so the space the body puts between one block and the next is
      -- taken off. Left on, it fell between every part of the page as well.
      .. "#set block(spacing: 0pt)\n"))
    for _, item in ipairs(page.items) do
      if item.kind == "gap" then
        out:insert(raw("typst",
          string.format("#v(%.1fpt, weak: false)", item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("typst", string.format(
          "#align(center)[#line(length: %.2fin, stroke: 0.5pt)]", kRuleWidth)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "typst"))
        end
        local body = table.concat(lines, " \\\n")
        if item.bold then body = "#strong[" .. body .. "]" end
        -- A single-spaced paragraph says so; a double-spaced one keeps the
        -- leading the document is set in, which in this mode is double.
        if not item.double then
          body = "#par(leading: 0.65em)[" .. body .. "]"
        end
        out:insert(raw("typst",
          "#align(" .. item.align .. ")[" .. body .. "]"))
      end
    end
    out:insert(raw("typst", "]\n]\n"))
  end
  -- The front matter is numbered in lower-case roman, which the thesis
  -- layout sets; the body begins again at 1 in arabic.
  out:insert(raw("typst",
    "\n#set page(numbering: \"1\")\n#counter(page).update(1)\n"))
  return out
end

-- html. There are no pages here, so the gaps are the only thing that carries
-- the arrangement across, and there is nothing to number.
local function render_html(pages)
  local out = pandoc.List({})
  for _, page in ipairs(pages) do
    out:insert(raw("html", '<div class="thesis-front-matter-page">'))
    for _, item in ipairs(page.items) do
      if item.kind == "gap" then
        out:insert(raw("html", string.format(
          '<div style="height:%.1fpt"></div>', item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("html", string.format(
          '<hr style="width:%.2fin;margin:0 auto;border:none;'
          .. 'border-top:0.5pt solid currentColor">', kRuleWidth)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "html"))
        end
        local body = table.concat(lines, "<br>\n")
        if item.bold then body = "<strong>" .. body .. "</strong>" end
        out:insert(raw("html", '<p style="text-align:' .. item.align ..
          ";margin:0;text-indent:0;line-height:" ..
          (item.double and "2" or "1.15") .. '">' .. body .. "</p>"))
      end
    end
    out:insert(raw("html", "</div>"))
  end
  return out
end

-- docx -----------------------------------------------------------------------
--
-- Written as word markup so that the spacing is exact and the pages still
-- read as ordinary paragraphs a writer can edit in word.

local function xml_escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function docx_runs(inlines, bold, italic)
  local out = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local properties = {}
      if bold then properties[#properties + 1] = "<w:b/>" end
      if italic then properties[#properties + 1] = "<w:i/>" end
      local rpr = ""
      if #properties > 0 then
        rpr = "<w:rPr>" .. table.concat(properties) .. "</w:rPr>"
      end
      out[#out + 1] = "<w:r>" .. rpr .. '<w:t xml:space="preserve">'
        .. xml_escape(inline.text) .. "</w:t></w:r>"
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      out[#out + 1] = '<w:r><w:t xml:space="preserve"> </w:t></w:r>'
    elseif inline.t == "Strong" then
      out[#out + 1] = docx_runs(inline.content, true, italic)
    elseif inline.t == "Emph" then
      out[#out + 1] = docx_runs(inline.content, bold, true)
    elseif inline.content then
      out[#out + 1] = docx_runs(inline.content, bold, italic)
    else
      out[#out + 1] = "<w:r>" .. '<w:t xml:space="preserve">'
        .. xml_escape(pandoc.utils.stringify(inline)) .. "</w:t></w:r>"
    end
  end
  return table.concat(out)
end

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
  local refdoc = PANDOC_WRITER_OPTIONS.reference_doc
  if not refdoc then return "" end
  local f = io.open(refdoc, "rb")
  if not f then return "" end
  local data = f:read("a")
  f:close()
  local ok, archive = pcall(pandoc.zip.Archive, data)
  if not ok then return "" end
  for _, entry in ipairs(archive.entries) do
    if entry.path == "word/document.xml" then
      local sect = entry:contents():match("<w:sectPr.-</w:sectPr>")
      if not sect then return "" end
      local found = {}
      for element in sect:gmatch("<w:footerReference[^>]*/>") do
        found[#found + 1] = element
      end
      return table.concat(found)
    end
  end
  return ""
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

local function render_docx(pages)
  local out = pandoc.List({})
  local footers = reference_footers()

  for index, page in ipairs(pages) do
    local pending = 0
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
        local inset = twips((page.measure - kRuleWidth) / 2 * 72)
        local extra = '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="0"'
          .. ' w:color="auto"/></w:pBdr>'
          .. string.format('<w:ind w:left="%d" w:right="%d"/>', inset, inset)
        out:insert(raw("openxml", "<w:p>" .. properties(extra) .. "</w:p>"))
      elseif item.kind == "para" then
        local runs = pandoc.List({})
        for i, line in ipairs(item.lines) do
          if i > 1 then runs:insert("<w:r><w:br/></w:r>") end
          runs:insert(docx_runs(line, item.bold, false))
        end
        local extra = item.align == "center"
          and '<w:jc w:val="center"/>' or '<w:jc w:val="left"/>'
        out:insert(raw("openxml",
          "<w:p>" .. properties(extra, item.double)
          .. table.concat(runs) .. "</w:p>"))
      end
    end
    out:insert(raw("openxml", docx_section(page, footers, index == 1)))
  end
  return out
end

local renderers = {
  latex = render_latex,
  html = render_html,
  docx = render_docx,
}

-- ----------------------------------------------------------------------------

local function is_thesis(meta)
  return meta.documentmode ~= nil and stringify(meta.documentmode) == "thesis"
end

-- The margins the handbook asks for. Quarto's pdf format sets 1" all round
-- for an APA manuscript; a dissertation is bound at the left and wants more
-- there. typst takes its margins from the thesis layout in
-- typst-template.typ, and .docx from its reference document.
function Meta(meta)
  if not is_thesis(meta) then return nil end
  if FORMAT == "latex" then
    meta.geometry = pandoc.MetaList({
      pandoc.MetaString(string.format("left=%.2fin", kMargins.left)),
      pandoc.MetaString(string.format("right=%.2fin", kMargins.right)),
      pandoc.MetaString(string.format("top=%.2fin", kMargins.top)),
      pandoc.MetaString(string.format("bottom=%.2fin", kMargins.bottom)),
    })
  end
  return meta
end

function Pandoc(doc)
  if not is_thesis(doc.meta) then return nil end
  local render = FORMAT:match("typst") and render_typst or renderers[FORMAT]
  if render == nil then return nil end

  local pages = build_pages(doc.meta)
  if #pages == 0 then return nil end

  local blocks = pandoc.List({})
  blocks:extend(render(pages))
  blocks:extend(doc.blocks)
  doc.blocks = blocks
  return doc
end

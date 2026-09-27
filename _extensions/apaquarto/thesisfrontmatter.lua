-- The title page of a Temple University dissertation or thesis.
--
-- documentmode: thesis is APA manuscript mode with a front matter of its
-- own, and this is the first page of it. The arrangement is the Graduate
-- School's: the title in capitals in an inverted pyramid, three centred
-- blocks under it saying what the work is, what degree it answers to and who
-- wrote it, each set off by a rule, and the examining committee flush left
-- at the foot.
--
-- The page is built here for all four formats rather than left to each of
-- them. The lines of the title have to be worked out once --- see
-- thesistitle.lua, and a .docx can measure nothing while it is being written
-- --- so the same lines and the same spacing go to every format and the page
-- comes out the same in all four.

local utilsapa = require("utilsapa")
local thesistitle = require("thesistitle")
local stringify = utilsapa.stringify

local kModes = { docx = true, latex = true, html = true, typst = true }

-- The measure the title is broken against. The margins that give it are in
-- utilsapa, where the pdf and the .docx read them as well.
local kMargins = utilsapa.thesis_margins
local kMeasureInches = utilsapa.thesis_measure()
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
  if type(value) == "table" and value.t == nil then
    -- A MetaList or MetaMap where inlines were wanted
    return pandoc.Inlines({ pandoc.Str(stringify(value)) })
  end
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

-- The page, as a list of things to set: a gap of so many points, a rule, or
-- a paragraph of one or more lines, centred or flush left. Each format is
-- handed this same list.
local function build_items(meta)
  local thesis = meta.thesis
  local items = pandoc.List({})

  local function gap(points)
    items:insert({ kind = "gap", points = points })
  end
  local function rule()
    items:insert({ kind = "rule" })
  end
  local function para(align, lines, bold)
    local kept = pandoc.List({})
    for _, line in ipairs(lines) do
      if line and #line > 0 then kept:insert(line) end
    end
    if #kept > 0 then
      items:insert({ kind = "para", align = align, lines = kept, bold = bold })
    end
    return #kept > 0
  end

  gap(kTitleDrop)
  para("center", title_lines(meta), true)

  -- What the work is: "A Dissertation / Submitted to / the Temple University
  -- Graduate Board".
  local kind = field(thesis, "type") or text("Dissertation")
  local article = language(meta, "thesis-article", "A")
  local what = pandoc.Inlines({ pandoc.Str(article), pandoc.Space() })
  what:extend(kind)
  local board = field(thesis, "submitted-to")
    or text("the Temple University Graduate Board")
  gap(kRuleSpace)
  rule()
  gap(kRuleSpace)
  para("center", {
    what,
    text(language(meta, "thesis-submitted-to", "Submitted to")),
    board,
  })

  -- What degree it answers to.
  local degree = field(thesis, "degree")
  if degree then
    gap(kRuleSpace)
    rule()
    gap(kRuleSpace)
    para("center", {
      text(language(meta, "thesis-fulfillment", "In Partial Fulfillment")),
      text(language(meta, "thesis-requirements",
        "of the Requirements for the Degree")),
      degree,
    })
  end

  -- Who wrote it, and when they take the degree.
  local author = author_inlines(meta)
  if author then
    gap(kRuleSpace)
    rule()
    gap(kRuleSpace)
    para("center", {
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
    gap(kCommitteeDrop)
    para("left", { text(language(meta, "thesis-committee",
      "Examining Committee Members:")) })
    gap(kLineSpace)
    para("left", lines)
  end

  return items
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

-- latex. setspace is loaded by apalatex.tex, so the page can be set single
-- spaced inside a group and leave the body's spacing alone.
local function render_latex(items)
  local out = pandoc.List({})
  out:insert(raw("latex", "\\begingroup\\setstretch{1}\\thispagestyle{empty}"))
  for _, item in ipairs(items) do
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
      local body = table.concat(lines, "\\\\\n")
      if item.bold then body = "\\bfseries " .. body end
      local align = item.align == "center" and "\\centering"
        or "\\raggedright\\noindent"
      out:insert(raw("latex", "{" .. align .. "\n" .. body .. "\\par}"))
    end
  end
  out:insert(raw("latex", "\\endgroup\\clearpage"))
  return out
end

-- typst. The page is set inside a block of its own so that the leading and
-- the paragraph indent it wants do not reach the body.
local function render_typst(items)
  local out = pandoc.List({})
  out:insert(raw("typst",
    "#[\n#set par(leading: 0.65em, first-line-indent: 0pt, justify: false)\n"
    -- The page carries its own spacing, in the gaps written between the
    -- blocks, so the space the body puts between one block and the next is
    -- taken off. Left on, it fell between every part of the page as well.
    .. "#set block(spacing: 0pt)\n"))
  for _, item in ipairs(items) do
    if item.kind == "gap" then
      out:insert(raw("typst", string.format("#v(%.1fpt, weak: false)", item.points)))
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
      out:insert(raw("typst",
        "#align(" .. item.align .. ")[" .. body .. "]"))
    end
  end
  out:insert(raw("typst", "]\n#pagebreak(weak: false)"))
  return out
end

-- html. There are no pages here, so the gaps are the only thing that carries
-- the arrangement across.
local function render_html(items)
  local out = pandoc.List({})
  out:insert(raw("html", '<div class="thesis-title-page">'))
  for _, item in ipairs(items) do
    if item.kind == "gap" then
      out:insert(raw("html", string.format(
        '<div style="height:%.1fpt"></div>', item.points)))
    elseif item.kind == "rule" then
      out:insert(raw("html", string.format(
        '<hr style="width:%.2fin;margin:0 auto;border:none;border-top:0.5pt solid currentColor">',
        kRuleWidth)))
    elseif item.kind == "para" then
      local lines = pandoc.List({})
      for _, line in ipairs(item.lines) do
        lines:insert(written(line, "html"))
      end
      local body = table.concat(lines, "<br>\n")
      if item.bold then body = "<strong>" .. body .. "</strong>" end
      out:insert(raw("html", '<p style="text-align:' .. item.align ..
        ';margin:0;text-indent:0">' .. body .. "</p>"))
    end
  end
  out:insert(raw("html", "</div>"))
  return out
end

-- docx. Written as word markup so that the spacing is exact and the page
-- still reads as ordinary paragraphs a writer can edit in word.
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

local function render_docx(items)
  local out = pandoc.List({})
  local pending = 0
  local function properties(extra)
    local spacing = string.format(
      '<w:spacing w:before="%d" w:after="0" w:line="240" w:lineRule="auto"/>',
      twips(pending))
    pending = 0
    return "<w:pPr>" .. spacing .. (extra or "") .. "</w:pPr>"
  end

  for _, item in ipairs(items) do
    if item.kind == "gap" then
      pending = pending + item.points
    elseif item.kind == "rule" then
      -- A rule is a paragraph with a border under it, which is how word
      -- draws one. The indents narrow the paragraph to the rule's width.
      local inset = twips((kMeasureInches - kRuleWidth) / 2 * 72)
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
        "<w:p>" .. properties(extra) .. table.concat(runs) .. "</w:p>"))
    end
  end
  out:insert(raw("openxml",
    '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
  return out
end

local renderers = {
  latex = render_latex,
  typst = render_typst,
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
  local render = renderers[FORMAT:match("^%a+")] or renderers[FORMAT]
  if FORMAT:match("typst") then render = render_typst end
  if render == nil then return nil end

  local items = build_items(doc.meta)
  if #items == 0 then return nil end

  local page = render(items)
  local blocks = pandoc.List({})
  blocks:extend(page)
  blocks:extend(doc.blocks)
  doc.blocks = blocks
  return doc
end

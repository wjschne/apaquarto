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
local thesiscontents = require("thesiscontents")
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
local kDedicationDrop = 164  -- points from the top margin to a dedication
-- The examining committee begins where the rules above it begin, rather
-- than out at the margin: the rules are narrower than the measure and are
-- centred in it, so this is the half-inch that leaves on either side.
local kCommitteeIndent = (kMeasureInches - kRuleWidth) / 2
local kDoubleSpace = 27.6    -- and a double-spaced one
-- From the abstract heading down to the first line of the abstract, which
-- is a blank double-spaced line between them.
local kAbstractGap = 27.6
-- Where the copyright notice sits: far enough down the page to read as a
-- page of its own rather than as a heading, which is where the Graduate
-- School's template puts it.
local kCopyrightDrop = 289
-- The column of page numbers is at the right margin and the leader dots run
-- out to meet it, so a line of the contents is as wide as the measure.
local kNumberColumn = 0.25   -- inches from a chapter number to its title
local kSubheadingStep = 0.5  -- inches a level of subheading is indented
-- A line of the contents is a block of its own, and typst measures such a
-- block by the glyphs in it rather than by the line it sits on --- about 8
-- points at 12pt Times --- so the space above it is what settles how far
-- apart two entries are. This leaves a double-spaced line between them.
local kContentsLead = kDoubleSpace - 8.2

-- The colour the entries of a contents take, which is quarto's toccolor.
--
-- Black unless a document asks otherwise. They are links, and a link would
-- otherwise take linkcolor and leave the contents reading as a page of
-- cross references rather than as a list. This is what the lists apaquarto
-- builds for its other modes already do; a dissertation's are built here and
-- had been taking the link colour.
-- Whether a document asks for one of the four lists.
--
-- All four are set in a dissertation unless it says otherwise, which is the
-- other way round from the rest of apaquarto: the Graduate School expects a
-- contents and a list for each kind of float, so the field says what to
-- leave out rather than what to put in.
--
-- A list with nothing in it is left out whatever the field says. A heading
-- reading LIST OF TABLES over an empty page helps nobody, and the handbook's
-- own template says as much: "if no tables, delete this page".
local function wants_list(meta, field)
  local asked = meta[field]
  if asked == nil then return true end
  return stringify(asked) ~= "false"
end

-- What the field for a kind of float is called: list-of-tables for a Table,
-- list-of-illustrations for an Illustration.
local function list_field(kind)
  return "list-of-" .. pandoc.text.lower(kind) .. "s"
end

local function contents_colour(meta)
  return utilsapa.colour_hex(meta and meta.toccolor) or "000000"
end

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
    para = function(align, lines, options)
      options = options or {}
      local kept = pandoc.List({})
      for _, line in ipairs(lines) do
        if line and #line > 0 then kept:insert(line) end
      end
      if #kept > 0 then
        items:insert({ kind = "para", align = align, lines = kept,
          bold = options.bold, double = options.double,
          indent = options.indent })
      end
      return #kept > 0
    end,
    -- The lines of a table of contents, each with its leader dots and the
    -- page it points at. What the entries are is thesiscontents.lua's; how
    -- they are set is each format's.
    contents = function(entries)
      if entries and #entries > 0 then
        items:insert({ kind = "contents", entries = entries })
      end
    end,
    -- The two column labels a list stands under: what the list is of at the
    -- left margin, and Page at the right.
    columns = function(left, right)
      items:insert({ kind = "columns", left = left, right = right })
    end,
    -- A mark a page can be pointed at, for a contents entry to reference.
    anchor = function(name)
      items:insert({ kind = "anchor", name = name })
    end,
    -- Prose that flows, rather than lines set where they are put: the
    -- abstract, which runs as long as it runs and may take a second page.
    -- The blocks are the document's own and every format writes them as it
    -- writes any other prose.
    blocks = function(blocks)
      if blocks and #blocks > 0 then
        items:insert({ kind = "blocks", blocks = pandoc.Blocks(blocks) })
      end
    end,
  }
end

local function title_page(meta)
  local thesis = meta.thesis
  local items, add = collector()

  add.gap(kTitleDrop)
  add.para("center", title_lines(meta), { bold = true })

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
      "Examining Committee Members:")) }, { indent = kCommitteeIndent })
    add.gap(kLineSpace)
    add.para("left", lines, { indent = kCommitteeIndent })
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
  }, { double = true })
  return items
end

-- The table of contents.
--
-- "Page" stands at the right margin under the heading, the front matter is
-- listed first, then the chapters under a label reading CHAPTER, then the
-- back matter. The copyright page is not listed and neither is this page,
-- which is what the handbook asks.
local function contents_page(meta, front, body)
  if #front == 0 and #body == 0 then return nil end

  local items, add = collector()
  add.para("center", { text(language(meta, "thesis-contents",
    "TABLE OF CONTENTS")) }, { bold = true })
  add.gap(kAbstractGap)
  add.para("right", { text(language(meta, "thesis-page-column", "Page")) })

  local entries = pandoc.List({})
  entries:extend(front)
  entries:extend(body)
  add.contents(entries)
  return items
end

-- A list of tables, of figures, or of whatever else the document declares.
--
-- The same shape as the contents and for the same reason: the handbook asks
-- for the entries at the left margin with leader dots out to the page
-- numbers, and a front matter that is consistent with itself is easier to
-- defend than one that is not. Above the entries stand two column labels ---
-- what the list is of, and Page.
--
-- The heading is the kind in the plural and in capitals: LIST OF TABLES.
-- language can name it, for a kind whose plural is not its word and an s.
local function list_page(meta, kind, entries)
  if #entries == 0 then return nil end

  local key = "thesis-list-of-" .. kind:lower()
  local heading = language(meta, key,
    "LIST OF " .. pandoc.text.upper(kind) .. "S")

  local items, add = collector()
  add.para("center", { text(heading) }, { bold = true })
  add.gap(kAbstractGap)
  add.columns(text(kind), text(language(meta, "thesis-page-column", "Page")))
  add.contents(entries)
  return items
end

-- The front matter, page by page. Each page says what margins it is set on
-- and whether it carries its number; the numbering itself is lower-case
-- roman throughout, and the body that follows begins again at 1 in arabic.
-- Metadata that is prose, as blocks. A field written as a yaml string comes
-- through as inlines and one written as a block comes through as blocks, and
-- a page wants the same thing from either.
local function prose(value)
  if value == nil then return nil end
  local first = value[1]
  if first == nil then return nil end
  if first.t == "Para" or first.t == "Plain" or first.t == "BlockQuote"
      or first.t == "Div" or first.t == "LineBlock" then
    return pandoc.Blocks(value)
  end
  return pandoc.Blocks({ pandoc.Para(pandoc.Inlines(value)) })
end

-- A page of prose under a heading of its own: the abstract, and the
-- acknowledgments after it. The heading is in capitals and centred, a blank
-- double-spaced line stands under it, and the prose runs as long as it runs
-- and takes a second page where it needs one.
--
-- The Graduate School's own template sets these two pages differently from
-- one another --- its abstract begins at the margin and its acknowledgments
-- are indented, and the air under the heading is not the same on both. They
-- are set alike here: a front matter that is consistent with itself is
-- easier to defend than one that copies a template's slips.
local function prose_page(written, heading)
  local blocks = prose(written)
  if blocks == nil then return nil end

  local items, add = collector()
  add.para("center", { text(heading) }, { bold = true })
  add.gap(kAbstractGap)
  add.blocks(blocks)
  return items
end

-- apastriptitle.lua keeps a copy of the abstract in apaabstract, which is the
-- one to read: the .docx has its abstract taken off the metadata so that
-- pandoc does not set one of its own.
local function abstract_page(meta)
  return prose_page(meta.apaabstract or meta.abstract,
    language(meta, "thesis-abstract", "ABSTRACT"))
end

-- Acknowledgments, which the Graduate School spells without an e in the
-- middle. The field is read either way, since a writer may not.
local function acknowledgments_page(meta)
  local thesis = meta.thesis
  local written = meta.acknowledgments or meta.acknowledgements
    or (thesis and (thesis.acknowledgments or thesis.acknowledgements))
  return prose_page(written,
    language(meta, "thesis-acknowledgments", "ACKNOWLEDGMENTS"))
end

-- The dedication, which carries no heading: it is a page with a line or two
-- on it, centred and set well down the page.
local function dedication_page(meta)
  local thesis = meta.thesis
  local written = meta.dedication or (thesis and thesis.dedication)
  local blocks = prose(written)
  if blocks == nil then return nil end

  local lines = pandoc.List({})
  for _, block in ipairs(blocks) do
    if block.content then lines:insert(pandoc.Inlines(block.content)) end
  end

  local items, add = collector()
  add.gap(kDedicationDrop)
  add.para("center", lines, { double = true })
  return items
end

local function build_pages(meta, blocks)
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

  -- The order the handbook sets for the front matter: the copyright page,
  -- the abstract, the dedication, the acknowledgments, the contents. Each is
  -- left out when the document gives it nothing to set, and the numbering
  -- runs on over whatever is there.
  --
  -- The copyright page is not listed in the contents and the contents does
  -- not list itself, so those two carry no anchor and no entry of their own.
  local specs = {
    { build = copyright_page },
    { build = abstract_page, anchor = "apathesis-abstract",
      listed = "thesis-abstract", fallback = "ABSTRACT" },
    { build = dedication_page, anchor = "apathesis-dedication",
      listed = "thesis-dedication", fallback = "DEDICATION" },
    { build = acknowledgments_page, anchor = "apathesis-acknowledgments",
      listed = "thesis-acknowledgments", fallback = "ACKNOWLEDGMENTS" },
  }

  local front = pandoc.List({})
  local built = pandoc.List({})
  for _, spec in ipairs(specs) do
    local items = spec.build(meta)
    if items and #items > 0 then
      if spec.anchor then
        items:insert(1, { kind = "anchor", name = spec.anchor })
        front:insert({ kind = "entry", indent = 0, front = true,
          text = text(language(meta, spec.listed, spec.fallback)),
          target = spec.anchor })
      end
      built:insert(items)
    end
  end

  -- The lists come after the contents, and the contents lists them, so each
  -- one is named and marked before the contents is built.
  local kinds, floats = thesiscontents.float_kinds(meta)
  local lists = pandoc.List({})
  for _, kind in ipairs(kinds) do
    local items = nil
    if wants_list(meta, list_field(kind)) then
      items = list_page(meta, kind, floats[kind])
    end
    if items then
      local anchor = "apathesis-list-of-" .. kind:lower()
      items:insert(1, { kind = "anchor", name = anchor })
      lists:insert(items)
      front:insert({ kind = "entry", indent = 0, front = true,
        text = text(language(meta, "thesis-list-of-" .. kind:lower(),
          "LIST OF " .. pandoc.text.upper(kind) .. "S")),
        target = anchor })
    end
  end

  local body = thesiscontents.body_entries(blocks,
    thesiscontents.depth(meta), {
      chapter = text(language(meta, "thesis-chapter-column", "CHAPTER")),
      appendices = text(language(meta, "thesis-appendices", "APPENDICES")),
    })
  local contents = nil
  if wants_list(meta, "list-of-contents") then
    contents = contents_page(meta, front, body)
  end
  if contents then built:insert(contents) end
  built:extend(lists)

  for _, items in ipairs(built) do
    pages:insert({
      margins = kMargins,
      measure = kBodyMeasureInches,
      numbered = true,
      items = items,
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

-- latex. The spacing is set on each paragraph rather than on the front
-- matter as a whole: the pages hold single-spaced lines and double-spaced
-- ones side by side, and a group around the lot could only be one of them.
-- It has to be per paragraph in any case, since a change of geometry puts
-- the line spacing back to the document's. geometry's
-- \newgeometry sets a page's own margins and \restoregeometry gives the body
-- back the ones the document asked for.
-- latex.
--
-- The spacing is set between the blocks rather than inside them. setspace
-- works the stretch into the size command, and a \setstretch or a
-- \linespread inside the group that holds a paragraph does not reach the
-- lines of that paragraph: the front matter came out double spaced whatever
-- was asked for, and the title page ran onto a page more than it needed. Set
-- between them, where the size command is run again, it holds.
--
-- A change of geometry puts the spacing back to the document's, so the state
-- is forgotten whenever the geometry changes and asked for again.
-- One line of the contents: the number in a box of its own so that every
-- title begins at the same place, the title, the leader dots, and the page.
-- The left skip takes in the width of the number box and the number is set
-- back into it, so that a title too long for its line turns over under its
-- own first word rather than under the number.
local function latex_contents_line(entry)
  local indent = entry.indent * kSubheadingStep
  if entry.kind == "label" then
    return string.format(
      "{\\parindent=0pt\\leftskip=%.2fin\\noindent %s\\par}",
      indent, written(entry.text, "latex"))
  end

  local number, back = "", ""
  if entry.number then
    number = string.format("\\makebox[%.2fin][l]{%s}",
      kNumberColumn, entry.number)
    back = string.format("\\hspace*{-%.2fin}", kNumberColumn)
    indent = indent + kNumberColumn
  end

  local body = written(entry.text, "latex")
  local page = ""
  if entry.target then
    -- The colour is set on the words rather than through hyperref: a
    -- \hypersetup inside a group did not reach a \hyperref set in it and
    -- every entry came out the colour a link takes. \textcolor sits
    -- inside the link and is the colour that shows. apathesistoc is
    -- defined in the preamble from toccolor, black unless asked otherwise.
    body = "\\hyperref[" .. entry.target .. "]{\\textcolor{apathesistoc}{"
      .. body .. "}}"
    page = "\\apadotfill\\hyperref[" .. entry.target
      .. "]{\\textcolor{apathesistoc}{\\pageref{" .. entry.target .. "}}}"
  end
  return string.format(
    "{\\parindent=0pt\\leftskip=%.2fin\\noindent%s%s%s%s\\par}",
    indent, back, number, body, page)
end

local function render_latex(pages, meta)
  local out = pandoc.List({})
  -- No running head, the page number at the centre of the foot, and the
  -- front matter numbered in lower-case roman. The title page is page i and
  -- is counted, which is why the numbering starts before it.
  out:insert(raw("latex", "\\apathesishead\\pagenumbering{roman}"))

  local geometry, spacing = nil, nil
  local function set_spacing(double)
    local wanted = double and "\\doublespacing" or "\\singlespacing"
    if wanted ~= spacing then
      out:insert(raw("latex", wanted))
      spacing = wanted
    end
  end

  for _, page in ipairs(pages) do
    local wanted = string.format(
      "\\newgeometry{left=%.2fin,right=%.2fin,top=%.2fin,bottom=%.2fin}",
      page.margins.left, page.margins.right,
      page.margins.top, page.margins.bottom)
    if wanted ~= geometry then
      out:insert(raw("latex", wanted))
      geometry, spacing = wanted, nil
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
        set_spacing(item.double)
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "latex"))
        end
        local body = table.concat(lines, "\\\\\n")
        if item.bold then body = "\\bfseries " .. body end
        local align = item.align == "center" and "\\centering"
          or item.align == "right" and "\\raggedleft"
          or "\\raggedright\\noindent"
        local indent = item.indent
          and string.format("\\leftskip=%.2fin\\relax", item.indent) or ""
        out:insert(raw("latex",
          "{" .. align .. indent .. "\n" .. body .. "\\par}"))
      elseif item.kind == "anchor" then
        out:insert(raw("latex", "\\label{" .. item.name .. "}"))
      elseif item.kind == "columns" then
        set_spacing(false)
        out:insert(raw("latex", "{\\parindent=0pt\\noindent "
          .. written(item.left, "latex") .. "\\hfill "
          .. written(item.right, "latex") .. "\\par}"))
      elseif item.kind == "contents" then
        -- A title of two or more lines is single spaced, and a double space
        -- stands between one entry and the next. \apathesissingle works the
        -- second out from the first, so it is asked for while the double
        -- spacing is still in force, and the list is set in a group so that
        -- what follows it takes the page's spacing again. The skip is
        -- \parskip, which stands between the column heading and the first
        -- entry as well as between one entry and the next.
        set_spacing(true)
        out:insert(raw("latex", "{\\apathesissingle"
          .. "\\setlength{\\parskip}{\\apathesisentrysep}"))
        for _, entry in ipairs(item.entries) do
          out:insert(raw("latex", latex_contents_line(entry)))
        end
        out:insert(raw("latex", "}"))
      elseif item.kind == "blocks" then
        -- Prose, which the handbook asks to be double spaced. The first line
        -- is not indented: an abstract begins at the margin, which is where
        -- the Graduate School's template begins one and where the other
        -- formats begin it.
        set_spacing(true)
        out:insert(raw("latex", "{\\setlength{\\parindent}{0pt}"))
        out:extend(item.blocks)
        out:insert(raw("latex", "}"))
      end
    end
    out:insert(raw("latex", "\\clearpage"))
  end

  -- The body begins again at 1, in arabic, which is what \pagenumbering does
  -- to the counter as well as to the shape of the numeral. The spacing goes
  -- back to the document's along with the geometry.
  out:insert(raw("latex",
    "\\restoregeometry\\doublespacing\\pagenumbering{arabic}"))
  return out
end

-- typst. #page with a body sets those pages on their own: their own margins,
-- and for the title page no footer at all, which is what leaves it
-- unnumbered. What comes after begins a new page, so no page break has to be
-- written.
-- typst is told where an entry points and works the page out for itself, at
-- the place that label stands. The front matter is numbered in roman and the
-- body in arabic, and the counter restarts between them, so which of the two
-- a page takes is said here rather than read off the counter.
local kTypstHelper = [==[
#let apatocline(indent, number, body, target, roman, dots) = context {
  let found = if target == none { () } else { query(target) }
  let dest = if found.len() > 0 { found.first().location() } else { none }
  let pg = if dest == none { none } else {
    let n = counter(page).at(dest).first()
    if roman { numbering("i", n) } else { numbering("1", n) }
  }
  block(above: LINESPACE, below: 0pt, inset: (left: indent), width: 100%)[
    #set text(fill: TOCCOLOUR)
    // A show rule as well as the set: typst-template.typ sets its own blue
    // over every link, and a set does not reach inside a link that rule has
    // already coloured. This one stands nearer and wins.
    #show link: set text(fill: TOCCOLOUR)
    #par(leading: 0.65em, hanging-indent: if number == none { 0pt } else { NUMBERCOLUMN })[
      #if number != none [#box(width: NUMBERCOLUMN)[#number]]
      #if dest == none { body } else { link(dest)[#body] }
      #if dots [#box(width: 1fr, repeat[.]) #pg]
    ]
  ]
}
]==]

local function typst_contents_line(entry)
  local indent = string.format("%.2fin", entry.indent * kSubheadingStep)
  local body = written(entry.text, "typst")
  if entry.kind == "label" then
    return "#apatocline(" .. indent .. ", none, [" .. body ..
      "], none, false, false)"
  end
  local number = entry.number and ("[" .. entry.number .. "]") or "none"
  local target = entry.target and ("<" .. entry.target .. ">") or "none"
  return "#apatocline(" .. indent .. ", " .. number .. ", [" .. body ..
    "], " .. target .. ", " .. tostring(entry.front == true) .. ", true)"
end

local function render_typst(pages, meta)
  local out = pandoc.List({})

  -- The helper goes in at the head of the document rather than where it is
  -- first wanted. Each page is set inside a #page block of its own, which is
  -- a scope: a let written in one of them is not there for the next, and the
  -- lists of tables and figures that follow the contents could not see it.
  local wants_helper = false
  for _, page in ipairs(pages) do
    for _, item in ipairs(page.items) do
      if item.kind == "contents" then wants_helper = true end
    end
  end
  if wants_helper then
    out:insert(raw("typst", (kTypstHelper
      :gsub("NUMBERCOLUMN", string.format("%.2fin", kNumberColumn))
      :gsub("LINESPACE", string.format("%.1fpt", kContentsLead))
      :gsub("TOCCOLOUR", 'rgb("#' .. contents_colour(meta) .. '")'))))
  end
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
        body = "#align(" .. item.align .. ")[" .. body .. "]"
        if item.indent then
          body = string.format("#pad(left: %.2fin)[", item.indent)
            .. body .. "]"
        end
        out:insert(raw("typst", body))
      elseif item.kind == "anchor" then
        out:insert(raw("typst", "#metadata(none) <" .. item.name .. ">"))
      elseif item.kind == "columns" then
        out:insert(raw("typst",
          "#block(above: " .. string.format("%.1fpt", kContentsLead)
          .. ", below: 0pt, width: 100%)[" .. written(item.left, "typst")
          .. " #box(width: 1fr) " .. written(item.right, "typst") .. "]"))
      elseif item.kind == "contents" then
        for _, entry in ipairs(item.entries) do
          out:insert(raw("typst", typst_contents_line(entry)))
        end
      elseif item.kind == "blocks" then
        out:extend(item.blocks)
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

-- The line spacing a dissertation asks for, which is where .html differs from
-- the stylesheet every other mode shares. The body stays double spaced, but a
-- block quotation, a note and the entries of the reference list are single
-- spaced, and a double space stands between one entry and the next: a line of
-- space under an entry puts the line after it twice as far down as the one
-- before. The half inch a quotation is indented from both margins is in
-- apa.css already.
--
-- A note's first line is not indented here. In the three paged formats the
-- half inch the handbook asks for is where the note's number goes; in .html
-- the number belongs to the list the browser draws, which is left alone.
--
-- 1em is single and 2em is double throughout that stylesheet.
local kHtmlThesisStyle = table.concat({
  "blockquote p, .blockquote p { line-height: 1em; }",
  ".csl-bib-body .csl-entry { line-height: 1em; margin-bottom: 1em; }",
  ".footnotes li p { line-height: 1em; }",
  ".footnotes li { margin-bottom: 1em; }",
}, "\n")

-- html. There are no pages here, so the gaps are the only thing that carries
-- the arrangement across, and there is nothing to number.
local function render_html(pages, meta)
  local out = pandoc.List({})
  -- The entries are links and would take the theme's link colour; toccolor
  -- says what they take instead, and black is what it says unless a document
  -- asks otherwise.
  out:insert(raw("html", "<style>.thesis-front-matter-page a { color: #"
    .. contents_colour(meta) .. "; }\n" .. kHtmlThesisStyle .. "</style>"))
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
        local indent = item.indent
          and string.format(";margin-left:%.2fin", item.indent) or ""
        out:insert(raw("html", '<p style="text-align:' .. item.align ..
          ";margin:0" .. indent .. ";text-indent:0;line-height:" ..
          (item.double and "2" or "1.15") .. '">' .. body .. "</p>"))
      elseif item.kind == "anchor" then
        out:insert(raw("html", '<span id="' .. item.name .. '"></span>'))
      elseif item.kind == "columns" then
        out:insert(raw("html",
          '<p style="margin:0;text-indent:0;display:flex;'
          .. 'justify-content:space-between"><span>'
          .. written(item.left, "html") .. "</span><span>"
          .. written(item.right, "html") .. "</span></p>"))
      elseif item.kind == "contents" then
        -- No pages here, so no page numbers: an entry is the words and a
        -- link to them, which is all a web page can offer.
        for _, entry in ipairs(item.entries) do
          local body = written(entry.text, "html")
          if entry.number then body = entry.number .. " " .. body end
          if entry.target then
            body = '<a href="#' .. entry.target .. '">' .. body .. "</a>"
          end
          out:insert(raw("html", string.format(
            '<p style="margin:0;text-indent:0;margin-left:%.2fin">%s</p>',
            entry.indent * kSubheadingStep, body)))
        end
      elseif item.kind == "blocks" then
        out:extend(item.blocks)
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

local function docx_runs(inlines, bold, italic, colour)
  local out = {}
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      local properties = {}
      if bold then properties[#properties + 1] = "<w:b/>" end
      if italic then properties[#properties + 1] = "<w:i/>" end
      if colour then
        properties[#properties + 1] = '<w:color w:val="' .. colour .. '"/>'
      end
      local rpr = ""
      if #properties > 0 then
        rpr = "<w:rPr>" .. table.concat(properties) .. "</w:rPr>"
      end
      out[#out + 1] = "<w:r>" .. rpr .. '<w:t xml:space="preserve">'
        .. xml_escape(inline.text) .. "</w:t></w:r>"
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      out[#out + 1] = '<w:r><w:t xml:space="preserve"> </w:t></w:r>'
    elseif inline.t == "Strong" then
      out[#out + 1] = docx_runs(inline.content, true, italic, colour)
    elseif inline.t == "Emph" then
      out[#out + 1] = docx_runs(inline.content, bold, true, colour)
    elseif inline.content then
      out[#out + 1] = docx_runs(inline.content, bold, italic, colour)
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
local function bookmark_name(identifier)
  if #identifier <= 40 then return identifier end
  return "X" .. pandoc.utils.sha1(identifier):sub(2)
end

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
        local inset = twips((page.measure - kRuleWidth) / 2 * 72)
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

local renderers = {
  latex = render_latex,
  html = render_html,
  docx = render_docx,
}

-- ----------------------------------------------------------------------------

-- A page break, in whatever this format calls one. .html has no pages and
-- gets nothing.
local function page_break()
  if FORMAT == "latex" then return raw("latex", "\\clearpage") end
  if FORMAT:match("typst") then
    return raw("typst", "#pagebreak(weak: true)")
  end
  if FORMAT == "docx" then
    return raw("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  end
  return nil
end

-- The body of a dissertation: its level-one headings in capitals, and over
-- each chapter the word CHAPTER and its number, on a line of its own and set
-- like the heading under it.
--
-- Only a chapter gets one. A level-one heading with a part to play --- the
-- references, an appendix, the label over an appendix --- is not a chapter
-- and is left with its own name and nothing above it. The front matter is
-- not here at all: those pages are built by this filter rather than written
-- as headings.
--
-- Done after the contents has been built, and for that reason: the contents
-- lists a chapter by its own name, not by the CHAPTER over it, and a label
-- inserted before the contents was made would have been listed as though it
-- were a heading of the paper.
local function decorate_body(meta, blocks)
  local divisions = thesiscontents.divisions(blocks)
  local word = language(meta, "thesis-chapter-label", "CHAPTER")
  local out = pandoc.List({})

  for index, block in ipairs(blocks) do
    local division = divisions[index]
    if division then
      -- Every major division begins a page of its own: each chapter, the
      -- sources section, and each appendix. The break before an appendix is
      -- written by apafloatstoend.lua, in every format that has pages, so
      -- what is written here is the break before a chapter and before the
      -- references.
      if division.page and not division.others_break then
        local brk = page_break()
        if brk then out:insert(brk) end
      end
      if division.number then
        local label = pandoc.Header(1, pandoc.Inlines({
          pandoc.Str(word), pandoc.Space(),
          pandoc.Str(tostring(division.number)) }))
        -- Unlisted and unnumbered, so that nothing else takes it for a
        -- heading of the paper, and with no identifier so that nothing can
        -- point at it instead of at the chapter.
        label.classes = { "unnumbered", "unlisted" }
        out:insert(label)
      end
      block.content = thesiscontents.upper(block.content)
    end
    out:insert(block)
  end
  return out
end

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
    quarto.doc.include_text("in-header",
      "\\definecolor{apathesistoc}{HTML}{" .. contents_colour(meta) .. "}")
  end
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

  local pages = build_pages(doc.meta, doc.blocks)
  -- What thesisfloats.lua left for this filter is of no use to anything
  -- downstream, and metadata a writer does not expect is metadata that can
  -- go wrong.
  doc.meta[thesiscontents.field] = nil
  if #pages == 0 then return nil end

  local blocks = pandoc.List({})
  blocks:extend(render(pages, doc.meta))
  blocks:extend(decorate_body(doc.meta, doc.blocks))
  doc.blocks = blocks
  return doc
end

-- The front matter of a dissertation, page by page, in no format at all.
--
-- build() reads the document and returns its front-matter pages, each a
-- table of
--
--   margins   the page's margins, in inches
--   measure   the width of its text block, in inches
--   numbered  whether it carries its page number
--   first     true for the title page
--   items     what is set on it, top to bottom
--
-- and each item one of
--
--   gap       { points }                       space down the page
--   rule      {}                               a centred rule
--   para      { align, lines, bold, double, indent }
--   anchor    { name }                         a mark a contents points at
--   columns   { left, right }                  the two labels over a list
--   contents  { entries }                      lines of a contents or list
--   blocks    { blocks }                       the document's own prose
--
-- thesislatex, thesistypst, thesishtml and thesisdocx each set that list in
-- their own format; thesisfrontmatter.lua picks the one being written. What
-- the pages hold and in what order is decided here, once, so that the four
-- formats cannot disagree about it.

local utilsapa = require("utilsapa")
local thesistitle = require("thesistitle")
local thesiscontents = require("thesiscontents")
local stringify = utilsapa.stringify

local M = {}

-- The margins every page but the first takes: the handbook's, with any side
-- the document names laid over them (utilsapa.thesis_body_margins).
local kMargins = utilsapa.thesis_margins
-- The title page is set on 1" all round, which is what the dissertations
-- Temple publishes do and what the Graduate School's template draws: the
-- block of the page stands at the centre of the paper rather than at the
-- centre of a text block pushed right by the binding margin. So the title is
-- broken against the measure the title page has, not the one the body has.
-- thesis: title-margin changes it.
local kTitleMargins = utilsapa.thesis_title_margins
local kMeasureInches = utilsapa.thesis_title_measure()
local kBodyMeasureInches = utilsapa.thesis_measure()
local kTitleSize = 12
-- The measure in thousandths of an em of the title's own size, which is what
-- thesistitle measures a word in.
local kMeasure = kMeasureInches * 72 / kTitleSize * 1000

-- The rule under each block: the width the Graduate School's template draws,
-- or the whole measure of a title page narrower than that.
local kTemplateRuleWidth = 5.5
local kRuleWidth = kTemplateRuleWidth
local kRuleSpace = 21        -- points above and below each rule
local kTitleDrop = 70        -- points from the top margin down to the title
local kCommitteeDrop = 70    -- points from the last block down to the committee
local kLineSpace = 13.8      -- a single-spaced line of 12pt Times
local kDedicationDrop = 164  -- points from the top margin to a dedication
-- The examining committee begins where the rules above it begin, rather
-- than out at the margin: the rules are narrower than the measure and are
-- centred in it, so this is the half-inch that leaves on either side.
local kCommitteeIndent = (kMeasureInches - kRuleWidth) / 2

-- The margins and the measures they leave, for this document. Every value
-- above that hangs on the margins is set again here, before a page is built.
local function set_geometry(meta)
  kMargins = utilsapa.thesis_body_margins(meta)
  kTitleMargins = utilsapa.thesis_page_one_margins(meta)
  kMeasureInches = utilsapa.thesis_title_measure(kTitleMargins)
  kBodyMeasureInches = utilsapa.thesis_measure(kMargins)
  kMeasure = kMeasureInches * 72 / kTitleSize * 1000
  kRuleWidth = math.min(kTemplateRuleWidth, kMeasureInches)
  kCommitteeIndent = (kMeasureInches - kRuleWidth) / 2
end
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

-- The measures the renderers need as well, to set what is built here.
M.number_column = kNumberColumn
M.subheading_step = kSubheadingStep
M.contents_lead = kContentsLead

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

-- The colour the entries of a contents take, which is quarto's toccolor.
--
-- Black unless a document asks otherwise. They are links, and a link would
-- otherwise take linkcolor and leave the contents reading as a page of
-- cross references rather than as a list. This is what the lists apaquarto
-- builds for its other modes already do; a dissertation's are built here and
-- had been taking the link colour.
function M.contents_colour(meta)
  return utilsapa.colour_hex(meta and meta.toccolor) or "000000"
end

local language = utilsapa.lang

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
    -- At the width this document's title page leaves room for.
    rule = function()
      items:insert({ kind = "rule", width = kRuleWidth })
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
--
-- The language key is thesis- and the field that asks for the list, so the
-- two read alike: thesis-list-of-tables names the list list-of-tables sets.
local function list_heading(meta, kind)
  return language(meta, "thesis-" .. list_field(kind),
    "LIST OF " .. pandoc.text.upper(kind) .. "S")
end

local function list_page(meta, kind, entries)
  if #entries == 0 then return nil end

  local heading = list_heading(meta, kind)

  local items, add = collector()
  add.para("center", { text(heading) }, { bold = true })
  add.gap(kAbstractGap)
  add.columns(text(kind), text(language(meta, "thesis-page-column", "Page")))
  add.contents(entries)
  return items
end

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

-- The front matter, page by page. Each page says what margins it is set on
-- and whether it carries its number; the numbering itself is lower-case
-- roman throughout, and the body that follows begins again at 1 in arabic.
function M.build(meta, blocks)
  set_geometry(meta)
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
        text = text(list_heading(meta, kind)),
        target = anchor })
    end
  end

  -- The label over the appendices is Quarto's word for them, in capitals,
  -- unless thesis-appendices says otherwise: APPENDICES in English, and the
  -- translation in a dissertation written in another language.
  local appendices_word = pandoc.text.upper(
    language(meta, "section-title-appendices", "Appendices"))
  local body = thesiscontents.body_entries(blocks,
    thesiscontents.depth(meta), {
      chapter = text(language(meta, "thesis-chapter-column", "CHAPTER")),
      appendices = text(language(meta, "thesis-appendices", appendices_word)),
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

-- Inlines written out in a format, for a renderer to put inside its markup.
function M.written(inlines, format)
  local out = pandoc.write(
    pandoc.Pandoc({ pandoc.Plain(inlines) }), format)
  return (out:gsub("%s+$", ""))
end

return M

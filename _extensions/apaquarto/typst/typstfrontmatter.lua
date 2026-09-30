-- The front matter in typst: laid out for the document's mode, and the rules
-- that go at the head of the document with it.
--
-- frontmatter.lua builds the front matter for every format as the same
-- blocks, and for typst hands it over in a div of its own (the class is
-- frontmatterlayout.kFrontMatterClass). This lays it out and takes the div
-- away. A manuscript, a student paper and a dissertation print the blocks one
-- after another; a journal article sets the title, byline and abstract as a
-- masthead across both columns and the author note at the foot of the first;
-- a document runs them on as one flow. The markers frontmatter.lua leaves for
-- the table of contents and the lists of figures and tables are written as
-- typst outlines, and the rule that colours a link goes at the head of the
-- document.
--
-- Loaded by typst/formattypst.lua with require("typstfrontmatter"); a module,
-- not a filter. It runs as that filter's first pass after its Meta, before
-- the passes that set the author block, the note indents and the spacing
-- before a first paragraph, which read the front matter as they always have.

local List = require 'pandoc.List'
local utilsapa = require("utilsapa")
local layout = require("frontmatterlayout")
local stringify = utilsapa.stringify

local M = {}

local function raw(text)
  return pandoc.RawBlock("typst", text)
end

-- Text put into typst markup, with the characters that mean something there
-- escaped.
local function typst_text(text)
  return (text:gsub("([\\%[%]#%$%*_`<>@])", "\\%1"))
end

-- A path as a typst string literal
local function typst_string(text)
  return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

-- The colour a document asks a link to take. Quarto's fields are latex's --
-- linkcolor, urlcolor, citecolor, filecolor, toccolor -- and a colour is named
-- the way latex names it, so xcolor's table is what resolves the name and
-- typst is handed the code. typst knows some of those names itself and means
-- something else by them -- its green is #2ECC40 where xcolor's is #00FF00 --
-- and knows nothing of violet or brown at all, which stopped the compile
-- outright. Nothing named leaves typst with what it had.
local function typst_colour(meta, field, fallback)
  if meta[field] == nil then return fallback end
  local hex = utilsapa.colour_hex(meta[field])
  if hex == nil then
    quarto.log.warning(field .. " is \"" .. stringify(meta[field]) ..
      "\", which is not a colour apaquarto knows, so it was left out." ..
      " Name one of xcolor's colours, or write the code as #rrggbb.")
    return fallback
  end
  return 'rgb("#' .. hex .. '")'
end

-- ---------------------------------------------------------------------------
-- The colour of a link

-- The colour a link takes, by the kind of link it is: urlcolor for one that
-- leaves the document, citecolor for a citation, filecolor for a file, and
-- linkcolor for another anchor -- a cross reference, or a link to a heading.
-- The same reading latex makes of the four fields, put to typst as a show
-- rule that looks at where the link goes: a string destination is a url or a
-- path, and a label is a cross reference or, when it names one of citeproc's
-- entries, a citation.
--
-- typst-template.typ sets its own blue, which is #0074D9, and a show rule
-- written after that one wins. This is only written when a document names one
-- of the four, so that one naming none is written exactly as it was before,
-- blue and all.
--
-- It goes at the head of the document, so that the front matter takes it
-- too: the corresponding author's email is a link, and so is anything written
-- into the abstract. Each list writes a rule of its own over its entries,
-- where the list is, and that one is nearer the link and answers for it.
local function link_rule(meta)
  local names_a_colour = false
  for _, field in ipairs(utilsapa.link_fields) do
    if meta[field] then names_a_colour = true end
  end
  if not names_a_colour then return nil end

  local link = typst_colour(meta, "linkcolor", "blue")
  return raw(table.concat({
    '#show link: it => {',
    '  let d = it.dest',
    -- An entry of one of the lists is a link to a location, and the list
    -- sets its own colour over its entries. Left to this rule it would take
    -- linkcolor, since it points inside the document, and a list would read
    -- as a page of cross references.
    '  if type(d) == location { return it }',
    '  let c = if type(d) == str {',
    '    if d.starts-with("mailto:") or d.contains("://") { '
      .. typst_colour(meta, "urlcolor", link) .. ' }',
    '    else { ' .. typst_colour(meta, "filecolor", link) .. ' }',
    '  } else if type(d) == label and str(d).starts-with("ref-") {',
    '    ' .. typst_colour(meta, "citecolor", link),
    '  } else { ' .. link .. ' }',
    '  text(fill: c, it)',
    '}',
    '', '',
  }, '\n'))
end

-- ---------------------------------------------------------------------------
-- The contents and the lists

-- The outline a list marker stands for.
local function outline(meta, which)
  local toccolor = typst_colour(meta, "toccolor", "black")
  if which == "list-of-contents" then
    return raw('\n\n#show outline.entry: it => {show link: set text(fill: ' ..
      toccolor .. ')\nlink(it.element.location(),it.indented(none, it.inner(), ))}\n\n#outline(title: [' ..
      typst_text(utilsapa.lang(meta, "toc-title-document", "Table of Contents")) ..
      '], indent: 1.5em, depth: ' .. tostring(utilsapa.toc_depth(meta, 3)) .. ')\n\n')
  end

  -- "Figure 1. The Figure Caption", which is the line .docx gives. The show
  -- rule written for the table of contents passes none as the prefix, which
  -- dropped the "Figure 1" from these two outlines as well, so each gets a
  -- rule of its own inside a block that keeps it there.
  local title, target
  if which == "list-of-figures" then
    title = utilsapa.lang(meta, "crossref-lof-title", "List of Figures")
    -- The document's own kinds of float as well, such as an Illustration, as
    -- the .pdf and .docx lists take them.
    target = 'figure.where(kind: "quarto-float-fig")'
    local custom_kinds = {}
    for kind in pairs(utilsapa.float_prefixes(meta)) do
      if kind ~= "fig" and kind ~= "tbl" then custom_kinds[#custom_kinds + 1] = kind end
    end
    table.sort(custom_kinds)
    for _, kind in ipairs(custom_kinds) do
      target = target .. '.or(figure.where(kind: "quarto-float-' .. kind .. '"))'
    end
  else
    title = utilsapa.lang(meta, "crossref-lot-title", "List of Tables")
    target = 'figure.where(kind: "quarto-float-tbl")'
  end
  return raw(
    '\n\n#[\n' ..
    '#show outline.entry: it => {show link: set text(fill: ' .. toccolor .. ')\n' ..
    'let loc = it.element.location()\n' ..
    'let n = it.element.counter.at(loc).first()\n' ..
    'let a = appendixcounter.at(loc).first()\n' ..
    'let name = if a > 0 {[#it.element.supplement #numbering("A", a)#n]}\n' ..
    '  else {[#it.element.supplement #n]}\n' ..
    'link(loc, it.indented(none, name + [. ] + it.inner()))}\n' ..
    '#outline(title: [' .. typst_text(title) .. '], target: ' .. target .. ',)\n]\n\n')
end

local function is_list_marker(block)
  return block.t == "Div" and (block.classes:includes("list-of-contents")
    or block.classes:includes("list-of-figures")
    or block.classes:includes("list-of-tables"))
end

-- The outlines for some list markers. A list stands on its own page except in
-- journal mode, which runs continuously.
local function outlines(meta, markers, paged)
  local out = List:new {}
  for _, marker in ipairs(markers) do
    out:insert(outline(meta, marker.classes[1]))
    if paged then out:insert(raw('#pagebreak()\n\n')) end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Journal mode

-- apa7 sets the byline larger than the affiliations under it. Quarto emits
-- both inside one Div, so the sizes are switched partway through its content:
-- the byline is the first paragraph, and every paragraph after it is an
-- affiliation.
local function size_jou_byline(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.classes:includes("Author") then
      local content = List:new {
        raw("#set par(..joubylinepar)"),
        raw("#set block(spacing: 0.55em)")
      }
      local seen_byline = false
      for _, inner in ipairs(block.content) do
        if inner.t == "Para" and not seen_byline then
          seen_byline = true
          content:extend({ raw("#set text(size: jouauthorsize)") })
          content:extend({ inner })
          content:extend({ raw("#set text(size: jouaffiliationsize)") })
        else
          content:extend({ inner })
        end
      end
      block.content = content
    end
  end
  return blocks
end

-- The two lines of one side of the masthead, under the rule
local function masthead_lines(first, second)
  local out = List:new {}
  if first then out:extend(first) end
  if second then
    if #out > 0 then out:extend({ pandoc.LineBreak() }) end
    out:extend(second)
  end
  if #out == 0 then return nil end
  return List:new { pandoc.Plain(out) }
end

-- The apaquarto logo, asked for by writing logo: default. utilsapa finds the
-- extension folder it ships in; the masthead writes it as raw typst, so the
-- path is the one typst reads.
local kDefaultLogo = "default"
local kShippedLogo = "apaquarto-logo.png"

-- Journal masthead for jou mode, following the way the journals set one: the
-- journal's name at the right of the page with its logo opposite, a rule
-- under both, and the issue on the right beneath it with the copyright on the
-- left. Journal of Educational Psychology is the model.
local function journal_masthead(meta)
  local title = utilsapa.journal_title(meta)
  local issue_line = utilsapa.journal_issue_line(meta)
  local url = utilsapa.journal_field(meta, "url")
  local logo = utilsapa.journal_field(meta, "logo")
  if logo and stringify(logo) == kDefaultLogo then
    local shipped = utilsapa.extension_file_typst(kShippedLogo)
    if shipped then
      logo = pandoc.Inlines({ pandoc.Str(shipped) })
    else
      quarto.log.warning(
        "logo: default could not find " .. kShippedLogo ..
        " in the apaquarto extension folder, so the masthead has no logo.")
      logo = nil
    end
  end
  local issn = utilsapa.journal_field(meta, "issn")
  local copyright = utilsapa.journal_copyright(meta)

  if not (title or issue_line or url or logo or issn or copyright) then
    return List:new {}
  end

  -- The url is set as a link, so that it is both live and coloured the way
  -- the journals print a doi.
  local url_line
  if url then
    local target = stringify(url)
    url_line = List:new { pandoc.Link(url, target) }
  end

  local issn_line
  if issn then
    issn_line = List:new { pandoc.Str("ISSN:"), pandoc.Space() }
    issn_line:extend(issn)
  end

  local left = masthead_lines(copyright, issn_line)
  local right = masthead_lines(issue_line, url_line)

  local result = List:new {}
  -- Into the top margin, so that the masthead sits where a journal puts it
  -- without moving the pages after the first.
  result:extend({ raw("#joumastheadlift()") })
  result:extend({ raw(
    "#block(width: 100%, below: 1em)[\n" ..
    "#set par(first-line-indent: 0pt)") })

  -- Above the rule: the logo at the left, the journal's name at the right,
  -- both sitting on it.
  if logo or title then
    result:extend({ raw(
      "#grid(columns: (1fr, auto), align: (left + bottom, right + bottom),\n" ..
      "  column-gutter: 1em, [") })
    -- The logo is written as typst rather than as a pandoc image so that it
    -- can be fitted to the height of the masthead band: pandoc drops a height
    -- it cannot read as a dimension, and the band is named in the template.
    if logo then
      result:extend({ raw(
        "#image(" .. typst_string(stringify(logo)) .. ", height: joulogoheight)") })
    end
    result:extend({ raw("], [\n#set text(size: joujournalsize)") })
    if title then
      result:extend({ pandoc.Plain(title) })
    end
    result:extend({ raw("])") })
  end

  result:extend({ raw(
    -- Plain v rather than weak: a weak space collapses against the edge
    -- of a block, which left the rule touching the descenders of the
    -- journal's name whenever there was no logo to give the row height.
    "#v(3pt)\n#line(length: 100%, stroke: 0.5pt + black)\n#v(3pt)") })

  -- Below it: the copyright at the left, the issue and the doi at the right.
  if left or right then
    result:extend({ raw(
      "#grid(columns: (1fr, 1fr), align: (left + top, right + top),\n" ..
      "  column-gutter: 1em, [\n#set text(size: joumastheadsize)") })
    if left then result:extend(left) end
    result:extend({ raw("], [\n#set text(size: joumastheadsize)") })
    if right then result:extend(right) end
    result:extend({ raw("])") })
  end

  result:extend({ raw("]") })

  return result
end

-- The number of columns the author note is set across: author-note-columns
-- when it says 1 or 2, and otherwise auto, which lets jouauthornote in
-- typst-template.typ decide from the length of the note.
local function author_note_columns(meta)
  local notecols = "auto"
  -- There can be a note without an author-note field: a corresponding author
  -- makes one out of the address and the email. Reading the field without
  -- looking first brought the render down on any journal document that had
  -- not written one.
  local note_meta = meta["author-note"]
  for _, value in ipairs({
    note_meta and note_meta["author-note-columns"],
    meta["author-note-columns"],
  }) do
    local asked = stringify(value)
    if asked == "1" or asked == "2" then notecols = asked end
  end
  return notecols
end

-- A published article: the masthead, the title and authors and then the
-- abstract, impact statement and keywords in a narrower block, all spanning
-- both columns; the author note at the foot of the first column; and the
-- lists, which are too large for the masthead, in the body.
local function journal(meta, front)
  local kept, markers = layout.take_list_markers(front)
  local head, narrow, notes, tail = layout.split_journal(kept)
  local out = List:new {}
  out:extend({ raw('#place(top, scope: "parent", float: true, clearance: 1.5em)[') })
  -- The masthead carries its own block, sizes and alignment, and lifts
  -- itself into the top margin of the page it sits on.
  out:extend(journal_masthead(meta))
  -- The title and authors. The template's heading rule pins every heading to
  -- the body size, so the title size is restated here in a show rule of its
  -- own, which being the later rule wins inside this block only. apa7's
  -- journal title is \LARGE but not bold, so the weight is reset along with
  -- the size; typst headings are bold by default.
  out:extend({ raw(
    '#block(width: 100%)[\n' ..
    '#show heading.where(level: 1): set text(size: joutitlesize, weight: "regular")') })
  out:extend(size_jou_byline(head))
  out:extend({ raw(']') })
  if #narrow > 0 then
    -- Abstract, impact statement and keywords: smaller, and set in a block
    -- narrower than the masthead, centered under the authors. Leading is set
    -- in em so it follows the smaller text at the same ratio the body uses,
    -- rather than keeping the body's absolute leading and looking slack at
    -- this size.
    out:extend({ raw(
      '#align(center)[\n' ..
      '#block(width: jouabstractwidth, above: 1em, below: 0.6em)[\n' ..
      '#set align(left)\n#set text(size: jouabstractsize)\n' ..
      '#set par(leading: jouabstractleading, first-line-indent: 0pt)\n' ..
      '#show heading.where(level: 1): set text(size: jouabstractsize)') })
    out:extend(layout.box_impact(narrow,
      raw('#block(width: 100%, inset: 6pt, above: 9pt, below: 9pt, stroke: .5pt + black)['),
      raw(']')))
    out:extend({ raw(']\n]') })
  end
  out:extend({ raw(']') })
  if #notes > 0 then
    -- jouauthornote in typst-template.typ places the note at the foot of the
    -- first column, or across the foot of the page in two columns when it is
    -- too long for one. Emitting it at the head of the body puts it on the
    -- first page.
    out:extend({ raw('#jouauthornote(cols: ' .. author_note_columns(meta) .. ')[') })
    -- Each ORCID line is one short name-and-link paragraph, so justifying it
    -- stretches the gaps across the column and indenting it leaves the names
    -- out of line with each other. They are set flush left and unindented,
    -- while the prose paragraphs of the note keep the indent they are given.
    out:extend(layout.set_off_orcid(layout.fit_orcid(notes),
      raw("#block[\n#set par(justify: false, first-line-indent: 0pt)"),
      raw("]")))
    out:extend({ raw(']') })
  end
  out:extend(tail)
  out:extend(outlines(meta, markers, false))
  return out
end

-- ---------------------------------------------------------------------------
-- Document mode

-- Document mode: one continuous flow, set the way apa7 sets it in .pdf.
--
-- The manuscript front matter is built once for every mode, and document mode
-- differs from it in four ways, all of them handled here:
--
--   * the title is large and unemphasised rather than bold, there being no
--     title page for a bold title to head;
--   * the author note goes to the foot of the first page instead of standing
--     between the authors and the abstract, and loses its heading with it;
--   * the abstract is inset from both margins, so that it does not read as one
--     more body paragraph;
--   * two lines are left clear between the abstract and the body.
--
-- The typst side of each is a helper in typst-template.typ, which is where the
-- sizes and widths are written down.
local function document(meta, front)
  -- Read by hand rather than with classes:includes, since a block that has
  -- no classes at all answers a method call on them with an error rather
  -- than with false.
  local function has_class(block, name)
    local classes = block.classes
    if type(classes) ~= "table" then return false end
    for _, class in ipairs(classes) do
      if class == name then return true end
    end
    return false
  end

  local out = List:new {}
  local authornote = List:new {}
  local in_note = false

  for _, block in ipairs(front) do
    local header = block.t == "Header"

    -- Everything from the author note's heading to the next heading is the
    -- note, and goes to the foot of the page rather than staying here.
    if in_note and not header then
      if block.t ~= "RawBlock" then
        authornote:extend({ block })
      end
      goto continue
    end
    in_note = false

    if header and block.identifier == "firstheader" then
      -- Title already appears at the top of the document.
    elseif layout.is_spacing(block) then
      -- Continuous flow: no manuscript breaks.
    elseif header and block.identifier == "title" then
      -- Plain rather than Para: a paragraph picks up the first-line shift
      -- apaquarto puts in front of body text, which has no business in a
      -- centred title.
      out:extend({ raw("#apadoctitle["), pandoc.Plain(block.content), raw("]") })
    elseif header and block.identifier == "author-note" then
      in_note = true
    elseif has_class(block, "AbstractFirstParagraph") then
      out:extend({ raw("#apadocabstract["), block, raw("]"),
        raw("#apadocabstractgap()") })
    elseif is_list_marker(block) then
      -- A document runs on, so its lists do not start pages of their own.
      out:extend(outlines(meta, { block }, false))
    else
      out:extend({ block })
    end
    ::continue::
  end

  -- Emitted at the end of the front matter, which is on the first page; a
  -- footnote is set at the foot of the page its mark is on, so that is where
  -- the note is set. The separator is asked for here rather than in the
  -- template because a set rule has to be written into the document to reach
  -- the page's footnote area.
  if #authornote > 0 then
    out:extend({
      raw("#set footnote.entry(separator: docauthornoterule)"),
      raw("#apadocauthornote["),
    })
    out:extend(authornote)
    out:extend({ raw("]") })
  end

  return out
end

-- ---------------------------------------------------------------------------
-- Every other mode: the blocks one after another, the lists written in place.
local function manuscript(meta, front)
  local out = List:new {}
  for _, block in ipairs(front) do
    if is_list_marker(block) then
      out:extend(outlines(meta, { block }, true))
    else
      out:insert(block)
    end
  end
  return out
end

-- The document with its front matter laid out and the link rule at its head.
function M.lay_out(doc)
  local meta = doc.meta
  local mode = utilsapa.mode(meta)
  local blocks = pandoc.Blocks({})
  for _, block in ipairs(doc.blocks) do
    if block.t == "Div" and block.classes:includes(layout.kFrontMatterClass) then
      local front = List:new(block.content)
      if mode == "jou" then
        blocks:extend(journal(meta, front))
      elseif mode == "doc" then
        blocks:extend(document(meta, front))
      else
        blocks:extend(manuscript(meta, front))
      end
    else
      blocks:insert(block)
    end
  end
  local rule = link_rule(meta)
  if rule then blocks:insert(1, rule) end
  doc.blocks = blocks
  return doc
end

return M

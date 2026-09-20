-- Handle frontmatter stuff for .docx, html, typst, and plain latex formats.
--
-- apaquarto-pdf leaves all of this to the apa7 class, so this filter stands
-- down for it. apaquarto-latex-pdf does not use apa7 and is built out of the
-- same blocks as every other format, so it runs here like the rest. The two
-- are told apart by utilsapa.apa7_latex, which reads the metadata, so the test
-- is made below where the metadata is in hand rather than here.


local andreplacement = "and"



local List = require 'pandoc.List'
local utilsapa = require("utilsapa")
local stringify = utilsapa.stringify

-- The paragraphs of an abstract or an impact statement, as the two divs the
-- stylesheets and the reference document expect: the first paragraph on its
-- own, flush left, and the rest under a style that indents them.
--
-- The text arrives in one of two shapes. Written in the yaml under a block
-- scalar it comes as line blocks, a paragraph to a line; written as a section
-- of the document, which abstractsection.lua allows, it comes as ordinary
-- paragraphs. Both are read here so that neither way of writing it is second
-- best.
local function paragraph_divs(blocks)
  local rest = pandoc.Div({})
  local first = pandoc.Div({})
  local counter = 1
  -- typst indents the first paragraph itself, so nothing is set apart for it
  -- and the count starts past it.
  if FORMAT == "typst" then
    counter = 2
  end

  local function add(para)
    if counter == 1 then
      first.content:extend({ para })
      first.classes:insert("AbstractFirstParagraph")
    else
      rest.content:extend({ para })
      if counter == 2 then
        rest.classes:insert("Abstract")
      end
    end
    counter = counter + 1
  end

  local has_lines = false
  blocks:walk { LineBlock = function() has_lines = true end }

  if has_lines then
    blocks:walk {
      LineBlock = function(lb)
        lb:walk {
          traverse = "topdown",
          Inlines = function(el)
            add(pandoc.Para(el))
            return el, false
          end
        }
      end
    }
  else
    for _, block in ipairs(blocks) do
      if block.t == "Para" or block.t == "Plain" then
        add(pandoc.Para(block.content))
      elseif block.t ~= "Header" then
        -- Anything else -- a block quote, a list -- is kept whole rather than
        -- taken apart, and counts as a paragraph for the styling above.
        add(block)
      end
    end
  end

  local out = pandoc.List({})
  if counter > 1 then out:insert(first) end
  if counter > 2 then out:insert(rest) end
  return out
end

local function get_and(m)
  if m.language and m.language["citation-last-author-separator"] then
    andreplacement = stringify(m.language["citation-last-author-separator"])
  end
end

---http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
  return string.sub(str.text, -1) == ending
end

-- Check if meta is present or if it has length of 0
local function chkmeta(meta_item)
  ispresent = false
  if meta_item then
    if #meta_item > 0 then
      ispresent = true
    end
  end
  return ispresent
end

-- Convert list to string with oxford comma
local function oxfordcommalister(lists)
  local lastsep = pandoc.Str(", " .. andreplacement .. " ")
  local sep = pandoc.Str(", ")

  if #lists == 2 then
    lastsep = pandoc.Str(" " .. andreplacement .. " ")
  end

  local result = List:new {}
  for i, v in ipairs(lists) do
    if i > 1 then
      if i == #lists then
        result:extend(List:new { lastsep })
      else
        result:extend(List:new { sep })
      end
    end
    result:extend(List:new { v })
  end

  return result
end




local get_author_paragraph = function(authors, different)
  local authordisplay = List:new {}
  local superii = ""
  local sep = ", "

  for i, a in ipairs(authors) do
    if i == 1 then
      sep = ""
    elseif i == #authors then
      if i == 2 then
        sep = " " .. andreplacement .. " "
      else
        sep = ", " .. andreplacement .. " "
      end
    else
      sep = ", "
    end

    authordisplay:extend({ pandoc.Str(sep .. stringify(a.apaauthordisplay)) })

    superii = ""
    if a.affiliations then
      for j, aff in ipairs(a.affiliations) do
        if j > 1 then
          superii = superii .. ","
        end
        superii = superii .. aff.number
      end
    end

    if different then
      authordisplay:extend({ pandoc.Superscript(superii) })
    end
  end
  return pandoc.Para(authordisplay)
end


local extend_paragraph = function(para, meta_item, sep)
  sep = sep or pandoc.Space()



  if meta_item and #meta_item > 0 then
    if #para.content > 1 then
      para.content:extend({ sep })
    end
    para.content:extend(meta_item)
  end
  return para
end


-- Typst document-mode helpers ------------------------------------------------

local function is_typst_mode(meta, mode)
  return FORMAT:match 'typst' and meta.documentmode and
    stringify(meta.documentmode) == mode
end

-- Manuscript front matter uses explicit line and page breaks to space the title
-- page; journal and document modes drop them for a continuous layout.
local function is_frontmatter_spacing(block)
  return block.t == "LineBreak" or block.t == "SoftBreak" or
    (block.t == "RawBlock" and block.format == "typst" and
      block.text:find("#pagebreak", 1, true) ~= nil)
end

-- Journal mode: split the front matter into the full-width masthead (title,
-- byline, affiliations, abstract, keywords) and the author note. The caller
-- wraps the masthead in place(scope: "parent", float: true) so it spans both
-- columns; the author note then flows into the two-column body rather than
-- crowding the masthead.
-- Surname for the journal running head. Quarto's parsed name.family is used
-- when it really is the trailing surname of the displayed name, which keeps
-- compound surnames ("van der Berg") whole. When an author writes the name as
-- a given/family pair, Quarto can fold the two together and re-split on the
-- last space, leaving family as a middle initial; in that case the last word
-- of the display name is the better answer.
local function author_surname(a)
  local display = a.apaauthordisplay and stringify(a.apaauthordisplay) or ""
  local family = a.name and a.name.family and stringify(a.name.family) or ""
  if family ~= "" and display:sub(-#family) == family then
    return family
  end
  return display:match("(%S+)%s*$") or family
end

-- Running head byline: surnames with serial commas, an ampersand before the
-- last, and "et al." once there are more than three authors.
local function running_authors(byauthor)
  local names = List:new {}
  for _, a in ipairs(byauthor) do
    local surname = author_surname(a)
    if surname ~= "" then
      names:insert(surname)
    end
  end
  if #names == 0 then
    return nil
  elseif #names == 1 then
    return names[1]
  elseif #names == 2 then
    return names[1] .. " & " .. names[2]
  elseif #names == 3 then
    return names[1] .. ", " .. names[2] .. ", & " .. names[3]
  end
  return names[1] .. " et al."
end

-- The ORCID icon carries a width in millimetres, which next to the author
-- note's smaller text is taller than the text itself and opens up every line
-- it sits on. Typst measures a line from the cap height to the baseline, about
-- 0.66em in Times, so sizing the icon to that keeps it level with the capitals
-- beside it and leaves the line height alone. The height must be written as a
-- literal dimension, since Pandoc parses this attribute rather than passing it
-- through. Dropping the width keeps the icon square.
local function fit_jou_orcid(blocks)
  return pandoc.Blocks(blocks):walk {
    Image = function(img)
      if img.identifier == "orcid" then
        img.attributes.width = nil
        img.attributes.height = "0.8em"
        return img
      end
    end
  }
end

-- Each ORCID line is one short name-and-link paragraph, so justifying it
-- stretches the gaps across the column and indenting it leaves the names out
-- of line with each other. They are set flush left and unindented, while the
-- prose paragraphs of the note keep the indent they are given.
local function has_orcid(block)
  local found = false
  block:walk {
    Image = function(img)
      if img.identifier == "orcid" then
        found = true
      end
    end
  }
  return found
end

local function set_off_jou_orcid(blocks)
  local out = List:new {}
  local open = false
  for _, block in ipairs(blocks) do
    local orcid = block.t == "Para" and has_orcid(block)
    if orcid and not open then
      out:extend({ pandoc.RawBlock("typst",
        "#block[\n#set par(justify: false, first-line-indent: 0pt)") })
      open = true
    elseif open and not orcid then
      out:extend({ pandoc.RawBlock("typst", "]") })
      open = false
    end
    out:extend({ block })
  end
  if open then
    out:extend({ pandoc.RawBlock("typst", "]") })
  end
  return out
end

-- apa7 sets the byline larger than the affiliations under it. Quarto emits
-- both inside one Div, so the sizes are switched partway through its content:
-- the byline is the first paragraph, and every paragraph after it is an
-- affiliation.
local function size_jou_byline(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" and block.classes:includes("Author") then
      local content = List:new {
        pandoc.RawBlock("typst", "#set par(..joubylinepar)"),
        pandoc.RawBlock("typst", "#set block(spacing: 0.55em)")
      }
      local seen_byline = false
      for _, inner in ipairs(block.content) do
        if inner.t == "Para" and not seen_byline then
          seen_byline = true
          content:extend({ pandoc.RawBlock("typst", "#set text(size: jouauthorsize)") })
          content:extend({ inner })
          content:extend({ pandoc.RawBlock("typst", "#set text(size: jouaffiliationsize)") })
        else
          content:extend({ inner })
        end
      end
      block.content = content
    end
  end
  return blocks
end

-- The masthead is set in three pieces. "front" is the title and authors, at
-- the sizes apa7 gives them. "narrow" is everything from the abstract on --
-- abstract, impact statement, keywords -- which apa7 sets smaller and in a
-- block narrower than the masthead. "notes" is the author note, which is
-- separated by a rule below both.
local function split_jou_frontmatter(blocks)
  local front = List:new {}
  local narrow = List:new {}
  local notes = List:new {}
  local tail = List:new {}
  local in_notes = false
  local in_narrow = false
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.identifier == "author-note" then
      -- The note sits alone at the foot of the column under a rule, the way
      -- apa7 sets it, so it needs no heading to introduce it.
      in_notes = true
      in_narrow = false
    elseif block.t == "Header" and block.identifier == "abstract" then
      -- apa7 prints no heading above the abstract in journal mode; the small
      -- narrow block is what marks it out.
      in_notes = false
      in_narrow = true
    elseif block.t == "Header" and block.identifier == "impact" then
      -- The impact statement does keep its heading. Everything from here to
      -- the author note belongs in the narrow block, including the keywords
      -- line that trails the abstract.
      in_notes = false
      in_narrow = true
      narrow:extend({ block })
    elseif block.t == "Header" and block.identifier == "firstheader" then
      -- The masthead already carries the title; do not repeat it.
    elseif block.t == "RawBlock" and block.format == "typst" and
        (block.text:find("#outline", 1, true) ~= nil or
         block.text:find("#show outline", 1, true) ~= nil) then
      -- A table of contents / list of figures or tables is too large for the
      -- floating masthead; let it flow in the two-column body instead. Match
      -- both the #outline call and any #show outline styling rule Quarto emits.
      tail:extend({ block })
    elseif is_frontmatter_spacing(block) then
      -- No manuscript spacing in journal mode.
    elseif in_notes then
      notes:extend({ block })
    elseif in_narrow then
      narrow:extend({ block })
    else
      front:extend({ block })
    end
  end
  return front, narrow, notes, tail
end

-- The impact statement is set off from the abstract above it and the keywords
-- below it by a half-point rule, 6pt clear of the text on every side and 9pt
-- clear of the abstract and the keywords. The box is emitted at width 100%
-- inside the narrow block, so its outer edge lines up with the abstract rather
-- than standing proud of it.
local function box_jou_impact(blocks)
  local out = List:new {}
  local i = 1
  while i <= #blocks do
    local block = blocks[i]
    if block.t == "Header" and block.identifier == "impact" then
      out:extend({ pandoc.RawBlock('typst',
        '#block(width: 100%, inset: 6pt, above: 9pt, below: 9pt, stroke: .5pt + black)[') })
      out:extend({ block })
      i = i + 1
      -- The statement itself arrives as one or more Divs. The keywords line
      -- that follows it is a Para, which closes the box.
      while i <= #blocks and blocks[i].t == "Div" do
        out:extend({ blocks[i] })
        i = i + 1
      end
      out:extend({ pandoc.RawBlock('typst', ']') })
    else
      out:extend({ block })
      i = i + 1
    end
  end
  return out
end

-- Document mode: one continuous flow, set the way apa7 sets it in .pdf.
--
-- The manuscript front matter is built once for every mode, and document mode
-- differs from it in four ways, all of them handled here so that the rest of
-- the front matter can stay as it is:
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
local function strip_doc_frontmatter(blocks)
  local function raw(text)
    return pandoc.RawBlock("typst", text)
  end

  -- Read by hand rather than with classes:includes. What arrives here is not
  -- all blocks -- the spacing between the title and the authors comes as line
  -- breaks, which are inlines -- and an element that has no classes at all
  -- answers a method call on them with an error rather than with false.
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

  for _, block in ipairs(blocks) do
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
    elseif is_frontmatter_spacing(block) then
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

-- Student paper title fields (course, instructor, due date, note).
local function add_student_field(body, meta, field)
  local content = meta[field]
  if not content or stringify(content) == "" then
    return
  end
  local div
  local content_type = pandoc.utils.type(content)
  if content_type == "Blocks" then
    div = pandoc.Div(content)
  elseif content_type == "Inlines" then
    div = pandoc.Div({ pandoc.Para(content) })
  else
    div = pandoc.Div({ pandoc.Para(pandoc.Inlines({ pandoc.Str(stringify(content)) })) })
  end
  div.classes:insert("Author")
  body:extend({ div })
end

-- Coerce a metadata value to Inlines (or nil if empty). Shared with the
-- latex side, which reads the journal fields through utilsapa as well.
local meta_inlines = utilsapa.meta_inlines

-- Journal masthead for jou mode, following the way the journals set one: the
-- journal's name at the right of the page with its logo opposite, a rule
-- under both, and the issue on the right beneath it with the copyright on the
-- left. Journal of Educational Psychology is the model.
--
-- The fields belong under journal, but an author who writes any of them at
-- the top level gets the same reading of them, which is how volume,
-- copyrightnotice and copyrighttext were given before there was anywhere else
-- to put them.

local journal_title = utilsapa.journal_title
local journal_field = utilsapa.journal_field
local journal_issue_line = utilsapa.journal_issue_line

-- The logo apaquarto ships with, asked for by writing logo: default.
--
-- The apaquarto logo, asked for by writing logo: default. utilsapa finds the
-- extension folder it ships in; the masthead writes it as raw typst, so the
-- path is the one typst reads.
local kDefaultLogo = "default"
local kShippedLogo = "apaquarto-logo.png"
local kOrcidIcon = "ORCID-iD_icon-vector.svg"

local function shipped_logo()
  return utilsapa.extension_file_typst(kShippedLogo)
end

-- A path as a typst string literal
local function typst_string(text)
  return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

-- "(c) 2025 The Author(s)", from whichever of the two was given
local function journal_copyright(meta)
  local notice = journal_field(meta, "copyrightnotice")
  local text = journal_field(meta, "copyrighttext")
  if not (notice or text) then return nil end
  local out = List:new { pandoc.Str("\u{00A9}") }
  if notice then
    out:extend({ pandoc.Space() })
    out:extend(notice)
  end
  if text then
    out:extend({ pandoc.Space() })
    out:extend(text)
  end
  return out
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

-- One side of the masthead's lower row as inlines rather than blocks, which is
-- what the latex masthead passes to a command.
local function masthead_inlines(first, second)
  local out = pandoc.Inlines({})
  if first then out:extend(first) end
  if second then
    if #out > 0 then out:insert(pandoc.LineBreak()) end
    out:extend(second)
  end
  if #out == 0 then return nil end
  return out
end

-- The journal's logo, resolved from logo: default to the file apaquarto ships.
-- Returns the path as the writer in question wants to read it, or nil.
local function masthead_logo(meta, resolve)
  local logo = journal_field(meta, "logo")
  if not logo then return nil end
  if stringify(logo) ~= kDefaultLogo then return stringify(logo) end
  local shipped = resolve(kShippedLogo)
  if shipped then return shipped end
  quarto.log.warning(
    "logo: default could not find " .. kShippedLogo ..
    " in the apaquarto extension folder, so the masthead has no logo.")
  return nil
end

-- The same masthead for plain latex, built out of the commands apalatex.tex
-- defines and set in a div formatlatex.lua knows to hand to \twocolumn. The
-- band is the one the typst format sets, off the Journal of Educational
-- Psychology, and the pieces go in the same order: the logo and the journal's
-- name on one line, a rule, then the copyright and the issn at the left with
-- the issue and the doi at the right.
-- The orcid lines of the author note, set off for latex the way
-- set_off_jou_orcid sets them off for typst.
local function set_off_jou_orcid_latex(blocks)
  local out = List:new {}
  local open = false
  for _, block in ipairs(blocks) do
    local orcid = block.t == "Para" and has_orcid(block)
    if orcid and not open then
      out:extend({ pandoc.RawBlock("latex", "\\begin{apajouorcid}") })
      open = true
    elseif open and not orcid then
      out:extend({ pandoc.RawBlock("latex", "\\end{apajouorcid}") })
      open = false
    end
    out:extend({ block })
  end
  if open then
    out:extend({ pandoc.RawBlock("latex", "\\end{apajouorcid}") })
  end
  return out
end

-- The impact statement in its box, for latex. The same shape box_jou_impact
-- draws in typst: the statement arrives as a heading followed by one or more
-- divs, and the keywords line after it, which is a para, closes the box.
local function box_jou_impact_latex(blocks)
  local out = List:new {}
  local i = 1
  while i <= #blocks do
    local block = blocks[i]
    if block.t == "Header" and block.identifier == "impact" then
      out:extend({ pandoc.RawBlock("latex", "\\begin{apajouimpact}") })
      out:extend({ block })
      i = i + 1
      while i <= #blocks and blocks[i].t == "Div" do
        out:extend({ blocks[i] })
        i = i + 1
      end
      out:extend({ pandoc.RawBlock("latex", "\\end{apajouimpact}") })
    else
      out:extend({ block })
      i = i + 1
    end
  end
  return out
end

local function latex_journal_metadata(meta)
  if not utilsapa.has_journal_masthead(meta) then return nil end

  local title = journal_title(meta)
  local logo = masthead_logo(meta, utilsapa.extension_file_relative)
  local url = journal_field(meta, "url")
  local issn = journal_field(meta, "issn")

  local url_line
  if url then url_line = List:new { pandoc.Link(url, stringify(url)) } end
  local issn_line
  if issn then
    issn_line = List:new { pandoc.Str("ISSN:"), pandoc.Space() }
    issn_line:extend(issn)
  end

  local left = masthead_inlines(journal_copyright(meta), issn_line)
  local right = masthead_inlines(journal_issue_line(meta), url_line)

  local blocks = List:new {}

  local head = pandoc.Inlines({ pandoc.RawInline("latex",
    "\\apamastheadhead{" ..
    (logo and ("\\apamastheadlogo{" .. logo:gsub("\\", "/") .. "}") or "") ..
    "}{") })
  if title then head:extend(title) end
  head:insert(pandoc.RawInline("latex", "}"))
  blocks:insert(pandoc.Para(head))

  blocks:insert(pandoc.RawBlock("latex", "\\apamastheadline"))

  if left or right then
    local foot = pandoc.Inlines({
      pandoc.RawInline("latex", "\\apamastheadfoot{") })
    if left then foot:extend(left) end
    foot:insert(pandoc.RawInline("latex", "}{"))
    if right then foot:extend(right) end
    foot:insert(pandoc.RawInline("latex", "}"))
    blocks:insert(pandoc.Para(foot))
  end

  return pandoc.Div(blocks, pandoc.Attr("", { "JournalMasthead" }))
end

local function typst_journal_metadata(meta)
  local title = journal_title(meta)
  local issue_line = journal_issue_line(meta)
  local url = journal_field(meta, "url")
  local logo = journal_field(meta, "logo")
  if logo and stringify(logo) == kDefaultLogo then
    local shipped = shipped_logo()
    if shipped then
      logo = pandoc.Inlines({ pandoc.Str(shipped) })
    else
      quarto.log.warning(
        "logo: default could not find " .. kShippedLogo ..
        " in the apaquarto extension folder, so the masthead has no logo.")
      logo = nil
    end
  end
  local issn = journal_field(meta, "issn")
  local copyright = journal_copyright(meta)

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
  result:extend({ pandoc.RawBlock("typst", "#joumastheadlift()") })
  result:extend({ pandoc.RawBlock("typst",
    "#block(width: 100%, below: 1em)[\n" ..
    "#set par(first-line-indent: 0pt)") })

  -- Above the rule: the logo at the left, the journal's name at the right,
  -- both sitting on it.
  if logo or title then
    result:extend({ pandoc.RawBlock("typst",
      "#grid(columns: (1fr, auto), align: (left + bottom, right + bottom),\n" ..
      "  column-gutter: 1em, [") })
    -- The logo is written as typst rather than as a pandoc image so that it
    -- can be fitted to the height of the masthead band: pandoc drops a height
    -- it cannot read as a dimension, and the band is named in the template.
    if logo then
      result:extend({ pandoc.RawBlock("typst",
        "#image(" .. typst_string(stringify(logo)) .. ", height: joulogoheight)") })
    end
    result:extend({ pandoc.RawBlock("typst",
      "], [\n#set text(size: joujournalsize)") })
    if title then
      result:extend({ pandoc.Plain(title) })
    end
    result:extend({ pandoc.RawBlock("typst", "])") })
  end

  result:extend({ pandoc.RawBlock("typst",
    -- Plain v rather than weak: a weak space collapses against the edge
    -- of a block, which left the rule touching the descenders of the
    -- journal's name whenever there was no logo to give the row height.
    "#v(3pt)\n#line(length: 100%, stroke: 0.5pt + black)\n#v(3pt)") })

  -- Below it: the copyright at the left, the issue and the doi at the right.
  if left or right then
    result:extend({ pandoc.RawBlock("typst",
      "#grid(columns: (1fr, 1fr), align: (left + top, right + top),\n" ..
      "  column-gutter: 1em, [\n#set text(size: joumastheadsize)") })
    if left then result:extend(left) end
    result:extend({ pandoc.RawBlock("typst",
      "], [\n#set text(size: joumastheadsize)") })
    if right then result:extend(right) end
    result:extend({ pandoc.RawBlock("typst", "])") })
  end

  result:extend({ pandoc.RawBlock("typst", "]") })

  return result
end

return {
  { Meta = get_and },
  {
    Pandoc = function(doc)
      if utilsapa.apa7_latex(doc.meta) then return nil end
      local body = List:new {}
      local meta = doc.meta

      local latex_jou = utilsapa.plain_latex(meta) and meta.documentmode
        and stringify(meta.documentmode) == "jou"
      local typst_jou = is_typst_mode(meta, "jou")
      local typst_doc = is_typst_mode(meta, "doc")
      local typst_stu = is_typst_mode(meta, "stu")

      local documenttitle = ""
      local intabovetitle = 2
      local newline = pandoc.LineBreak()
      if FORMAT:match 'docx' then
        newline = pandoc.SoftBreak()
      end

      if meta.apatitledisplay then
        if meta["blank-lines-above-title"] and #meta["blank-lines-above-title"] > 0 then
          local possiblenumber = stringify(meta["blank-lines-above-title"])
          if type(possiblenumber) == "number" then
            local intnumber = tonumber(possiblenumber) * 1
            intabovetitle = math.floor(intnumber) or 2
          else
            intabovetitle = 2
          end
        end
        for i = 1, intabovetitle do
          body:extend({ newline })
        end
        documenttitle = pandoc.Header(1, meta.apatitledisplay)
        documenttitle.classes = { "title", "unnumbered", "unlisted" }
        documenttitle.identifier = "title"
        if not meta["suppress-title"] then
          body:extend({ documenttitle })
        end
      end

      local byauthor = meta["by-author"]

      -- Byline for the journal-mode even-page running head. Left unset when
      -- authorship is masked or suppressed, and the header falls back to the
      -- short title.
      if byauthor and not meta["suppress-author"] and
          not (meta["mask"] and stringify(meta["mask"]) == "true") then
        local line = running_authors(byauthor)
        if line then
          meta["jou-running-authors"] = pandoc.MetaString(line)
        end
      end
      local affiliations = meta["affiliations"]

      local authornote = false
      if meta["author-note"] and not meta["suppress-author-note"] then
        authornote = meta["author-note"]
      end

      local mask = false

      if meta["mask"] and stringify(meta["mask"]) == "true" then
        mask = true
      end

      local affilations_different = meta.affiliationsdifferent

      if meta["suppress-affiliation"] then
        affilations_different = false
      end

      local affiliations_str = List()

      local authordiv = pandoc.Div({})
      if not meta["suppress-author"] and byauthor then
        authordiv = pandoc.Div({
          newline,
          get_author_paragraph(byauthor, affilations_different)
        })
      end

      authordiv.classes:insert("Author")
      if affiliations then
        if byauthor then
          for i, a in ipairs(affiliations) do
            affiliations_str = List()

            mysep = pandoc.Str("")

            if affilations_different and not meta["suppress-author"] then
              affiliations_str:extend({ pandoc.Superscript(stringify(a.number)) })
            end

            if chkmeta(a.group) then
              affiliations_str:extend(a.group)
              mysep = pandoc.Str(", ")
            end

            if chkmeta(a.department) then
              affiliations_str:extend({ mysep })
              affiliations_str:extend(a.department)
              mysep = pandoc.Str(", ")
            end

            if chkmeta(a.name) then
              affiliations_str:extend({ mysep })
              affiliations_str:extend(a.name)
              mysep = pandoc.Str(", ")
            end

            if not (chkmeta(a.group) or chkmeta(a.department) or chkmeta(a.name)) then
              mysep = pandoc.Str("")
              if chkmeta(a.city) then
                affiliations_str:extend(a.city)
                mysep = pandoc.Str(", ")
              end
              if chkmeta(a.region) then
                affiliations_str:extend({ mysep })
                affiliations_str:extend(a.region)
              end
            end
            if not meta["suppress-affiliation"] then
              authordiv.content:extend({ pandoc.Para(pandoc.Inlines(affiliations_str)) })
            end
          end
        end
      end

      if not mask then
        body:extend({ authordiv })
      end

      if typst_stu and not mask then
        add_student_field(body, meta, "course")
        add_student_field(body, meta, "professor")
        add_student_field(body, meta, "duedate")
        add_student_field(body, meta, "note")
      end

      if meta["draft-date"] then
        draftdate = os.date("%B %d, %Y")
        if type(meta["draft-date"]) == "table" then
          draftdate = meta["draft-date"]
        end
        draftdatediv = pandoc.Div({
          pandoc.Para(draftdate)
        })
        draftdatediv.classes:insert("Author")
        body:extend({ draftdatediv })
      end

      local authornoteheadertext = "Author Note"
      if meta.language and meta.language["title-block-author-note"] then
        authornoteheadertext = meta.language["title-block-author-note"]
      end

      local emailword = "Email"
      if meta.language and meta.language.email then
        emailword = stringify(meta.language.email)
      end

      local authornoteheader = pandoc.Header(1, authornoteheadertext)
      authornoteheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
      authornoteheader.identifier = "author-note"

      local intabovenote = 2
      local possiblenumber = 2

      if not mask and not meta["suppress-author-note"] and (byauthor or authornote) then
        if authornote then
          if authornote["blank-lines-above-author-note"] and #authornote["blank-lines-above-author-note"] > 0 then
            possiblenumber = stringify(authornote["blank-lines-above-author-note"])
            intabovenote = math.floor(tonumber(possiblenumber)) or 2
          end
        end

        if meta["blank-lines-above-author-note"] and #meta["blank-lines-above-author-note"] > 0 then
          possiblenumber = stringify(meta["blank-lines-above-author-note"])
          intabovenote = math.floor(tonumber(possiblenumber)) or 2
        end

        for i = 1, intabovenote do
          body:extend({ newline })
        end

        body:extend({ authornoteheader })
      end

      local img

      if byauthor then
        for i, a in ipairs(byauthor) do
          if a.orcid then
            -- The icon goes into the document rather than into raw typst,
            -- so it is written as a path from the document, which every
            -- writer reads the same way.
            local orcidfile = utilsapa.extension_file_relative(kOrcidIcon)
            img = pandoc.Image("Orcid ID Logo: A green circle with white letters ID", orcidfile or kOrcidIcon)
            img.attr = pandoc.Attr('orcid', { 'img-fluid' }, { width = '4.23mm' })
            pp = pandoc.Para(pandoc.Str(""))
            pp.content:extend(a.apaauthordisplay)
            pp.content:extend({ pandoc.Space(), img })
            pp.content:extend({ pandoc.Space(), pandoc.Link("https://orcid.org/" .. stringify(a.orcid),
              "https://orcid.org/" .. stringify(a.orcid)) })

            if not mask and not meta["suppress-orcid"] then
              body:extend({ pp })
            end
          end
        end
      end

      if authornote then
        if authornote["status-changes"] then
          local second_paragraph = pandoc.Para(pandoc.Str(""))
          second_paragraph = extend_paragraph(second_paragraph,
            authornote["status-changes"]["affiliation-change"] or authornote["affiliation-change"] or
            meta["affiliation-change"])
          second_paragraph = extend_paragraph(second_paragraph,
            authornote["status-changes"].deceased or authornote.deceased or meta.deceased)

          if #second_paragraph.content > 1 then
            if not mask and not meta["suppress-status-change-paragraph"] then
              body:extend({ second_paragraph })
            end
          end
        end

        if authornote.disclosures then
          local third_paragraph = pandoc.Para(pandoc.Str(""))

          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["study-registration"] or authornote["study-registration"] or
            meta["study-registration"])
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["data-sharing"] or authornote["data-sharing"] or meta["data-sharing"])
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["related-report"] or authornote["related-report"] or meta["related-report"])
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["conflict-of-interest"] or authornote["conflict-of-interest"] or
            meta["conflict-of-interest"])
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["financial-support"] or authornote["financial-support"] or meta["financial-support"])
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures.gratitude or authornote.gratitude or meta.gratitude)
          third_paragraph = extend_paragraph(third_paragraph,
            authornote.disclosures["authorship-agreements"] or authornote["authorship-agreements"] or
            meta["authorship-agreements"])

          if #third_paragraph.content > 1 then
            if not mask and not meta["suppress-disclosures-paragraph"] then
              body:extend({ third_paragraph })
            end
          end
        end
      end

      local credit_paragraph = pandoc.Para(pandoc.Str(""))

      if byauthor then
        for i, a in ipairs(byauthor) do
          if a.roles then
            credit_paragraph = extend_paragraph(credit_paragraph, { pandoc.Emph(a.apaauthordisplay) }, pandoc.Str(". "))
            credit_paragraph.content:extend({ pandoc.Strong(pandoc.Str(": ")) })
            local rolelist = {}
            for j, role in ipairs(a.roles) do
              if role.role == "Writing - original draft" or role.role == "writing - original draft" then
                role["vocab-term"] = "writing – original draft"
              end
              if role.role == "Writing - reviewing & editing" or role.role == "writing - reviewing & editing" then
                role["vocab-term"] = "Writing – reviewing & editing"
              end

              if role["vocab-term"] then
                role.display = role["vocab-term"]
              else
                role.display = role.role
              end

              if role["degree-of-contribution"] then
                role.display = role.display .. " (" .. role["degree-of-contribution"] .. ")"
              end
              table.insert(rolelist, pandoc.Str(role.display))
            end
            credit_paragraph.content:extend(oxfordcommalister(rolelist))
          end
        end
      end

      if #credit_paragraph.content > 1 then
        local authorroleintroduction = pandoc.Str(
        "Author roles were classified using the Contributor Role Taxonomy (CRediT; https://credit.niso.org/) as follows:")
        if meta.language and meta.language["title-block-role-introduction"] then
          authorroleintroduction = meta.language["title-block-role-introduction"]
          if type(authorroleintroduction) == "string" then
            authorroleintroduction = pandoc.Inlines(authorroleintroduction)
          end
        end

        credit_paragraph.content:insert(1, pandoc.Space())
        for i, j in pairs(authorroleintroduction) do
          credit_paragraph.content:insert(i, j)
        end
        if not mask and not meta["suppress-credit-statement"] then
          body:extend({ credit_paragraph })
        end
      end

      local corresponding_paragraph = pandoc.Para(pandoc.Str(""))
      local check_corresponding = false
      if meta["author-note"] and meta["author-note"]["correspondence-note"] then
        corresponding_paragraph.content:extend(meta["author-note"]["correspondence-note"])
      else
        if byauthor then
          for i, a in ipairs(byauthor) do
            if a.attributes then
              if a.attributes.corresponding and stringify(a.attributes.corresponding) == "true" then
                if check_corresponding then
                  error("There can only be one author marked as the corresponding author. " ..
                  stringify(a.apaauthordisplay) .. " is the second author you have marked as the corresponding author.")
                end
                check_corresponding = true
                corresponding_paragraph.content:extend(a.apaauthordisplay)

                if a.affiliations then
                  local address = a.affiliations[1]
                  if not meta["suppress-corresponding-group"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.group, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-department"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.department,
                      pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-affiliation-name"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.name, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-address"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.address, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-city"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.city, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-region"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.region, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-postal-code"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address["postal-code"])
                  end

                  if not meta["suppress-corresponding-country"] then
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.country, pandoc.Str(", "))
                  end

                  if not meta["suppress-corresponding-email"] then
                    if a.email then
                      corresponding_paragraph.content:extend({ pandoc.Str(", " .. emailword .. ":") })
                      corresponding_paragraph = extend_paragraph(corresponding_paragraph,
                        { pandoc.Link(stringify(a.email), "mailto:" .. stringify(a.email)) })
                    end
                  end
                end
              end
            end
          end
        end

        if #corresponding_paragraph.content > 1 then
          local correspondencenote = pandoc.Str("Correspondence concerning this article should be addressed to ")
          if meta.language and meta.language["title-block-correspondence-note"] then
            correspondencenote = meta.language["title-block-correspondence-note"]
            if type(correspondencenote) == "string" then
              correspondencenote = pandoc.Inlines(correspondencenote)
            end
          end
          corresponding_paragraph.content:insert(1, pandoc.Space())
          for i, j in pairs(correspondencenote) do
            corresponding_paragraph.content:insert(i, j)
          end
        end
      end

      if (not mask) and (not meta["suppress-corresponding-paragraph"]) then
        body:extend({ corresponding_paragraph })
      end

      if meta.apaabstract and #meta.apaabstract > 0 and not meta["suppress-abstract"] then
        local abstractheadertext = pandoc.Str("Abstract")
        if meta.language and meta.language["section-title-abstract"] then
          abstractheadertext = meta.language["section-title-abstract"]
        end
        local abstractheader = pandoc.Header(1, abstractheadertext)
        abstractheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
        abstractheader.identifier = "abstract"
        if FORMAT:match 'docx' then
          body:extend({ pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>') })
        end

        if FORMAT:match 'typst' then
          body:extend({ pandoc.RawBlock('typst', '#pagebreak()\n\n') })
        end

        if FORMAT:match 'html' then
          body:extend({ pandoc.RawBlock('html', '<br>') })
        end

        body:extend({ abstractheader })
        local abstract_paragraph = pandoc.Para(pandoc.Str(""))

        if pandoc.utils.type(meta.apaabstract) == "Inlines" then
          abstract_paragraph.content:extend(meta.apaabstract or meta.abstract)
          local abstractdiv = pandoc.Div(abstract_paragraph)
          abstractdiv.classes:insert("AbstractFirstParagraph")
          body:extend({ abstractdiv })
        end

        if pandoc.utils.type(meta.apaabstract) == "Blocks" then
          body:extend(paragraph_divs(meta.apaabstract))
        end
      end

      if meta["impact-statement"] and #meta["impact-statement"] > 0 and not meta["suppress-impact-statement"] then
        local impactheadertext = pandoc.Str("Impact Statement")
        if meta.language and meta.language["title-impact-statement"] then
          impactheadertext = meta.language["title-impact-statement"]
        end
        local impactheader = pandoc.Header(1, impactheadertext)
        impactheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
        impactheader.identifier = "impact"
        body:extend({ impactheader })
        local impact_paragraph = pandoc.Para(pandoc.Str(""))
        if pandoc.utils.type(meta["impact-statement"]) == "Inlines" then
          impact_paragraph.content:extend(meta["impact-statement"])
          local impactdiv = pandoc.Div(impact_paragraph)
          impactdiv.classes:insert("AbstractFirstParagraph")
          body:extend({ impactdiv })
        end

        -- An impact statement of more than one paragraph, which is what a
        -- statement written as a section of the document gives.
        if pandoc.utils.type(meta["impact-statement"]) == "Blocks" then
          body:extend(paragraph_divs(meta["impact-statement"]))
        end
      end

      if meta.keywords and not meta["suppress-keywords"] then
        local keywordsword = pandoc.Str("Keywords")
        if meta.language and meta.language["title-block-keywords"] then
          keywordsword = stringify(meta.language["title-block-keywords"])
        end

        local keywords_paragraph = pandoc.Para({ pandoc.Emph(keywordsword), pandoc.Str(":") })

        if pandoc.utils.type(meta.keywords) == "Inlines" then
          keywords_paragraph.content:extend(meta.keywords)
        else
          for i, k in ipairs(meta.keywords) do
            if i == 1 then
              keywords_paragraph = extend_paragraph(keywords_paragraph, k)
            else
              keywords_paragraph = extend_paragraph(keywords_paragraph, k, pandoc.Str(", "))
            end
          end
        end

        body:extend({ keywords_paragraph })
      end

      -- A pointer to supplemental materials (a repository, an OSF page, a data
      -- archive) sits on its own line under the keywords, labelled the way the
      -- keywords line is.
      if meta["supplemental-materials"] and
          stringify(meta["supplemental-materials"]) ~= "" and
          not meta["suppress-supplemental-materials"] then
        local supplementalword = pandoc.Str("Supplemental materials")
        if meta.language and meta.language["title-supplemental-materials"] then
          supplementalword = stringify(meta.language["title-supplemental-materials"])
        end

        local supplemental_paragraph = pandoc.Para({ pandoc.Emph(supplementalword), pandoc.Str(":"), pandoc.Space() })
        supplemental_paragraph.content:extend(meta_inlines(meta["supplemental-materials"]))
        body:extend({ supplemental_paragraph })
      end

      if meta["word-count"] then
        local word_count_word = "Word Count"
        if meta.language and meta.language["title-block-word-count"] then
          word_count_word = stringify(meta.language["title-block-word-count"])
        end


        local word_count_paragraph = pandoc.Para({ pandoc.Emph(word_count_word), pandoc.Str(": " .. meta.wordn) })
        body:extend({ word_count_paragraph })
      end

      if FORMAT:match 'docx' then
        body:extend({ pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>') })
      end

      if FORMAT:match 'typst' then
        local pg = '#pagebreak()\n\n'
        if meta['first-page'] then
          pg = '#counter(page).update(' .. stringify(meta['first-page']) .. ' - 1)\n #pagebreak()\n\n'
        end
        body:extend({ pandoc.RawBlock('typst', pg) })
      end



      if FORMAT:match 'html' then
        body:extend({ pandoc.RawBlock('html', '<br>') })
      end

      local myshorttitle = ""

      if meta["apatitle"] then
        myshorttitle = meta["apatitle"]
      end

      if meta["shorttitle"] and #meta["shorttitle"] > 0 then
        myshorttitle = meta["shorttitle"]
      end

      for i, v in ipairs(myshorttitle) do
        if v.t == "Str" then
          v.text = pandoc.text.upper(v.text)
        end
      end
      if not meta["suppress-short-title"] then
        meta.description = myshorttitle
      else
        meta.description = " "
      end

      if meta["suppress-title-page"] then
        body = List:new {}
      end

      if FORMAT:match 'typst' and PANDOC_WRITER_OPTIONS["table_of_contents"] then
        body:extend({ pandoc.RawBlock('typst', '\n\n#show outline.entry: it => {show link: set text(fill: black)\nlink(it.element.location(),it.indented(none, it.inner(), ))}\n\n#outline(title: [Table of Contents], indent: 1.5em)\n\n') })
        body:extend({ pandoc.RawBlock('typst', '#pagebreak()\n\n') })
      end

      if FORMAT:match 'typst' and meta["list-of-figures"] then
        body:extend({ pandoc.RawBlock('typst',
          '\n\n#outline(title: [List of Figures], target: figure.where(kind: "quarto-float-fig"),)\n\n') })
        body:extend({ pandoc.RawBlock('typst', '#pagebreak()\n\n') })
      end

      if FORMAT:match 'typst' and meta["list-of-tables"] then
        body:extend({ pandoc.RawBlock('typst',
          '\n\n#outline(title: [List of Tables], target: figure.where(kind: "quarto-float-tbl"),)\n\n') })
        body:extend({ pandoc.RawBlock('typst', '#pagebreak()\n\n') })
      end

      if meta.apatitledisplay and not meta["suppress-title-introduction"] then
        local firstpageheader = documenttitle:clone()
        firstpageheader.identifier = "firstheader"
        firstpageheader.classes = { "title", "unnumbered" }
        body:extend({ firstpageheader })
      end

      if typst_jou then
        -- Masthead (title/byline/affiliations/abstract) spans both columns via
        -- place(float); the author note flows into the two-column body beneath
        -- it, set off by a thin rule, rather than crowding the masthead.
        local front, narrow, notes, tail = split_jou_frontmatter(body)
        local metadata = typst_journal_metadata(meta)
        local out = List:new {}
        out:extend({ pandoc.RawBlock('typst',
          '#place(top, scope: "parent", float: true, clearance: 1.5em)[') })
        -- The masthead carries its own block, sizes and alignment, and lifts
        -- itself into the top margin of the page it sits on.
        out:extend(metadata)
        -- The title and authors. The template's heading rule pins every
        -- heading to the body size, so the title size is restated here in a
        -- show rule of its own, which being the later rule wins inside this
        -- block only.
        -- apa7's journal title is \LARGE but not bold, so the weight is reset
        -- along with the size; typst headings are bold by default.
        out:extend({ pandoc.RawBlock('typst',
          '#block(width: 100%)[\n' ..
          '#show heading.where(level: 1): set text(size: joutitlesize, weight: "regular")') })
        out:extend(size_jou_byline(front))
        out:extend({ pandoc.RawBlock('typst', ']') })
        if #narrow > 0 then
          -- Abstract, impact statement and keywords: smaller, and set in a
          -- block narrower than the masthead, centered under the authors.
          -- Leading is set in em so it follows the smaller text at the same
          -- ratio the body uses, rather than keeping the body's absolute
          -- leading and looking slack at this size.
          out:extend({ pandoc.RawBlock('typst',
            '#align(center)[\n' ..
            '#block(width: jouabstractwidth, above: 1em, below: 0.6em)[\n' ..
            '#set align(left)\n#set text(size: jouabstractsize)\n' ..
            '#set par(leading: jouabstractleading, first-line-indent: 0pt)\n' ..
            '#show heading.where(level: 1): set text(size: jouabstractsize)') })
          out:extend(box_jou_impact(narrow))
          out:extend({ pandoc.RawBlock('typst', ']\n]') })
        end
        out:extend({ pandoc.RawBlock('typst', ']') })
        if #notes > 0 then
          -- jouauthornote in typst-template.typ places the note at the foot of
          -- the first column, or across the foot of the page in two columns
          -- when it is too long for one. Emitting it at the head of the body
          -- puts it on the first page. author-note-columns overrides the
          -- reading it takes of the length; anything else, "auto" included,
          -- leaves the decision to it.
          local notecols = "auto"
          local asked
          -- There can be a note without an author-note field: a corresponding
          -- author makes one out of the address and the email. Reading the
          -- field without looking first brought the render down on any journal
          -- document that had not written one.
          local note_meta = meta["author-note"]
          if note_meta and note_meta["author-note-columns"] then
            asked = stringify(note_meta["author-note-columns"])
            if asked == "1" or asked == "2" then
              notecols = asked
            end
          end
          if meta["author-note-columns"] then
            asked = stringify(meta["author-note-columns"])
            if asked == "1" or asked == "2" then
              notecols = asked
            end
          end
          out:extend({ pandoc.RawBlock('typst',
            '#jouauthornote(cols: ' .. notecols .. ')[') })
          out:extend(set_off_jou_orcid(fit_jou_orcid(notes)))
          out:extend({ pandoc.RawBlock('typst', ']') })
        end
        out:extend(tail)
        out:extend(doc.blocks)
        body = out
      elseif typst_doc then
        body = strip_doc_frontmatter(body)
        body:extend(doc.blocks)
      elseif latex_jou then
        -- A published article in plain latex, laid out the way the typst one
        -- is: the masthead, the title and the byline, then the abstract and
        -- what follows it in a narrower block, all of it spanning the page;
        -- the author note goes to the foot of the first column. The same
        -- split as typst makes, since the front matter it reads is the same;
        -- formatlatex.lua is what turns each part into latex, and it needs
        -- them marked off from one another to do it.
        local front, narrow, notes, tail = split_jou_frontmatter(body)
        local out = List:new {}
        local masthead = latex_journal_metadata(meta)
        if masthead then out:extend({ masthead }) end
        out:extend({ pandoc.Div(front, pandoc.Attr("", { "JournalWide" })) })
        if #narrow > 0 then
          out:extend({ pandoc.Div(box_jou_impact_latex(narrow),
            pandoc.Attr("", { "JournalNarrow" })) })
        end
        if #notes > 0 then
          -- The orcid icon carries a width in millimetres, which beside the
          -- note's smaller text is taller than the text itself and opens up
          -- every line it sits on. Sized to the text it leaves the line
          -- height alone, which is what fit_jou_orcid does for typst.
          out:extend({ pandoc.Div(
            set_off_jou_orcid_latex(fit_jou_orcid(notes)),
            pandoc.Attr("", { "JournalNote" })) })
        end
        out:extend(tail)
        out:extend(doc.blocks)
        body = out
      else
        body:extend(doc.blocks)
      end
      return pandoc.Pandoc(body, meta)
    end
  }
}

-- Sets the blocks apaquarto's filters produce, in latex.
--
-- This is the plain latex format's counterpart to typst/formattypst.lua. By
-- the time it runs, frontmatter.lua has written the title page, apanote.lua
-- has written the notes and apacaption.lua the figure and table titles, all as
-- ordinary divs and headers carrying the classes those filters use. Nothing
-- here decides what a document says; it only wraps each of those in the
-- command that apalatex.tex defines for it.
--
-- A div that is not wrapped goes through pandoc unchanged, which is what
-- should happen to everything this file does not name.

local utilsapa = require("utilsapa")

local mode = "man"
local shorttitle = nil
local line_numbers = false

local function raw(text)
  return pandoc.RawBlock("latex", text)
end

-- A block wrapped in a latex environment.
local function environment(name, blocks)
  local out = pandoc.List({ raw("\\begin{" .. name .. "}") })
  out:extend(blocks)
  out:insert(raw("\\end{" .. name .. "}"))
  return out
end

-- A heading or paragraph passed to a latex command that takes its text.
local function command(name, inlines)
  local out = pandoc.List({ raw("\\" .. name .. "{") })
  out:insert(pandoc.Plain(inlines))
  out:insert(raw("}"))
  return out
end

-- The type size the writer asked for, with fontsize or with a size among the
-- class options, or nil when they asked for none. The format's own manifest
-- sets 12pt, so that one does not count as a request.
local function asked_for_size(m)
  if m.fontsize then
    local text = utilsapa.stringify(m.fontsize)
    if text ~= "" then return text end
  end
  if m.classoption then
    for _, option in ipairs(m.classoption) do
      local text = utilsapa.stringify(option)
      if text:match("^%d+%.?%d*pt$") and text ~= "12pt" then
        return text
      end
    end
  end
  return nil
end

-- Whether the writer asked for numbered lines, which APA wants on a
-- manuscript sent out for review.
local function asked_for_line_numbers(m)
  if m["numbered-lines"] == nil then return false end
  return utilsapa.stringify(m["numbered-lines"]) ~= "false"
end

local function meta(m)
  if m.documentmode then mode = utilsapa.stringify(m.documentmode) end
  if m.shorttitle then
    shorttitle = utilsapa.stringify(m.shorttitle)
  elseif m.title then
    shorttitle = utilsapa.stringify(m.title)
  end
  -- The running head is a preamble setting, so it goes in the header rather
  -- than into the body where the rest of this filter works.
  if shorttitle and shorttitle ~= "" then
    quarto.doc.include_text("in-header",
      "\\setapashorttitle{" .. shorttitle:gsub("([\\{}%$&#%^_~%%])", "\\%1") .. "}")
  end

  -- frontmatter.lua has already written the title page into the body, so the
  -- fields it was built from are taken away before quarto's template can set
  -- them a second time. Leaving them would print the title, the authors and
  -- the abstract twice over, and would call \maketitle, which puts the first
  -- page into the plain page style and loses the running head from it.
  m.title = nil
  m.subtitle = nil
  m.author = nil
  m.date = nil
  m.abstract = nil
  m.keywords = nil

  -- Quarto writes every markdown table as a longtable, and flextable builds
  -- its tables out of one. Every mode sets those as ordinary tabulars.
  --
  -- Two columns is what made this necessary -- a longtable refuses to start
  -- there at all -- but it is wanted everywhere. A longtable inside a float,
  -- which is where every table in this format goes, never emits the material
  -- its \endlastfoot marks: a pandoc table lost the \bottomrule that closes
  -- it and a flextable lost its note row, silently, in manuscript, student
  -- and document modes. Set as a tabular the foot is written out under the
  -- table, which is where it belongs, and a longtable inside a float could
  -- not break over pages to earn its keep either way.
  --
  -- At the start of the document rather than here, because the command renews
  -- the longtable environment and an include reaches the preamble before
  -- quarto's own packages have defined it.
  quarto.doc.include_text("in-header",
    "\\AtBeginDocument{\\apalongtableastabular}")

  -- A published article is set in two columns and carries the authors' names
  -- in the head rather than the manuscript's short title.
  if mode == "jou" then
    -- A published article is set smaller and single spaced, which is what
    -- apa7 sets its journal mode at: ten point on twelve, against the
    -- twelve on twenty-four a manuscript takes. The size is asked for as a
    -- class option so that every size command scales with it rather than
    -- only the body text, and only when the writer has not asked for a
    -- size of their own.
    -- Set as the one class option, so that it is the size the class is given
    -- rather than one of two it has to choose between: the manifest asks for
    -- 12pt, and a size the writer put beside it had no effect at all.
    local size = asked_for_size(m) or "10pt"
    -- twoside as well, which is what makes a recto page differ from a verso
    -- one. Without it fancyhdr's [LE] and [RO] both land on every page and
    -- the head cannot alternate.
    m.classoption = pandoc.MetaList({
      pandoc.MetaString(size), pandoc.MetaString("twoside") })
    -- The page of a published article, which the typst format sets at three
    -- quarters of an inch all round rather than the inch a manuscript takes.
    -- includehead puts the running head inside that margin rather than above
    -- it, which is where typst puts its own: the text block then begins a
    -- head and a little more below the top of the page, as it does there.
    m.geometry = pandoc.MetaList({
      pandoc.MetaString("margin=0.75in"),
      pandoc.MetaString("includehead"),
      pandoc.MetaString("headheight=13pt"),
      pandoc.MetaString("headsep=4pt") })
    quarto.doc.include_text("in-header", "\\singlespacing")
    -- Two columns, asked for at the start of the document. A journal that has
    -- a masthead asks for them differently: the masthead is handed to
    -- \twocolumn in the body, since its optional argument is the only thing
    -- that sets material across both columns of a two-column page, and asking
    -- for two columns twice would leave the first page blank.
    if not utilsapa.has_journal_masthead(m) then
      quarto.doc.include_text("in-header", "\\apatwocolumn")
    end
    quarto.doc.include_text("in-header", "\\apajournalhead")
    quarto.doc.include_text("in-header", "\\apajoucolumnsep")
    quarto.doc.include_text("in-header", "\\apajoufloats")
    -- References hang by the paragraph indent rather than by a manuscript's
    -- half inch, which is what the typst format does in this mode.
    quarto.doc.include_text("in-header", "\\apajouhangindent")
    local authors = m["jou-running-authors"]
    if authors then
      quarto.doc.include_text("in-header",
        "\\setapaauthorline{" ..
        utilsapa.stringify(authors):gsub("([\\{}%$&#%^_~%%])",
          "\\%1") .. "}")
    end
  end
  -- Numbered lines, which apa7 draws with lineno and so does this. The size,
  -- the right alignment and the distance from the text are lineno's own,
  -- which is what apa7 leaves them at; journal mode moves the number closer
  -- and opens the gutter, so that the number of a second-column line has
  -- somewhere to sit. Emitted after the journal block above, whose narrower
  -- gutter this one supersedes.
  --
  -- nolongtablepatch: lineno patches longtable to number its rows, and every
  -- table here is set as a tabular instead, so the patch has nothing to do.
  line_numbers = asked_for_line_numbers(m)
  if line_numbers then
    quarto.doc.include_text("in-header",
      "\\usepackage[nolongtablepatch]{lineno}")
    if mode == "jou" then
      quarto.doc.include_text("in-header",
        "\\setlength{\\linenumbersep}{5pt}")
      quarto.doc.include_text("in-header",
        "\\setlength{\\columnsep}{25pt}")
    end
    quarto.doc.include_text("in-header", "\\linenumbers")
  end

  return m
end

-- Manuscript and student papers put the title page and the abstract on pages
-- of their own. The other modes run straight on.
local function paged()
  return mode == "man" or mode == "stu"
end

local function is_title(block)
  return block.t == "Header" and block.classes:includes("title")
end

local function is_titlepage_heading(block)
  return block.t == "Header" and block.classes:includes("AuthorNote")
end

local function front_div(block, name)
  return block.t == "Div" and block.classes:includes(name)
end

-- Whether a block is one of the line breaks the manuscript front matter
-- spaces itself out with. They arrive as a bare LineBreak among the blocks,
-- or wrapped in a paragraph of their own; either way a journal byline follows
-- its title directly and wants none of them. Counting a wrapped one as a
-- paragraph is what dropped the byline to the affiliation size, since it came
-- first and took the size switch with it.
local function is_spacing(block)
  if block.t == "LineBreak" then return true end
  if block.t ~= "Para" and block.t ~= "Plain" then return false end
  for _, inline in ipairs(block.content) do
    if inline.t ~= "LineBreak" and inline.t ~= "SoftBreak"
        and inline.t ~= "Space" then
      return false
    end
  end
  return true
end

-- The byline, with the affiliations under it one size smaller. Quarto puts
-- both inside one div; apa7 sets the byline larger, so the size is switched
-- after the first paragraph, which is the byline.
local function jou_byline(div)
  local out = pandoc.List({ raw("\\begin{apajoubyline}") })
  local switched = false
  for _, block in ipairs(div.content) do
    if not is_spacing(block) then
      out:insert(block)
      if not switched and (block.t == "Para" or block.t == "Plain") then
        switched = true
        out:insert(raw("\\apajouaffiliationsize"))
      end
    end
  end
  out:insert(raw("\\end{apajoubyline}"))
  return out
end

-- One block of front matter, written out as latex. jou is a published
-- article, which sets the title and the byline at sizes of their own.
local function render_front(list, jou)
  local out = pandoc.List({})
  for _, block in ipairs(list) do
    if is_title(block) and block.identifier == "title" then
      -- The title page proper. APA sets the title three or four lines down.
      if paged() then out:insert(raw("\\vspace*{3\\baselineskip}")) end
      out:extend(command(jou and "apajoutitle" or "apatitle", block.content))

    elseif is_title(block) and block.identifier == "firstheader" then
      -- The title again, at the head of the body.
      if paged() then out:insert(raw("\\clearpage")) end
      out:extend(command("apatitle", block.content))

    elseif is_titlepage_heading(block) then
      -- Author Note, Abstract, Impact Statement. The abstract opens a page of
      -- its own in the modes that have one.
      if paged() and block.identifier == "abstract" then
        out:insert(raw("\\clearpage"))
      end
      out:extend(command("apatitlepageheading", block.content))

    elseif block.t == "Div" and block.classes:includes("Author") then
      if jou then
        out:extend(jou_byline(block))
      else
        out:extend(environment("apaauthor", block.content))
      end

    elseif block.t == "Div" and block.classes:includes("AbstractFirstParagraph") then
      out:extend(environment("apanoindent", block.content))

    else
      out:insert(block)
    end
  end
  return out
end

local function blocks(doc)
  local out = pandoc.List({})

  -- The front matter of a published article, which frontmatter.lua has
  -- already sorted into the masthead, the title and byline, the abstract and
  -- what follows it, and the author note.
  --
  -- The first three span the page, which in two columns only the optional
  -- argument of \twocolumn can do, and \twocolumn has to be the first thing
  -- in the document: it begins with a \clearpage, which ships out whatever
  -- has been set so far, and a masthead on a page of its own is not a
  -- masthead. The argument is a box rather than the blocks themselves, since
  -- it is read as one argument and a blank line anywhere in it would end the
  -- paragraph inside the brackets and take the rest of the front matter with
  -- it.
  local rest = pandoc.List({})
  local masthead, wide, narrow, note
  for _, block in ipairs(doc.blocks) do
    if masthead == nil and front_div(block, "JournalMasthead") then
      masthead = block
    elseif wide == nil and front_div(block, "JournalWide") then
      wide = block
    elseif narrow == nil and front_div(block, "JournalNarrow") then
      narrow = block
    elseif note == nil and front_div(block, "JournalNote") then
      note = block
    else
      rest:insert(block)
    end
  end

  if masthead or wide or narrow then
    out:insert(raw("\\begin{lrbox}{\\apamastheadbox}%"))
    out:insert(raw("\\begin{minipage}{\\textwidth}"))
    if masthead then out:extend(masthead.content) end
    if wide then out:extend(render_front(wide.content, true)) end
    if narrow then
      out:insert(raw("\\begin{apajounarrow}"))
      out:extend(render_front(narrow.content, true))
      out:insert(raw("\\end{apajounarrow}"))
    end
    out:insert(raw("\\end{minipage}\\end{lrbox}"))
    out:insert(raw("\\twocolumn[\\apamastheadlift\\usebox{\\apamastheadbox}]"))
  end

  -- The first page of a journal or a plain document carries the masthead, or
  -- nothing, where the other modes carry a running head. The head returns on
  -- the second page, which is how apa7 sets both. After the masthead: the
  -- \clearpage inside \twocolumn would otherwise carry the page style away
  -- with the page it thinks it is ending.
  if mode == "jou" or mode == "doc" then
    out:insert(raw("\\thispagestyle{apafirstpage}"))
  end
  -- A first line indent smaller than a manuscript's half inch.
  if mode == "jou" then
    out:insert(raw("\\apajournalindent"))
  end
  -- The count starts at one where the document does, which is what apa7 asks
  -- lineno for at the same point.
  if line_numbers then
    out:insert(raw("\\resetlinenumber[1]"))
  end

  -- The author note, raised in the first column so that it falls to the foot
  -- of it. After the page style, and before any of the article: a footnote
  -- goes to the foot of the column it was raised in, and this one belongs at
  -- the foot of the first.
  if note then
    out:insert(raw("\\begin{apajounote}"))
    out:extend(note.content)
    out:insert(raw("\\end{apajounote}"))
  end

  out:extend(render_front(rest, false))

  return out
end

-- A raw latex longtable that does not say where its head and foot end.
--
-- apalatex.tex sets every longtable as a tabular, and to do
-- that it reads the head that repeats, which ends at \endhead, and the foot,
-- which ends at \endlastfoot, so that it can throw the first away and write
-- the second under the table. A marker that never arrives is looked for to the
-- end of the document, which is a runaway argument rather than a diagnosis.
--
-- Pandoc writes both markers into every longtable it makes, whether or not the
-- table has anything to put in them. A table written as raw latex need not:
-- flextable writes \endlastfoot only for a table that has a footer, so a
-- flextable without a note had none, and the render simply stopped. The
-- missing marker is added here, with nothing in front of it, which is what
-- pandoc would have written.
local function guard_longtable(el)
  if el.format ~= "latex" and el.format ~= "tex" then return nil end
  local text = el.text
  if not text:find("\\begin{longtable", 1, true) then return nil end

  local changed = false
  if text:find("\\endfirsthead", 1, true)
      and not text:find("\\endhead", 1, true) then
    text = text:gsub("(\\endfirsthead)", "%1\n\\endhead", 1)
    changed = true
  end
  if text:find("\\endhead", 1, true)
      and not text:find("\\endlastfoot", 1, true) then
    text = text:gsub("(\\endhead)", "%1\n\\endlastfoot", 1)
    changed = true
  end
  if not changed then return nil end
  el.text = text
  return el
end

-- Divs that can be anywhere in the document rather than only at its head.
local function div(el)
  if el.classes:includes("FigureNote") then
    return environment("apafloatnote", el.content)
  end
  -- The reference list is left exactly as it is.
  --
  -- The div citeproc fills is the same one that carries the csl-bib-body
  -- class, so wrapping it in an environment of apaquarto's own took it away,
  -- and with it both the CSLReferences list pandoc writes around the entries
  -- and the \citeproc definition its template only emits when it can see such
  -- a div. Every citation in the body calls that command, so the build stopped
  -- at the first one with "Undefined control sequence". The hanging indent APA
  -- asks for is set on cslhangindent in apalatex.tex instead.
end

return {
  { Meta = meta },
  { Div = div, RawBlock = guard_longtable },
  { Pandoc = function(doc) return pandoc.Pandoc(blocks(doc), doc.meta) end },
}

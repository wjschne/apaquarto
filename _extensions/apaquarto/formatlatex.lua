-- Sets the blocks apaquarto's filters produce, in latex.
--
-- This is the plain latex format's counterpart to typst/formattypst.lua. By
-- the time it runs, frontmatter.lua has written the title page and
-- floatlatex.lua the figures and tables with their titles and notes, the
-- notes as ordinary divs carrying the classes those filters use. Nothing
-- here decides what a document says; it only wraps each of those in the
-- command that apalatex.tex defines for it.
--
-- A div that is not wrapped goes through pandoc unchanged, which is what
-- should happen to everything this file does not name.

-- These two filters are the whole of the pdf format, and they are in the
-- shared chain so that their place in it is fixed. Nothing here has
-- anything to say about .html, .docx or typst.
if FORMAT ~= "latex" then
  return
end
local utilsapa = require("utilsapa")

local mode = "man"

-- Whether the document carries a list of contents, figures or tables.
-- Set in blocks() and read in render_front(), which is where the body's
-- title is written out.
local haslist = false
local shorttitle = nil
local line_numbers = false
local first_page = nil

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
  return utilsapa.flag(m, "numbered-lines")
end

-- The number the first page carries, for an article whose pages are numbered
-- from where it begins in the issue rather than from one. Only a whole number
-- is taken: the value is written straight into a latex counter, and anything
-- else there is a compilation error rather than a page number.
-- A colour field written as an html code.
--
-- latex takes a colour by name, and pandoc's template hands hyperref the
-- name as it stands: linkcolor: "#cc0000" reaches the preamble as
-- \hypersetup{linkcolor={\#cc0000}} and the render stops on it. xcolor
-- will take the code, so a field written that way is defined as a colour of
-- its own and the field rewritten to name that colour. A field naming a
-- colour xcolor already knows -- teal, violet, one of the rest -- is left
-- alone, which is how they have always worked.
local colour_fields = { table.unpack(utilsapa.link_fields) }
table.insert(colour_fields, "toccolor")

local function define_html_colours(m)
  for _, field in ipairs(colour_fields) do
    if m[field] ~= nil then
      local text = utilsapa.stringify(m[field])
      if text:sub(1, 1) == "#" then
        local hex = utilsapa.colour_hex(m[field])
        if hex then
          local name = "apacolor" .. field:gsub("color$", "")
          quarto.doc.include_text("in-header",
            "\\definecolor{" .. name .. "}{HTML}{" .. hex .. "}")
          m[field] = pandoc.MetaString(name)
        else
          quarto.log.warning(field .. " is \"" .. text ..
            "\", which is not a colour, so it was left out.")
          m[field] = nil
        end
      end
    end
  end
  return m
end

-- filecolor, for the links markdown actually writes.
--
-- hyperref colours a link by the kind of link it decides it is, and it knows
-- a file link by its scheme. [text](figure.png) reaches it as an ordinary
-- url, so filecolor applied to nothing a document was likely to contain. The
-- colour is set around such a link instead, in a group of its own, and only
-- when it differs from urlcolor -- which it does not by default, both being
-- apalink, and a document that leaves them alone is written exactly as it
-- was before.
local file_colour = nil

local function asked_for_file_colour(m)
  local file = m.filecolor and utilsapa.stringify(m.filecolor) or nil
  local url = m.urlcolor and utilsapa.stringify(m.urlcolor) or nil
  if file == nil or file == "" or file == url then return nil end
  return file
end

local function file_link(link)
  if file_colour == nil then return nil end
  if link.attributes["apa-filecolor"] ~= nil then return nil end
  if utilsapa.link_field(link.target) ~= "filecolor" then return nil end
  link.attributes["apa-filecolor"] = "1"
  return pandoc.Inlines({
    pandoc.RawInline("latex",
      "\\begingroup\\hypersetup{urlcolor=" .. file_colour .. "}"),
    link,
    pandoc.RawInline("latex", "\\endgroup"),
  })
end

-- The colour a document asks for in its lists. Pandoc's own hypersetup
-- carries linkcolor, filecolor, citecolor and urlcolor; toccolor it leaves
-- out, so apaquarto reads it here and the lists honour it.
local toc_colour = nil
local toc_depth = nil

local function asked_for_toc_colour(m)
  if m.toccolor == nil then return nil end
  local name = utilsapa.stringify(m.toccolor)
  if name == "" or name == "false" then return nil end
  return name
end

local function asked_for_first_page(m)
  if m["first-page"] == nil then return nil end
  local text = utilsapa.stringify(m["first-page"])
  if text:match("^%-?%d+$") then return text end
  quarto.log.warning(
    "first-page must be a whole number, and is \"" .. text ..
    "\", so the pages are numbered from one.")
  return nil
end

-- The document's own geometry options, as a list of strings: written as one
-- string ("margin=2in") or as a list of them.
local function asked_for_geometry(m)
  local out = pandoc.List({})
  local value = m.geometry
  if value == nil then return out end
  if pandoc.utils.type(value) == "List" then
    for _, item in ipairs(value) do out:insert(utilsapa.stringify(item)) end
  else
    out:insert(utilsapa.stringify(value))
  end
  return out
end

local function meta(m)
  mode = utilsapa.mode(m)
  -- The page each mode is set on. A document's margin field is written after
  -- it, the same field typst and .docx read, and then its own geometry
  -- options, for anything else geometry can do. geometry takes the last
  -- value it is given for a key, so a writer's margins win in every mode
  -- while what they leave unsaid --- the head and foot of a journal page,
  -- say --- stays as the mode sets it, and geometry wins over margin where
  -- both name a side. A dissertation's front matter sets its own margins
  -- page by page (thesislatex.lua), and \restoregeometry hands the body back
  -- these.
  local asked_margin = utilsapa.margin_sides(m.margin, true) or {}
  local asked_geometry = asked_for_geometry(m)
  local mode_geometry = { "margin=1in" }
  if mode == "thesis" then
    -- A dissertation is bound at the left and wants more there.
    local margins = utilsapa.thesis_margins
    mode_geometry = {
      string.format("left=%.2fin", margins.left),
      string.format("right=%.2fin", margins.right),
      string.format("top=%.2fin", margins.top),
      string.format("bottom=%.2fin", margins.bottom),
    }
  end
  if m.shorttitle then
    shorttitle = utilsapa.stringify(m.shorttitle)
  elseif m.title then
    shorttitle = utilsapa.stringify(m.title)
  end
  -- The running head is a preamble setting, so it goes in the header rather
  -- than into the body where the rest of this filter works.
  -- The headings of the lists, in the document's language
  local function latex_text(text)
    return (text:gsub("([\\{}%$&#%^_~%%])", "\\%1"))
  end
  for _, pair in ipairs({
    { "apacontentsname", "toc-title-document" },
    { "apalistfigurename", "crossref-lof-title" },
    { "apalisttablename", "crossref-lot-title" },
  }) do
    local macro, key = pair[1], pair[2]
    local word = utilsapa.lang(m, key, nil)
    if word then
      quarto.doc.include_text("in-header",
        "\\renewcommand{\\" .. macro .. "}{" .. latex_text(word) .. "}")
    end
  end

  -- suppress-short-title leaves the running head empty, as it does in typst
  -- and .docx: \apashorttitle is empty until something sets it.
  if utilsapa.flag(m, "suppress-short-title") then shorttitle = nil end
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
  if mode == "jou" then
    quarto.doc.include_text("in-header",
      "\\AtBeginDocument{\\apalongtableastabular}")
  end

  -- A student paper carries the page number and nothing else. APA seventh
  -- edition drops the running head from student work, which is what the
  -- typst format does and what the apa7 class did for the .pdf before 6.0.0
  -- stopped using it: a student paper has carried a manuscript's running
  -- head ever since. Issue #166.
  if mode == "stu" then
    quarto.doc.include_text("in-header", "\\apastudenthead")
  end

  -- The line spacing of a table's rows: double unless table-spacing, or a
  -- journal or doc mode, asks for single or one-and-a-half
  -- (\apatablestretch in apalatex.tex).
  local tablespacing = utilsapa.table_spacing(m)
  if tablespacing ~= "double" then
    quarto.doc.include_text("in-header", "\\renewcommand{\\apatablestretch}{"
      .. utilsapa.table_stretch[tablespacing] .. "}")
  end

  -- A block quotation half an inch in on the left and not at all on the
  -- right. Journal mode and a dissertation set their own below.
  if mode ~= "jou" and mode ~= "thesis" then
    quarto.doc.include_text("in-header", "\\apaquote")
  end

  -- A dissertation sets a block quotation, a note and the entries of its
  -- reference list single spaced, indents a quotation half an inch on the
  -- left and a note's first line half an inch, and keeps a page from
  -- breaking after the first line of a paragraph or before its last. The reference list is patched at the start of the document
  -- rather than in the preamble: the environment quarto writes it in is one
  -- of pandoc's own, and where an include lands among those is a detail of
  -- pandoc's template rather than something to lean on.
  if mode == "thesis" then
    quarto.doc.include_text("in-header", "\\apathesisquote")
    quarto.doc.include_text("in-header", "\\apathesisnotes")
    quarto.doc.include_text("in-header", "\\apathesispenalties")
    quarto.doc.include_text("in-header",
      "\\AtBeginDocument{\\apathesisreferences}")
  end

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
    -- Three quarters of an inch at the sides and the top, an inch at the
    -- foot, which is the page the typst format sets: its own margin is
    -- (x: 0.75in, y: 1in) there. Written out side by side rather than as one
    -- margin, which had set the foot at three quarters too and left this
    -- format eighteen points more text on every page than typst had.
    mode_geometry = {
      "left=0.75in",
      "right=0.75in",
      "top=0.75in",
      "bottom=1in",
      "includehead",
      "headheight=13pt",
      "headsep=4pt",
      -- The opening page carries its number at the foot. footskip is measured
      -- to the baseline, so this sets the number about eleven points under the
      -- text block, which is where the Journal of Educational Psychology puts
      -- it; latex's own leaves it half an inch down.
      "footskip=18pt",
    }
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
    -- Headings the size and spacing of a published APA article's.
    quarto.doc.include_text("in-header", "\\apajouheadings")
    -- Block quotations indented on the left only.
    quarto.doc.include_text("in-header", "\\apajouquote")
    local authors = m["jou-running-authors"]
    if authors then
      quarto.doc.include_text("in-header",
        "\\setapaauthorline{" ..
        utilsapa.stringify(authors):gsub("([\\{}%$&#%^_~%%])",
          "\\%1") .. "}")
    end
  end
  local geometry = pandoc.MetaList({})
  for _, option in ipairs(mode_geometry) do
    geometry:insert(pandoc.MetaString(option))
  end
  for _, side in ipairs({ "left", "right", "top", "bottom" }) do
    if asked_margin[side] then
      geometry:insert(pandoc.MetaString(
        string.format("%s=%gin", side, asked_margin[side])))
    end
  end
  for _, option in ipairs(asked_geometry) do
    geometry:insert(pandoc.MetaString(option))
  end
  m.geometry = geometry

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
  first_page = asked_for_first_page(m)
  m = define_html_colours(m)
  toc_colour = asked_for_toc_colour(m)
  -- Quarto hands toc-depth to pandoc as a writer option, so it is read from
  -- there rather than from the metadata. Only a depth that is not the
  -- article class's own three is written out, so that a document which never
  -- mentions the field is set exactly as it was before.
  local depth = utilsapa.toc_depth(m, 3)
  if depth ~= 3 then toc_depth = depth end
  file_colour = asked_for_file_colour(m)
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
      -- The title again, at the head of the body. A page of its own in the
      -- modes that have a title page, and in any mode that has put a list of
      -- contents, figures or tables in front of it -- jou excepted, where
      -- the masthead owns the top of the first page.
      if paged() or (haslist and not jou) then
        out:insert(raw("\\clearpage"))
      end
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

-- ---------------------------------------------------------------------------
-- The front matter

local layout = require("frontmatterlayout")
local List = require 'pandoc.List'
local stringify = utilsapa.stringify

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
local journal_copyright = utilsapa.journal_copyright

-- The apaquarto logo, asked for by writing logo: default. utilsapa finds the
-- extension folder it ships in.
local kDefaultLogo = "default"
local kShippedLogo = "apaquarto-logo.png"

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

-- The masthead for the .pdf, built out of the commands apalatex.tex defines
-- and set in a div formatlatex.lua knows to hand to \twocolumn. The band is
-- the one typst/formattypst.lua sets for typst, off the Journal of
-- Educational Psychology, and the pieces go in the same order: the logo and
-- the journal's name on one line, a rule, then the copyright and the issn at
-- the left with the issue and the doi at the right.
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

-- A published article, laid out the way the typst one is: the masthead, the
-- title and the byline, then the abstract and what follows it in a narrower
-- block, all of it spanning the page; the author note goes to the foot of the
-- first column. Each part is a div of its own (JournalMasthead, JournalWide,
-- JournalNarrow, JournalNote), which blocks() below writes out. The three
-- list markers are taken out first: they would otherwise be swept into the
-- masthead's own divs, and the lists a journal paper asked for would never
-- appear.
local function journal(meta, front)
  local kept, lists = layout.take_list_markers(front)
  local head, narrow, notes, tail = layout.split_journal(kept)
  local out = List:new {}
  local masthead = latex_journal_metadata(meta)
  if masthead then out:extend({ masthead }) end
  out:extend({ pandoc.Div(head, pandoc.Attr("", { "JournalWide" })) })
  if #narrow > 0 then
    out:extend({ pandoc.Div(layout.box_impact(narrow,
      raw("\\begin{apajouimpact}"), raw("\\end{apajouimpact}")),
      pandoc.Attr("", { "JournalNarrow" })) })
  end
  if #notes > 0 then
    -- The orcid lines are set off from the prose of the note, and the icon
    -- sized to the note's text.
    out:extend({ pandoc.Div(
      layout.set_off_orcid(layout.fit_orcid(notes),
        raw("\\begin{apajouorcid}"), raw("\\end{apajouorcid}")),
      pandoc.Attr("", { "JournalNote" })) })
  end
  out:extend(tail)
  out:extend(lists)
  return out
end

-- The document's blocks with the front matter frontmatter.lua handed over
-- laid out for the mode: sorted into the parts of a journal article, or
-- otherwise put back where it stood.
local function lay_out_front(doc)
  local out = pandoc.List({})
  for _, block in ipairs(doc.blocks) do
    if block.t == "Div" and block.classes:includes(layout.kFrontMatterClass) then
      if mode == "jou" then
        out:extend(journal(doc.meta, List:new(block.content)))
      else
        out:extend(block.content)
      end
    else
      out:insert(block)
    end
  end
  return out
end

local function blocks(doc)
  local out = pandoc.List({})

  doc.blocks = lay_out_front(doc)

  -- The front matter of a published article, which lay_out_front has
  -- sorted into the masthead, the title and byline, the abstract and what
  -- follows it, and the author note.
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
  -- Whether any of the three lists is in the document. Each of them starts a
  -- page of its own, and the body wants one too: in man and stu the title
  -- page sees to that, but doc has no title page and ran the body on under
  -- the last list.
  haslist = false
  for _, block in ipairs(doc.blocks) do
    if block.t == "Div" and (block.classes:includes("list-of-contents")
        or block.classes:includes("list-of-figures")
        or block.classes:includes("list-of-tables")) then
      haslist = true
    end
  end

  for _, block in ipairs(doc.blocks) do
    if masthead == nil and front_div(block, "JournalMasthead") then
      masthead = block
    elseif wide == nil and front_div(block, "JournalWide") then
      wide = block
    elseif narrow == nil and front_div(block, "JournalNarrow") then
      narrow = block
    elseif note == nil and front_div(block, "JournalNote") then
      note = block
    elseif block.t == "Div" and (block.classes:includes("list-of-contents")
        or block.classes:includes("list-of-figures")
        or block.classes:includes("list-of-tables")) then
      -- A list stands on a page of its own, except in jou: a published
      -- article runs them on in the columns, which is what typst's journal
      -- mode does with the same three.
      --
      -- The figures and tables are read back out of the .lof and the .lot,
      -- which every float has been writing its line into as it was set. The
      -- heading and the shape of a line are in apalatex.tex.
      if mode ~= "jou" then rest:insert(raw("\\clearpage")) end
      if block.classes:includes("list-of-contents") then
        rest:insert(raw("\\apatableofcontents"))
      elseif block.classes:includes("list-of-figures") then
        rest:insert(raw("\\apalistoffigures"))
      else
        rest:insert(raw("\\apalistoftables"))
      end
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
  if mode == "jou" then
    out:insert(raw("\\thispagestyle{apajoufirstpage}"))
  elseif mode == "doc" then
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
  -- The page number the article starts at, set where apa7 sets it: at the
  -- head of the body, after the page style, so that the first page carries it.
  if first_page then
    out:insert(raw("\\setcounter{page}{" .. first_page .. "}"))
  end

  -- toccolor, which pandoc's latex template does not write out. The
  -- lists are apaquarto's own, so honouring it is apaquarto's to do.
  if toc_colour then
    out:insert(raw("\\renewcommand{\\apatoccolor}{" .. toc_colour .. "}"))
  end

  -- And how deep it goes, which is quarto's toc-depth. The article class
  -- counts three levels of its own accord and nothing read the field.
  if toc_depth then
    out:insert(raw("\\renewcommand{\\apatocdepth}{" .. toc_depth .. "}"))
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
  -- The dash attribution under a block quotation (apaquote.lua).
  if el.classes:includes("quote-attribution") then
    return environment("apaquoteattribution", el.content)
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
  { Div = div, RawBlock = guard_longtable, Link = file_link },
  { Pandoc = function(doc) return pandoc.Pandoc(blocks(doc), doc.meta) end },
}

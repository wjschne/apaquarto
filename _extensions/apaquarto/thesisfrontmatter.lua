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
-- The pages are worked out once for all four formats rather than left to
-- each of them. The lines of the title have to be worked out once --- see
-- thesistitle.lua, and a .docx can measure nothing while it is being written
-- --- so the same lines and the same spacing go to every format.
--
-- What is on each page is thesispages.lua's; how a format sets it is
-- thesislatex.lua's, thesistypst.lua's, thesishtml.lua's or thesisdocx.lua's.
-- This filter picks the renderer, puts the pages it writes ahead of the
-- body, and dresses the body's chapters.

local utilsapa = require("utilsapa")
local thesiscontents = require("thesiscontents")
local thesispages = require("thesispages")

local language = utilsapa.lang
local contents_colour = thesispages.contents_colour

-- The renderer for each format, which sets the pages thesispages builds.
local renderers = {
  latex = require("thesislatex").render,
  typst = require("thesistypst").render,
  html = require("thesishtml").render,
  docx = require("thesisdocx").render,
}

-- A page break, in whatever this format calls one. .html has no pages and
-- gets nothing.
local function page_break()
  return utilsapa.page_break(true)
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
  return utilsapa.mode(meta) == "thesis"
end

-- The colour the latex contents takes. The margins the handbook asks for are
-- set with the rest of the page: in formatlatex.lua for the .pdf, by the
-- thesis layout in typst-template.typ for typst, and by docxreferencedoc.lua
-- for .docx.
function Meta(meta)
  if not is_thesis(meta) then return nil end
  if FORMAT == "latex" then
    quarto.doc.include_text("in-header",
      "\\definecolor{apathesistoc}{HTML}{" .. contents_colour(meta) .. "}")
  end
  return nil
end

function Pandoc(doc)
  if not is_thesis(doc.meta) then return nil end
  local render = FORMAT:match("typst") and renderers.typst or renderers[FORMAT]
  if render == nil then return nil end

  local pages = thesispages.build(doc.meta, doc.blocks)
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

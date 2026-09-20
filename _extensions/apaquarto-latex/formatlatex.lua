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

local function blocks(doc)
  local out = pandoc.List({})

  for _, block in ipairs(doc.blocks) do
    if is_title(block) and block.identifier == "title" then
      -- The title page proper. APA sets the title three or four lines down.
      if paged() then out:insert(raw("\\vspace*{3\\baselineskip}")) end
      out:extend(command("apatitle", block.content))

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
      out:extend(environment("apaauthor", block.content))

    elseif block.t == "Div" and block.classes:includes("AbstractFirstParagraph") then
      out:extend(environment("apanoindent", block.content))

    else
      out:insert(block)
    end
  end

  return out
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
  { Div = div },
  { Pandoc = function(doc) return pandoc.Pandoc(blocks(doc), doc.meta) end },
}

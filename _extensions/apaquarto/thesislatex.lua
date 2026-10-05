-- The front matter of a dissertation, set in latex. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
local written = thesispages.written
local raw = pandoc.RawBlock

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
          "{\\centering\\noindent\\rule{%.2fin}{0.5pt}\\par}", item.width)))
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

return { render = render_latex }

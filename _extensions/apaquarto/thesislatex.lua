-- The front matter of a dissertation, set in latex. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
local kPageColumn = thesispages.page_column
local kLabelLead = thesispages.label_lead
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
    -- Its lead over the \parskip that stands between every two entries.
    return string.format(
      "\\vspace{%dpt}{\\parindent=0pt\\leftskip=%.2fin\\noindent %s\\par}",
      kLabelLead, indent, written(entry.text, "latex"))
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
    -- The words stop the page column short of the margin on every line:
    -- \rightskip, ragged as the other formats are. The last line has the
    -- column back (\parfillskip takes the skip off again) for the dots and
    -- the number, and the dots are never shorter than the column less the
    -- number, so the words on it stop where they stop on the others. One run
    -- of \apadotfill's dots, so there is no seam in them.
    page = string.format("\\setbox0\\hbox{\\hyperref[%s]{\\textcolor"
      .. "{apathesistoc}{\\pageref{%s}}}}\\leavevmode\\cleaders\\hbox to .3em"
      .. "{\\hss.\\hss}\\hskip\\dimexpr %.2fin-\\wd0\\relax plus 1fill"
      .. "\\kern0pt\\box0", entry.target, entry.target, kPageColumn)
  end
  local fill = page ~= ""
    and string.format("\\parfillskip=-%.2fin", kPageColumn) or ""
  return string.format(
    "{\\parindent=0pt\\leftskip=%.2fin\\rightskip=%.2fin plus 1fil"
    .. "%s\\noindent%s%s%s%s\\par}",
    indent, kPageColumn, fill, back, number, body, page)
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
      elseif item.kind == "fill" then
        out:insert(raw("latex",
          string.format("\\vspace*{%.1fpt plus 1fill}", item.points)))
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
        if item.hanging then
          -- A paragraph a line, each turning under itself.
          for _, line in ipairs(lines) do
            out:insert(raw("latex", string.format(
              "{%s\\parskip=0pt%s\\hangindent=%.2fin\\hangafter=1\n%s\\par}",
              align, indent, item.hanging, line)))
          end
        else
          out:insert(raw("latex",
            "{" .. align .. indent .. "\n" .. body .. "\\par}"))
        end
      elseif item.kind == "notice" then
        -- A tabular is as wide as its widest line, so a \hline in it is the
        -- rule, and a fill above and below stands the block in the middle of
        -- the page. Its rows are \baselineskip apart, single here.
        set_spacing(false)
        local rows = pandoc.List({})
        for i, line in ipairs(item.lines) do
          local row = written(line, "latex")
          if i == item.space_after then
            -- Half of \normalbaselineskip, the single spacing: a tabular sets
            -- \baselineskip to nothing inside itself.
            row = row .. "\\\\\\noalign{\\vskip 0.5\\normalbaselineskip}"
          elseif i == item.rule_after then
            -- 3pt each side of the rule, but a row's strut leaves more room
            -- under its line than over the next, so the 6pt is shared out
            -- to leave the rule as clear of the one as of the other.
            row = row .. "\\\\\\noalign{\\vskip 1.8pt}\\hline\\noalign{\\vskip 4.2pt}"
          elseif i < #item.lines then
            row = row .. "\\\\"
          end
          rows:insert(row)
        end
        out:insert(raw("latex", "\\vspace*{\\fill}\n{\\centering"
          .. "\\setlength{\\arrayrulewidth}{0.5pt}"
          .. "\\renewcommand{\\arraystretch}{1}\n"
          .. "\\begin{tabular}{@{}c@{}}\n" .. table.concat(rows, "\n")
          .. "\n\\end{tabular}\\par}\n\\vspace*{\\fill}"))
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

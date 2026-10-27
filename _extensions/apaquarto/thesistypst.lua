-- The front matter of a dissertation, set in typst. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
local kPageColumn = thesispages.page_column
local kLabelLead = thesispages.label_lead
local kContentsLead = thesispages.contents_lead
local contents_colour = thesispages.contents_colour
local written = thesispages.written
local raw = pandoc.RawBlock

-- typst. #page with a body sets those pages on their own: their own margins,
-- and for the title page no footer at all, which is what leaves it
-- unnumbered. What comes after begins a new page, so no page break has to be
-- written.
-- typst is told where an entry points and works the page out for itself, at
-- the place that label stands. The front matter is numbered in roman and the
-- body in arabic, and the counter restarts between them, so which of the two
-- a page takes is said here rather than read off the counter.
local kTypstHelper = [==[
#let apatocline(indent, number, body, target, roman, dots, lead: 0pt) = context {
  let found = if target == none { () } else { query(target) }
  let dest = if found.len() > 0 { found.first().location() } else { none }
  let pg = if dest == none { none } else {
    let n = counter(page).at(dest).first()
    if roman { numbering("i", n) } else { numbering("1", n) }
  }
  // The words stop PAGECOLUMN short of the margin on every line, which the
  // inset on the right does, and the dots run to where they stop. The rest of
  // the dots and the number are placed out across the inset to the margin,
  // from inside the box of dots: set after it as a box of their own, they
  // were a place the line could break, and a title that filled its line
  // sent its number to the start of the next.
  // lead is a label's space over the space between two entries.
  block(above: LINESPACE + lead, below: 0pt, inset: (left: indent, right: PAGECOLUMN), width: 100%)[
    #set text(fill: TOCCOLOUR)
    // A show rule as well as the set: typst-template.typ sets its own blue
    // over every link, and a set does not reach inside a link that rule has
    // already coloured. This one stands nearer and wins.
    #show link: set text(fill: TOCCOLOUR)
    // The number's box and the title are on one line with nothing between
    // them: a line break there is a space, which put the first line of the
    // title that much further in than the lines it turns over onto.
    #par(leading: 0.65em, hanging-indent: if number == none { 0pt } else { NUMBERCOLUMN })[
      #if number != none [#box(width: NUMBERCOLUMN)[#number]]#if dest == none { body } else { link(dest)[#body] }
      #if dots [#box(width: 1fr)[#repeat[.]#place(top + right, dx: PAGECOLUMN, box(width: PAGECOLUMN)[#box(width: 1fr, repeat[.])#pg])]]
    ]
  ]
}
]==]

-- The title page as the .pdf sets it. latex adds the line spacing to a gap
-- written between two lines, where typst counts a gap from the baseline of
-- the one to the top of the capitals of the next and adds nothing, so the
-- same gaps had set typst's page tighter all down: the title 35pt higher,
-- 12pt less over each rule and 6pt less under it. What each gap needs on
-- top, by what stands before and after it, measured off both. Only the title
-- page is set this way; the pages after it were matched to the .pdf on their
-- own terms.
local kTitleSpace = {
  ["top>para"] = 35,
  ["para>rule"] = 12.5,
  ["rule>para"] = 6.5,
  ["para>para"] = 6.5,
}
-- And its single spacing the .pdf's 14.5pt, where 0.65em set 15.5pt.
local kTitleLeading = "6.8pt"

local function title_space(before, after)
  return kTitleSpace[before .. ">" .. after] or 0
end

local function typst_contents_line(entry)
  local indent = string.format("%.2fin", entry.indent * kSubheadingStep)
  local body = written(entry.text, "typst")
  if entry.kind == "label" then
    return "#apatocline(" .. indent .. ", none, [" .. body ..
      "], none, false, false, lead: " .. kLabelLead .. "pt)"
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
      :gsub("PAGECOLUMN", string.format("%.2fin", kPageColumn))
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
    -- The title page is set as the .pdf sets it (kTitleSpace).
    local single = page.first and kTitleLeading or "0.65em"
    for index, item in ipairs(page.items) do
      if item.kind == "gap" then
        local points = item.points
        if page.first then
          local before = page.items[index - 1]
          local after = page.items[index + 1]
          points = points + title_space(before and before.kind or "top",
            after and after.kind or "end")
        end
        out:insert(raw("typst",
          string.format("#v(%.1fpt, weak: false)", points)))
      elseif item.kind == "fill" then
        -- Its least, and then all that is left, which sets what follows on
        -- the foot of the page.
        out:insert(raw("typst", string.format(
          "#v(%.1fpt, weak: false)\n#v(1fr)", item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("typst", string.format(
          "#align(center)[#line(length: %.2fin, stroke: 0.5pt)]", item.width)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "typst"))
        end
        local body = table.concat(lines, " \\\n")
        if item.hanging then
          -- A paragraph a line, each turning under itself. Said in a set
          -- rule, since a paragraph element may not hold a paragraph break.
          body = string.format(
            "#[#set par(first-line-indent: 0pt, hanging-indent: %.2fin, "
            .. "spacing: %s%s)\n%s\n]", item.hanging, single,
            item.double and "" or ", leading: " .. single,
            table.concat(lines, "\n\n"))
        end
        if item.bold then body = "#strong[" .. body .. "]" end
        -- A single-spaced paragraph says so; a double-spaced one keeps the
        -- leading the document is set in, which in this mode is double.
        if not item.double and not item.hanging then
          body = "#par(leading: " .. single .. ")[" .. body .. "]"
        end
        body = "#align(" .. item.align .. ")[" .. body .. "]"
        if item.indent then
          body = string.format("#pad(left: %.2fin)[", item.indent)
            .. body .. "]"
        end
        out:insert(raw("typst", body))
      elseif item.kind == "notice" then
        -- The lines are measured where they are set, and the block is made
        -- as wide as the widest, so the rule across it is that wide too. A
        -- fraction of the page above and below stands it in the middle.
        -- The rule is 3pt further from each line than it first was, which
        -- leaves it about 6pt clear of both, as in the .pdf and the .docx.
        -- The half line of space is half the distance from one baseline to
        -- the next, added to the leading that is there already. That
        -- distance is the leading and the height of a capital, which is
        -- measured: a paragraph measured whole came out at the body's double
        -- spacing whatever its leading was set to.
        local first, second, below = pandoc.List({}), pandoc.List({}),
          pandoc.List({})
        for i, line in ipairs(item.lines) do
          local into = i <= item.space_after and first
            or i <= item.rule_after and second or below
          into:insert("[" .. written(line, "typst") .. "]")
        end
        local function array(list)
          if #list == 0 then return "()" end
          return "(" .. table.concat(list, ", ") .. ",)"
        end
        out:insert(raw("typst", table.concat({
          "#v(1fr, weak: false)",
          "#context {",
          "  let first = " .. array(first),
          "  let second = " .. array(second),
          "  let below = " .. array(below),
          "  let width = calc.max(..(first + second + below).map(line => measure(line).width))",
          "  set par(leading: 0.65em, spacing: 0pt)",
          "  let pitch = 0.65em.to-absolute() + measure([X]).height",
          "  align(center, block(width: width, {",
          "    set align(center)",
          "    par(first.join(linebreak()))",
          "    if second.len() > 0 {",
          "      v(0.65em + pitch / 2)",
          "      par(second.join(linebreak()))",
          "    }",
          "    if below.len() > 0 {",
          "      v(7pt)",
          "      line(length: 100%, stroke: 0.5pt)",
          "      v(7pt)",
          "      par(below.join(linebreak()))",
          "    }",
          "  }))",
          "}",
          "#v(1fr, weak: false)",
        }, "\n")))
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

return { render = render_typst }

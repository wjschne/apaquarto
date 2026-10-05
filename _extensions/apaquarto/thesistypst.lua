-- The front matter of a dissertation, set in typst. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kNumberColumn = thesispages.number_column
local kSubheadingStep = thesispages.subheading_step
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
#let apatocline(indent, number, body, target, roman, dots) = context {
  let found = if target == none { () } else { query(target) }
  let dest = if found.len() > 0 { found.first().location() } else { none }
  let pg = if dest == none { none } else {
    let n = counter(page).at(dest).first()
    if roman { numbering("i", n) } else { numbering("1", n) }
  }
  block(above: LINESPACE, below: 0pt, inset: (left: indent), width: 100%)[
    #set text(fill: TOCCOLOUR)
    // A show rule as well as the set: typst-template.typ sets its own blue
    // over every link, and a set does not reach inside a link that rule has
    // already coloured. This one stands nearer and wins.
    #show link: set text(fill: TOCCOLOUR)
    #par(leading: 0.65em, hanging-indent: if number == none { 0pt } else { NUMBERCOLUMN })[
      #if number != none [#box(width: NUMBERCOLUMN)[#number]]
      #if dest == none { body } else { link(dest)[#body] }
      #if dots [#box(width: 1fr, repeat[.]) #pg]
    ]
  ]
}
]==]

local function typst_contents_line(entry)
  local indent = string.format("%.2fin", entry.indent * kSubheadingStep)
  local body = written(entry.text, "typst")
  if entry.kind == "label" then
    return "#apatocline(" .. indent .. ", none, [" .. body ..
      "], none, false, false)"
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
    for _, item in ipairs(page.items) do
      if item.kind == "gap" then
        out:insert(raw("typst",
          string.format("#v(%.1fpt, weak: false)", item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("typst", string.format(
          "#align(center)[#line(length: %.2fin, stroke: 0.5pt)]", item.width)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "typst"))
        end
        local body = table.concat(lines, " \\\n")
        if item.bold then body = "#strong[" .. body .. "]" end
        -- A single-spaced paragraph says so; a double-spaced one keeps the
        -- leading the document is set in, which in this mode is double.
        if not item.double then
          body = "#par(leading: 0.65em)[" .. body .. "]"
        end
        body = "#align(" .. item.align .. ")[" .. body .. "]"
        if item.indent then
          body = string.format("#pad(left: %.2fin)[", item.indent)
            .. body .. "]"
        end
        out:insert(raw("typst", body))
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

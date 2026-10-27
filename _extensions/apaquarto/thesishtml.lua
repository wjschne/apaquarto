-- The front matter of a dissertation, set in html. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kSubheadingStep = thesispages.subheading_step
local kLabelLead = thesispages.label_lead
local contents_colour = thesispages.contents_colour
local written = thesispages.written
local raw = pandoc.RawBlock

-- The line spacing a dissertation asks for, which is where .html differs from
-- the stylesheet every other mode shares. The body stays double spaced, but a
-- block quotation, a note and the entries of the reference list are single
-- spaced, and a double space stands between one entry and the next: a line of
-- space under an entry puts the line after it twice as far down as the one
-- before. The half inch a quotation is indented on the left is in apa.css
-- already; the half inch on the right is a dissertation's alone, which the
-- Graduate School asks for though APA does not.
--
-- A note's first line is not indented here. In the three paged formats the
-- half inch the handbook asks for is where the note's number goes; in .html
-- the number belongs to the list the browser draws, which is left alone.
--
-- 1em is single and 2em is double throughout that stylesheet.
local kHtmlThesisStyle = table.concat({
  "blockquote, .blockquote { margin-right: 0.5in; }",
  "blockquote p, .blockquote p { line-height: 1em; }",
  ".csl-bib-body .csl-entry { line-height: 1em; margin-bottom: 1em; }",
  ".footnotes li p { line-height: 1em; }",
  ".footnotes li { margin-bottom: 1em; }",
}, "\n")

-- html. There are no pages here, so the gaps are the only thing that carries
-- the arrangement across, and there is nothing to number.
local function render_html(pages, meta)
  local out = pandoc.List({})
  -- The entries are links and would take the theme's link colour; toccolor
  -- says what they take instead, and black is what it says unless a document
  -- asks otherwise.
  out:insert(raw("html", "<style>.thesis-front-matter-page a { color: #"
    .. contents_colour(meta) .. "; }\n" .. kHtmlThesisStyle .. "</style>"))
  for _, page in ipairs(pages) do
    out:insert(raw("html", '<div class="thesis-front-matter-page">'))
    for _, item in ipairs(page.items) do
      -- A fill is its least: there is no foot of a page here to reach.
      if item.kind == "gap" or item.kind == "fill" then
        out:insert(raw("html", string.format(
          '<div style="height:%.1fpt"></div>', item.points)))
      elseif item.kind == "rule" then
        out:insert(raw("html", string.format(
          '<hr style="width:%.2fin;margin:0 auto;border:none;'
          .. 'border-top:0.5pt solid currentColor">', item.width)))
      elseif item.kind == "para" then
        local lines = pandoc.List({})
        for _, line in ipairs(item.lines) do
          lines:insert(written(line, "html"))
        end
        local body = table.concat(lines, "<br>\n")
        if item.bold then body = "<strong>" .. body .. "</strong>" end
        local indent = item.indent
          and string.format(";margin-left:%.2fin", item.indent) or ""
        if item.hanging then
          -- A paragraph a line, each turning under itself.
          for _, line in ipairs(lines) do
            out:insert(raw("html", string.format(
              '<p style="text-align:%s;margin:0;margin-left:%.2fin;'
              .. 'text-indent:-%.2fin;line-height:%s">%s</p>',
              item.align, (item.indent or 0) + item.hanging, item.hanging,
              item.double and "2" or "1.15", line)))
          end
        else
          out:insert(raw("html", '<p style="text-align:' .. item.align ..
            ";margin:0" .. indent .. ";text-indent:0;line-height:" ..
            (item.double and "2" or "1.15") .. '">' .. body .. "</p>"))
        end
      elseif item.kind == "notice" then
        -- A block as wide as its widest line, so a border on the lines over
        -- the rule is as wide as they are, padded 3pt clear of them. The
        -- half line of space is half of the 1.15 lines are set at. There is
        -- no page to centre it on.
        local first, second, below = pandoc.List({}), pandoc.List({}),
          pandoc.List({})
        for i, line in ipairs(item.lines) do
          local into = i <= item.space_after and first
            or i <= item.rule_after and second or below
          into:insert(written(line, "html"))
        end
        local p = '<p style="margin:0;text-indent:0%s">%s</p>'
        local function paragraph(lines, style)
          if #lines == 0 then return "" end
          return string.format(p, style, table.concat(lines, "<br>\n"))
        end
        local ruled = #below > 0
          and ";padding-bottom:3pt;border-bottom:0.5pt solid currentColor"
          or ""
        out:insert(raw("html", table.concat({
          '<div style="width:fit-content;margin:0 auto;text-align:center;'
            .. 'line-height:1.15">',
          -- The border goes under the whole of what is over the rule.
          '<div style="' .. ruled:sub(2) .. '">',
          paragraph(first, ""),
          paragraph(second, #first > 0 and ";margin-top:0.575em" or ""),
          "</div>",
          paragraph(below, ";padding-top:3pt"),
          "</div>",
        })))
      elseif item.kind == "anchor" then
        out:insert(raw("html", '<span id="' .. item.name .. '"></span>'))
      elseif item.kind == "columns" then
        out:insert(raw("html",
          '<p style="margin:0;text-indent:0;display:flex;'
          .. 'justify-content:space-between"><span>'
          .. written(item.left, "html") .. "</span><span>"
          .. written(item.right, "html") .. "</span></p>"))
      elseif item.kind == "contents" then
        -- No pages here, so no page numbers: an entry is the words and a
        -- link to them, which is all a web page can offer.
        for _, entry in ipairs(item.entries) do
          local body = written(entry.text, "html")
          if entry.number then body = entry.number .. " " .. body end
          if entry.target then
            body = '<a href="#' .. entry.target .. '">' .. body .. "</a>"
          end
          -- A label, CHAPTER or APPENDICES, has its lead above it.
          local lead = entry.kind == "label"
            and string.format(";margin-top:%dpt", kLabelLead) or ""
          out:insert(raw("html", string.format(
            '<p style="margin:0;text-indent:0;margin-left:%.2fin%s">%s</p>',
            entry.indent * kSubheadingStep, lead, body)))
        end
      elseif item.kind == "blocks" then
        out:extend(item.blocks)
      end
    end
    out:insert(raw("html", "</div>"))
  end
  return out
end

return { render = render_html }

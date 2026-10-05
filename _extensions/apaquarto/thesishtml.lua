-- The front matter of a dissertation, set in html. See thesispages.lua
-- for the pages it is handed.

local thesispages = require("thesispages")

local kSubheadingStep = thesispages.subheading_step
local contents_colour = thesispages.contents_colour
local written = thesispages.written
local raw = pandoc.RawBlock

-- The line spacing a dissertation asks for, which is where .html differs from
-- the stylesheet every other mode shares. The body stays double spaced, but a
-- block quotation, a note and the entries of the reference list are single
-- spaced, and a double space stands between one entry and the next: a line of
-- space under an entry puts the line after it twice as far down as the one
-- before. The half inch a quotation is indented from both margins is in
-- apa.css already.
--
-- A note's first line is not indented here. In the three paged formats the
-- half inch the handbook asks for is where the note's number goes; in .html
-- the number belongs to the list the browser draws, which is left alone.
--
-- 1em is single and 2em is double throughout that stylesheet.
local kHtmlThesisStyle = table.concat({
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
      if item.kind == "gap" then
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
        out:insert(raw("html", '<p style="text-align:' .. item.align ..
          ";margin:0" .. indent .. ";text-indent:0;line-height:" ..
          (item.double and "2" or "1.15") .. '">' .. body .. "</p>"))
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
          out:insert(raw("html", string.format(
            '<p style="margin:0;text-indent:0;margin-left:%.2fin">%s</p>',
            entry.indent * kSubheadingStep, body)))
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

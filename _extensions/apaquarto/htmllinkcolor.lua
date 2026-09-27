-- The colour a link takes in .html.
--
-- Quarto's colour fields are latex's, and a web page has never answered to
-- them: a link takes whatever the theme says. They are a reasonable thing to
-- ask for in any format, though, so the ones a document names are written
-- into the head as a stylesheet of their own.
--
-- The reading of each field is latex's, put as a selector: urlcolor is
-- anything with a scheme, citecolor a link into the bibliography, linkcolor
-- another anchor -- a cross reference, or a link to a heading -- and
-- filecolor a path to a file. A citation is an anchor as well, so the two
-- rules that could both take one are written in the order that lets the
-- narrower reading win, theirs being of equal specificity.
--
-- toccolor takes the contents, whether it is the one list-of-contents builds
-- into the page or the one toc: true puts in the margin.
--
-- Only the article is coloured. The navigation quarto sets around it is the
-- theme's own and has nothing to do with what the document asked for.

if FORMAT ~= "html" then
  return
end

local utilsapa = require("utilsapa")

local rules = {
  { field = "linkcolor", selectors = { 'main a[href^="#"]' } },
  { field = "filecolor", selectors = {
      'main a[href]:not([href^="#"]):not([href*="//"]):not([href^="mailto:"])' } },
  { field = "urlcolor", selectors = {
      'main a[href*="//"]', 'main a[href^="mailto:"]' } },
  { field = "citecolor", selectors = { 'main .citation a' } },
  -- nav-link is what quarto calls an entry of the contents it puts in the
  -- margin. The other links in that nav -- the download links it lists under
  -- "Other Formats" -- are not entries and are left as the theme has them.
  { field = 'toccolor', selectors = { 'main .apaquarto-contents a', 'nav#TOC a.nav-link' } },
}

function Meta(meta)
  local css = pandoc.List({})
  for _, rule in ipairs(rules) do
    local hex = utilsapa.colour_hex(meta[rule.field])
    if hex then
      css:insert(table.concat(rule.selectors, ", ") .. " { color: #" .. hex .. "; }")
    end
  end
  if #css == 0 then return nil end

  quarto.doc.include_text("in-header",
    "<style>\n" .. table.concat(css, "\n") .. "\n</style>")
  return nil
end

-- The line spacing of a table's rows in .html, from table-spacing.
--
-- apa.css sets a table's rows double spaced, at 2 lines, as the .pdf, typst
-- and .docx set them. A document asking for single or one-and-a-half spacing
-- has its own line height written into the head as a stylesheet of its own:
-- 1.2 or 1.5 lines, which at the body's 12pt are the .pdf's 14.5pt and 18pt.

if FORMAT ~= "html" then
  return
end

local utilsapa = require("utilsapa")

local line_heights = { single = "1.2", onehalf = "1.5" }

function Meta(meta)
  local height = line_heights[utilsapa.table_spacing(meta)]
  if not height then return nil end
  -- Ahead of apa.css in the head, so the selector is made the more specific
  -- one rather than relying on coming later.
  quarto.doc.include_text("in-header",
    "<style>\nbody .table>:not(caption)>*>* { line-height: " .. height .. "; }\n</style>")
  return nil
end

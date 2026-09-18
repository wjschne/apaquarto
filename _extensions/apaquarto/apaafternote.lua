-- apaquarto-pdf leaves this spacing to apa7, so this filter stands down for
-- it. apaquarto-latex-pdf does not use apa7 and needs it like every other
-- format; the two are told apart from the metadata, inside Pandoc below.
local utilsapa = require("utilsapa")

-- The spacing in paragraphs after a figure or table
-- without a note makes a special style necessary.

-- Set custom style in paragraph by setting it in a custom div
local function makeafternote(p)
  div = pandoc.Div(p)
  div.classes:insert("AfterWithoutNote")
  div.attributes['custom-style'] = 'AfterWithoutNote'
  return div
end


function Pandoc(doc)
  if utilsapa.apa7_latex(doc.meta) then return nil end
  local hblocks = {}
  local isfloatref = false

  -- Loop through all blocks in reverse
  for i = #doc.blocks - 1, 1, -1 do
    -- Look for a div followed by a paragraph
    if doc.blocks[i + 1].t == "Para" and doc.blocks[i].t == "Div" then
      -- If the div is a figure or table without a note,
      -- set the paragraph's custom style to be AfterWithoutNote
      if (doc.blocks[i].attributes["custom-style"] == "FigureWithoutNote") or doc.blocks[i].identifier:find("^tbl%-") then
        doc.blocks[i + 1] = makeafternote(doc.blocks[i + 1])
      end
    end
  end
  return pandoc.Pandoc(doc.blocks, doc.meta)
end

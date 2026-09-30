-- The spacing in paragraphs after a figure or table
-- without a note makes a special style necessary.

-- Set custom style in paragraph by setting it in a custom div
local function makeafternote(p)
  local div = pandoc.Div(p)
  div.classes:insert("AfterWithoutNote")
  div.attributes['custom-style'] = 'AfterWithoutNote'
  return div
end


function Pandoc(doc)
  local hblocks = {}
  local isfloatref = false

  -- Loop through all blocks in reverse
  for i = #doc.blocks - 1, 1, -1 do
    -- Look for a div followed by a paragraph
    if doc.blocks[i + 1].t == "Para" and doc.blocks[i].t == "Div" then
      -- If the div is a figure or table without a note,
      -- set the paragraph's custom style to be AfterWithoutNote
      -- A table with a note of its own is not one of them. Its note used to
      -- follow it as a block of its own, which kept this from reaching the
      -- paragraph after; now the note is inside the table's float, so the
      -- float says itself that it has one.
      local style = doc.blocks[i].attributes["custom-style"]
      if style == "FigureWithoutNote"
          or (doc.blocks[i].identifier:find("^tbl%-") and style ~= "FigureWithNote") then
        doc.blocks[i + 1] = makeafternote(doc.blocks[i + 1])
      end
    end
  end
  return pandoc.Pandoc(doc.blocks, doc.meta)
end

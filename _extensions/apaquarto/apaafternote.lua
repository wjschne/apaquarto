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
      --
      -- In .docx the blank line APA asks for under a figure or table ("add a
      -- double-spaced blank line between the text and the table or figure")
      -- is the space after the float's own last paragraph: its note, or the
      -- picture of a figure without one (the reference document's FigureNote
      -- and FigureWithoutNote), which holds whatever follows, a heading
      -- included. A table without a note ends in the table, which cannot carry
      -- space after it, so there the paragraph after takes the space before.
      local style = doc.blocks[i].attributes["custom-style"]
      local tablewithoutnote = doc.blocks[i].identifier:find("^tbl%-")
        and style ~= "FigureWithNote"
      if FORMAT == "docx" then
        if tablewithoutnote then
          doc.blocks[i + 1] = makeafternote(doc.blocks[i + 1])
        end
      elseif style == "FigureWithoutNote" or tablewithoutnote then
        doc.blocks[i + 1] = makeafternote(doc.blocks[i + 1])
      end
    end
  end
  return pandoc.Pandoc(doc.blocks, doc.meta)
end

-- The spacing in paragraphs after a figure or table
-- without a note makes a special style necessary.

-- Set custom style in paragraph by setting it in a custom div
local function makeafternote(p)
  local div = pandoc.Div(p)
  div.classes:insert("AfterWithoutNote")
  div.attributes['custom-style'] = 'AfterWithoutNote'
  return div
end

-- In .docx, the blank line under a table without a note when what follows is
-- not a paragraph to carry it: a heading, a list. An empty paragraph a point
-- high, kept with the block after it, whose space before is the blank line,
-- one of Word's double-spaced lines (552 twips) like AfterWithoutNote's. A
-- heading after such a table had no space above it at all
-- (tests/layout-float-space.qmd). Space before rather than a blank line of
-- its own, because Word drops space before at the top of a page: if the
-- heading goes over to the next page, the spacer goes with it and leaves no
-- gap there.
local docx_spacer = pandoc.RawBlock("openxml",
  '<w:p><w:pPr><w:keepNext/><w:spacing w:before="552" w:after="0" '
  .. 'w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr>'
  .. '</w:pPr></w:p>')

-- A figure or table: its title has the blank line above it already.
local function is_float(block)
  return block.t == "Div" and (block.classes:includes("FigureWithNote")
    or block.classes:includes("FigureWithoutNote"))
end


function Pandoc(doc)
  local hblocks = {}
  local isfloatref = false

  -- Loop through all blocks in reverse
  for i = #doc.blocks - 1, 1, -1 do
    -- A table without a note followed by something other than a paragraph,
    -- in .docx: the spacer above. The blocks after i are done already, so
    -- inserting one there moves nothing still to come.
    if FORMAT == "docx" and doc.blocks[i].t == "Div"
        and doc.blocks[i + 1].t ~= "Para" and not is_float(doc.blocks[i + 1])
        and doc.blocks[i].identifier:find("^tbl%-")
        and doc.blocks[i].attributes["custom-style"] ~= "FigureWithNote" then
      doc.blocks:insert(i + 1, docx_spacer)
    end
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

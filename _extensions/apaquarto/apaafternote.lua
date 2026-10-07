-- The space after a figure or table, which is set by what follows it.

-- Set custom style in paragraph by setting it in a custom div
local function makeafternote(p)
  local div = pandoc.Div(p)
  div.classes:insert("AfterWithoutNote")
  div.attributes['custom-style'] = 'AfterWithoutNote'
  return div
end

-- In .docx, the blank line under a figure or table when what follows is not
-- a paragraph to carry it: a heading, a list. An empty paragraph a point
-- high, kept with the block after it, whose space before is the blank line,
-- one of Word's double-spaced lines (552 twips) like AfterWithoutNote's. A
-- heading after a table had no space above it at all
-- (tests/layout-float-space.qmd). Space before rather than a blank line of
-- its own, because Word drops space before at the top of a page: if the
-- heading goes over to the next page, the spacer goes with it and leaves no
-- gap there.
local docx_spacer = pandoc.RawBlock("openxml",
  '<w:p><w:pPr><w:keepNext/><w:spacing w:before="552" w:after="0" '
  .. 'w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr>'
  .. '</w:pPr></w:p>')

-- A figure or table, as apafloat.lua marks one.
local function is_float(block)
  return block.t == "Div" and (block.classes:includes("FigureWithNote")
    or block.classes:includes("FigureWithoutNote")
    or (block.identifier or ""):find("^tbl%-") ~= nil)
end

-- A paragraph with nothing in it but spaces, no-break ones included.
local function is_empty_para(block)
  if not block or block.t ~= "Para" then return false end
  local text = pandoc.utils.stringify(block):gsub("\u{A0}", ""):gsub("%s", "")
  return text == ""
end

function Pandoc(doc)
  -- In reverse, so that a block inserted after the one in hand moves nothing
  -- still to come.
  for i = #doc.blocks - 1, 1, -1 do
    -- quarto writes an empty paragraph after a float, which in .docx is a
    -- blank double-spaced line of its own: on top of the space before the
    -- title of a float after it, the two stood 111pt apart where a blank
    -- line is 55 (tests/multipanel-notes.qmd). It goes, and what follows
    -- is spaced as below. Two tables cannot run together for want of it: a
    -- float begins with its title.
    if FORMAT == "docx" and is_float(doc.blocks[i]) then
      while is_empty_para(doc.blocks[i + 1]) do doc.blocks:remove(i + 1) end
      if not doc.blocks[i + 1] then goto continue end
    end
    local block, after = doc.blocks[i], doc.blocks[i + 1]
    if FORMAT == "docx" then
      -- The blank line APA asks for under a figure or table ("add a
      -- double-spaced blank line between the text and the table or
      -- figure"), set as space before whatever follows. Not as space after
      -- the float's note or picture: Word adds a paragraph's space after to
      -- the next one's space before, and a float followed by another, whose
      -- title has the blank line above it already, stood two blank lines
      -- from it. So a paragraph after a float takes the space before
      -- (AfterWithoutNote), another float takes none, and anything else, a
      -- heading or a list, is preceded by the spacer.
      if is_float(block) then
        if after.t == "Para" then
          doc.blocks[i + 1] = makeafternote(after)
        elseif not is_float(after) then
          doc.blocks:insert(i + 1, docx_spacer)
        end
      end
    elseif after.t == "Para" and block.t == "Div" then
      -- A figure or table without a note: the paragraph after it takes the
      -- AfterWithoutNote style. A table with a note of its own is not one of
      -- them; the note is inside the table's float, so the float says itself
      -- that it has one.
      local style = block.attributes["custom-style"]
      local tablewithoutnote = (block.identifier or ""):find("^tbl%-")
        and style ~= "FigureWithNote"
      if style == "FigureWithoutNote" or tablewithoutnote then
        doc.blocks[i + 1] = makeafternote(after)
      end
    end
    ::continue::
  end
  return pandoc.Pandoc(doc.blocks, doc.meta)
end

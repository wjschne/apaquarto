--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

local utilsapa = require("utilsapa")

-- The identifier prefixes a float can carry. Read from the document, because
-- a document may declare kinds of its own under crossref.custom --- an
-- Illustration is the one apaquarto ships --- and quarto wraps one of those
-- exactly as it wraps a figure. Left unwrapped, the float stayed a table cell,
-- and word takes the paragraphs of a cell as its own: the title over the
-- caption and the note held on the page with what it describes are styles of
-- apaquarto's, and every line of such a float came out as body text instead.
local prefixes = { fig = true, tbl = true }

-- Quarto encloses tables and figures in a table environment
-- This function removes that table environment
local function unwrap(tb)
  local mydivs = pandoc.List()
  tb:walk {
    Div = function(div)
      if utilsapa.is_float(div.identifier, prefixes) then
        div.content = div.content:walk { RawInline = function(ri) return {} end }
        mydivs:insert(div)
      end
    end
  }
  -- Only the wrapper, which holds the float and nothing else in a single
  -- cell. A figure of panels has a table inside that wrapper as well -- the
  -- one word needs to put the panels side by side -- and its cells hold
  -- fig- divs too, so unwrapping whatever matched took that layout apart and
  -- left the panels one under the other. A table with more than one cell is
  -- carrying something, not wrapping it.
  local ncells = 0
  for _, body in ipairs(tb.bodies) do
    for _, row in ipairs(body.body) do ncells = ncells + #row.cells end
  end
  if #mydivs > 0 and ncells == 1 then return mydivs end
end

return {
  { Meta = function(m) prefixes = utilsapa.float_prefixes(m) end },
  { Table = unwrap },
}

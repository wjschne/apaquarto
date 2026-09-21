--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

-- Quarto encloses tables and figures in a table environment
-- This function removes that table environment
function Table(tb)
  local mydivs = pandoc.List()
  tb:walk {
    Div = function(div)
      if div.identifier:find("^tbl%-") or div.identifier:find("^fig%-") then
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

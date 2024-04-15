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
        div.content = div.content:walk {RawInline = function(ri) return {} end}
        mydivs:insert(div)
      end
    end
  } 
  if #mydivs > 0 then return mydivs end
end
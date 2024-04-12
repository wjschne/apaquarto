--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

-- Removes table environment inserted by Quarto
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
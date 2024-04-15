if FORMAT ~= "latex" then
  return 
end
-- Insert column width for figures if not set
Div = function(div)
  if div.identifier:find("^fig%-") then
    div.content = div.content:walk {
      Image = function(img)
        if img.attributes.width == nil then
          img.attributes.width = "\\columnwidth"
        end
        return img
      end
    }
  end
  
  div.content = div.content:walk {
    Figure = function(fg)
      if fg.identifier:find("^fig%-") then
        fg.content = fg.content:walk {
          Image = function(img)
            if img.attributes.width == nil then
              img.attributes.width = "\\columnwidth"
            end
            return img
          end
        }
        return fg
      end
    end
  }
  return div
end
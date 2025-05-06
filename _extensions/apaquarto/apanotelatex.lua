if FORMAT ~= "latex" then
  return 
end
-- If div if a figure with apa-note, then insert it into the image
Div = function(div)
   if div.attributes then
    if div.attributes["apa-note"] then
      if div.identifier:find("^fig%-") then
        div.content = div.content:walk {
          Image = function(img)
                img.attributes["apa-note"] = div.attributes["apa-note"]
                return img
              end
        }
      end
      
      div.content = div.content:walk {
        Figure = function(fg)
          if fg.identifier:find("^fig%-") then
            fg.content = fg.content:walk {
              Image = function(img)
                img.attributes["apa-note"] = div.attributes["apa-note"]
                return img
              end
            }
            return fg
          end
        end
      }
      return div
    end 
  end
end



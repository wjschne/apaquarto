-- Inserts apa-twocolumn div property into image

-- This filter for latex only
if FORMAT ~= "latex" then
  return
end

Div = function(div)
  if div.attributes then
    if div.attributes["apa-twocolumn"] then
      div.content = div.content:walk {
        Image = function(img)
          img.attributes["apa-twocolumn"] = div.attributes["apa-twocolumn"]
          return img
        end
      }
      return div
    end
  end
end

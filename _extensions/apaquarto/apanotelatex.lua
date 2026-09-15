if FORMAT ~= "latex" then
  return
end
-- How many images does this div hold?
local function count_images(blocks)
  local n = 0
  blocks:walk {
    Image = function(_)
      n = n + 1
    end
  }
  return n
end

-- If div is a figure with apa-note, then insert it into the image
Div = function(div)
  if div.attributes then
    if div.attributes["apa-note"] then
      -- Only when the div holds a single image. A div of several images is a
      -- sub-figure layout, and a note on that div belongs to the figure as a
      -- whole: floatwithsubfigure.lua puts it below the grid. Copying it onto
      -- the panels as well would print it once more under each of them.
      if count_images(div.content) ~= 1 then
        return nil
      end

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

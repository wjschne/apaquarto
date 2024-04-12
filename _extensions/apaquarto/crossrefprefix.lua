local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local prefix = ""
local intprefix = 0
local tblnum = 0
local fignum = 0
local tbl = {}
local fig = {}

local tbllabel = function(id)
  if id ~= "" then
    if tbl[id] then
    
    else
      tblnum = tblnum + 1
      tbl[id] = tblnum
    end
    return tbl[id]
  end
end

local figlabel = function(id)
  if id ~= "" then
     
    if fig[id] then
    
    else
      fignum = fignum + 1
      fig[id] = fignum
    end
    --print(id);print(fignum)
  end
 
  return fig[id]
end

Block = function(b)
  if b.tag == "Header" and b.level == 1 and pandoc.text.sub(pandoc.utils.stringify(b.content), 1, 8) == "Appendix" then
    intprefix = intprefix + 1
    tblnum = 0
    fignum = 0
    prefix = pandoc.text.sub(abc,intprefix,intprefix)
  end
  
  if b.identifier then
    if b.identifier:find("^tbl%-") then
      b.attributes.prefix = prefix
      b.attributes.tblnum = tbllabel(b.identifier)
    else
      if b.identifier:find("^fig%-") then
        b.attributes.prefix = prefix
        b.attributes.fignum = figlabel(b.identifier)
        b.content:walk {
          Image = function(img)
            img.attributes.prefix = prefix
            img.attributes.fignum = figlabel(b.identifier)
          end
        }
      else
        b:walk {
          Figure = function(fg)
            if fg.identifier then
              if fg.identifier:find("^fig%-") then
                fg.attributes.prefix = prefix
                fg.attributes.fignum = figlabel(fg.identifier)
                fg.content:walk {
                  Image = function(img)
                    img.attributes.prefix = prefix
                    img.attributes.fignum = figlabel(fg.identifier)
                  end
                  }
              end
            end
          end
            }
      end
    end
    return b
  end
end
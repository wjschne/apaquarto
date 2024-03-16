local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local prefix = ""
local intprefix = 0
Block = function(b)
  if b.tag == "Header" and b.level == 1 and pandoc.text.sub(pandoc.utils.stringify(b.content), 1, 8) == "Appendix" then
    intprefix = intprefix + 1
    prefix = pandoc.text.sub(abc,intprefix,intprefix)
  end
  
  if b.identifier then
    if b.identifier:find("^tbl%-") then
      b.attributes.prefix = prefix
    else
      if b.identifier:find("^fig%-") and b.tag == "Figure" then
        
        b.content:walk {
          Image = function(img)
            img.attributes.prefix = prefix
          end
        }
        --quarto.log.output(b)
      else
        b:walk {
          Figure = function(fg)
            if fg.identifier then
              if fg.identifier:find("^fig%-") then
                fg.content:walk {
                  Image = function(img)
                    img.attributes.prefix = prefix
                  end
                  }
              end
            end
          end
            }
      end
    end
  end
end
-- This filter creates prefixes for figures and tables in appedices.

-- List of appendix names
local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- Default prefix
local prefix = ""
-- Default pre-prefex if appendices exceed 26
local preprefix = ""
-- Prefix counter
local intprefix = 0
-- Pre-prefix counter
local intpreprefix = 0
-- Table counter
local tblnum = 0
-- Figure counter
local fignum = 0
-- Table table
local tbl = {}
-- Figure table
local fig = {}

-- return table number associated with id
local tbllabel = function(id)
  if id ~= "" then
    -- Is id in tbl?
    if tbl[id] then
      -- Do nothing
    else
      -- Add id to tbl
      tblnum = tblnum + 1
      tbl[id] = tblnum
    end
    return tbl[id]
  end
end

-- return figure number associated with id
local figlabel = function(id)
  if id ~= "" then
    -- Is id in fig?
    if fig[id] then
      -- Do nothing
    else
      -- Add id to fig
      fignum = fignum + 1
      fig[id] = fignum
    end
  end
 
  return fig[id]
end


Block = function(b)
  -- Increment prefix for every level-1 header starting with Appendix
  if b.tag == "Header" and b.level == 1 and pandoc.text.sub(pandoc.utils.stringify(b.content), 1, 8) == "Appendix" then
    if intprefix == 26 then
      intprefix = 0
      intpreprefix = intpreprefix + 1
      preprefix = preprefix .. pandoc.text.sub(abc,intpreprefix,intpreprefix)
    end
    intprefix = intprefix + 1
    tblnum = 0
    fignum = 0
    prefix = preprefix .. pandoc.text.sub(abc,intprefix,intprefix)
  end
  
  -- Assign prefixes and numbers
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
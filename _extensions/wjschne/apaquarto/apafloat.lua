
-- Finds divs that are Tables and Figures.
-- Adds FigureWithNote or FigureWithoutNote class to the Div
-- If docx, strips enclosing table and raw cod
function Div (elem)
  local isfigure = false
  local istable = false
  
  -- Is cell output
  if elem.classes:includes("cell") then
    -- Is Figure or Table
    elem.content:walk {
      Div = function(dv)
        if dv.identifier:find("^fig-") then
          isfigure = true
        end
        if dv.identifier:find("^tbl-") then
          istable = true
        end
      end
        }

      if FORMAT == "docx" and elem.identifier:find("^tbl-") then
          elem.content = elem.content:walk {RawInline = function(ri) return {} end}
          elem.content = elem.content:walk {
            Table = function(tb) 
             
                if tb.classes:includes("do-not-create-environment") then
                   
                else
                  tb.classes:insert(1, "do-not-create-environment")
                  return tb
                end
                
              end
            
          }
          local newdiv = pandoc.Div(elem)
          newdiv.classes:insert("cell")
          newdiv.attributes = elem.attributes
          if elem.attributes["apa-note"] then
            newdiv.classes:insert("FigureWithNote")
            newdiv.attributes["custom-style"] = "FigureWithNote"
          else
            newdiv.classes:insert("FigureWithoutNote")
            newdiv.attributes["custom-style"] = "FigureWithoutNote"
          end 
          
          
          elem = newdiv
          
          --print(elem)
      end
      
    -- Adds classes to Divs with Figure or Table in them.
    if isfigure or istable then

      local figureclass = "FigureWithoutNote"
      if elem.attributes["apa-note"] then
        figureclass = "FigureWithNote"
      end
      elem.attributes["custom-style"] = figureclass
      elem.classes:insert(figureclass)
--      if FORMAT == "docx" then
--        -- Strips figure from table
--        elem.content:walk {
--        Div = function(dv)
--          if dv.identifier:find("^fig-") or dv.identifier:find("^tbl-") then
--            dv.content = dv.content:walk {RawInline = function(ri) return {} end}
--            elem.content = dv
--          end
--        end
--      }
--      end 
    end
    --print(elem)
  end
      

  return elem
end
-- Finds divs that are Tables and Figures.
-- Adds FigureWithNote or FigureWithoutNote class to the Div
function Pandoc (doc)
  local isfigure = false
  local istable = false
  local hasnote = false
  for i = 1, #doc.blocks, 1 do
    isfigure = false
    istable = false
    hasnote = false
    if doc.blocks[i].identifier then
      if doc.blocks[i].identifier:find("^fig%-") then
        isfigure = true
        
      end
      if doc.blocks[i].identifier:find("^tbl%-") then
        istable = true
        
      end
      
    end
    if doc.blocks[i].t == "Div" then
      
      doc.blocks[i].content:walk {
        Div = function(div)
          if div.identifier then
            if div.identifier:find("^fig%-") then
              isfigure = true
    
              
            end
            if div.identifier:find("^tbl%-") then
              istable = true
            end
          end
        end
        }
    end
    if isfigure or istable then
       if istable and FORMAT == "docx" then
        doc.blocks[i].content = doc.blocks[i].content:walk {
        Table = function(tb) 
             
                if tb.classes:includes("do-not-create-environment") then
                   
                else
                  tb.classes:insert(1, "do-not-create-environment")
                  return tb
                end
                
        end
            }

      end
      

        if doc.blocks[i].attributes["apa-note"] then
          doc.blocks[i].classes:insert("FigureWithNote")
          doc.blocks[i].attributes["custom-style"] = "FigureWithNote"
        else
          doc.blocks[i].classes:insert("FigureWithoutNote")
          doc.blocks[i].attributes["custom-style"] = "FigureWithoutNote"          
        end
      end
  end
  return doc
end

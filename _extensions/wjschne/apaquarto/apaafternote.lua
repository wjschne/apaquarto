if FORMAT == "latex" then
  return 
end

local function makeafternote(p)
  div = pandoc.Div(p)
  div.classes:insert("AfterWithoutNote")
  div.attributes['custom-style'] = 'AfterWithoutNote'
  return div
end


function Pandoc(doc)
    local hblocks = {}
    local isfloatref = false

    for i = #doc.blocks - 1, 1, -1 do
      if doc.blocks[i+1].t == "Para" then
      end
      if doc.blocks[i+1].t == "Para" and doc.blocks[i].t == "Div" then
        
        if doc.blocks[i].attributes["custom-style"] == "FigureWithoutNote" then
          doc.blocks[i+1] = makeafternote(doc.blocks[i+1])
          --print(makeafternote(doc.blocks[i+1]))
          
        end
        if doc.blocks[i].identifier:find("^tbl%-") then
          doc.blocks[i+1] = makeafternote(doc.blocks[i+1])
        end
      end

      

    end
    return pandoc.Pandoc(doc.blocks, doc.meta)
end




if FORMAT == "latex" then
  return
end

local beginapanote = "Note"

local function getnote(m)
    if m.language and m.language["figure-table-note"] then
        beginapanote = pandoc.utils.stringify(m.language["figure-table-note"])
    end
end

local function apanote(elem)
  if elem.attributes["apa-note"] then
      hasnote = true
      elem.content:walk {
        Div = function(div) 
          if div.attributes["apa-note"] then
            hasnote = false
          end
        end
      }
      if hasnote then
        local apanotepara = pandoc.Para({pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."),pandoc.Space()})
        apanotepara.content:extend(quarto.utils.string_to_inlines(elem.attributes["apa-note"]))
        local apanote = pandoc.Div(apanotepara)
        
        apanote.attributes['custom-style'] = 'FigureNote'
        apanote.classes:extend({"FigureNote"})
        return {elem, apanote}
      end
    end
end

return {
  {Meta = getnote},
  {Div = apanote}
}
if FORMAT ~= "latex" then
  function Div (elem)
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
        local apanotepara = pandoc.Para({pandoc.Emph(pandoc.Str("Note.")), pandoc.Space()})
        apanotepara.content:extend(quarto.utils.string_to_inlines(elem.attributes["apa-note"]))
        local apanote = pandoc.Div(apanotepara)
        
        apanote.attributes['custom-style'] = 'FigureNote'
        apanote.classes:extend({"FigureNote"})
        return {elem, apanote}
      end
    end
  end
end
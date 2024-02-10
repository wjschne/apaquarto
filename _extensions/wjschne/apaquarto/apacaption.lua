local caption_formatter = function(p)

  if pandoc.utils.stringify(p.content[1]) == "Figure" or pandoc.utils.stringify(p.content[1]) == "Table" then
            local figuretitle = pandoc.Para({})
            local figurecaption = pandoc.Para({})
            
            local intStart = 0
            --print(p.content)
            for i, v in ipairs(p.content) do
              if i > intStart and i < intStart + 4 then
                figuretitle.content:extend({v})
              end
              if i > intStart + 5 then
                figurecaption.content:extend({v})
              end
            end
            local figuretitlediv = pandoc.Div(figuretitle)
            figuretitlediv.classes:insert("FigureTitle")
            figuretitlediv.attributes["custom-style"] = "FigureTitle"
            local figurecaptiondiv = pandoc.Div(figurecaption)
            figurecaptiondiv.classes:insert("Caption")
            figurecaptiondiv.attributes["custom-style"] = "Caption"
            return {figuretitlediv, figurecaptiondiv}
  end
end

Div = function(div)
  if div.identifier:find("^tbl%-") or div.identifier:find("^fig%-") then
    if FORMAT == "html" then
      div.content = div.content:walk {Plain = caption_formatter}
    end
    if FORMAT == "docx" then
      div.content = div.content:walk {RawInline = function(ri) return {} end}
      div.content = div.content:walk {Para = caption_formatter}
    end 
    return div
  end

end


-- Get names for Figure and Table in language specified in lang field
local figureword = "Figure"
local tableword = "Table"
local labelnum = ""

local function gettablefig(m)
 -- Get names for Figure and Table specified in language field
    if m.language then
      if m.language["crossref-fig-title"] then
        figureword = pandoc.utils.stringify(m.language["crossref-fig-title"])
      end
      
      if m.language["crossref-tbl-title"] then
        tableword = pandoc.utils.stringify(m.language["crossref-tbl-title"])
      end
    else
      
    end
end


-- Format caption
local caption_formatter = function(p)
  
  if p.content[1] and (p.content[1].text == figureword or p.content[1].text == tableword) then
    if p.content[2] and p.content[2].text == '\u{a0}' then
      --print(p.content[4])
      if p.content[4] and p.content[4].text == ':' then
            local figuretitle = pandoc.Para({})
            local figurecaption = pandoc.Para({})
            
            local intStart = 0


            for i, v in ipairs(p.content) do
              if i > intStart and i < intStart + 4 then
                if i == 3 then 
                  v = pandoc.Str(labelnum) 
                end
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
  end
end

local divcaption = function(div)
  if div.identifier:find("^tbl%-") or div.identifier:find("^fig%-") then
    if div.attributes.prefix then
      if div.attributes.fignum then
        --quarto.log.output(div.attributes.fignum)
        labelnum = div.attributes.prefix .. div.attributes.fignum
        --print(labelnum)
      end
      if div.attributes.tblnum then
        labelnum = div.attributes.prefix .. div.attributes.tblnum
      end
    end
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

return {
  {Meta = gettablefig},
  {Div = divcaption}
}


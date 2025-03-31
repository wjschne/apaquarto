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
  -- If the paragraph content's first element is the figureword or tableword
  if p.content[1] and (p.content[1].text == figureword or p.content[1].text == tableword) then
    -- If the paragraph content's second element is a non-breaking space
    if p.content[2] and p.content[2].text == '\u{a0}' then
      -- If the paragraph content's fourth element is a colon
      if p.content[4] and p.content[4].text == ':' then
            local figuretitle = pandoc.Para({})
            local figurecaption = pandoc.Para({})
            
            local intStart = 0
            -- separate figure title from figure caption
            for i, v in ipairs(p.content) do
              -- Figure/table title
              if i > intStart and i < intStart + 4 then
                if i == 3 then 
                  -- Figure or table number
                  v = pandoc.Str(labelnum) 
                end
                figuretitle.content:extend({v})
              end
              -- Figure/table caption
              if i > intStart + 5 then
                figurecaption.content:extend({v})
              end
            end
            -- enclose figure/table title in a div with custom style
            local figuretitlediv = pandoc.Div(figuretitle)
            figuretitlediv.classes:insert("FigureTitle")
            figuretitlediv.attributes["custom-style"] = "FigureTitle"
            -- enclose figure/table caption in a div with custom style
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
    
    -- Get figure/table prefix and number
    if div.attributes.prefix then
      if div.attributes.fignum then
        -- Have to remove subfigure letters if present
        labelnum = div.attributes.prefix .. string.match(div.attributes.fignum, "%d+")
      end
      if div.attributes.tblnum then
        labelnum = div.attributes.prefix .. string.match(div.attributes.tblnum, "%d+")
      end
    end
    
    if FORMAT == "html" then
      div.content = div.content:walk {Plain = caption_formatter}
    end
    if FORMAT == "docx" then
      -- Remove raw openxml from div
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


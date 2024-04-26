local hasrefdiv = false
local referenceword = "References"
return {
  {
    Meta = function(meta)
      if meta.language then
        -- Is there another word for reference section?
        if meta.language["section-title-references"] then
          referenceword = pandoc.utils.stringify(meta.language["section-title-references"])
        end
      end
    end
  },
  { Div = function(div) 
      if div.identifier and div.identifier == "refs" then
          -- There are references and there is a refdiv
          hasrefdiv = true
      end
    end
  },
  { Header = function(h)
      if h.content and pandoc.utils.stringify(h.content) == referenceword then
        if hasrefdiv then
        else
          local refdiv = pandoc.Div({})
          refdiv.identifier = "refs"
          refdiv.classes:insert("references")
          return {h, refdiv}
        end
      end
    end }
}
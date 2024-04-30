-- This filter adds a refdiv if there is a Reference header but no refdiv

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
          -- There is a refdiv
          hasrefdiv = true
      end
    end
  },
  { Header = function(h)
      if h.content and pandoc.utils.stringify(h.content) == referenceword then
        if hasrefdiv then
          -- Do nothing because there is a refdiv
        else
          -- Add refdiv after References header
          local refdiv = pandoc.Div({})
          refdiv.identifier = "refs"
          refdiv.classes:insert("references")
          return {h, refdiv}
        end
      end
    end }
}
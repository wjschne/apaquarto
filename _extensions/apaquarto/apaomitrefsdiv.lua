-- This filter adds a refdiv if there is a Reference header but no refdiv

local hasrefdiv = false
local referenceword = "References"
local appendixword = "Appendix"
local appendixcount = 0


-- Change Appendix A to Appendix if there is only one appendix.
local fixloneappendix = function(h) 
  if appendixcount == 1 then
    
    if h.level == 1 then
      hcontent = pandoc.utils.stringify(h.content)
      if  hcontent == appendixword .. " A" or  hcontent == "Appendix A" then
        h.content = h.content[1]
        return h
      end
    end
  end
end

return {
  {
    Meta = function(meta)
      if meta.language then
        -- Is there another word for reference section?
        if meta.language["section-title-references"] then
          referenceword = pandoc.utils.stringify(meta.language["section-title-references"])
        end
          if meta.language["crossref-apx-prefix"] then
            appendixword = pandoc.utils.stringify(meta.language["crossref-apx-prefix"])
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
      if h.attr.attributes.appendixtitle then
        appendixcount = appendixcount + 1
      end
      if h.content and ((pandoc.utils.stringify(h.content) == referenceword) or (pandoc.utils.stringify(h.content) == "References"))  then
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
  end },
  { Header = fixloneappendix
  }
}
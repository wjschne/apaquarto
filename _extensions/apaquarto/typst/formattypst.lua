if FORMAT ~='typst' then
  return
end



return {
  {
    -- Replace LaTeX logo
    Math = function(eq)
      if eq.mathtype == "InlineMath" then
        if eq.text == "\\LaTeX" then
          return pandoc.Str("LaTeX")
        end
        if eq.text == "\\TeX" then
          return pandoc.Str("TeX")
        end
      end
    end
  },
  { 
      Div = function(div)
      -- Center author and affiliation
      if div.classes:includes("Author") then
        return {pandoc.RawBlock('typst', "#set align(center)"), div, pandoc.RawBlock('typst', "#set align(left)")}
      end
      
      -- Hanging indent on refs
      if div.identifier == "refs" then
        return {pandoc.RawBlock("typst", "#set par(first-line-indent: 0in, hanging-indent: 0.5in)"), div, pandoc.RawBlock("typst","#set par(first-line-indent: 0.5in, hanging-indent: 0in)") }
      end
      
      if div.classes:includes("NoIndent") then
        return {pandoc.RawBlock('typst', "#set par(first-line-indent: 0mm)"), div, pandoc.RawBlock('typst', "#set par(first-line-indent: firstlineindent)")}
      end
    end
  } ,
  {
    Pandoc = function (doc)
      -- typst aggressively wants to make first paragraphs after something not indented. 
      -- APA style wants almost all paragraphs to be indented.
      -- This function inserts a blank  paragraph and then negative vertical space
      -- before any first paragraph. Hoping that typst will fix this and that this function
      -- becomes unnecessary.
      local appendixword = "Appendix"
      if doc.meta.language and doc.meta.language["crossref-apx-prefix"] then
        appendixword = pandoc.utils.stringify(doc.meta.language["crossref-apx-prefix"])
      end
      
      for i = #doc.blocks, 1, -1 do
        if doc.blocks[i].t == "Para" and doc.blocks[i-1].t ~= "Para" then 
          if doc.blocks[i-1].t == "Header" and doc.blocks[i-1].level > 3 then
            --Do nothing
          else
            doc.blocks:insert(i, pandoc.RawBlock("typst", "#par()[#text(size:0.5em)[#h(0.0em)]]\n#v(-18pt)"))
          end
        end       
        -- Count appendices
        if doc.blocks[i].t == "Header" and doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == appendixword then
          doc.blocks:insert(i+1, pandoc.RawBlock("typst", "#counter(figure.where(kind: \"quarto-float-fig\")).update(0)\n#counter(figure.where(kind: \"quarto-float-tbl\")).update(0)\n#appendixcounter.step()"))
        end
      end
      return doc
    end
  }
}
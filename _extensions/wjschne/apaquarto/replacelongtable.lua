if FORMAT:match 'latex' then
  
  
  local onecolumn = false
  
  Meta = function(m)
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      onecolumn = true
    end
  end
  

  RawBlock  = function (elem)
    

    if onecolumn and (elem.format == "tex" or elem.format == "latex") then

    
      if elem.text:match ("longtable") then
        --elem.text = elem.text:gsub("\\begin{longtable", "\\onecolumn \\begin{longtable")
        elem.text = elem.text:gsub("\\endfirsthead.*\\endhead", "")
        --elem.text = elem.text:gsub("\\end{longtable%*}", "\\bottomrule\\noalign{}\\end{longtable*}")
        if elem.text:match ("\\endlastfoot") then
          elem.text = elem.text:gsub("\\endlastfoot", "")
          elem.text = elem.text:gsub("\\bottomrule\\noalign{}", "")
          elem.text = elem.text:gsub("\\end{longtable%*}", "\\bottomrule\\noalign{}\\end{longtable*}")
          elem.text = elem.text:gsub("\\end{longtable}", "\\bottomrule\\noalign{}\\end{longtable}")
        end
        return elem
      end 
    end 
    


  end
  
  return {
    { Meta = Meta },
  { RawBlock  = RawBlock  }
}
end


if FORMAT:match 'latex' then
  
  local indenter = '\\setlength\\parindent{0.5in}'
  
  Meta = function(m)
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      indenter = '\\setlength\\parindent{0.15in}'
    end
  end
  
  Div = function (div)

    if div.classes:includes 'NoIndent' then
      return {
        pandoc.RawBlock('latex', '\\setlength\\parindent{0in}'),
        div,
        pandoc.RawBlock('latex', indenter)
      }
    end
  end
  
  return {
  { Meta = Meta },
  { Div = Div }
}
end


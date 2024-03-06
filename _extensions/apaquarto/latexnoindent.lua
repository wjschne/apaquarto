if FORMAT:match 'latex' then
  
  local indenter = '\\setlength\\parindent{0.5in}'
  
  Meta = function(m)
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      indenter = '\\setlength\\parindent{0.15in}'
    end

  end
  
  Div = function (div)

    if div.classes:includes 'NoIndent' then
        div.content = div.content:walk {
          Para = function(p)
            p.content:insert(1, pandoc.RawInline("latex", "\\noindent "))
            return p
          end
        }
      return(div)
    end
  end
  
  return {
  { Meta = Meta },
  { Div = Div }
}
end


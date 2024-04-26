-- Sets paragraph indenting

if FORMAT:match 'latex' then
  
  local indenter = '\\setlength\\parindent{0.5in}'
  
  local setindent = function(m)
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      indenter = '\\setlength\\parindent{0.15in}'
    end

  end
  
  local indenter = function(div)

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
  
  local fixlatexcommand = function(m) 
    if m.text == "\\LaTeX" then
      return pandoc.RawInline("latex", m.text)
    end
  end
  
  return {
  { Meta = setindent },
  { Div = indenter },
  { Math = fixlatexcommand}
}
end


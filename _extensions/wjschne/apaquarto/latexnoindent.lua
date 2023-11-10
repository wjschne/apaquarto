if FORMAT:match 'latex' then
  function Div (div)
    if div.classes:includes 'NoIndent' then
      return {
        pandoc.RawBlock('latex', '\\setlength\\parindent{0in}'),
        div,
        pandoc.RawBlock('latex', '\\setlength\\parindent{0.5in}')
      }
    end
  end
end


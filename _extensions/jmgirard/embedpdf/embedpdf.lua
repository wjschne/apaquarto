function pdf(args, kwargs)
  local data = pandoc.utils.stringify(args[1])
  local width = pandoc.utils.stringify(kwargs['width'])
  local height = pandoc.utils.stringify(kwargs['height'])
  local class = pandoc.utils.stringify(kwargs['class'])
  local border = pandoc.utils.stringify(kwargs['border'])
  
  if width ~= '' then
    width = 'width="' .. width .. '" '
  end
  
  if height ~= '' then
    height = 'height="' .. height .. '" '
  end
  
  if class ~= '' then
    class = 'class="' .. class .. '" '
  end
  
  if border ~= '' then
    border = 'border="' .. border .. '" '
  end
  
  -- detect html
  if quarto.doc.isFormat("html:js") then
    return pandoc.RawInline('html', '<object data="' .. data .. '" type="application/pdf"' .. width .. height .. class .. border .. '><p>Unable to display PDF file. <a href="' .. data .. '">Download</a> instead.</p></object>')
  else
    return pandoc.Null()
  end

end

function embedpdf(...)
  return pdf(...)
end

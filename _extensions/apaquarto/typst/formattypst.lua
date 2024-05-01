if FORMAT ~='typst' then
  return
end

Div = function(div)
  if div.classes:includes("Author") then
    return {pandoc.RawBlock('typst', "#set align(center)"), div, pandoc.RawBlock('typst', "#set align(left)")}
  end
  
  if div.identifier == "refs" then
    return {pandoc.RawBlock("typst", "#set par(first-line-indent: 0in, hanging-indent: 0.5in)"), div, pandoc.RawBlock("typst","#set par(first-line-indent: 0.5in, hanging-indent: 0in)") }
  end
end
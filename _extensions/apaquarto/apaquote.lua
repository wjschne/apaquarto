--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end


local i

BlockQuote = function (element)
  i = 0
  return pandoc.walk_block(element, {
    Para = function (el)
      i = i + 1
      if i > 1 then return pandoc.Div({el}, pandoc.Attr("", {}, {["custom-style"]="NextBlockText"}))
      else return el end
    end
  })
end
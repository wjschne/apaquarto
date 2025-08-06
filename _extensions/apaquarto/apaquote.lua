-- In blockquotes with multiple paragraphs, give special
-- style to paragraphs after the first paragraph

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

BlockQuote = function(element)
  local i = 0
  return pandoc.walk_block(element, {
    Para = function(el)
      i = i + 1
      -- Is this after the first paragraph?
      if i > 1 then
        return pandoc.Div({ el }, pandoc.Attr("", {}, { ["custom-style"] = "NextBlockText" }))
      else
        return el
      end
    end
  })
end

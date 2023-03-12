if FORMAT ~= "docx" then
  return
end
stringify = pandoc.utils.stringify

local function ends_with(str, ending)
   return string.sub(str.text, -1) == ending
end

---function Header (elem)
---  if elem.level > 3 and elem.content then
---    if not (ends_with(elem.content[#elem.content],".") or ends_with(elem.content[#elem.content],"?") or ends_with(elem.content[#elem.content],"?")) then
---      elem.content[#elem.content + 1] = pandoc.Str(".")
---      ---elem.attr = {id = elem.identifier, class = pandoc.utils.stringify(elem.classes), vanish="vanisher"}
---      local d = pandoc.Div()
---      if elem.level == 4 then 
---        return pandoc.Para(pandoc.Strong(pandoc.utils.stringify(elem.content)))
---      end 
---      if elem.level == 5 then 
---        return pandoc.Div(pandoc.Para(pandoc.Strong(pandoc.Emph(pandoc.utils.stringify(elem.content)))), Attr("",{"H5"},{}))
---      end 
---    end
---  end
---end

function Header (hx)
  if hx.level > 3 then
    if not (ends_with(hx.content[#hx.content],".") or ends_with(hx.content[#hx.content],"?") or ends_with(hx.content[#hx .content],"?")) then
      hx.content[#hx.content + 1] = pandoc.Str(".")
    end 
    local htext = stringify(hx.content)
    local prefix = "<w:p><w:pPr><w:pStyle w:val=\"Heading" .. hx.level .. "\"/><w:rPr><w:vanish/><w:specVanish/></w:rPr></w:pPr><w:r><w:t>"
		local suffix = "</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:p>"

    return pandoc.RawBlock('openxml', prefix .. htext .. suffix)
---    local startTag = '<text:h text:style-name=\"' .. class .. '\" text:outline-level=\"' .. hx.level .. '\">'
---    local endTag = '</text:h>'
---    local content = startTag .. pandoc.utils.stringify(hx) .. endTag
---    content = string.gsub(content, "\t", "<text:tab/>")
---return pandoc.RawBlock('opendocument',stringify(hx.content))
  end
end




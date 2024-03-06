local andreplacement = "and"

local function get_and(m)
    if m.language and m.language["citation-last-author-separator"] then
        andreplacement = pandoc.utils.stringify(m.language["citation-last-author-separator"])
    end
end

---From Samuel Dodson
---https://github.com/citation-style-language/styles/issues/3748#issuecomment-430871259
local function replace_and(elem)
    if elem.citations[1].mode == "AuthorInText" then
        elem.content = pandoc.walk_inline(elem, {
            Str = function(el)
                return pandoc.Str(string.gsub(el.text, "&", andreplacement))
            end})
        if elem.citations[1].suffix and #elem.citations[1].suffix > 0 then

            if elem.citations[1].suffix[1].text == "’s" or elem.citations[1].suffix[1].text == "'s" then
                
                if elem.content.content then
                  local intLeftParen = 0
                  for i, j in pairs(elem.content.content) do
                    if j.tag == "Str" and string.find(j.text, "’s") then
                        j.text = string.gsub(j.text, "’s", "")
                    end
                    if j.tag == "Str" and string.find(j.text, "%(") then
                        intLeftParen = i
                    end
                  end
                  if intLeftParen > 2 then
                          elem.content.content[intLeftParen - 2].text = elem.content.content[intLeftParen - 2].text .. "’s"
                  end
                end
            end
        end
        --print(elem.content)
        return elem.content
    end
    --return pandoc.Cite(elem.content, elem.citations)
end

return {
    { Meta = get_and },
    { Cite = replace_and }
}
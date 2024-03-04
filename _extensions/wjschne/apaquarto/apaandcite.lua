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
        return elem.content
    end
    return pandoc.Cite(elem.content, elem.citations)
end

return {
    { Meta = get_and },
    { Cite = replace_and }
}
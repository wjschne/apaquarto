---From Samuel Dodson
---https://github.com/citation-style-language/styles/issues/3748#issuecomment-430871259
function Cite(elem)
    if elem.citations[1].mode == "AuthorInText" then
        elem.content = pandoc.walk_inline(elem, {
            Str = function(el)
                return pandoc.Str(string.gsub(el.text, "&", "and"))
            end})
        return elem.content
    end
    --Originally looked like this, but lua interpreter did not like it
    --return pandoc.Cite(elem.content, elem.citations, elem.tag)
    return pandoc.Cite(elem.content, elem.citations)
end
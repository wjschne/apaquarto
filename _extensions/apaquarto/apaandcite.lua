local andreplacement = "and"
-- make string, if it exists, else return default
local stringify = function(s, default)
  if s then
    s = pandoc.utils.stringify(s)
  else
    if default then
      s = default
    else
      s = ""
    end
  end
  return s
end


local function get_and(m)
  if m.language and m.language["citation-last-author-separator"] then
    andreplacement = stringify(
      m.language["citation-last-author-separator"], 
      andreplacement)
  end
end

---Adapted from Samuel Dodson
---https://github.com/citation-style-language/styles/issues/3748#issuecomment-430871259
local function replace_and(ct)
    if ct.citations[1].mode == "AuthorInText" then
        ct.content = ct.content:walk {
            Str = function(s)
                if s.text == "&" then
                  s.text = andreplacement
                end
                return s
            end
        }
            
        if ct.citations[1].suffix and #ct.citations[1].suffix > 0 then

            if ct.citations[1].suffix[1].text == "’s" or ct.citations[1].suffix[1].text == "'s" then
                print(ct)
                if ct.content then
                  local intLeftParen = 0
                  for i, j in pairs(ct.content) do
                    if j.tag == "Str" and string.find(j.text, "’s") then
                        j.text = string.gsub(j.text, "’s", "")
                    end
                    if j.tag == "Str" and string.find(j.text, "%(") then
                        intLeftParen = i
                    end
                  end
                  if intLeftParen > 2 then
                    ct.content[intLeftParen - 2].text = ct.content[intLeftParen - 2].text .. "’s"
                  end
                end
            end
        end
        return ct.content
    end
end

return {
    { Meta = get_and },
    { Cite = replace_and }
}
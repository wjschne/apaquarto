-- Formats level 4 and 5 headers for APA format.

-- Does the header already end in a punctuation mark? The whole header is
-- read rather than its last inline, which has no text of its own when the
-- header ends in something like bold or code.
local function ends_with_punctuation(content)
  return pandoc.utils.stringify(content):match("[.?!]%s*$") ~= nil
end

-- APA runs a level-four or level-five heading in with the paragraph after
-- it. In .docx that takes raw openxml, which docxcontents.lua writes at the
-- end of the chain; here the heading is only marked. It has to stay a heading
-- until then: quarto resolves a reference to it after this runs, and a
-- heading already turned into raw openxml had nothing to be found by, so
-- @sec- to one printed as ?@sec-x.
local kRunIn = "apa-runin"

function Header(hx)
  if hx.level > 3 then
    -- Add a period unless a punctuation mark is already present
    if not ends_with_punctuation(hx.content) then
      hx.content[#hx.content + 1] = pandoc.Str(".")
    end
    if FORMAT == "docx" then
      hx.classes:insert(kRunIn)
    end
    return hx
  end
end

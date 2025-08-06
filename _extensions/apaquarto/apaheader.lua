-- Formats level 4 and 5 headers for APA format.

-- Does the string end with a specific character?
---http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
  return string.sub(str.text, -1) == ending
end


function Header(hx)
  if hx.level > 3 then
    -- Add a period unless a punctuation mark is already present
    if not (ends_with(hx.content[#hx.content], ".") or ends_with(hx.content[#hx.content], "?") or ends_with(hx.content[#hx.content], "?")) then
      hx.content[#hx.content + 1] = pandoc.Str(".")
    end
    if FORMAT == "docx" then
      -- Adds a "Style Separator" character that allows the headier to appear as if it were on the same line as the subsequent paragraph.
      local htext = pandoc.utils.stringify(hx.content)
      local prefix = "<w:p><w:pPr><w:pStyle w:val=\"Heading" ..
      hx.level .. "\"/><w:rPr><w:vanish/><w:specVanish/></w:rPr></w:pPr><w:r><w:t>"
      local suffix = "</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:p>"
      return pandoc.RawBlock('openxml', prefix .. htext .. suffix)
    end
    return hx
  end
end

-- Formats level 4 and 5 headers for APA format.

-- Does the header already end in a punctuation mark? The whole header is
-- read rather than its last inline, which has no text of its own when the
-- header ends in something like bold or code.
local function ends_with_punctuation(content)
  return pandoc.utils.stringify(content):match("[.?!]%s*$") ~= nil
end

-- The header text below is put into raw openxml, where these characters are
-- markup. Word refuses to open a file with an unescaped ampersand in it.
local function xml_escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end


function Header(hx)
  if hx.level > 3 then
    -- Add a period unless a punctuation mark is already present
    if not ends_with_punctuation(hx.content) then
      hx.content[#hx.content + 1] = pandoc.Str(".")
    end
    if FORMAT == "docx" then
      -- Adds a "Style Separator" character that allows the headier to appear as if it were on the same line as the subsequent paragraph.
      local htext = pandoc.utils.stringify(hx.content)
      local prefix = "<w:p><w:pPr><w:pStyle w:val=\"Heading" ..
      hx.level .. "\"/><w:rPr><w:vanish/><w:specVanish/></w:rPr></w:pPr><w:r><w:t>"
      local suffix = "</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:p>"
      return pandoc.RawBlock('openxml', prefix .. xml_escape(htext) .. suffix)
    end
    return hx
  end
end

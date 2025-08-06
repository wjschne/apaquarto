-- For now, apa.csl cannot handle different separators for in-text
-- and parenthetical citations. Forthcoming updates to csl will handle
-- them automatically.
-- This filter finds in-text citations with multiple authors and converts
-- the ampersand to "and" (or whatever separator specified in the yaml
-- language field "citation-last-author-separator")

-- This filter also implements possessive citations. For example:
-- @schneider2021 ['s] primary findings were replicated in our study.
-- becomes:
-- Schneider's (2021) primary findings were replicated in our study.

-- This filter also removes the asterisk for in-text citations that are also no-cite meta-analytic references.

local andreplacement = "and"
local makelinks = false
local no_ampersand_parenthetical = false

local utilsapa = require("utilsapa")

-- Get alternate separator, if it exists
local function get_and(m)
  if m.language and m.language["citation-last-author-separator"] then
    andreplacement = utilsapa.stringify(
      m.language["citation-last-author-separator"],
      andreplacement)
  end
  if m["link-citations"] then
    makelinks = true
  end

  if m["no-ampersand-parenthetical"] then
    no_ampersand_parenthetical = true
  end
end

local function remove_asterisk(s)
  s.text = string.gsub(s.text, "^%*", "")
  return s
end

local function replace_and(ct)
  -- Replace ampersand
  ---Adapted from Samuel Dodson
  ---https://github.com/citation-style-language/styles/issues/3748#issuecomment-430871259
  ct.content = ct.content:walk {
    Str = function(s)
      if s.text == "&" then
        s.text = andreplacement
      end
      return s
    end
  }
  return ct
end

local function process_citation(ct)
  -- Remove initial asterisk
  ct.content = ct.content:walk {
    Str = remove_asterisk,
    Link = function(l)
      l.content = l.content:walk {
        Str = remove_asterisk
      }
      return (l)
    end
  }


  local replace_possessive = false
  local remove_ampersand_suffix = false

  -- Replace & with and if no_ampersand_parenthetical or narrative citation
  if no_ampersand_parenthetical or ct.citations[1].mode == "AuthorInText" then
    -- Do not replace ampsersand if suffix == "&"
    if ct.citations[1].hash == 1 or ct.citations[1].hash == 3 then
      replace_possessive = true
    end
    if ct.citations[1].hash == 2 or ct.citations[1].hash == 3 then
      remove_ampersand_suffix = true
    end

    if not remove_ampersand_suffix then
      ct = replace_and(ct)
    end
  end
  -- Make possessive citation
  if replace_possessive then
    if ct.content then
      local intLeftParen = 0
      for i, j in pairs(ct.content) do
        if j.tag == "Str" then
          --- Where is the left parenthesis?
          if string.find(j.text, "%(") then
            intLeftParen = i
          end
        end
      end
      
      if intLeftParen > 2 and replace_possessive then
        ct.content[intLeftParen - 2].text = ct.content[intLeftParen - 2].text .. "\u{2019}s"
      end
    end
  end

  if FORMAT == "typst" then
    return ct.content
  else
    return ct
  end
end

return {
  { Meta = get_and },
  { Cite = process_citation }
}

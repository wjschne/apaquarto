-- This filter inserts the appendix macro in latex documents
if FORMAT ~= "latex" then
  return
end

local afterrefs = false

-- Word for appendix
local appendixword = "Appendix"
getappendixword = function(meta)
  if meta.language and meta.language["crossref-apx-prefix"] then
    appendixword = pandoc.utils.stringify(meta.language["crossref-apx-prefix"])
  end
end

-- Count how many appendices there are
local appendixcount = 0
-- Count how many level 1 headers are in each appendix
local appendixheadercount = {}



local count_headers_in_appendix = function(h)
  -- Is the level 1 header an appendix?
  if h.level == 1 and h.content[1] and h.content[1].text == appendixword then
    appendixcount = appendixcount + 1
    appendixheadercount[appendixcount] = 0
    -- Is the level 1 header in an appendix?
  elseif appendixcount > 0 and h.level == 1 then
    appendixheadercount[appendixcount] = appendixheadercount[appendixcount] + 1
  end
end


-- Count how many appendices there are
local appendixcount2 = 0

local make_appendix = function(h)
  if h.level == 1 and h.content[1].text == appendixword then
    appendixcount2 = appendixcount2 + 1
    -- If this is the first appendix, then start the appendix section
    if appendixcount2 == 1 then
      -- If user did not supply an appendix title, then make a blank title
      if appendixheadercount[appendixcount2] == 0 then
        return { pandoc.RawBlock("latex", "\\appendix"), pandoc.RawBlock("latex",
          "\\section{}\\label{" .. h.identifier .. "}") }
      else
        return { pandoc.RawBlock("latex", "\\appendix") }
      end
    else
      -- If user did not supply an appendix title, then make a blank title
      if appendixheadercount[appendixcount2] == 0 then
        return pandoc.RawBlock("latex", "\\section{}\\label{" .. h.identifier .. "}")
      else
        return pandoc.RawBlock("latex", "")
      end
    end
  end
end



return {
  { Meta = getappendixword },
  { Block = findappendixheader },
  { Header = count_headers_in_appendix },
  { Header = make_appendix }
}

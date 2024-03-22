if FORMAT ~= "latex" then
  return
end

local appendixcount = 0
local appendixheadercount = {}

local count_headers_in_appendix = function(h)
  if h.level == 1 and h.content[1] and h.content[1].text == "Appendix" then
    appendixcount = appendixcount + 1
    appendixheadercount[appendixcount] = 0
  elseif appendixcount > 0 and h.level == 1 then
    appendixheadercount[appendixcount] = appendixheadercount[appendixcount] + 1
  end
end



local appendixcount2 = 0

local make_appendix = function(h)
  
  if h.level == 1 and h.content[1].text == "Appendix" then
    appendixcount2 = appendixcount2 + 1
    if appendixcount2 == 1 then
      if appendixheadercount[appendixcount2] == 0 then
        return {pandoc.RawBlock("latex", "\\appendix"), pandoc.RawBlock("latex", "\\section{}\\label{" .. h.identifier .. "}")}
      else
        return {pandoc.RawBlock("latex", "\\appendix")}
      end
    else
      if appendixheadercount[appendixcount2] == 0 then
        return pandoc.RawBlock("latex", "\\section{}\\label{" .. h.identifier .. "}")
      else
        return pandoc.RawBlock("latex", "")
      end
    end
  elseif h.level == 1 and appendixcount2 > 0 then
    
  end
end

return {
  {Header = count_headers_in_appendix},
  {Header = make_appendix},
}
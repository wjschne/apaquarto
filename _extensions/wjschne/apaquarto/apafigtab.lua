
local apatb = {}
local apafg = {}

function GetTableLng(tbl)
  local getN = 0
  for n in pairs(tbl) do 
    getN = getN + 1 
  end
  return getN
end

local function starts_with(start, str)
  return str:sub(1, #start) == start
end

function makefignums (s)
  if s.identifier then
    if starts_with("apafg", s.identifier) then
      apafg[s.identifier]=GetTableLng(apafg)+1
    end
    if starts_with("apatb", s.identifier) then
      apatb[s.identifier]= GetTableLng(apatb)+1
    end
  end
  return s
end 


function makefigrefs (s)
  if starts_with("{apafg", s.text) or starts_with("({apafg", s.text) then
    local sfg = string.match(s.text, "%{(.-)%}")
    if FORMAT ~= "latex" then
      local figtitle = apafg[sfg] and "Figure\u{a0}" .. apafg[sfg]
      local new_s = s.text and figtitle and string.gsub(s.text, "%b{}", figtitle)
      return new_s and pandoc.Str(new_s)
    else 
      local figtitle = "Figure~" .. "\\ref{" .. sfg .. "}"
      return pandoc.RawInline('latex', string.gsub(s.text, "%b{}", figtitle))
    end

    
  end
  if starts_with("{apatb", s.text) or starts_with("({apatb", s.text) then
    local stb = string.match(s.text, "%{(.-)%}")
    if FORMAT ~= "latex" then
      local tabtitle = apatb[stb] and "Table\u{a0}" .. apatb[stb]
      local new_s = s.text and tabtitle and string.gsub(s.text, "%b{}", tabtitle)
      return new_s and pandoc.Str(new_s)
    else
      local tabtitle = "Table~" .. "\\ref{" .. stb .. "}"
      return pandoc.RawInline('latex', string.gsub(s.text, "%b{}", tabtitle))
    end
  end
end

return {
  { Div = makefignums},
  { Str = makefigrefs}
}

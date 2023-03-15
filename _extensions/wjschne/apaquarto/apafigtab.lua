
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
  if starts_with("{apafg", s.text) then
    local sfg = string.match(s.text, "%{(.-)%}")
    ---quarto.log.output(sfg)
    return apafg[sfg] and pandoc.Str("Figure\u{a0}" .. apafg[sfg])
  end
  if starts_with("{apatb", s.text) then
    local stb = string.match(s.text, "%{(.-)%}")
    return apatb[stb] and pandoc.Str("Table\u{a0}" .. apatb[stb])
  end
end

return {
  { Div = makefignums},
  { Str = makefigrefs}
}

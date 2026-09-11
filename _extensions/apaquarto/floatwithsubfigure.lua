local beginapanote = "Note"
local utilsapa = require("utilsapa")

local function getnote(m)
  if m.language and m.language["figure-table-note"] then
    beginapanote = pandoc.utils.stringify(m.language["figure-table-note"])
  end
end

local mynote = function(float)
    if float.attributes["disable-apaquarto-processing"] then
    if not (float.attributes["disable-apaquarto-processing"] == "false") then
      return float
    end
  end
  
  if float.attributes.hassubfigs then
    
    if float.attributes['apa-note'] then
      prefix = pandoc.Para({ pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."), pandoc.Space() })
      apanotedivs = utilsapa.make_note(float.attributes['apa-note'], prefix)

        float.content:extend({ apanotedivs })

      return float
    end
  end
end

return {
  { Meta = getnote },
  { FloatRefTarget = mynote }
}
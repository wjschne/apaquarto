local M = {}

function M.make_note(s, prefix) 

        s = string.gsub(s, '^%[%"', "")
        s = string.gsub(s, '%"%]$', "")

        local includeprefix = true



        local apanotedivs = pandoc.Div(pandoc.Blocks{})

        local cnt = 0
        
        for v in string.gmatch(s..'","', '(.-)%",%"') do
          if string.find(v, '^NoNote ') then
            includeprefix = false
            v = string.gsub(v, '^NoNote ', "")
          end
          local apanote = pandoc.Div({})
          apanote.attributes['custom-style'] = 'FigureNote'
          apanote.classes:extend({"FigureNote"})
          apanote.classes:extend({"NoIndent"})
          cnt = cnt + 1
          if (cnt == 1 and includeprefix) then
            apanote.content:extend(prefix.content:extend(quarto.utils.string_to_inlines(v)))
          else
              apanote.content:extend(quarto.utils.string_to_inlines(v))
          end
          apanotedivs.content:extend({apanote})
        end
    return(apanotedivs)
end

-- make string, if it exists, else return default
function M.stringify(s, default)
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

return M
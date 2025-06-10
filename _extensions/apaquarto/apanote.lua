-- This filter prints the apa-note, if present

-- Do nothing if latex
if FORMAT == "latex" then
  return
end

-- Default word for note
local beginapanote = "Note"
-- Replace note word, if specified
local function getnote(m)
    if m.language and m.language["figure-table-note"] then
        beginapanote = pandoc.utils.stringify(m.language["figure-table-note"])
    end
end

local function apanote(elem)
  if elem.attributes["apa-note"] then
      hasnote = true
      -- If div contains another div with apa-note, do nothing
      elem.content:walk {
        Div = function(div)
          if div.attributes["apa-note"] then
            hasnote = false
          end
        end
      }
      if hasnote then
        -- Make note
        local apanotepara = pandoc.Para({pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."),pandoc.Space()})
        local apanoteparas = elem.attributes["apa-note"]

        local apanotedivs = pandoc.Div(pandoc.Blocks{})

        local cnt = 0
        for v in string.gmatch(apanoteparas, "([^|]+)") do
          local apanote = pandoc.Div({})
          apanote.attributes['custom-style'] = 'FigureNote'
          apanote.classes:extend({"FigureNote"})
          apanote.classes:extend({"NoIndent"})
          if (not(v == "[" or v == "]" or v == ",")) then
            cnt = cnt + 1
            if (cnt == 1) then
              apanote.content:extend(quarto.utils.string_to_blocks("*" .. beginapanote .. "*. "  .. v))
            else
                apanote.content:extend(quarto.utils.string_to_blocks(v))
            end
            apanotedivs.content:extend({apanote})
          end
      end

        return {elem, apanotedivs}
      end
    end
end

return {
  {Meta = getnote},
  {Div = apanote}
}

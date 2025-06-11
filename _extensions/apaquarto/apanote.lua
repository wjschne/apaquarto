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

local utilsapa = require("utilsapa")

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
        prefix = pandoc.Para({pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."),pandoc.Space()})
        apanotedivs = utilsapa.make_note(elem.attributes["apa-note"], prefix)


        return {elem, apanotedivs}
      end
    end
end

return {
  {Meta = getnote},
  {Div = apanote}
}

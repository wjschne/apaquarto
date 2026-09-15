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

-- Set on a float once its note has been written, so that a second run of this
-- filter leaves it alone. A document in an apaquarto format that also names
-- apaquarto in its own `filters:` runs this twice, which without the mark
-- prints every note twice. The mark is added rather than apa-note being taken
-- off, because apafloat.lua reads apa-note afterwards to tell a float that has
-- a note from one that has none.
local kWritten = "apa-note-written"

local function apanote(elem)
  if elem.attributes[kWritten] then
    return nil
  end

  
 -- If div contains image with note
    if FORMAT ==  "typst" then
    elem.content:walk {
      Image = function(img)
        if img.attributes["apa-note"] then
          if not(elem.attributes["apa-note"]) then
            elem.attributes["apa-note"] = img.attributes["apa-note"]  
            hasnote = false
          end

        end
        return img, false
      end
    }
    end
  
  
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
      prefix = pandoc.Para({ pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."), pandoc.Space() })
      apanotedivs = utilsapa.make_note(elem.attributes["apa-note"], prefix)
      elem.attributes[kWritten] = "true"
      return { elem, apanotedivs }
    end
  end
end


return {
  { Meta = getnote },
  { Div = apanote }
}

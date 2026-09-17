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
-- apanote in its own `filters:` runs this twice, which without the mark prints
-- every note twice. The mark is added rather than apa-note being taken off,
-- because apafloat.lua reads apa-note afterwards to tell a float that has a
-- note from one that has none.
--
-- What is marked is which document the note was written for, not merely that
-- it was written. A manuscript project renders a notebook on its own before
-- the article embeds a cell out of it, and the cell arrives carrying whatever
-- was marked on it during that render -- while the note itself stays behind,
-- since only the cell's output is embedded. A mark that said no more than
-- "written" would silence the article and lose the note altogether. Naming the
-- document tells the two apart: the same name means this filter has already
-- been over this float in this render, a different one means the note belongs
-- to another document and has still to be written here.
local kWritten = "apa-note-written"

-- A short digest of the document being rendered. The path itself would do the
-- job but would also be written into the output, where a reader has no use for
-- someone else's directory names.
local function written_by()
  local ok, input = pcall(function() return quarto.doc.input_file end)
  if not ok or not input or input == "" then return "true" end
  local hash = 2166136261
  for i = 1, #input do
    hash = (hash ~ input:byte(i)) * 16777619 % 4294967296
  end
  return string.format("%08x", hash)
end

local written_mark = nil
local function mark()
  if written_mark == nil then written_mark = written_by() end
  return written_mark
end

-- Where inside a cell the note should go, or nil for a float that is not a
-- cell, whose note follows it as before.
--
-- A manuscript project puts a "Source: ..." link under every figure that came
-- from a notebook. The link belongs under both the figure and its note, but it
-- is part of the cell rather than something after it, so a note added after
-- the cell came out beneath the link. Putting the note inside the cell instead
-- settles the order for both ways quarto writes that link: as a block at the
-- foot of the cell, which the note goes in front of, and as an anchor that
-- quarto appends to the cell's html once the filters have run, which lands
-- after the note by itself.
--
-- The block form is found by its shape -- a lone subscript holding a link,
-- which is how quarto builds it -- rather than by the word "Source", which is
-- whatever the document's language calls it.
local function note_position(elem)
  if not elem.classes:includes("cell") then return nil end
  local blocks = elem.content
  local last = blocks[#blocks]
  if last and (last.t == "Plain" or last.t == "Para")
      and #last.content == 1 and last.content[1].t == "Subscript" then
    for _, inline in ipairs(last.content[1].content) do
      if inline.t == "Link" then return #blocks end
    end
  end
  return #blocks + 1
end

local function apanote(elem)
  if elem.attributes[kWritten] == mark() then
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
      elem.attributes[kWritten] = mark()
      local at = note_position(elem)
      if at then
        elem.content:insert(at, apanotedivs)
        return elem
      end
      return { elem, apanotedivs }
    end
  end
end


return {
  { Meta = getnote },
  { Div = apanote }
}

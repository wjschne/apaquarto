-- This filter prints the apa-note, if present

local utilsapa = require("utilsapa")

-- Default word for note
local beginapanote = "Note"
-- Replace note word, if specified
-- The notes of markdown tables as they were written, by identifier
local tablenotes = {}

-- Whether apaquarto's own stylesheet is in use, which spaces a float and its
-- note itself, and whether a note was written in this run.
local ownstyle = false
local wrote = false

local function getnote(m)
  if m.css then
    for _, c in ipairs(m.css) do
      if pandoc.utils.stringify(c):match("apa%.css$") then ownstyle = true end
    end
  end
  beginapanote = utilsapa.lang(m, "figure-table-note", beginapanote)
  tablenotes = utilsapa.table_notes(m)
end

-- Set on a float once its note has been written, so that a second run of this
-- filter leaves it alone, and so that a note floatnote.lua or
-- floatwithsubfigure.lua has already written inside a float is not written
-- again here. A document in an apaquarto format that also names apanote in its
-- own `filters:` runs this twice, which without the mark prints every note
-- twice. The mark is added rather than apa-note being taken off, because
-- apafloat.lua reads apa-note afterwards to tell a float that has a note from
-- one that has none. utilsapa.note_mark says what the mark is and why it names
-- the document.
local kWritten = utilsapa.note_written
local mark = utilsapa.note_mark

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
  -- A code chunk is a cell; a panel written as a markdown image becomes a
  -- layout cell once quarto has built the grid. Either way the note belongs
  -- inside the panel rather than after it: placed after, it is a flex item of
  -- its own beside the panels rather than under the one it describes.
  if not (elem.classes:includes("cell")
      or elem.classes:includes("quarto-layout-cell")) then
    return nil
  end
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
  local hasnote = false

  
 -- If div contains image with note
    if FORMAT ==  "typst" then
    elem.content:walk {
      Image = function(img)
        -- A panel of a figure laid out in panels. Its note belongs under the
        -- panel, where formattypst.lua puts it as it builds the grid, so it is
        -- left alone here: taken onto the div around it, which is the scaffold
        -- quarto wraps the panels in, the note would be written a second time
        -- and after the whole figure rather than under its panel.
        if img.attributes["ref-parent"] then
          return img, false
        end
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
      local prefix = pandoc.Para({ pandoc.Emph(pandoc.Str(beginapanote)), pandoc.Str("."), pandoc.Space() })
      local note = tablenotes[elem.identifier] or elem.attributes["apa-note"]
      local apanotedivs = utilsapa.make_note(note, prefix)
      -- A note is not indented. formattypst.lua sees to that for the notes it
      -- writes, but it has run by now, so a note written here in typst turns
      -- the indent off for itself, inside a block that ends the setting with
      -- the note. In journal mode, which indents every paragraph, the note
      -- was indented without this.
      if FORMAT == "typst" then
        apanotedivs = pandoc.Div({
          pandoc.RawBlock("typst", "#block[#set par(first-line-indent: 0em)"),
          apanotedivs,
          pandoc.RawBlock("typst", "]"),
        })
      end
      elem.attributes[kWritten] = mark()
      wrote = true
      local at = note_position(elem)
      if at then
        elem.content:insert(at, apanotedivs)
        return elem
      end
      return { elem, apanotedivs }
    end
  end
end


-- In a document that does not use apaquarto's stylesheet, a note in .html is
-- a bare div and the paragraph after it runs on from it. A blank line below
-- the note, as in .docx and .pdf, is added here, and only when a note was
-- written.
local function notespacing(doc)
  if wrote and not ownstyle and quarto.doc.is_format("html") then
    quarto.doc.include_text("in-header",
      "<style>.FigureNote { margin-block-end: 1em; }</style>")
  end
  return nil
end

return {
  { Meta = getnote },
  { Div = apanote },
  { Pandoc = notespacing }
}

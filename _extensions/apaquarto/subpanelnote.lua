-- Tells a panel's note apart from the note of the figure it sits in.
--
-- Both are made by apanote.lua and both come out as FigureNote, but APA sets
-- them differently: the note of the whole figure is flush left under the whole
-- figure, while a panel's note is centred under the panel it belongs to. So
-- the panel's note is given a style of its own, SubPanelNote, which apa.scss
-- and the reference document define as FigureNote centred.
--
-- A panel is recognised by carrying a note of its own: inside a figure laid out
-- in panels, the blocks that have an apa-note are the panels, while the note of
-- the whole figure is written straight into the figure by
-- floatwithsubfigure.lua and hangs off no such block.
--
-- typst and latex are left alone: formattypst.lua and floatlatex.lua build
-- their own panels and centre the notes as they go.

-- quarto.doc.isFormat rather than a comparison against FORMAT, which is the
-- name of the pandoc writer and so is "revealjs" for slides. Notes work in
-- slides -- the apanote extension is written for exactly that -- and a panel's
-- note was the one part of them that did not, because the writer's name did
-- not happen to read "html".
if not (quarto.doc.isFormat("html") or quarto.doc.isFormat("docx")) then
  return
end

local kNote = "FigureNote"
local kPanelNote = "SubPanelNote"
-- The layout cell quarto gives a panel that carries a label of its own.
local kPanelCell = "quarto-layout-cell-subref"

local function is_float(div)
  return div.classes:includes("FigureWithNote")
    or div.classes:includes("FigureWithoutNote")
end

-- Whether the float is laid out in panels. Without this a float holding one
-- thing would count too: a table with a note of its own is a div carrying an
-- apa-note inside a float, which is the same shape a panel has, and its note
-- would be centred as though it belonged to a panel.
local function is_laid_out(float)
  if float.classes:includes("quarto-layout-panel") then return true end
  local a = float.attributes
  if not a then return false end
  return a["layout"] ~= nil or a["layout-ncol"] ~= nil
    or a["layout-nrow"] ~= nil or a.hassubfigs ~= nil
end

-- Every FigureNote inside a panel, restyled.
local function restyle(panel)
  return panel:walk {
    Div = function(div)
      if not div.classes:includes(kNote) then return nil end
      div.classes = div.classes:map(function(class)
        if class == kNote then return kPanelNote end
        return class
      end)
      div.attributes["custom-style"] = kPanelNote
      return div
    end
  }
end

return {
  {
    Div = function(float)
      if not is_float(float) or not is_laid_out(float) then return nil end
      local touched = false
      float.content = float.content:walk {
        Div = function(div)
          -- A panel arrives in one of two shapes, and the note of the whole
          -- figure has to be told from both.
          --
          -- A panel written as a plain code chunk is a div carrying the
          -- apa-note itself, with the note written inside it. A panel given a
          -- label of its own is a float, and its note is not inside it but
          -- beside it: quarto puts the two together in a layout cell, and
          -- marks that cell quarto-layout-cell-subref because it holds a
          -- sub-reference. The note of the whole figure sits in a cell of its
          -- own, a plain quarto-layout-cell with no subref, which is what
          -- keeps it flush left while these are centred.
          if div.classes:includes(kPanelCell)
              or div.attributes["apa-note"] then
            touched = true
            return restyle(div)
          end
        end
      }
      if touched then return float end
    end
  }
}

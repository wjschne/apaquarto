-- Finds divs that are floats: tables, figures, and every other kind a
-- document declares under crossref.custom.
-- Adds FigureWithNote or FigureWithoutNote class to the Div
local utilsapa = require("utilsapa")

function Pandoc(doc)
  -- An Illustration is a figure as far as these styles go: only a table is
  -- treated apart, and then only in .docx.
  local prefixes = utilsapa.float_prefixes(doc.meta)
  local isfigure = false
  local istable = false
  local hasnote = false
  for i = 1, #doc.blocks, 1 do
    isfigure = false
    istable = false
    hasnote = false
    if doc.blocks[i].identifier then
      if doc.blocks[i].identifier:find("^tbl%-") then
        istable = true
      elseif utilsapa.is_float(doc.blocks[i].identifier, prefixes) then
        isfigure = true
      end
    end
    if doc.blocks[i].attributes and doc.blocks[i].attributes["apa-note"] then
      hasnote = true
    end
    if doc.blocks[i].t == "Div" then
      doc.blocks[i].content:walk {
        Div = function(div)
          if div.identifier then
            if div.identifier:find("^tbl%-") then
              istable = true
            elseif utilsapa.is_float(div.identifier, prefixes) then
              isfigure = true
            end
          end
          -- An {{< embed other.qmd#fig-x >}} wraps the cell in a div of its
          -- own, which puts the note one level deeper than it is for a figure
          -- written in the document. The figure is already looked for at any
          -- depth, so the note is looked for at any depth as well. Without
          -- this an embedded figure that has a note is styled as one that has
          -- none, losing the keepNext that holds the note on the page with
          -- its figure, and word is free to break between the two.
          if div.attributes["apa-note"] then
            hasnote = true
          end
        end
      }
    end
    if isfigure or istable then
      if istable and FORMAT == "docx" then
        doc.blocks[i].content = doc.blocks[i].content:walk {
          Table = function(tb)
            if tb.classes:includes("do-not-create-environment") then

            else
              tb.classes:insert(1, "do-not-create-environment")
              return tb
            end
          end
        }
      end


      if hasnote then
        doc.blocks[i].classes:insert("FigureWithNote")
        doc.blocks[i].attributes["custom-style"] = "FigureWithNote"
      else
        doc.blocks[i].classes:insert("FigureWithoutNote")
        doc.blocks[i].attributes["custom-style"] = "FigureWithoutNote"
      end
    end
  end
  return doc
end

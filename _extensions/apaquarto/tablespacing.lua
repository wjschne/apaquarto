-- A table's own line spacing, from table-spacing written on the table:
--
--     #| table-spacing: single              (a code chunk)
--     : Caption {#tbl-x table-spacing="onehalf"}   (a markdown table)
--
-- The chunk option lands on the chunk's cell, and the attribute on the
-- table's float, so each is carried down onto the tables pandoc writes
-- inside it, checked and in one spelling: single, onehalf or double. Each
-- format reads it off the table from there (utilsapa.table_own_spacing):
-- floatlatex.lua and formatlatex.lua for the .pdf, formattypst.lua for
-- typst, docxreferencedoc.lua for .docx and htmltablespacing.lua for .html.
-- A table a package writes in a format of its own has no table here and
-- keeps its own spacing, as it does under the document's table-spacing.

local utilsapa = require("utilsapa")

-- The spacing onto every table inside, leaving one that asks for its own.
local function carry(el, content)
  local value = el.attributes["table-spacing"]
  if value == nil then return nil end
  el.attributes["table-spacing"] = nil
  local spacing = utilsapa.own_table_spacing(value)
  if not spacing then return el end
  return el, content:walk({
    Table = function(tbl)
      if tbl.attr.attributes["table-spacing"] == nil then
        tbl.attr.attributes["table-spacing"] = spacing
        return tbl
      end
    end,
  })
end

return {
  {
    FloatRefTarget = function(float)
      local el, content = carry(float, float.content)
      if content then float.content = content end
      return el
    end,
    Div = function(div)
      local el, content = carry(div, div.content)
      if content then div.content = content end
      return el
    end,
    Table = function(tbl)
      local value = tbl.attr.attributes["table-spacing"]
      if value == nil then return nil end
      tbl.attr.attributes["table-spacing"] = utilsapa.own_table_spacing(value)
      return tbl
    end,
  },
}

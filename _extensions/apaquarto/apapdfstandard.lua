-- Warns when a pdf standard asks for a tagged pdf and the document contains a
-- table made by flextable.
--
-- Latex's tagging code cannot tag the longtable full of \multicolumn cells
-- that flextable writes. The run stops with "Undefined control sequence
-- <argument> \ERRORtbl", which gives no hint of the cause, so the cause is
-- named here while the document is still being made.

--- This filter only runs on latex format
if FORMAT ~= "latex" then
  return
end

--- Quarto sets the tagging field of its pdfstandard variable only for the
--- standards that need a tagged pdf, so its presence is the thing to test
local function wants_tagging()
  local variables = PANDOC_WRITER_OPTIONS and PANDOC_WRITER_OPTIONS.variables
  local standard = variables and variables["pdfstandard"]
  return standard ~= nil and standard.tagging ~= nil
end

--- flextable defines \ascline for every table it writes
local function is_flextable(raw)
  return raw.format == "latex" and raw.text:find("\\ascline", 1, true) ~= nil
end

function Pandoc(doc)
  if not wants_tagging() then
    return nil
  end

  local found = false
  doc:walk {
    RawBlock = function(raw)
      found = found or is_flextable(raw)
    end,
    RawInline = function(raw)
      found = found or is_flextable(raw)
    end
  }

  if found then
    quarto.log.warning(
      "This document asks for a pdf standard that needs a tagged pdf, but it " ..
      "has a table made by flextable, which latex cannot tag. The render is " ..
      "about to stop with an error about an undefined \\ERRORtbl. Make the " ..
      "table with markdown or knitr::kable instead, or take out the " ..
      "pdf-standard option.")
  end

  return nil
end

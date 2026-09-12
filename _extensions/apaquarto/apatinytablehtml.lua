-- Places a tinytable table sideways on the page in html.
--
-- tinytable centres its html tables by giving them automatic margins on both
-- sides. Apa style wants a table flush with the left margin, which is where
-- it already sits in the other formats, so left is the default here too, and
-- tbl-align moves it.
--
-- This runs while the table is still part of its float, because that is the
-- last point at which the float still carries tbl-align; quarto drops the
-- attribute when it writes the float out.

--- This filter only runs on html format
if FORMAT ~= "html" then
  return
end

local margins = {
  left = "margin-left: 0; margin-right: auto",
  center = "margin-left: auto; margin-right: auto",
  right = "margin-left: auto; margin-right: 0"
}

--- Replace the side margins in the table's own style attribute
local function set_margins(text, margin)
  return (text:gsub('(<table class="tinytable[^>]-style=")([^"]*)(")',
    function(before, style, after)
      style = style:gsub("margin%-left:%s*[^;]*;?%s*", "")
      style = style:gsub("margin%-right:%s*[^;]*;?%s*", "")
      if style ~= "" and not style:match(";%s*$") then
        style = style .. "; "
      end
      return before .. style .. margin .. ";" .. after
    end))
end

function FloatRefTarget(float)
  if float.type ~= "Table" then
    return nil
  end

  local margin = margins[float.attributes["tbl-align"]] or margins.left
  local found = false
  local content = float.content:walk {
    RawBlock = function(raw)
      if raw.format == "html" and raw.text:find('class="tinytable', 1, true) then
        found = true
        return pandoc.RawBlock(raw.format, set_margins(raw.text, margin))
      end
    end
  }

  if not found then
    return nil
  end
  float.content = content
  return float
end

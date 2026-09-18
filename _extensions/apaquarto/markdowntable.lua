if FORMAT == "latex" then
  return
end

-- This filter finds and assigns the table identifier in plain
-- markdown tables so that the crossrefprefix.lua filter can find it.

-- The attribute text with the inside of every quoted value blanked out.
--
-- A class is looked for below as a dot followed by a run of word characters,
-- and an identifier as a hash followed by one. Run over the whole attribute
-- text those patterns read the values too: a note ending in a full stop,
-- apa-note="A note.", left the closing quotation mark itself as the table's
-- first class, which is not valid utf-8 on its own and came out of the html
-- writer as a replacement character; a note mentioning a version number would
-- have made a class of the digits after the dot. The values are still read
-- from the unmasked text afterwards, so nothing is lost by hiding them here.
local function mask_values(text)
  local quote_pairs = { { '"', '"' }, { "'", "'" },
                        { "\u{201C}", "\u{201D}" },
                        { "\u{2018}", "\u{2019}" } }
  for _, quotes in ipairs(quote_pairs) do
    local open, close = quotes[1], quotes[2]
    text = text:gsub("(=%s*" .. open .. ")(.-)" .. close, function(head, value)
      return head .. string.rep(" ", #value) .. close
    end)
  end
  return text
end

local function add_caption_attributes(tb)
  if tb.caption and tb.caption.long then
    local caption = pandoc.utils.stringify(tb.caption.long)
    local attr_text = caption:match("%{([^{}]-)%}%s*$")

    if not attr_text then
      return
    end

    local outside_values = mask_values(attr_text)

    local identifier = outside_values:match("#([%w%-%_%.:]+)")
    if identifier then
      tb.identifier = identifier
    end

    for class in outside_values:gmatch("%.([%w%-%_%.:]+)") do
      if not tb.classes:includes(class) then
        tb.classes:insert(class)
      end
    end

    for key, quote, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*([\"'])(.-)%2") do
      tb.attributes[key] = value
    end

    for key, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*“(.-)”") do
      tb.attributes[key] = value
    end

    for key, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*‘(.-)’") do
      tb.attributes[key] = value
    end

    for key, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*([^%s]+)") do
      if not tb.attributes[key] then
        tb.attributes[key] = value:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
      end
    end
  end
end

Table = function(tb)
  add_caption_attributes(tb)

  if tb.caption.long then
    tb.caption.long:walk {
      Str = function(s)
        if not tb.identifier and s.text:find("%{%#tbl%-%w+") then
          tb.identifier = s.text:match("tbl%-%w+")
        end
      end
    }
    return tb
  end
end

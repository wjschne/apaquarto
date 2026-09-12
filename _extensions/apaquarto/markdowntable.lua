if FORMAT == "latex" then
  return
end

-- This filter finds and assigns the table identifier in plain
-- markdown tables so that the crossrefprefix.lua filter can find it.

local function add_caption_attributes(tb)
  if tb.caption and tb.caption.long then
    local caption = pandoc.utils.stringify(tb.caption.long)
    local attr_text = caption:match("%{([^{}]-)%}%s*$")

    if not attr_text then
      return
    end

    local identifier = attr_text:match("#([%w%-%_%.:]+)")
    if identifier then
      tb.identifier = identifier
    end

    for class in attr_text:gmatch("%.([%w%-%_%.:]+)") do
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

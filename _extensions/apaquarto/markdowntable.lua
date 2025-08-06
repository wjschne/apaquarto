if FORMAT == "latex" then
  return
end

-- This filter finds and assigns the table identifier in plain
-- markdown tables so that the crossrefprefix.lua filter can find it.

Table = function(tb)
  if tb.caption.long then
    tb.caption.long:walk {
      Str = function(s)
        if s.text:find("%{%#tbl%-%w+") then
          tb.identifier = s.text:match("tbl%-%w+")
        end
      end
    }
    return tb
  end
end

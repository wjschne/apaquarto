-- The whole of a cross reference is the link, not just its number.
--
-- Quarto writes a reference as the word, a non-breaking space and a ref:
-- "Figure~\ref{fig-one}", which is what plain quarto writes too. hyperref
-- makes the number a link and leaves the word beside it as plain text, so
-- "Figure" is not clickable and does not take the link colour. Both halves
-- name the same float, and a reader reaching for one of them reaches for
-- the phrase.
--
-- The three become one \hyperref, with \ref* inside it: a plain \ref
-- there would be a link inside a link, which hyperref warns about.

if FORMAT ~= "latex" then
  return
end

local function is_nbsp(inline)
  return inline ~= nil and inline.t == "Str" and inline.text == "\u{00a0}"
end

local function ref_target(inline)
  if inline == nil or inline.t ~= "RawInline" then return nil end
  if inline.format ~= "latex" and inline.format ~= "tex" then return nil end
  return inline.text:match("^\\ref{(.-)}$")
end

-- The word is one quarto chose -- Figure, Table, Appendix -- so only the
-- characters latex reads as markup need anything done to them.
local function escape(text)
  return (text:gsub("([#%%&_])", "\\%%1"))
end

function Inlines(inlines)
  local out = pandoc.Inlines({})
  local i = 1
  while i <= #inlines do
    local word, space, ref = inlines[i], inlines[i + 1], inlines[i + 2]
    local target = ref_target(ref)
    if target ~= nil and word.t == "Str" and is_nbsp(space) then
      out:insert(pandoc.RawInline("latex",
        "\\hyperref[" .. target .. "]{" .. escape(word.text)
        .. "~\\ref*{" .. target .. "}}"))
      i = i + 3
    else
      out:insert(word)
      i = i + 1
    end
  end
  return out
end

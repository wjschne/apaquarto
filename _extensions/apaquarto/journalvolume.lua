--- Composes the journal's issue line for latex.
---
--- apa7 prints the line through \volume{}, and title.tex reads it from the
--- top level of the document. The masthead fields the typst journal mode
--- takes -- year, volume, issue, pages, whether they are written under
--- journal or at the top level -- are assembled into that one line here, so
--- that the .pdf carries the same "2026, Vol. 118, No. 6, 869-888" the typst
--- masthead does.
---
--- A volume given on its own is returned exactly as it was written, so a
--- document that carries the whole line there keeps setting it that way. A
--- volume written only under journal reaches \volume{} this way too, which it
--- never did before: title.tex has always read the top level for it.
---
--- The apa7 class has nowhere to put a logo, an issn or a doi, so those are
--- left to the typst masthead.

--- This filter only runs on latex format
if FORMAT ~= "latex" then
  return
end

local utilsapa = require("utilsapa")

function Meta(m)
  local line = utilsapa.journal_issue_line(m)
  if line then
    m.volume = line
  end
  return m
end

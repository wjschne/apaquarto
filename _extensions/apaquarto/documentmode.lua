-- Accepts spelled-out aliases for documentmode and rewrites them to the three
-- letter codes everything downstream expects: the apa7 class option in
-- doc-class.tex, the show rule in typst-show.typ, and the filters that branch
-- on "jou". This runs first, before any of them read the field, so the alias
-- is resolved in one place rather than in each of them.
local aliases = {
  journal    = "jou",
  manuscript = "man",
  document   = "doc",
  student    = "stu",
}

function Meta(m)
  if m.documentmode then
    local alias = aliases[pandoc.utils.stringify(m.documentmode)]
    if alias then
      m.documentmode = alias
    end
  end
  return m
end

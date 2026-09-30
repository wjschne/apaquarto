-- Accepts spelled-out aliases for documentmode and rewrites them to the codes
-- everything downstream expects: the show rule in typst-show.typ, and the
-- filters that branch on "jou", "stu", "thesis" and the rest. This runs
-- first, before any of them read the field, so the alias is resolved in one
-- place rather than in each of them.
--
-- It also settles what a mode implies. thesis mode is the one that implies
-- anything so far: a dissertation has a front matter of its own, built by
-- thesisfrontmatter.lua, so the APA title page is turned off and the title is
-- not repeated at the head of the body. Set here rather than there because
-- frontmatter.lua reads both fields long before that filter runs.
local aliases = {
  journal      = "jou",
  manuscript   = "man",
  document     = "doc",
  student      = "stu",
  dissertation = "thesis",
}

-- What a mode asks for unless the document says otherwise.
local implied = {
  thesis = {
    ["suppress-title-page"] = true,
    ["suppress-title-introduction"] = true,
  },
}

function Meta(m)
  -- A document that names no mode is a manuscript. Said here, first, so that
  -- every filter and template after this one finds a mode, and typst-show.typ,
  -- which calls the mode by name, finds one it can call.
  if not m.documentmode then
    m.documentmode = "man"
  end
  if m.documentmode then
    local mode = pandoc.utils.stringify(m.documentmode)
    local alias = aliases[mode]
    if alias then
      mode = alias
      m.documentmode = mode
    end
    for key, value in pairs(implied[mode] or {}) do
      if m[key] == nil or pandoc.utils.stringify(m[key]) == "false" then
        m[key] = value
      end
    end
  end
  return m
end

-- Makes a citation of a float, @fig-x, @tbl-x or one of the document's own
-- kinds such as @ill-x, into a link reading "Figure A1", with the appendix
-- letter a float in an appendix carries.
--
-- The numbers are the ones crossrefprefix.lua worked out and left in
-- meta["apa-float-labels"], which is read here and then taken out of the
-- metadata. References to appendices are apaciteappendix.lua's. Latex writes
-- its own references from the labels floatlatex.lua sets, so it is left alone.

if FORMAT == "latex" then
  return
end

local utilsapa = require("utilsapa")

local kAriaExpanded = "aria-expanded"
local kLabels = "apa-float-labels"
local refhyperlinks = true
-- The number a reader sees, by identifier
local labels = {}
-- The word for each kind of float, by the prefix of its identifier
local words = { fig = "Figure", tbl = "Table" }

local function read_meta(m)
  words.fig = utilsapa.lang(m, "crossref-fig-title", words.fig)
  words.tbl = utilsapa.lang(m, "crossref-tbl-title", words.tbl)
  if m.crossref and m.crossref.custom then
    for _, entry in ipairs(m.crossref.custom) do
      if entry.key and entry["reference-prefix"] then
        words[utilsapa.stringify(entry.key)] =
          utilsapa.stringify(entry["reference-prefix"])
      end
    end
  end

  if m["ref-hyperlink"] == false then
    refhyperlinks = false
  end

  if m[kLabels] then
    for id, label in pairs(m[kLabels]) do
      labels[id] = utilsapa.stringify(label)
    end
    m[kLabels] = nil
  end
  return m
end

local function figtblconvert(ct)
  if #ct.citations ~= 1 then return nil end
  local id = ct.citations[1].id
  local kind = id:match("^(%a+)%-")
  if not (kind and words[kind]) then return nil end

  if not labels[id] then
    quarto.log.warning("Cannot find @" .. id)
    return nil
  end

  local floatreftext = pandoc.Inlines({ pandoc.Str(words[kind]), pandoc.Str('\u{a0}'), pandoc.Str(labels[id]) })
  if refhyperlinks then
    local reflink = pandoc.Link(floatreftext, "#" .. id)
    reflink.classes = { "quarto-xref" }
    reflink.attributes[kAriaExpanded] = "false"
    return reflink
  end
  return floatreftext
end


return {
  { Meta = read_meta },
  { Cite = figtblconvert }
}

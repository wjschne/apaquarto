-- Makes a citation of an appendix, @apx-x or @sec-x, into a link reading
-- "Appendix A", or "Appendix" when there is only the one.
--
-- crossrefprefix.lua has already decided what the appendices are: each
-- appendix heading carries its letter as appendixtitle, and
-- meta["apa-appendix-count"] says how many there are. References to figures
-- and tables are apafigtblappendix.lua's.

local utilsapa = require("utilsapa")

local app = {}
local appendixcount = 0
local kAriaExpanded = "aria-expanded"
local refhyperlinks = true
-- Word for appendix
local appendixword = "Appendix"

local journalmode = false

local getappendixword = function(meta)
  appendixword = utilsapa.lang(meta, "crossref-apx-prefix", appendixword)
  appendixcount = tonumber(utilsapa.stringify(meta["apa-appendix-count"], "0")) or 0
  if meta["ref-hyperlink"] == false then
    refhyperlinks = false
  end
  journalmode = FORMAT == "latex" and utilsapa.mode(meta) == "jou"
end

local function cite_appendix(ct)
  if #ct.citations ~= 1 then return nil end
  local id = ct.citations[1].id
  if not (id:find("^sec%-") or id:find("^apx%-")) or not app[id] then
    return nil
  end

  local floatreftext
  if appendixcount == 1 then
    floatreftext = pandoc.Inlines({ pandoc.Str(appendixword) })
  else
    floatreftext = pandoc.Inlines({ pandoc.Str(appendixword), pandoc.Str('\u{a0}'), pandoc.Str(app[id]) })
  end

  if refhyperlinks then
    local reflink = pandoc.Link(floatreftext, "#" .. id)
    reflink.classes = { "quarto-xref" }
    reflink.attributes[kAriaExpanded] = "false"
    return reflink
  end
  return floatreftext
end

local function getappendix(h)
  if h.attr.attributes.appendixtitle then
    app[h.identifier] = h.attr.attributes.appendixtitle
    if journalmode then
      local p = pandoc.RawBlock("latex", "\\setlength{\\parindent}{1em}")
      return { h, p }
    end
  end
end


return {
  { Meta = getappendixword },
  { Header = getappendix },
  { Cite = cite_appendix }
}

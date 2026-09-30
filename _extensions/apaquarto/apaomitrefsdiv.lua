-- This filter adds a refdiv if there is a Reference header but no refdiv

local utilsapa = require("utilsapa")

local hasrefdiv = false
local referenceword = "References"
local appendixcount = 0
local n_citation = 0
local hasrefheader = false
-- Identifier prefixes that make a citation a cross reference rather than a
-- work cited: every kind of float, sections, appendices and equations.
local xrefprefixes = { sec = true, apx = true, eq = true }

-- The class crossrefprefix.lua gives the heading it writes over each appendix
local kAppendixClass = "apa-appendix"

return {
  {
    Meta = function(meta)
      if meta.nocite then
        n_citation = 1
      end
      referenceword = utilsapa.lang(meta, "section-title-references", referenceword)
      appendixcount = tonumber(utilsapa.stringify(meta["apa-appendix-count"], "0")) or 0
      for kind in pairs(utilsapa.float_prefixes(meta)) do
        xrefprefixes[kind] = true
      end
    end
  },
  {
    Div = function(div)
      if div.identifier and div.identifier == "refs" then
        -- There is a refdiv
        hasrefdiv = true
      end
    end
  },
  {
    Header = function(h)
      if h.content and ((pandoc.utils.stringify(h.content) == referenceword) or (pandoc.utils.stringify(h.content) == "References")) then
        hasrefheader = true
        if hasrefdiv then
          -- Do nothing because there is a refdiv
        else
          -- Add refdiv after References header
          local refdiv = pandoc.Div({})
          refdiv.identifier = "refs"
          refdiv.classes:insert("references")
          return { h, refdiv }
        end
      end
    end
  },
  {
    -- A cross reference is written as a citation, but it cites no work, and a
    -- paper that has only those has no references to list.
    Cite = function(c)
      for _, citation in ipairs(c.citations) do
        local prefix = citation.id:match("^(%a+)%-")
        if not (prefix and xrefprefixes[prefix]) then
          n_citation = n_citation + 1
          return nil
        end
      end
    end
  },
  {
    Div = function(div)
      if not hasrefheader and div.identifier and div.identifier == "refs" then
        return {pandoc.Header(1, referenceword), div}
      end
    end
  },
  {
    Pandoc = function(doc)
      if n_citation > 0 then
        if not hasrefheader and not hasrefdiv then
          local refdiv = pandoc.Div({})
          refdiv.identifier = "refs"
          refdiv.classes:insert("references")
          local refheader = pandoc.Header(1, referenceword)
          if appendixcount == 0 then
            doc.blocks[#doc.blocks + 1] = refheader
            doc.blocks[#doc.blocks + 1] = refdiv
          else 
            for i = 1, #doc.blocks, 1 do

              if doc.blocks[i].tag == "Header" and doc.blocks[i].classes:includes(kAppendixClass) then
                table.insert(doc.blocks, i, refdiv)
                table.insert(doc.blocks, i, refheader)
                break
              end
            end
          end
          return doc
        end
      end
    end
  }
}

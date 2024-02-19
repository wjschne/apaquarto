-- This filter does 2 things.
-- 1. It runs citeproc. Citeproc is needed so that the apaandcite.lua filter can do its job.
-- 2. It removes the References Header if there are no citations and sets the zerocitations slot in the metadata

-- Counter for citation
local n_citations = 0


return {
  --{FloatRefTarget = function(float)},
  {Cite = function(ct) 
    n_citations = n_citations + 1 
    end},
  {
    Meta = function(meta) 
      if n_citations > 0 then
        zerocitations = false
      else
        zerocitations = true
      end
      meta.zerocitations = zerocitations
      return meta 
    end
    
  },
  {
    Div = function(div)
      if div.identifier and div.identifier == "refs" and n_citations > 0 then
        div = nil
      end
    end
  },
  {
    Header = function(h)
      if n_citations == 0 and pandoc.utils.stringify(h.content) == "References" then
        return {}
      end
    end
  },
  {
    Pandoc = function(doc) 
      doc.meta.references = pandoc.utils.references(doc)
      doc.meta.bibliography = nil
      return pandoc.utils.citeproc(doc) 
      end
    
  }
}




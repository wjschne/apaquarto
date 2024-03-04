-- This filter does 2 things.
-- 1. It runs citeproc. Citeproc is needed so that the apaandcite.lua filter can do its job.
-- 2. It removes the References Header if there are no citations and sets the zerocitations slot in the metadata

-- Counter for citation
local n_citations = 0
local referenceword = "References"
local maskedauthor = "Masked Citation"
local maskedtitle = "Masked Title"
local maskeddate = "n.d."

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
      if meta.language then
        if meta.language["section-title-references"] then
          referenceword = pandoc.utils.stringify(meta.language["section-title-references"])
        end
        if meta.language["citation-masked-author"] then
          maskedauthor = pandoc.utils.stringify(meta.language["citation-masked-author"])
        end
        if meta.language["citation-masked-title"] then
          maskedtitle = pandoc.utils.stringify(meta.language["citation-masked-title"])
        end
        if meta.language["citation-masked-source"] then
          maskedsource = pandoc.utils.stringify(meta.language["citation-masked-source"])
        end
        if meta.language["citation-masked-date"] then
          maskeddate = pandoc.utils.stringify(meta.language["citation-masked-date"])
        end
     end

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
      if n_citations == 0 and pandoc.utils.stringify(h.content) == referenceword then
        return {}
      end
    end
  },
  {
    Pandoc = function(doc) 
      doc.meta.references = pandoc.utils.references(doc)
      maskedref = {
        author = pandoc.List:new({ {literal = maskedauthor}}),
        id = "maskedreference",
        issued = {literal = maskeddate},
        title = pandoc.Inlines(maskedtitle),
        type = "book"
      }
      doc.meta.references:insert(maskedref)
      doc.meta.bibliography = nil
      return pandoc.utils.citeproc(doc) 
    end
    
  }
}




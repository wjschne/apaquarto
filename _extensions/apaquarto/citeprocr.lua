-- This filter does 3 things.
-- 1. It runs citeproc. Citeproc is needed so that the apaandcite.lua filter can do its job.
-- 2. It removes the References Header if there are no citations and sets the zerocitations slot in the metadata
-- 3. Makes citations in nocite have asterisks unless meta-analysis is false

-- Counter for citation
local n_citations = 0
local referenceword = "References"
local maskedauthor = "Masked Citation"
local maskedtitle = "Masked Title"
local maskeddate = "n.d."
local metaanalysis = true
local metareferencesentence = "References marked with an asterisk indicate studies included in the meta-analysis."
return {
  --{FloatRefTarget = function(float)},
  {
    Cite = function(ct) 
    n_citations = n_citations + 1 
    end
    
  },
  {
    Meta = function(meta) 
      if n_citations > 0 then
        zerocitations = false
      else
        zerocitations = true
      end
      meta.zerocitations = zerocitations
      if meta["meta-analysis"] == false then
        metaanalysis = false
      end
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
        if meta.language["references-meta-analysis"] then
          metareferencesentence = pandoc.utils.stringify(meta.language["references-meta-analysis"])
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
      if metaanalysis and pandoc.utils.stringify(h.content) == referenceword then
        return {h, pandoc.Para(metareferencesentence)}
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
      
      --look up nocite references
      local ct_meta = {}
      if metaanalysis then
        if doc.meta.nocite then
          doc.meta.nocite:walk {
            Cite = function(ct)
              ct_meta[ct.citations[1].id] = true
            end
          }
          
          -- If reference is in nocite, then place an asterisk in front. 
          for i,j in pairs(doc.meta.references) do
            if ct_meta[j.id] then
              if j.author[1].literal then
                j.author[1].literal = "*" .. j.author[1].literal
              else
                if j.author[1].family then
                  j.author[1].family = "*" .. j.author[1].family
                end
              end
            end
          end
        end
      end
      return pandoc.utils.citeproc(doc) 
    end
    
  }
}




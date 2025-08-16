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
  {
    Cite = function(ct)
      -- count citations
      n_citations = n_citations + 1
      -- replaces possive and ampersand suffixes
      local replace_possessive = false
      local remove_ampersand_suffix = false

      
      if ct.citations and ct.citations[1].mode == "AuthorInText" then
    if ct.citations[1].suffix and #ct.citations[1].suffix > 0 then
      
      for i = #ct.citations[1].suffix, 1, -1 do
        if ct.citations[1].suffix[i].tag == "Str" then
          if string.find(ct.citations[1].suffix[i].text, "’s") then
            replace_possessive = true
            if ct.citations[1].suffix[i + 1] and ct.citations[1].suffix[i + 1].tag == "Space" then
              table.remove(ct.citations[1].suffix, i + 1)
            end
            table.remove(ct.citations[1].suffix, i)
          else
            if ct.citations[1].suffix[i] and string.find(ct.citations[1].suffix[i].text, "%&") then
              remove_ampersand_suffix = true
            if ct.citations[1].suffix[i + 1] and ct.citations[1].suffix[i + 1].tag == "Space" then
              table.remove(ct.citations[1].suffix, i + 1)
            end
              table.remove(ct.citations[1].suffix, i)
            end
          end
        end
      end
      if replace_possessive and remove_ampersand_suffix then
        ct.citations[1].hash = 3
      else
        if replace_possessive then
          ct.citations[1].hash = 1
        end
        if remove_ampersand_suffix then
          ct.citations[1].hash = 2
        end
      end

      return ct
    end
      end

    end
  },
  {
    Meta = function(meta)
      -- count references in nocite
      if meta.nocite and #meta.nocite > 0 then
        meta.nocite:walk {
          Cite = function(ct)
            n_citations = n_citations + 1
          end
        }
      end

      -- Need to tell latex if there are no citations
      if n_citations == 0 then
        meta.zerocitations = true
      else
        meta.zerocitations = false
      end
      -- Nocite citations are marked as part of meta-analysis unless
      -- meta-analysis field set to false
      if meta["meta-analysis"] == false then
        metaanalysis = false
      else
        -- If there are nocite citations (and meta-analysis field is
        -- not false), then this is a meta-analysis
        if meta.nocite then
          metaanalysis = true
        else
          metaanalysis = false
        end
      end

      if meta.language then
        -- Is there another word for reference section?
        if meta.language["section-title-references"] then
          referenceword = pandoc.utils.stringify(meta.language["section-title-references"])
        end
        -- Is there another phrase for masked references?
        if meta.language["citation-masked-author"] then
          maskedauthor = pandoc.utils.stringify(meta.language["citation-masked-author"])
        end
        -- Is there another phrase for masked titles?
        if meta.language["citation-masked-title"] then
          maskedtitle = pandoc.utils.stringify(meta.language["citation-masked-title"])
        end
        -- Is there another phrase for masked sources?
        if meta.language["citation-masked-source"] then
          maskedsource = pandoc.utils.stringify(meta.language["citation-masked-source"])
        end
        -- Is there another phrase for masked dates?
        if meta.language["citation-masked-date"] then
          maskeddate = pandoc.utils.stringify(meta.language["citation-masked-date"])
        end
        -- Is there another phrase for meta-analysis reference explanation?
        if meta.language["references-meta-analysis"] then
          metareferencesentence = pandoc.utils.stringify(meta.language["references-meta-analysis"])
        end
      end

      return meta
    end

  },
  {
    Div = function(div)
      if div.identifier and div.identifier == "refs" then
        -- remove reference div if there are no citations
        if n_citations == 0 then
          return {}
        end
      end
    end
  },
  {
    Header = function(h)
      if pandoc.utils.stringify(h.content) == referenceword then
        if n_citations == 0 then
          return {}
        else
          if metaanalysis then
            return { h, pandoc.Para(metareferencesentence) }
          end
        end
      end
    end
  },
  {
    Pandoc = function(doc)
      doc.meta.references = pandoc.utils.references(doc)
      maskedref = {
        author = pandoc.List:new({ { literal = maskedauthor } }),
        id = "maskedreference",
        issued = { literal = maskeddate },
        title = pandoc.Inlines(maskedtitle),
        type = "book"
      }
      doc.meta.references:insert(maskedref)
      doc.meta.bibliography = nil

      --look up nocite references
      local ct_meta = {}
      if metaanalysis then
        if doc.meta.nocite and #doc.meta.nocite > 0 then
          doc.meta.nocite:walk {
            Cite = function(ct)
              ct_meta[ct.citations[1].id] = true
            end
          }

          -- If reference is in nocite, then place an asterisk in front.
          for i, j in pairs(doc.meta.references) do
            if ct_meta[j.id] and j.author and j.author[1] then
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
      local d = pandoc.utils.citeproc(doc)
      if FORMAT == "typst" then
        d.meta.citeproc = true
      end
      return d
    end

  }
}

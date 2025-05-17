-- This filter allows English language defaults to be changed 
-- to any other language (or any other English words)

-- from quarto-cli/src/resources/pandoc/datadir/init.lua
-- global quarto params
local paramsJson = quarto.base64.decode(os.getenv("QUARTO_FILTER_PARAMS"))
local quartoParams = quarto.json.decode(paramsJson)

local function param(name, default)
  -- get name from quartoParams, if possible
  local value = quartoParams[name]
  if value == nil then
    -- get name from quartoParams.language, if possible
    if quartoParams.language then
      value = quartoParams.language[name]
    end
    -- If still nil, then assign default
    if value == nil then
      value = default
    end
  end
  return value
end

-- Fields and their defaults
local fields = {
  {field = "crossref-fig-title", default = "Figure"},
  {field = "crossref-tbl-title", default = "Table"},
  {field = "crossref-apx-title", default = "Appendix"},
  {field = "citation-last-author-separator", default = "and"},
  {field = "citation-masked-author", default = "Masked Citation"},
  {field = "citation-masked-title", default = "Masked Title"},
  {field = "citation-masked-date", default = "n.d."},
  {field = "email", default = "Email"},
  {field = "figure-table-note", default = "Note"},  
  {field = "section-title-abstract", default = "Abstract"},
  {field = "section-title-appendixes", default = "Appendices"},
  {field = "section-title-references", default = "References"},
  {field = "title-block-author-note", default = "Author Note"},
  {field = "title-block-correspondence-note", default = "Correspondence concerning this article should be addressed to"},
  {field = "title-block-keywords", default = "Keywords"},
  {field = "title-block-role-introduction", default = "Author roles were classified using the Contributor Role Taxonomy (CRediT; https://credit.niso.org/) as follows:"},
  {field = "title-impact-statement", "Impact Statement"},
  {field = "title-word-count", default = "Word Count"},
  {field = "references-meta-analysis", default = "References marked with an asterisk indicate studies included in the meta-analysis."},
}

Meta = function(m)
  -- Make empty language table if it does not exist
  if not m.language then
    m.language = {}
  end
  
  
  
  -- Find word for "note"
  if not m.language["figure-table-note"] then
    if param("callout-note-title") then
      m.language["figure-table-note"] = param("callout-note-title")
    end
  end

   -- Find word for "Appendix"
   if not m.language["crossref-apx-prefix"] then
    if param("crossref-apx-prefix") then
      m.language["crossref-apx-prefix"] = param("crossref-apx-prefix")
    end
  end 

  for i,x in ipairs(fields) do
    -- In case someone assigned variable to top-level meta instead of to language
    if m[x.field] then
      m.language[x.field] = m[x.field]
    end
    -- If field not assisned, assign default
    if not m.language[x.field] then
      m.language[x.field] = param(x.field, x.default)
      if m.crossref then
        if m.crossref[x.field:gsub("^crossref%-", "")] then
          m.language[x.field] = pandoc.utils.stringify(m.crossref[x.field:gsub("^crossref%-", "")])
        end
      end
    end
  end

  return m
end
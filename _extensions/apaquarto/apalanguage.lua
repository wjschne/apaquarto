-- This filter allows English language defaults to be changed
-- to any other language (or any other English words)
--
-- This is the one list of apaquarto's language defaults. Each word comes from
-- the document's own language field (or a top-level field of the same name),
-- then the document's crossref field, then Quarto's translation for lang, and
-- only then the English default below. _extension.yml deliberately sets none
-- of them, so that no default of apaquarto's can stand in for a translation.

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
  { field = "crossref-fig-title",              default = "Figure" },
  { field = "crossref-tbl-title",              default = "Table" },
  { field = "citation-last-author-separator",  default = "and" },
  { field = "citation-masked-author",          default = "Masked Author" },
  { field = "citation-masked-title",           default = "Masked Title" },
  { field = "citation-masked-date",            default = "n.d." },
  { field = "email",                           default = "Email" },
  { field = "figure-table-note",               default = "Note" },
  { field = "figure-panel",                    default = "Panel" },
  { field = "journal-volume",                  default = "Vol." },
  { field = "journal-issue",                   default = "No." },
  { field = "section-title-abstract",          default = "Abstract" },
  -- Quarto's own key, so that Quarto's translation for lang reaches it.
  { field = "section-title-appendices",        default = "Appendices" },
  { field = "section-title-introduction",      default = "Introduction" },
  { field = "section-title-references",        default = "References" },
  { field = "title-block-author-note",         default = "Author Note" },
  { field = "title-block-correspondence-note", default = "Correspondence concerning this article should be addressed to" },
  { field = "title-block-keywords",            default = "Keywords" },
  { field = "title-block-role-introduction",   default = "Author roles were classified using the Contributor Role Taxonomy (CRediT; https://credit.niso.org/) as follows:" },
  { field = "title-impact-statement",          default = "Impact Statement" },
  { field = "title-supplemental-materials",    default = "Supplemental materials" },
  { field = "title-word-count",                default = "Word Count" },
  { field = "references-meta-analysis",        default = "References marked with an asterisk indicate studies included in the meta-analysis." },
  -- The headings of the lists list-of-contents, list-of-figures and
  -- list-of-tables ask for. Quarto translates all three.
  { field = "crossref-lof-title",              default = "List of Figures" },
  { field = "crossref-lot-title",              default = "List of Tables" },
  { field = "toc-title-document",              default = "Table of Contents" },
}

Meta = function(m)
  -- Set numbersections
  m.numbersections = param("number-sections", false)

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

  -- apaquarto once spelled Quarto's section-title-appendices as
  -- section-title-appendixes, so a document may still say it that way.
  local appendixes = m.language["section-title-appendixes"]
    or m["section-title-appendixes"]
  if appendixes and not m.language["section-title-appendices"]
      and not m["section-title-appendices"] then
    m.language["section-title-appendices"] = appendixes
  end

  -- Find word for "Appendix"
  if not m.language["crossref-apx-prefix"] then
    if param("crossref-apx-prefix") then
      m.language["crossref-apx-prefix"] = param("crossref-apx-prefix")
    end
  end

  -- Quarto's English for the contents is "Table of contents". APA sets a
  -- heading in title case, which is what apaquarto has always printed, so the
  -- English is put in title case unless the document asked for it as it is.
  local toc_asked = m.language["toc-title-document"] ~= nil
    or m["toc-title-document"] ~= nil

  for i, x in ipairs(fields) do
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

  if not toc_asked and m.language["toc-title-document"] ~= nil
      and pandoc.utils.stringify(m.language["toc-title-document"]) == "Table of contents" then
    m.language["toc-title-document"] = "Table of Contents"
  end

  return m
end

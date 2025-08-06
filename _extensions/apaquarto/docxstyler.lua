--- This filter converts the class in customclasses

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

--- Is the class included in the customclasses table?
--- https://stackoverflow.com/a/2282542/4513316
function utils_Set(list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

-- Classes that are converted. Add additional classes as needed.
customclasses = {
  "Author",
  "AuthorNote",
  "Abstract",
  "AbstractFirstParagraph",
  "FigureTitle",
  "FigureNote",
  "FigureWithNote",
  "FigureWithoutNote",
  "Caption",
  "Compact",
  "NoIndent",
  "NextBlockText",
  "AfterWithoutNote",
  "H4",
  "H5"
}

-- Consult some value
_set = utils_Set(customclasses)


-- https://jmablog.com/post/pandoc-filters/
local function customstyler(elem)
  if _set[elem.classes[1]] then
    elem.attributes['custom-style'] = elem.classes[1]
    return elem
  end
end

return {
  { Span = customstyler },
  { Div = customstyler }
}

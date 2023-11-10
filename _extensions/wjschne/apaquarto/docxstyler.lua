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
  "FigureTitle", 
  "FigureNote", 
  "FigureWithNote", 
  "FigureWithoutNote", 
  "Caption",
  "Compact",
  "NoIndent"
}

-- Consult some value
_set = utils_Set(customclasses)


-- https://jmablog.com/post/pandoc-filters/
function Div (elem)
    if _set[elem.classes[1]] then
      elem.attributes['custom-style'] = elem.classes[1]
      return elem
    else
      return elem
    end
end

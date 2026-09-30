--- This filter converts the class in customclasses

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

--- Is the class included in the customclasses table?
--- https://stackoverflow.com/a/2282542/4513316
local function utils_Set(list)
  local set = {}
  for _, l in ipairs(list) do set[l] = true end
  return set
end

-- Classes that are converted. Add additional classes as needed.
--
-- Most of these are set by filters that give the block its custom-style
-- themselves, and several are only made at post-render, after this runs. The
-- list stays whole anyway: an author may write any of them as a div of their
-- own, and writing.qmd tells them to write ::: {.NoIndent}, which gets its
-- style in .docx only from here.
local customclasses = {
  "Author",
  "AuthorNote",
  "Abstract",
  "AbstractFirstParagraph",
  "FigureTitle",
  "FigureNote",
  "SubPanelNote",
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
local _set = utils_Set(customclasses)


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

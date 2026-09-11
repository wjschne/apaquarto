-- Puts the papersize option in the form the document class wants.
--
-- Pandoc's own latex template writes the class option as $papersize$paper, so
-- a4 becomes a4paper. Papersize is written several ways though, and the names
-- quarto uses for typst are among them, so they are all reduced to the stem
-- the class option is built from. doc-class.tex writes it out.
--
-- Only latex is touched. Typst takes its own paper names, and the docx format
-- reads papersize as written, so neither wants this.

--- This filter only runs on latex format
if FORMAT ~= "latex" then
  return
end

--- The paper sizes the standard classes, and so apa7, accept
local stems = {
  a4 = true,
  a5 = true,
  b5 = true,
  executive = true,
  legal = true,
  letter = true
}

function Meta(meta)
  if not meta.papersize then
    return nil
  end

  --- letterpaper, us-letter and USLetter all mean letter
  local name = pandoc.utils.stringify(meta.papersize):lower():gsub("[^%a%d]", "")
  name = name:gsub("^us", "")
  name = name:gsub("paper$", "")

  if not stems[name] then
    quarto.log.warning("The pdf format has no paper size named " ..
      pandoc.utils.stringify(meta.papersize) ..
      ", so the document class's own size was kept. Set the size with the " ..
      "geometry option instead.")
    meta.papersize = nil
    return meta
  end

  meta.papersize = pandoc.MetaString(name)
  return meta
end

if FORMAT ~= "docx" then
  return
end

function Header (elem)
  if elem.level >= 3 then
    elem.content[#elem.content + 1] = pandoc.Str(".")
  end

  return elem
end

function strip_meta(meta)
  meta.title = nil
  meta.subtitle = nil
  meta.author = nil
  meta.date = nil
  meta.abstract = nil
  return meta
end

return {{Meta = strip_meta}}

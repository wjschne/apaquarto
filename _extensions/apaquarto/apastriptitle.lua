if FORMAT ~= "docx" then
  return
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

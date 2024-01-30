if FORMAT ~= "docx" then
  return
end

function strip_meta(meta)
  meta.apatitle = meta.title
  meta.apasubtitle = meta.subtitle
  meta.apaauthor = meta.author
  meta.apadate =  meta.date
  meta.apaabstract = meta.abstract
  meta.title = nil
  meta.subtitle = nil
  meta.author = nil
  meta.date = nil
  meta.abstract = nil
  return meta
end

return {{Meta = strip_meta}}


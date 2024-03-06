---http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
   return string.sub(str.text, -1) == ending
end

Meta = function(meta)
  
  meta.apatitle = nil
  meta.apatitledisplay = nil
  if meta.title then
    meta.apatitle = meta.title:clone()
    meta.apatitledisplay = meta.title:clone()
  end

  if meta.subtitle then
    if not ends_with(meta.apatitledisplay[#meta.apatitledisplay], ":") then
      meta.apatitledisplay:insert(pandoc.Str(":"))
    end
    meta.apatitledisplay:insert(pandoc.Space())
    meta.apatitledisplay:extend(meta.subtitle)
  end
  meta.apasubtitle = meta.subtitle
  meta.apaauthor = meta.author
  meta.apadate =  meta.date
  meta.apaabstract = meta.abstract
  if meta.documentmode then
  else
     meta.documentmode = "man"
  end
  --Prevents pandoc from fomatting .docx document the way it thinks it should.
  if FORMAT == "docx" then
      meta.title = nil
      meta.subtitle = nil
      meta.author = nil
      meta.date = nil
      meta.abstract = nil
  end
  return meta
end




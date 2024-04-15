
--- Does the string end with a specific character?
--- http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
   return string.sub(str.text, -1) == ending
end

--- Trim string
local function trim(s)
  local l = 1
  while string.sub(s,l,l) == ' ' do
    l = l+1
  end
  local r = string.len(s)
  while string.sub(s,r,r) == ' ' do
    r = r-1
  end
  return string.sub(s,l,r)
end

--- Put a space before the string
local function prependspace(s)
  if s then
    return " " .. pandoc.utils.stringify(s)
  else
    return ""
  end
end

-- Are the affiliations different or same across authors?
local are_affiliations_different = function(authors)
  -- Superscript id
  local superii = ""
  
  -- List of superii
  local hash = {}
  -- index of superii
  local res = {}
      
      --Check if affilations are the same for each author
      for i, a in ipairs(authors) do
        superii = ""
        if a.affiliations then
          for j, aff in ipairs(a.affiliations) do
            if j > 1 then
              superii = superii .. ","
            end
            superii = superii .. aff.number
          end
        end

        if (not hash[superii]) then
          res[#res+1] = superii 
          hash[superii] = true
        end

      end
  
  return #res > 1
end

local function makeauthorname(a)

  local authorname = a.literal
  -- Make author name
  if pandoc.utils.type(a.literal) == "List" then
    if a.literal[1].literal then
      authorname = a[1].literal
    else
      authorname = ""
      authorname = authorname .. prependspace(a.literal[1].given) 
      authorname = authorname .. prependspace(a.literal[1]["dropping-particle"]) 
      authorname = authorname .. prependspace(a.literal[1]["non-dropping-particle"]) 
      authorname = authorname .. prependspace(a.literal[1].family) 
      authorname = pandoc.Inlines(trim(authorname))
    end
  end
  return authorname
end

Meta = function(meta)
  
  meta.apatitle = nil
  meta.apatitledisplay = nil
  if meta.title then
    meta.apatitle = meta.title:clone()
    meta.apatitledisplay = meta.title:clone()
  end
  
  if meta["by-author"] then
    meta.affiliationsdifferent = are_affiliations_different(meta["by-author"])
    
    for i,j in ipairs(meta["by-author"]) do
      j.apaauthordisplay = makeauthorname(j.name)
    end
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




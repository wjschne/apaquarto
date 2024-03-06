Meta = function(meta)
  if meta["by-author"] then
    if #meta["by-author"] == 1 then
      meta.oneauthor = true
    else
      meta.oneauthor = false
    end
  end
  
  if meta["by-affiliation"] then
    if #meta["by-affiliation"] == 1 then
      meta.oneaffiliation = true
    else
      meta.oneaffiliation = false
    end
  end
  return(meta)
end
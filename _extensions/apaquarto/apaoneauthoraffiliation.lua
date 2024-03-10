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
  for i,j in pairs(meta["by-author"]) do
    for k,l in pairs(j.name) do
      if k == "literal" then
      end
    end
    if not j.affiliations then
      local au = pandoc.utils.stringify(j.name.literal)
      error("No affiliation listed for " .. au .. "\nAll authors must have an affiliation.\nIf authors are unaffiliated, list a city, as well as a region and/or country.\nFor example, \n\nauthor:\n  - name: " .. au .. "\n    affiliations:\n      city: Los Angeles\n      region: CA")
    end
  end
  return(meta)
end
-- Latex needs to know if there is only one author and/or one affiliation
-- Checks to make sure all authors have an affiliation (or address)
Meta = function(meta)
  -- Is the only one author?
  if meta["by-author"] then
    if #meta["by-author"] == 1 then
      meta.oneauthor = true
    else
      meta.oneauthor = false
    end
  else
    -- There are no authors
    error(
    "At least one author must be specified in your yaml metadata. \nFor example, \n\nauthor:\n  - name: Fred Jones\n    affiliations: Generic University\n    email: fred.jones@generic.edu\n    corresponding: true\n")
  end

  -- Is the only one affiliation?
  if meta["by-affiliation"] then
    if #meta["by-affiliation"] == 1 then
      meta.oneaffiliation = true
    else
      meta.oneaffiliation = false
    end
  end

  local corresponsingauthor = false
  -- Does every author have an affiliation?
  if meta["by-author"] then
    for i, j in pairs(meta["by-author"]) do
      if j.attributes then
        if j.attributes.corresponding then
          corresponsingauthor = true
        end
      end
      if not j.affiliations then
        local au = pandoc.utils.stringify(j.name.literal)
        error("No affiliation listed for " ..
        au ..
        "\nAll authors must have an affiliation. For example,\n\nauthor:\n  - name: " ..
        au ..
        "\n    affiliations: Genereric University\n\nIf authors are unaffiliated, list a city, as well as a region and/or country.\nFor example, \n\nauthor:\n  - name: " ..
        au .. "\n    affiliations:\n      city: Los Angeles\n      region: CA\n")
      end
    end
  end

  if not corresponsingauthor then
    error(
    "At least one author needs to marked as the corresponding author. For example, \n\nauthor:\n  - name: Fred Jones\n    affiliations: Generic University\n    email: fred.jones@generic.edu\n    corresponding: true\n")
  end
  return (meta)
end

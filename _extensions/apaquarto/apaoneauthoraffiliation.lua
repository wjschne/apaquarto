-- Checks that there is at least one author, that every author has an
-- affiliation (or an address), and that one of them is the corresponding
-- author.
Meta = function(meta)
  if not meta["by-author"] then
    -- There are no authors
    error(
    "At least one author must be specified in your yaml metadata. \nFor example, \n\nauthor:\n  - name: Fred Jones\n    affiliations: Generic University\n    email: fred.jones@generic.edu\n    corresponding: true\n")
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
        "\n    affiliations: Generic University\n\nIf authors are unaffiliated, list a city, as well as a region and/or country.\nFor example, \n\nauthor:\n  - name: " ..
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

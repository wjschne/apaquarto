--List of masked citations
local maskedcitations = pandoc.List()

--Retrieves citations from metadata
local function getmasked(meta)
  if meta["masked-citations"] and meta["mask"] and pandoc.utils.stringify(meta["mask"]) == "true" then
    local maskedstrings = meta["masked-citations"]
    for i, v in pairs(maskedstrings) do
      maskedcitations:insert(pandoc.utils.stringify(v))
    end
  end
end

--Finds citations to be masked and converts them to masked citations
local function maskcite(cite)
  local k = 0
  local km = 0
  local maskid = "maskedreference"

  for i, v in pairs(cite.citations) do
    if maskedcitations:includes(v.id) then
      v.id = maskid
      v.suffix = nil
      k = k + 1
    end
  end

  if k > 0 then
    for i = #cite.citations, 1, -1 do
      if cite.citations[i].id == maskid then
        km = km + 1
        if km ~= k then
          cite.citations:remove(i)
        end
      end
    end
    return cite
  end
end


return {
  { Meta = getmasked },
  { Cite = maskcite }
}

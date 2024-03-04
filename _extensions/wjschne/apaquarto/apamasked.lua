local maskedcitations = pandoc.List()

local function getmasked(meta)
  
  if meta["masked-citations"] and meta["mask"] and pandoc.utils.stringify(meta["mask"]) == "true" then
    local maskedstrings = meta["masked-citations"]
    
    
    for i, v in pairs(maskedstrings) do
      maskedcitations:insert(pandoc.utils.stringify(v))
    end
    

    --local convert2meta = false
    --for i, v in ipairs(meta.bibliography or {}) do
    --  if pandoc.utils.type(v) == "Inline" then
    --    convert2meta = true
    --  end
    --end
    --
    --if convert2meta then
    --  local orig_bib = meta.bibliography
    --  meta.bibliography = pandoc.MetaList{orig_bib}
    --end
    --
--
    --if meta.bibliography then
    --  local maskedfile = "_extensions/wjschne/apaquarto/maskedbibliography.bib"
    --    meta.bibliography:insert({pandoc.Str(maskedfile)})
    --  else
    --    meta.bibliography = {{pandoc.Str(maskedfile)}}
    --end
    --return (meta)
    
  end

end


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
  {Meta = getmasked},
  {Cite = maskcite}
}

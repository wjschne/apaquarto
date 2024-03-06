if FORMAT == "latex" then
  return
end
Pandoc = function(doc)
  if doc.meta.floatsintext and pandoc.utils.stringify(doc.meta.floatsintext) == "true" then
    return
  end
  local tbl = {}
  local fig = {}
  for i = #doc.blocks, 1, -1 do
    

      if doc.blocks[i].identifier then
        if doc.blocks[i].identifier:find("^tbl%-") then
          if FORMAT == "docx" then
             table.insert(tbl, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
          end
          table.insert(tbl, 1, doc.blocks[i])
          doc.blocks:remove(i)
        else
          if doc.blocks[i].identifier:find("^fig%-") then
            if FORMAT == "docx" then
             table.insert(fig, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
            end
            table.insert(fig, 1, doc.blocks[i])
            doc.blocks:remove(i)
          else
            local hasfig = false
            doc.blocks[i]:walk {
              Figure = function(fg)
                if fg.identifier then
                  if fg.identifier:find("^fig%-") then
                    hasfig = true
                  end
                end
              end
            }
            if hasfig then
              if FORMAT == "docx" then
                table.insert(fig, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
              end
              table.insert(fig, 1, doc.blocks[i])
              doc.blocks:remove(i)
              hasfig = false
            end
          end
        end

      end

  end
  
  if #tbl > 0 then
    doc.blocks:extend(tbl)
  end 
  if #fig > 0 then
    doc.blocks:extend(fig)
  end 
return doc
end
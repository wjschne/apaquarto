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
          if doc.blocks[i].attributes and doc.blocks[i].attributes.prefix == "" then
            if FORMAT == "docx" then
               table.insert(tbl, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
            end
            table.insert(tbl, 1, doc.blocks[i])
            doc.blocks:remove(i)
          end
        else
          if doc.blocks[i].identifier:find("^fig%-") then
            if doc.blocks[i].attributes and doc.blocks[i].attributes.prefix == "" then
              if FORMAT == "docx" then
               table.insert(fig, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
              end
              table.insert(fig, 1, doc.blocks[i])
              doc.blocks:remove(i)
            end
          else
            local hasfig = false
            doc.blocks[i]:walk {
              Figure = function(fg)
                if fg.identifier then
                  if fg.identifier:find("^fig%-") then
                    if fg.attributes and fg.attributes.prefix == "" then
                      hasfig = true
                    end
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
            else
              
            end
          end
        end

      end

  end
  
  
  -- Insert page breaks for each appendix in docx
  if FORMAT == "docx" then
    for i = #doc.blocks, 1, -1 do
      if doc.blocks[i].tag == "Header" then
        if doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == "Appendix" then
          table.insert(doc.blocks, i, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
        end
      end
    end 
  end
  
  -- Find block where appendices begin
  local appendixblock = 0
  for i = 1, #doc.blocks, 1 do
    if doc.blocks[i].tag == "Header" then
      if doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == "Appendix" and appendixblock== 0 then
        appendixblock = i
      end
    end
  end 
  
  -- If there are no appendices, insert figures and tables at the end
    if appendixblock == 0 then
        if #tbl > 0 then
          doc.blocks:extend(tbl)
        end
        if #fig > 0 then
          doc.blocks:extend(fig)
        end
    else
    -- Insert figures and tables before appendices
      if #fig > 0 then
        for i = #fig, 1, -1 do
          doc.blocks:insert(appendixblock, fig[i])
        end
      end
      if #tbl > 0 then
        for i = #tbl, 1, -1 do
          doc.blocks:insert(appendixblock, tbl[i])
        end
      end
    end

return doc
end
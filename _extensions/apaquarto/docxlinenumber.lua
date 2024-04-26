--- Makes numbered lines in docx if numbered-lines is true

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end


function Pandoc(doc)
  if doc.meta["numbered-lines"] then
    if pandoc.utils.stringify(doc.meta["numbered-lines"]) == "true" then
      doc.blocks:insert(
        pandoc.RawBlock("openxml", 
         '<w:sectPr><w:lnNumType w:countBy="1" w:restart="continuous" /></w:sectPr>')
        )
      return doc
    end
  end
end
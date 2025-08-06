--- Makes numbered lines in docx if numbered-lines is true

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

function Math(eq)
  if eq.mathtype == "InlineMath" then
    if eq.text == "\\LaTeX" then
      return pandoc.Str("LaTeX")
    end
    if eq.text == "\\TeX" then
      return pandoc.Str("TeX")
    end
  end
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

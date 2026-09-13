--- Writes the LaTeX and TeX logos as plain words in docx.
---
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

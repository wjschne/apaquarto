--- Sets cross-referenced code listings flush left in docx.
---
--- Quarto renders every float in docx as a one-cell table and takes that
--- table's alignment from <prefix>-align, which for a float naming no
--- alignment of its own falls back to center. Centering is what a figure
--- wants; a code listing is not a figure, and the centering reaches the code
--- as direct paragraph formatting, which no style in the reference document
--- can override -- editing SourceCode in the reference docx has no effect on
--- it (issue #149). A listing is given an alignment of its own here, so that
--- captioned code reads from the left margin like the code blocks that carry
--- no caption.
---
--- Only a listing that names no alignment is touched, so an author who asks
--- for one keeps it.

--- This filter only runs on docx format
if FORMAT ~= "docx" then
  return
end

--- The alignment attribute quarto reads for a listing float, which is its
--- cross-reference prefix followed by -align
local alignment = "lst-align"

return {
  {
    FloatRefTarget = function(float)
      if float.type ~= "Listing" then
        return nil
      end
      if float.attributes[alignment] then
        return nil
      end
      float.attributes[alignment] = "left"
      return float
    end
  }
}

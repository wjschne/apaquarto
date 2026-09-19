-- Takes out a heading called Introduction at the start of the body.
--
-- APA does not label the introduction. The paper's title stands at the top of
-- the first page of text and the introduction runs on underneath it, so a
-- heading reading "Introduction" is one heading too many and putting one there
-- is a style error.
--
-- It is easy to write one anyway, and easier still now that the abstract can
-- be written as a section of the document: something has to mark where the
-- abstract ends, and a heading is the obvious thing to reach for. So the
-- heading is taken out here and the text under it is left where it is.
--
-- Only the first heading of the body, and only at level one. A heading called
-- Introduction further down belongs to whatever section it is in -- an
-- appendix, a supplement -- and is the writer's business rather than APA's.
--
-- Set keep-introduction-heading: true to leave it alone.

local kOption = "keep-introduction-heading"
local kLanguage = "section-title-introduction"
local kDefault = "Introduction"

local introword = kDefault
local keep = false

-- The identifier pandoc makes from a heading's own text, so that a heading
-- carrying one the writer wrote can be told from one that got its identifier
-- for free. Only the first is worth mentioning when it goes.
local function auto_identifier(inlines)
  local text = pandoc.utils.stringify(inlines)
  text = pandoc.text.lower(text)
  text = text:gsub("[^%w%s%-_]", ""):gsub("%s+", "-")
  return text
end

local function normalize(text)
  local plain = pandoc.utils.stringify(text)
  plain = plain:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return pandoc.text.lower(plain)
end

local function meta(m)
  if m[kOption] ~= nil then
    keep = pandoc.utils.stringify(m[kOption]) ~= "false"
  end
  if m.language and m.language[kLanguage] then
    introword = pandoc.utils.stringify(m.language[kLanguage])
  end
end

local function blocks(doc)
  if keep then return nil end

  for index, block in ipairs(doc.blocks) do
    if block.t == "Header" then
      -- The first heading in the body, whatever it says. Anything after it is
      -- somebody else's section.
      if block.level ~= 1 or normalize(block.content) ~= normalize(introword) then
        return nil
      end
      if block.identifier and block.identifier ~= ""
          and block.identifier ~= auto_identifier(block.content) then
        quarto.log.warning(
          "The Introduction heading has been taken out, as APA does not " ..
          "label the introduction, and it carried the identifier \"" ..
          block.identifier .. "\". A link or a cross-reference to that " ..
          "identifier will no longer find anything. Set " ..
          "keep-introduction-heading: true to keep the heading.")
      end
      doc.blocks:remove(index)
      return doc
    end
  end
  return nil
end

return {
  { Meta = meta },
  { Pandoc = blocks }
}

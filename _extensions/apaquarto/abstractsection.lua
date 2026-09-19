-- Lets the abstract and the impact statement be written in the document
-- instead of in the yaml.
--
-- An abstract of any length is awkward to write in a yaml field: it has to be
-- quoted or indented under a block scalar, an apostrophe or a colon in the
-- wrong place stops the render, and no editor gives it the spell checking and
-- word count it gives the rest of the prose. So a writer can put it in the
-- body instead, as a section:
--
--     # Abstract
--
--     Text of the abstract.
--
--     # Impact Statement
--
--     Text of the impact statement.
--
-- The section is taken out of the body and its content becomes the metadata
-- field, which is where everything downstream already looks for it. Nothing
-- else changes: the abstract is set on the title page exactly as it would have
-- been had it been written in the yaml.
--
-- This is apaquarto's counterpart to the pandoc-ext/abstract-section filter,
-- which does the same for the abstract alone. The section is found the same
-- way it is there, by its identifier rather than by the words in the heading,
-- so that `# Abstract` needs nothing added to it: pandoc gives a heading an
-- identifier made from its text, and `# Abstract` becomes `#abstract` on its
-- own. A document written in another language is matched on the heading text
-- as well, against whatever section-title-abstract and title-impact-statement
-- are set to, so `# Resumen` works without the writer naming an identifier.
--
-- Runs at pre-ast, before apastriptitle.lua copies the abstract and before
-- frontmatter.lua sets the title page.

-- What each section fills in, and the language field that names it.
local targets = {
  {
    field = "abstract",
    identifiers = { ["abstract"] = true },
    language = "section-title-abstract",
    fallback = "Abstract",
  },
  {
    field = "impact-statement",
    -- "impact" as well: frontmatter.lua gives its own impact heading that
    -- identifier, and a writer who has seen it in the output may well use it.
    identifiers = { ["impact-statement"] = true, ["impact"] = true },
    language = "title-impact-statement",
    fallback = "Impact Statement",
  },
}

-- Heading text and a language field are compared with the spacing and the
-- case taken out of them, so that "Impact statement" answers to the same
-- section as "Impact Statement". pandoc.text.lower rather than string.lower,
-- which only knows the ascii letters and would leave a heading written in
-- another alphabet unmatched.
local function normalize(text)
  local plain = pandoc.utils.stringify(text)
  plain = plain:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return pandoc.text.lower(plain)
end

-- Fills in the heading text each target answers to, from the language fields
-- so that a document written in another language is matched too.
local function read_language(meta)
  for _, target in ipairs(targets) do
    local title = target.fallback
    if meta.language and meta.language[target.language] then
      title = pandoc.utils.stringify(meta.language[target.language])
    end
    target.title = normalize(title)
  end
end

local function target_for(header)
  for _, target in ipairs(targets) do
    if header.identifier and target.identifiers[header.identifier] then
      return target
    end
    if target.title and normalize(header.content) == target.title then
      return target
    end
  end
  return nil
end

-- Whether the field already holds something a writer put there.
local function already_given(meta, field)
  local given = meta[field]
  if given == nil then return false end
  return pandoc.utils.stringify(given):match("^%s*$") == nil
end

-- The collected blocks as a metadata value.
--
-- One paragraph becomes inlines, which is the shape a field written in the
-- yaml has and the shape every format already sets; anything longer is kept as
-- blocks, so that the paragraphs of a long abstract stay separate.
local function as_meta(blocks)
  if #blocks == 0 then return nil end
  if #blocks == 1 and (blocks[1].t == "Para" or blocks[1].t == "Plain") then
    return pandoc.MetaInlines(blocks[1].content)
  end
  return pandoc.MetaBlocks(blocks)
end

local function pandoc_filter(doc)
  read_language(doc.meta)

  local kept = pandoc.List({})
  local found = {}
  local collecting = nil
  local level = nil

  for _, block in ipairs(doc.blocks) do
    if collecting then
      -- The section runs to the next heading at the same level or above it, or
      -- to a horizontal rule, which is how a writer ends a section that is
      -- followed by nothing in particular.
      if block.t == "Header" and block.level <= level then
        collecting = nil
      elseif block.t == "HorizontalRule" then
        collecting = nil
        goto continue
      else
        found[collecting]:insert(block)
        goto continue
      end
    end

    if block.t == "Header" then
      local target = target_for(block)
      if target and not found[target.field] then
        found[target.field] = pandoc.List({})
        collecting = target.field
        level = block.level
        goto continue
      end
    end

    kept:insert(block)
    ::continue::
  end

  if next(found) == nil then return nil end

  for field, blocks in pairs(found) do
    local value = as_meta(blocks)
    if value == nil then
      quarto.log.warning(
        "The " .. field .. " section in this document is empty. Nothing was " ..
        "taken from it, and the " .. field .. " field is left as it was.")
    else
      if already_given(doc.meta, field) then
        quarto.log.warning(
          "The " .. field .. " is written twice, once in the yaml and once " ..
          "as a section of the document. The section is the one being used. " ..
          "Take the " .. field .. " field out of the yaml to stop this being " ..
          "said again.")
      end
      doc.meta[field] = value
    end
  end

  doc.blocks = kept
  return doc
end

return {
  { Pandoc = pandoc_filter }
}

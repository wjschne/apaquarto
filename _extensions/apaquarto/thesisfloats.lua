-- Every float in the document, noted down while it can still be read.
--
-- A dissertation's front matter carries a list of tables, a list of figures
-- and a list of whatever else the document declares --- an Illustration is
-- the one apaquarto ships --- and each entry is the float's number, its
-- caption and the page it is on.
--
-- The lists are built at the very end, by thesisfrontmatter.lua, because they
-- go in front of a body it has to have seen. By then there is nothing left to
-- read: floatlatex.lua has turned every float into latex, and quarto's own
-- writers have done the same for typst. So the floats are read here instead,
-- while they are still FloatRefTargets, and what the lists need is left in
-- the metadata for that filter to pick up and take out again.
--
-- Only in thesis mode. No other mode asks for these lists, and metadata that
-- nothing reads is metadata that can go wrong.

local utilsapa = require("utilsapa")

local kField = "apathesis-floats"

local function is_thesis(meta)
  return meta.documentmode ~= nil
    and utilsapa.stringify(meta.documentmode) == "thesis"
end

-- What the float is called. Quarto's own two are Figure and Table; a float a
-- document declared for itself is called by its reference-prefix, which is
-- what quarto leaves in the type.
local function float_kind(float)
  if float.type == nil or float.type == "" then return "Figure" end
  return tostring(float.type)
end

-- The number the float is given, which apaquarto works out for itself where
-- an appendix is involved --- B1, B2 --- and quarto counts otherwise.
local function float_number(float)
  local attributes = float.attributes or {}
  local given = attributes.fignum or attributes.tblnum
  local number = nil
  if given and given ~= "" then
    number = tostring(given):match("%d+")
  elseif type(float.order) == "table" and float.order.order then
    number = tostring(float.order.order)
  end
  if number == nil then return nil end
  return (attributes.prefix or "") .. number
end

-- The caption, as inlines. Quarto hands it over as a Block, as Blocks or as
-- Inlines depending on how it was written, so all three are taken.
local function float_caption(float)
  local caption = float.caption_long
  if caption == nil then return pandoc.Inlines({}) end
  local kind = pandoc.utils.type(caption)
  if kind == "Inlines" then return pandoc.Inlines(caption) end
  if kind == "Block" then
    return pandoc.Inlines(caption.content or {})
  end
  if kind == "Blocks" and caption[1] then
    return pandoc.Inlines(caption[1].content or {})
  end
  return pandoc.Inlines({})
end

local floats = pandoc.List({})
local wanted = false

local function note_float(float)
  if not wanted then return nil end
  if float.identifier == nil or float.identifier == "" then return nil end
  -- A panel of a multipanel float is a float of its own and carries a label,
  -- but a list of figures wants the figure rather than each of its panels.
  -- quarto marks a panel by making its numbering a function.
  if type(float.numbering) == "function" then return nil end
  floats:insert(pandoc.MetaMap({
    kind = pandoc.MetaString(float_kind(float)),
    number = pandoc.MetaString(float_number(float) or ""),
    id = pandoc.MetaString(float.identifier),
    caption = pandoc.MetaInlines(float_caption(float)),
  }))
  return nil
end

-- Three passes over the one document: what mode it is in, then the floats,
-- then the note left in the metadata for thesisfrontmatter.lua. The floats
-- are read through quarto's own FloatRefTarget rather than walked for, since
-- a walk does not descend into the nodes quarto adds to the ast.
return {
  {
    Meta = function(m)
      wanted = is_thesis(m)
      return nil
    end
  },
  { FloatRefTarget = note_float },
  {
    Pandoc = function(doc)
      if not wanted then return nil end
      doc.meta[kField] = pandoc.MetaList(floats)
      return doc
    end
  },
}

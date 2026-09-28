-- Get names for Figure and Table in language specified in lang field
local figureword = "Figure"
local tableword = "Table"
local labelnum = ""

-- What a float of any kind is called, and the prefix its identifier carries.
--
-- Figures and tables are quarto's own. A document may declare others under
-- crossref.custom --- an Illustration is the one apaquarto ships --- and such
-- a float is a float like the rest: its number belongs on a line of its own
-- with its caption under it, not run together with the caption as quarto
-- sets one by default. So the words are collected rather than named, and
-- every one of them is read the same way.
local floatwords = {}
local floatprefixes = { ["fig"] = true, ["tbl"] = true }

local function is_float(identifier)
  local prefix = identifier:match("^(%a+)%-")
  return prefix ~= nil and floatprefixes[prefix] == true
end

local function gettablefig(m)
  -- Get names for Figure and Table specified in language field
  if m.language then
    if m.language["crossref-fig-title"] then
      figureword = pandoc.utils.stringify(m.language["crossref-fig-title"])
    end

    if m.language["crossref-tbl-title"] then
      tableword = pandoc.utils.stringify(m.language["crossref-tbl-title"])
    end
  end
  floatwords = { [figureword] = true, [tableword] = true }

  if m.crossref and m.crossref.custom then
    for _, entry in ipairs(m.crossref.custom) do
      if entry["reference-prefix"] then
        floatwords[pandoc.utils.stringify(entry["reference-prefix"])] = true
      end
      if entry.key then
        floatprefixes[pandoc.utils.stringify(entry.key)] = true
      end
    end
  end
end


-- Format caption
local caption_formatter = function(p)
  -- If the paragraph content's first element is the figureword or tableword
  if p.content[1] and p.content[1].text and floatwords[p.content[1].text] then
    -- If the paragraph content's second element is a non-breaking space
    if p.content[2] and p.content[2].text == '\u{a0}' then
      -- If the paragraph content's fourth element is a colon
      if p.content[4] and p.content[4].text == ':' then
        local figuretitle = pandoc.Para({})
        local figurecaption = pandoc.Para({})

        local intStart = 0
        -- separate figure title from figure caption
        for i, v in ipairs(p.content) do
          -- Figure/table title
          if i > intStart and i < intStart + 4 then
            if i == 3 and labelnum then
              -- Figure or table number, when apaquarto has one of its own.
              -- It has for a float in an appendix, where the number carries
              -- a letter; otherwise quarto's own number is already here.
              v = pandoc.Str(labelnum)
            end
            figuretitle.content:extend({ v })
          end
          -- Figure/table caption
          if i > intStart + 5 then
            figurecaption.content:extend({ v })
          end
        end
        -- enclose figure/table title in a div with custom style
        local figuretitlediv = pandoc.Div(figuretitle)
        figuretitlediv.classes:insert("FigureTitle")
        figuretitlediv.attributes["custom-style"] = "FigureTitle"
        -- enclose figure/table caption in a div with custom style
        local figurecaptiondiv = pandoc.Div(figurecaption)
        figurecaptiondiv.classes:insert("Caption")
        figurecaptiondiv.attributes["custom-style"] = "Caption"
        return { figuretitlediv, figurecaptiondiv }
      end
    end
  end
end

local divcaption = function(div)
  if is_float(div.identifier) then
    -- Forget the last float's number before working this one out. A float
    -- that carries no number of its own -- a multipanel figure is one, since
    -- quarto keeps the count on the panels rather than on the div around
    -- them -- used to keep whatever the float before it had, so the second
    -- figure of example.qmd came out as "Figure 1" while the third was
    -- correctly "Figure 3". Left nil, the number quarto already wrote into
    -- the caption stands, which is the right one.
    labelnum = nil

    -- Get figure/table prefix and number
    if div.attributes.prefix then
      if div.attributes.fignum then
        -- Have to remove subfigure letters if present
        labelnum = div.attributes.prefix .. string.match(div.attributes.fignum, "%d+")
      end
      if div.attributes.tblnum then
        labelnum = div.attributes.prefix .. string.match(div.attributes.tblnum, "%d+")
      end
    end

    if FORMAT == "html" then
      div.content = div.content:walk { Plain = caption_formatter }
    end
    if FORMAT == "docx" then
      -- Remove raw openxml from div
      div.content = div.content:walk { RawInline = function(ri) return {} end }
      div.content = div.content:walk { Para = caption_formatter }
    end
    return div
  end
end

return {
  { Meta = gettablefig },
  { Div = divcaption }
}

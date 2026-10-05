-- Block quotations.
--
-- An attribution, in every format. A quotation whose last paragraph begins
-- with an em dash is read as ending with one:
--
--   > The quoted passage, as long as it runs.
--   >
--   > --- Mary Shelley, *Frankenstein*
--
-- pandoc writes --- as the em dash, and a dash typed as it is works the same.
-- The paragraph is put in a div of class quote-attribution, which each format
-- sets right-aligned under the quotation and with no first-line indent:
-- formatlatex.lua as the apaquoteattribution environment, formattypst.lua in
-- an align, apa.css by its class, and .docx in the QuoteAttribution style
-- docxreferencedoc.lua writes into the reference document when a document
-- has an attribution at all. The paragraph is left as it was written rather
-- than turned into raw markup here, so that a citation in it is still a
-- citation when citeproc runs, which is long after this.
--
-- A quotation whose last paragraph only happens to begin with a dash --- the
-- last line of a dialogue --- is left alone when it is written inside a div of
-- class no-attribution.
--
-- In .docx, the paragraphs of a quotation after its first are given the
-- NextBlockText style, which indents their first lines.

local kDash = "\u{2014}"
local found = false

-- Whether a paragraph begins with an em dash.
local function is_attribution(block)
  if block == nil or block.t ~= "Para" then return false end
  local first = block.content[1]
  return first ~= nil and first.t == "Str"
    and first.text:sub(1, #kDash) == kDash
end

local function quote(element)
  local blocks = element.content
  local last = blocks[#blocks]
  -- An attribution and nothing above it is a line that begins with a dash,
  -- not a quotation with its source under it.
  local attributed = #blocks > 1 and is_attribution(last)

  if FORMAT == "docx" then
    local i = 0
    local upto = attributed and #blocks - 1 or #blocks
    for k = 1, upto do
      if blocks[k].t == "Para" then
        i = i + 1
        if i > 1 then
          blocks[k] = pandoc.Div({ blocks[k] },
            pandoc.Attr("", {}, { ["custom-style"] = "NextBlockText" }))
        end
      end
    end
  end

  if attributed then
    found = true
    blocks[#blocks] = pandoc.Div({ last }, pandoc.Attr("", { "quote-attribution" },
      { ["custom-style"] = "QuoteAttribution" }))
  end
  element.content = blocks
  return element
end

return {
  {
    traverse = "topdown",
    -- A no-attribution div is left exactly as written, quotations and all.
    Div = function(div)
      if div.classes:includes("no-attribution") then return div, false end
    end,
    BlockQuote = quote,
  },
  {
    Meta = function(meta)
      -- Read by docxreferencedoc.lua, which writes the QuoteAttribution style
      -- only for a document that uses it.
      if found then meta["apa-quote-attribution"] = true end
      return meta
    end,
  },
}

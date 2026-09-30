-- Reads the attributes a plain markdown table carries at the end of its
-- caption, {#tbl-x .class apa-note="..."}, onto the table itself.
--
-- Every format wants this, the pdf included: without an identifier on the
-- table, crossrefprefix.lua never counts it, so a markdown table takes no
-- number of its own and falls back to quarto's count -- a document with a
-- markdown table and a code chunk table in it then has two Table 1s.
--
-- The apa-note is read twice over. Pandoc has already parsed the caption as
-- markdown by now, so the caption's own text gives the note flattened:
-- emphasis and code keep their words but lose their markup, and raw spans
-- such as `\x`{=latex} are dropped. The caption still writes back out as
-- markdown, though, and the note read from that is the one the writer typed.
-- Quarto builds the table's attributes from the caption again later, which
-- would flatten a note put back on the table, so the markdown note is left in
-- meta["apa-table-notes"] instead, by identifier. utilsapa.table_notes reads
-- it for the filters that write notes: apanote.lua, floatlatex.lua and
-- typst/formattypst.lua.

local notes = {}

-- The attribute text with the inside of every quoted value blanked out.
--
-- A class is looked for below as a dot followed by a run of word characters,
-- and an identifier as a hash followed by one. Run over the whole attribute
-- text those patterns read the values too: a note ending in a full stop,
-- apa-note="A note.", left the closing quotation mark itself as the table's
-- first class, which is not valid utf-8 on its own and came out of the html
-- writer as a replacement character; a note mentioning a version number would
-- have made a class of the digits after the dot. The values are still read
-- from the unmasked text afterwards, so nothing is lost by hiding them here.
local function mask_values(text)
  local quote_pairs = { { '"', '"' }, { "'", "'" },
                        { "\u{201C}", "\u{201D}" },
                        { "\u{2018}", "\u{2019}" } }
  for _, quotes in ipairs(quote_pairs) do
    local open, close = quotes[1], quotes[2]
    text = text:gsub("(=%s*" .. open .. ")(.-)" .. close, function(head, value)
      return head .. string.rep(" ", #value) .. close
    end)
  end
  return text
end

-- The caption written back out as markdown, on one line
local function caption_markdown(tb)
  local ok, md = pcall(pandoc.write, pandoc.Pandoc(tb.caption.long), "markdown")
  if not ok then
    return nil
  end
  -- the caption may have been wrapped over several lines
  return (md:gsub("%s+", " "))
end

-- The apa-note as the writer typed it, read from the caption's markdown.
-- The quotes around the value may have been made curly by smart quotes.
local function markdown_note(tb)
  local md = caption_markdown(tb)
  if not md then return nil end
  return md:match('apa%-note%s*=%s*"([^"]*)"') or
    md:match("apa%-note%s*=%s*'([^']*)'") or
    md:match('apa%-note%s*=%s*\u{201C}([^\u{201D}]*)\u{201D}')
end

local function add_caption_attributes(tb)
  local caption = pandoc.utils.stringify(tb.caption.long)
  local attr_text = caption:match("%{([^{}]-)%}%s*$")

  if not attr_text then
    return
  end

  local outside_values = mask_values(attr_text)

  local identifier = outside_values:match("#([%w%-%_%.:]+)")
  if identifier then
    tb.identifier = identifier
  end

  for class in outside_values:gmatch("%.([%w%-%_%.:]+)") do
    if not tb.classes:includes(class) then
      tb.classes:insert(class)
    end
  end

  for key, quote, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*([\"'])(.-)%2") do
    tb.attributes[key] = value
  end

  for key, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*“(.-)”") do
    tb.attributes[key] = value
  end

  for key, value in attr_text:gmatch("([%w%-%_:]+)%s*=%s*‘(.-)’") do
    tb.attributes[key] = value
  end

  -- Unquoted values. Read from the masked text, so that a key=value written
  -- inside a quoted note is not taken for an attribute of the table.
  for key, value in outside_values:gmatch("([%w%-%_:]+)%s*=%s*([^%s]+)") do
    if not tb.attributes[key] then
      tb.attributes[key] = value:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
    end
  end

  if tb.attributes["apa-note"] and tb.identifier ~= "" then
    notes[tb.identifier] = markdown_note(tb)
  end
end

local function table_identifier(tb)
  if not (tb.caption and tb.caption.long) then return nil end

  add_caption_attributes(tb)
  return tb
end

return {
  { Table = table_identifier },
  {
    Meta = function(meta)
      if next(notes) == nil then return nil end
      local recovered = {}
      for id, note in pairs(notes) do
        recovered[id] = pandoc.MetaString(note)
      end
      meta["apa-table-notes"] = pandoc.MetaMap(recovered)
      return meta
    end
  }
}

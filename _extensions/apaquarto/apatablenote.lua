-- Recovers the apa-note of a plain markdown table.
--
-- Pandoc reads {#tbl-x apa-note="..."} on a markdown table as attributes, but
-- under quarto the block is still ordinary caption text at this point, and it
-- has already been parsed as markdown. Quarto builds the table's attributes
-- from that parsed caption, so the note arrives flattened: emphasis and code
-- keep their text but lose their markup, and raw spans such as `\x`{=latex}
-- are dropped altogether. Notes on figures are unaffected, because pandoc
-- reads image attributes directly.
--
-- The caption still writes back out as markdown here, so the note is
-- recovered from it and carried in the metadata, which quarto leaves alone.
-- apafloatlatex.lua prefers this copy over the flattened attribute.

local notes = {}

local function caption_markdown(tb)
  local caption = tb.caption and tb.caption.long
  if not caption then
    return nil
  end
  local ok, md = pcall(pandoc.write, pandoc.Pandoc(caption), "markdown")
  if not ok then
    return nil
  end
  -- the caption may have been wrapped over several lines
  return (md:gsub("%s+", " "))
end

return {
  {
    Table = function(tb)
      local md = caption_markdown(tb)
      if not md then
        return nil
      end
      local id = md:match("{#(tbl%-[%w%-_]+)")
      if not id then
        return nil
      end
      -- the quotes around the value may have been made curly by smart quotes
      local note = md:match('apa%-note%s*=%s*"([^"]*)"') or
        md:match("apa%-note%s*=%s*'([^']*)'") or
        md:match('apa%-note%s*=%s*\u{201C}([^\u{201D}]*)\u{201D}')
      if note then
        notes[id] = note
      end
    end
  },
  {
    Meta = function(meta)
      local recovered = {}
      local found = false
      for id, note in pairs(notes) do
        recovered[id] = pandoc.MetaString(note)
        found = true
      end
      if found then
        meta["apa-table-notes"] = pandoc.MetaMap(recovered)
        return meta
      end
    end
  }
}

local M = {}

function M.make_note(s, prefix)
  s = string.gsub(s, '^%[%"', "")
  s = string.gsub(s, '%"%]$', "")

  local includeprefix = true
  local apanotedivs = pandoc.Div(pandoc.Blocks {})
  local cnt = 0

  for v in string.gmatch(s .. '","', '(.-)%",%"') do
    if string.find(v, '^NoNote ') then
      includeprefix = false
      v = string.gsub(v, '^NoNote ', "")
    end
    local apanote = pandoc.Div({})
    apanote.attributes['custom-style'] = 'FigureNote'
    apanote.classes:extend({ "FigureNote" })
    apanote.classes:extend({ "NoIndent" })
    cnt = cnt + 1
    if (cnt == 1 and includeprefix) then
      apanote.content:extend(prefix.content:extend(quarto.utils.string_to_inlines(v:gsub(" ", "\u{00A0}", 1))))
    else
      apanote.content:extend(quarto.utils.string_to_inlines(v))
    end
    apanotedivs.content:extend({ apanote })
  end
  return (apanotedivs)
end

-- make string, if it exists, else return default
function M.stringify(s, default)
  if s then
    s = pandoc.utils.stringify(s)
  else
    if default then
      s = default
    else
      s = ""
    end
  end
  return s
end

--- Coerce a metadata value to Inlines, or nil when it is absent or empty
function M.meta_inlines(meta_item)
  if meta_item and M.stringify(meta_item) ~= "" then
    if pandoc.utils.type(meta_item) == "Inlines" then
      return meta_item
    end
    return pandoc.Inlines({ pandoc.Str(M.stringify(meta_item)) })
  end
end

--- The journal's name: journal.title, or journal itself when it was written
--- as a plain string. Never meta.title, which belongs to the article.
function M.journal_title(meta)
  if not meta.journal then return nil end
  return M.meta_inlines(meta.journal.title) or M.meta_inlines(meta.journal)
end

--- A journal field: under journal when it is there, at the top level when it
--- is not, which is how volume, copyrightnotice and copyrighttext were given
--- before there was anywhere else to put them.
function M.journal_field(meta, name)
  if meta.journal and meta.journal[name] ~= nil then
    return M.meta_inlines(meta.journal[name])
  end
  return M.meta_inlines(meta[name])
end

local function journal_label(meta, key, fallback)
  if meta.language and meta.language[key] then
    return M.stringify(meta.language[key])
  end
  return fallback
end

--- Join runs of inlines with ", "
local function comma_list(parts)
  local out = pandoc.Inlines({})
  for i, part in ipairs(parts) do
    if i > 1 then out:extend({ pandoc.Str(", ") }) end
    out:extend(part)
  end
  return out
end

--- "2026, Vol. 118, No. 6, 869-888" out of the parts, or the volume just as
--- it was written when it is the only one given, which is how the whole line
--- used to be supplied.
function M.journal_issue_line(meta)
  local year = M.journal_field(meta, "year")
  local volume = M.journal_field(meta, "volume")
  local issue = M.journal_field(meta, "issue")
  local pages = M.journal_field(meta, "pages")

  if volume and not (year or issue or pages) then
    return volume
  end

  local parts = {}
  if year then parts[#parts + 1] = year end
  if volume then
    local run = pandoc.Inlines({
      pandoc.Str(journal_label(meta, "journal-volume", "Vol.")), pandoc.Space() })
    run:extend(volume)
    parts[#parts + 1] = run
  end
  if issue then
    local run = pandoc.Inlines({
      pandoc.Str(journal_label(meta, "journal-issue", "No.")), pandoc.Space() })
    run:extend(issue)
    parts[#parts + 1] = run
  end
  if pages then parts[#parts + 1] = pages end
  if #parts == 0 then return nil end
  return comma_list(parts)
end

-- if any value in table
function M.containsValue(tbl, value)
  for _, v in pairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

return M

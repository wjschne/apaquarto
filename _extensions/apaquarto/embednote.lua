-- Recovers the apa-note of a figure or table pulled in with
-- {{< embed other.qmd#fig-x >}}.
--
-- Quarto has two ways of placing an embed. Where it places the cell, the cell's
-- div comes with it and the note is an attribute on that div, which apanote.lua
-- reads like any other. Where it places only the cell's output -- which is what
-- a manuscript project does, the one that builds a notebook view and puts a
-- "Source:" link under the embed -- the div carrying the note is not part of
-- what is placed, and the note is gone before any of these filters run. There
-- is nothing downstream to fix: apa-note is a cell option quarto knows nothing
-- about, so it is not carried into the output it keeps.
--
-- What is kept is where the cell came from. The wrapper div records the
-- notebook as `notebook` and the cell as `notebook-cellId`, which is the cell's
-- label behind a "cell-" prefix. That is enough to open the notebook and read
-- the note out of the cell's own options, which is what this does. It runs
-- before apanote.lua so that the note it finds is written out like any other.

if FORMAT == "latex" then
  return
end

local kEmbedClass = "quarto-embed-nb-cell"
local kCellPrefix = "^cell%-"

-- Notebooks are read once each, however many cells are embedded from them.
local cache = {}

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("a")
  fh:close()
  return text
end

-- A value as it is written after `#| apa-note:`. Quotes around it are the
-- writer's, not part of the note.
local function unquote(value)
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  local quote = value:sub(1, 1)
  if (quote == '"' or quote == "'") and value:sub(-1) == quote then
    value = value:sub(2, -2)
    if quote == '"' then
      value = value:gsub('\\"', '"')
    end
  end
  return value
end

-- Every apa-note in a notebook, by the label of the cell it belongs to.
--
-- Cell options are the `#|` lines at the top of a cell, so the file is read as
-- runs of them: a run ends at the first line that is not one, and a run that
-- names both a label and a note records the pair. A note written across more
-- than one line continues on `#|` lines that do not open a key of their own.
local function notes_by_label(text)
  local notes = {}
  local label, note, key = nil, nil, nil

  local function flush()
    if label and note then notes[label] = note end
    label, note, key = nil, nil, nil
  end

  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local option = line:match("^%s*#|%s?(.*)$")
    if option then
      local name, value = option:match("^([%w%-_]+)%s*:%s*(.*)$")
      if name then
        key = name
        if name == "label" then
          label = unquote(value)
        elseif name == "apa-note" then
          note = value
        end
      elseif key == "apa-note" and note then
        -- A continuation line of the note.
        note = note .. " " .. option:gsub("^%s+", "")
      end
    else
      -- Anything that is not an option line closes the run.
      if label or note then flush() end
    end
  end
  flush()

  for name, value in pairs(notes) do
    notes[name] = unquote(value)
  end
  return notes
end

-- A notebook stored as .ipynb keeps every line of every cell as its own json
-- string, so the option lines are all there but escaped and wrapped in quotes.
-- Reading the strings out of the file and laying them end to end gives back
-- something that can be read the same way as a .qmd's lines. The strings are
-- walked rather than matched, because a quote written inside a note is escaped
-- and a pattern would stop at it.
local function unescape_ipynb(text)
  local lines = {}
  local i, last = 1, #text
  while i <= last do
    if text:sub(i, i) == '"' then
      local buf, j = {}, i + 1
      while j <= last do
        local c = text:sub(j, j)
        if c == '"' then
          break
        elseif c == "\\" then
          local escaped = text:sub(j + 1, j + 1)
          if escaped == "n" then
            buf[#buf + 1] = "\n"
          elseif escaped == "t" then
            buf[#buf + 1] = "\t"
          else
            buf[#buf + 1] = escaped
          end
          j = j + 2
        else
          buf[#buf + 1] = c
          j = j + 1
        end
      end
      -- A source line is stored with the newline that ends it, and the join
      -- below adds one of its own, so the stored one goes. Leaving it would
      -- put a blank line between every pair of option lines, and a blank line
      -- closes a run of them.
      lines[#lines + 1] = (table.concat(buf):gsub("\r?\n$", ""))
      i = j + 1
    else
      i = i + 1
    end
  end
  return table.concat(lines, "\n")
end

local function notebook_notes(path)
  if cache[path] ~= nil then return cache[path] end
  local text = read_file(path)
  if not text then
    quarto.log.warning(
      "Could not open " .. path .. " to read the apa-note of an embedded " ..
      "figure or table, so the note is missing from the output.")
    cache[path] = {}
    return cache[path]
  end
  if path:lower():match("%.ipynb$") then
    text = unescape_ipynb(text)
  end
  cache[path] = notes_by_label(text)
  return cache[path]
end

-- Whether the note is already here, in which case there is nothing to recover.
local function has_note(div)
  if div.attributes["apa-note"] then return true end
  local found = false
  div.content:walk {
    Div = function(inner)
      if inner.attributes["apa-note"] then found = true end
    end,
    Image = function(img)
      if img.attributes["apa-note"] then found = true end
    end
  }
  return found
end

-- The note belongs on the float itself, so that it is written between the
-- float and the "Source:" link rather than after the link.
local function attach(div, note)
  local done = false
  div.content = div.content:walk {
    Div = function(inner)
      if done or not inner.identifier then return nil end
      if inner.identifier:find("^fig%-") or inner.identifier:find("^tbl%-") then
        inner.attributes["apa-note"] = note
        done = true
        return inner
      end
    end
  }
  if not done then
    div.attributes["apa-note"] = note
  end
  return div
end

local function embed(div)
  if not div.classes:includes(kEmbedClass) then return nil end
  if has_note(div) then return nil end

  local path = div.attributes["notebook"]
  local cellid = div.attributes["notebook-cellId"]
  if not path or not cellid then return nil end

  -- An unlabelled cell is "cell-3" and has no note to look up.
  local label = cellid:gsub(kCellPrefix, "")
  if label == cellid or label == "" then return nil end

  local note = notebook_notes(path)[label]
  if not note then return nil end

  return attach(div, note)
end

return {
  { Div = embed }
}

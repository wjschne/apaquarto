local M = {}

-- The markdown of a note, as inlines.
--
-- quarto.utils.string_to_inlines costs about 9 ms however short the string
-- given to it -- an empty one costs the same -- because it runs quarto's whole
-- ast normalization pipeline over what it reads. A note is a sentence or two,
-- and that pipeline is only needed for the syntax quarto adds on top of
-- markdown: shortcodes and fenced divs. Reading the rest with pandoc costs
-- about a tenth of a millisecond and gives back the same inlines, citations,
-- cross-references, footnotes, math and all, because quarto reads a note with
-- pandoc's markdown reader as well.
local function has_quarto_syntax(text)
  return text:find("{{<", 1, true) ~= nil or text:find(":::", 1, true) ~= nil
end

local function extension_set(extensions)
  local set = {}
  for key, value in pairs(extensions) do
    if type(key) == "number" then
      set[value] = true
    elseif value then
      set[key] = true
    end
  end
  return set
end

-- The name of the reader to give pandoc, or false when pandoc cannot be given
-- one and quarto's reader has to do the work.
--
-- Naming the format matters: handing pandoc a table of extensions instead
-- rebuilds the reader on every call and costs about 4 ms a note, against a
-- tenth of that for the name, for exactly the same result. The name can only
-- stand in when this document was read with the markdown reader's own
-- defaults, which is what a .qmd is read with unless a `from:` says otherwise,
-- so the two sets of extensions are compared once and anything else is left to
-- quarto. Worked out on first use, since the reader options are not settled
-- when this file is loaded.
local markdown_flavor

local function flavor()
  if markdown_flavor ~= nil then return markdown_flavor end
  markdown_flavor = false
  pcall(function()
    local default = extension_set(pandoc.format.extensions("markdown"))
    local actual = extension_set(PANDOC_READER_OPTIONS.extensions)
    for name in pairs(default) do
      if not actual[name] then return end
    end
    for name in pairs(actual) do
      if not default[name] then return end
    end
    markdown_flavor = "markdown"
  end)
  return markdown_flavor
end

function M.note_inlines(text)
  local format = flavor()
  if format and not has_quarto_syntax(text) then
    local ok, inlines = pcall(function()
      return pandoc.utils.blocks_to_inlines(pandoc.read(text, format).blocks)
    end)
    if ok then return inlines end
  end
  return quarto.utils.string_to_inlines(text)
end

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
      apanote.content:extend(prefix.content:extend(M.note_inlines(v:gsub(" ", "\u{00A0}", 1))))
    else
      apanote.content:extend(M.note_inlines(v))
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

-- Files that ship with the extension: the apaquarto logo and the ORCID icon.
--
-- The folder they sit in is not fixed. It is _extensions/apaquarto while the
-- extension is worked on and _extensions/<owner>/apaquarto once it has been
-- added with quarto add, and <owner> is whoever it was added from, so a fork
-- is not under wjschne. Rather than guess at it, the folder is taken from the
-- path of this file, which is in it.
--
-- PANDOC_SCRIPT_FILE would be the obvious way to ask, and is in a filter, but
-- not here: quarto gives each filter it runs its own environment, and a module
-- required from one is outside them all, where PANDOC_SCRIPT_FILE is quarto's
-- own main.lua. What a required module can always say is where it was loaded
-- from, so that is what is asked, once, as it loads.

local kFolder = (function()
  local ok, source = pcall(function() return debug.getinfo(1, "S").source end)
  if not ok or type(source) ~= "string" then return nil end
  -- A chunk loaded from a file names it after an @.
  if source:sub(1, 1) ~= "@" then return nil end
  local file = source:sub(2)
  if not pandoc.path.is_absolute(file) then
    file = pandoc.path.join({ pandoc.system.get_working_directory(), file })
  end
  return pandoc.path.directory(file)
end)()

local function script_directory()
  return kFolder
end

-- The directory the document is in, which is where its output is written.
local function document_directory()
  local ok, input = pcall(function() return quarto.doc.input_file end)
  if ok and input and input ~= "" then
    return pandoc.path.directory(input)
  end
  return pandoc.system.get_working_directory()
end

-- The root typst is given: the project, or the document's own directory when
-- there is no project.
local function typst_root()
  local ok, dir = pcall(function() return quarto.project.directory end)
  if ok and dir and dir ~= "" then return dir end
  return document_directory()
end

-- The absolute path of a file that ships with the extension, or nil when
-- there is no way to tell where the extension is.
function M.extension_file(name)
  local folder = script_directory()
  if not folder then return nil end
  local ok, path = pcall(pandoc.path.join, { folder, name })
  if not ok or not path or path == "" then return nil end
  return path
end

-- A shipped file as typst wants to read it: a path from the root typst is
-- given, which is what a leading slash means to it, with forward slashes,
-- which it wants on every platform. Anchoring on the root rather than writing
-- a path relative to the .typ keeps the file reachable from a paper that sits
-- in a subfolder of the project. For raw typst only; see
-- M.extension_file_relative for a path that goes into the document.
function M.extension_file_typst(name)
  local file = M.extension_file(name)
  if not file then return nil end
  local ok, path = pcall(pandoc.path.make_relative, file, typst_root())
  if not ok or not path or path == "" then return nil end
  path = path:gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  return path
end

local function split_path(path)
  local parts = {}
  for part in path:gsub("\\", "/"):gmatch("[^/]+") do
    if part ~= "." then parts[#parts + 1] = part end
  end
  return parts
end

-- A shipped file as a path from the document, which is how every writer reads
-- one that is put in the document itself. The ORCID icon goes in this way.
--
-- A document in a subfolder of the project has to climb out of it to reach the
-- extension, and pandoc's make_relative will not write the .. that takes it
-- there, so the two paths are walked apart by hand. Comparison is
-- case-insensitive, since the drive letter of an absolute path on windows is
-- not always given in the same case.
--
-- One thing is given up by climbing out. Pandoc rasterises an svg to a png for
-- word to fall back on when it cannot draw one, and it does not do that for a
-- src with a .. in it, so word 2013 and older show nothing where the icon
-- should be. Only a document in a subfolder is affected, and only in .docx.
function M.extension_file_relative(name)
  local file = M.extension_file(name)
  if not file then return nil end
  local from, to = split_path(document_directory()), split_path(file)
  local same = 0
  while same < #from and same < #to
    and from[same + 1]:lower() == to[same + 1]:lower() do
    same = same + 1
  end
  -- Nothing in common means separate drives, where no relative path exists.
  if same == 0 then return (file:gsub("\\", "/")) end
  local parts = {}
  for _ = same + 1, #from do parts[#parts + 1] = ".." end
  for i = same + 1, #to do parts[#parts + 1] = to[i] end
  return table.concat(parts, "/")
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

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
--- Test for nil, not for truthiness. A yaml false arrives as a lua false,
--- which the old `if s then` read as an absent field and answered the empty
--- string for, so every caller asking `stringify(x) ~= "false"` was told that
--- `x: false` meant true. pandoc's own stringify answers "false" for it.
function M.stringify(s, default)
  if s == nil then
    return default or ""
  end
  return pandoc.utils.stringify(s)
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

--- Whether the document has anything to put in a journal masthead.
---
--- Asked by the two formats that set one: typst builds it in frontmatter.lua
--- and latex builds it there too, but latex also has to know before the body
--- is written, since a masthead is what decides whether the article opens with
--- twocolumn or with a masthead handed to twocolumn.
-- "(c) 2025 The Author(s)", from whichever of copyrightnotice and
-- copyrighttext was given, for the journal masthead; nil when neither was.
function M.journal_copyright(meta)
  local notice = M.journal_field(meta, "copyrightnotice")
  local text = M.journal_field(meta, "copyrighttext")
  if not (notice or text) then return nil end
  local out = pandoc.List({ pandoc.Str("\u{00A9}") })
  if notice then
    out:extend({ pandoc.Space() })
    out:extend(notice)
  end
  if text then
    out:extend({ pandoc.Space() })
    out:extend(text)
  end
  return out
end

function M.has_journal_masthead(meta)
  if meta == nil then return false end
  local fields = { "url", "logo", "issn", "copyrightnotice", "copyrighttext" }
  if M.journal_title(meta) or M.journal_issue_line(meta) then return true end
  for _, name in ipairs(fields) do
    if M.journal_field(meta, name) then return true end
  end
  return false
end

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

-- The colour a document asks a link to take -------------------------------
--
-- Quarto's fields are latex's: linkcolor for a link inside the document,
-- urlcolor for one that leaves it, citecolor for a citation, filecolor for a
-- file, and toccolor for the lists of contents, figures and tables. Each
-- names either one of the colours xcolor defines out of the box or an html
-- code, #rrggbb or #rgb.
--
-- latex resolves such a name itself. .docx and .html cannot: word wants six
-- hex digits and a stylesheet wants a colour css knows, and the two agree on
-- fewer names than one would hope -- css green is 008000 where xcolor's is
-- 00FF00. The table below is xcolor's, so that a document that names a
-- colour gets the same colour in every format apaquarto writes.
local xcolors = {
  red = "FF0000", green = "00FF00", blue = "0000FF",
  cyan = "00FFFF", magenta = "FF00FF", yellow = "FFFF00",
  black = "000000", white = "FFFFFF", gray = "808080", grey = "808080",
  darkgray = "404040", darkgrey = "404040",
  lightgray = "BFBFBF", lightgrey = "BFBFBF",
  brown = "BF8040", lime = "BFFF00", olive = "808000",
  orange = "FF8000", pink = "FFBFBF", purple = "BF0040",
  teal = "008080", violet = "800080",
  -- apaquarto's own, which the pdf format names in every colour field and
  -- which apalatex.tex defines. It is typst's blue.
  apalink = "0074D9",
}

-- The identifier prefixes a float can carry.
--
-- fig and tbl are quarto's own. A document may declare other kinds of float
-- under crossref.custom --- an Illustration, keyed ill, is the one apaquarto
-- ships --- and such a float is a float like the rest: it takes the same
-- title, the same caption and the same note, and in .docx the same styles,
-- which are what hold a note on the page with the thing it describes. So the
-- filters that do that work ask here rather than naming fig and tbl
-- themselves.
function M.float_prefixes(meta)
  local prefixes = { fig = true, tbl = true }
  local custom = meta and meta.crossref and meta.crossref.custom
  if custom then
    for _, entry in ipairs(custom) do
      if entry.key then
        prefixes[M.stringify(entry.key)] = true
      end
    end
  end
  return prefixes
end

-- Whether an identifier is a float's, given the prefixes above
function M.is_float(identifier, prefixes)
  if identifier == nil or identifier == "" then return false end
  local prefix = identifier:match("^(%a+)%-")
  return prefix ~= nil and prefixes[prefix] == true
end

-- The four fields that give a link its colour, one for each kind of link.
-- toccolor, which colours the entries of a contents list, is the fifth of
-- the colour fields but belongs to no kind of link.
M.link_fields = { "linkcolor", "urlcolor", "citecolor", "filecolor" }

-- Which of those fields a link's target asks for. The reading latex makes:
-- a citation points at the bibliography quarto writes, another anchor is a
-- cross reference or a link to a heading, anything with a scheme leaves the
-- document, and what is left is a path to a file.
function M.link_field(target)
  if target:match("^#ref%-") then return "citecolor" end
  if target:match("^#") then return "linkcolor" end
  if target:match("^%a[%w+.-]*:") then return "urlcolor" end
  return "filecolor"
end

-- The headings a table of contents lists: every heading down to depth that
-- is not marked unlisted, in the order they come.
function M.contents_headings(blocks, depth)
  local out = pandoc.List({})
  pandoc.Blocks(blocks):walk {
    Header = function(h)
      if h.level > depth then return nil end
      if h.classes:includes("unlisted") then return nil end
      out:insert(h)
    end
  }
  return out
end

-- Six hex digits, upper cased, for a name or an html code; nil for anything
-- neither table nor code knows, which leaves the format with what it had.
function M.colour_hex(value)
  if value == nil then return nil end
  local name = M.stringify(value):gsub("^%s*(.-)%s*$", "%1")
  if name == "" or name == "false" then return nil end
  local code = name:match("^#(%x%x%x%x%x%x)$")
  if code then return code:upper() end
  local short = name:match("^#(%x%x%x)$")
  if short then
    return (short:upper():gsub("(%x)", "%1%1"))
  end
  return xcolors[name:lower()]
end

-- The page a Temple dissertation or thesis is set on, in inches: 1.5" at the
-- left, where the work is bound, and 1" elsewhere. That is what the Graduate
-- School's handbook asks for, and it says the margins are "the same for the
-- entire manuscript, including front matter", which is why the title page is
-- set on them too. The Graduate School's own title-page template uses 1" all
-- round; the handbook is what the work is held to.
--
-- Kept here because three files need them: the title page is broken against
-- the measure they leave (thesisfrontmatter.lua), the pdf sets them as its
-- geometry, and the .docx takes them from its reference document
-- (docxreferencedoc.lua).
M.thesis_margins = { left = 1.5, right = 1.0, top = 1.0, bottom = 1.0 }
M.thesis_paper_width = 8.5

-- The title page is the exception. The dissertations Temple publishes set
-- theirs on 1" all round, so that the block of it stands at the centre of the
-- page rather than at the centre of a text block pushed right by the binding
-- margin, and that is the page the Graduate School's own template draws. It
-- is one page and it is set on its own, so it takes margins of its own.
M.thesis_title_margins = { left = 1.0, right = 1.0, top = 1.0, bottom = 1.0 }

local function measure(margins)
  return M.thesis_paper_width - margins.left - margins.right
end

function M.thesis_measure()
  return measure(M.thesis_margins)
end

function M.thesis_title_measure()
  return measure(M.thesis_title_margins)
end

-- How many levels of heading a table of contents lists, which is quarto's
-- own toc-depth. Nothing read it before: .html and .docx counted three
-- levels because that is what was written into them, the .pdf three because
-- that is the article class's own, and typst listed every level there was.
-- One reading of the field, so that a contents is the same contents in all
-- four.
--
-- Quarto hands it to pandoc as a writer option rather than leaving it in the
-- metadata --- toc-depth is pandoc's own field, as toc is --- so that is
-- where it is read from, and the metadata is looked at only for a document
-- that puts it there itself. Pandoc's own default is three, so a document
-- that never mentions the field reads three here as well.
function M.toc_depth(meta, fallback)
  local written = nil
  if PANDOC_WRITER_OPTIONS ~= nil then
    written = PANDOC_WRITER_OPTIONS.toc_depth
  end
  if written == nil and meta ~= nil then written = meta["toc-depth"] end
  if written == nil then return fallback end
  local depth = tonumber(M.stringify(written))
  if depth == nil then return fallback end
  depth = math.floor(depth)
  if depth < 1 then return 1 end
  return depth
end

-- The apa-note of each plain markdown table as the writer typed it, by the
-- table's identifier, which markdowntable.lua leaves in the metadata. Quarto
-- rebuilds a markdown table's attributes from its caption, flattening the
-- note's emphasis, code and raw spans, so a note writer asks here first and
-- takes the attribute only for a table that is not listed.
function M.table_notes(meta)
  local notes = {}
  local recovered = meta and meta["apa-table-notes"]
  if recovered then
    for id, note in pairs(recovered) do
      notes[id] = pandoc.utils.stringify(note)
    end
  end
  return notes
end

-- The mark a float carries in apa-note-written once its note has been
-- written, so that no other filter writes it again.
--
-- What is marked is which document the note was written for, not merely that
-- it was written. A manuscript project renders a notebook on its own before
-- the article embeds a cell out of it, and the cell arrives carrying whatever
-- was marked on it during that render -- while the note itself stays behind,
-- since only the cell's output is embedded. A mark that said no more than
-- "written" would silence the article and lose the note altogether. Naming the
-- document tells the two apart: the same mark means the note has been written
-- in this render, a different one means it belongs to another document and has
-- still to be written here.
--
-- The mark is a short digest of the document's path. The path itself would do
-- the job but would also be written into the output, where a reader has no use
-- for someone else's directory names.
M.note_written = "apa-note-written"
local note_mark_value = nil
function M.note_mark()
  if note_mark_value ~= nil then return note_mark_value end
  local ok, input = pcall(function() return quarto.doc.input_file end)
  if not ok or not input or input == "" then
    note_mark_value = "true"
    return note_mark_value
  end
  local hash = 2166136261
  for i = 1, #input do
    hash = (hash ~ input:byte(i)) * 16777619 % 4294967296
  end
  note_mark_value = string.format("%08x", hash)
  return note_mark_value
end

-- Whether a float's note has been written in this render
function M.note_is_written(el)
  return el.attributes ~= nil
    and el.attributes[M.note_written] == M.note_mark()
end

-- A word from meta.language, or the fallback when the document has none.
--
-- apalanguage.lua fills in every word it knows before the other filters read
-- them, so inside the apaquarto formats the fallback is seldom reached. The
-- apanote extension runs a few of these filters without apalanguage.lua,
-- though, so every caller still names the English word it wants.
function M.lang(meta, key, fallback)
  local value = meta and meta.language and meta.language[key]
  if value == nil then return fallback end
  return pandoc.utils.stringify(value)
end

-- The documentmode, as the short code documentmode.lua leaves it in: man,
-- jou, doc, stu or thesis. A document that names none is a manuscript.
function M.mode(meta)
  if meta == nil or meta.documentmode == nil then return "man" end
  return pandoc.utils.stringify(meta.documentmode)
end

-- Whether a yes-or-no field is on. Absent is off, and so is false; anything
-- else the writer put there is taken as asking for it, which is how latex
-- and typst have always read numbered-lines.
function M.flag(meta, key)
  local value = meta and meta[key]
  if value == nil then return false end
  return pandoc.utils.stringify(value) ~= "false"
end

-- Whether an element's attribute says true. Written in markdown it is the
-- string "true"; set from a chunk option it may arrive as a boolean, or as a
-- string with quotes or brackets left on it.
function M.attr_true(el, name)
  -- Not every block has attributes, and asking one that has none may raise.
  local ok, attrs = pcall(function() return el.attributes end)
  if not ok or not attrs then return false end
  local value = attrs[name]
  if value == nil then return false end
  if value == true or tostring(value) == "true" then return true end
  return pandoc.utils.stringify(value):lower():gsub("[^%a]", "") == "true"
end

-- A page break in the format being written, or nil for html, which has no
-- pages. A weak break in typst is dropped when the page is already fresh.
function M.page_break(weak)
  if FORMAT == "docx" then
    return pandoc.RawBlock("openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  elseif FORMAT == "latex" then
    return pandoc.RawBlock("latex", "\\clearpage")
  elseif FORMAT:match("typst") then
    return pandoc.RawBlock("typst", weak and "#pagebreak(weak: true)" or "#pagebreak()\n\n")
  end
  return nil
end

-- Text made safe to put inside raw openxml, where these characters are
-- markup. Word refuses to open a file with an unescaped ampersand in it.
function M.xml_escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- A string without the white space at either end.
function M.trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Inlines in capitals, their markup kept.
function M.upper(inlines)
  return pandoc.Inlines(inlines):walk {
    Str = function(s) return pandoc.Str(pandoc.text.upper(s.text)) end
  }
end

return M

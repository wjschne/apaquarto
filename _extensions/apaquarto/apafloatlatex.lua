if FORMAT ~= "latex" then
  return
end

local utilsapa = require("utilsapa")

local noteword = "Note"

-- from quarto-cli/src/resources/pandoc/datadir/init.lua
-- global quarto params
local paramsJson = quarto.base64.decode(os.getenv("QUARTO_FILTER_PARAMS"))
local quartoParams = quarto.json.decode(paramsJson)
local function param(name, default)
  -- get name from quartoParams, if possible
  local value = quartoParams[name]
  if value == nil then
    -- get name from quartoParams.language, if possible
    if quartoParams.language then
      value = quartoParams.language[name]
    end
    -- If still nil, then assign default
    if value == nil then
      value = default
    end
  end
  return value
end


-- Is the .pdf in journal mode?
local journalmode = false
local manuscriptmode = true
-- A float resets the line spacing, so the note asks for the document's own
-- spacing back. apatemplate.tex defines \apanotespacing.
local notespacing = "\\ifdefined\\apanotespacing\\apanotespacing\\fi "
local noteprefix = notespacing .. "\\noindent\\textit{Note.}"
local beforenote = ""
-- Notes recovered from markdown table captions by apatablenote.lua, keyed by
-- the table identifier. Quarto flattens the note it puts on the table itself.
local tablenotes = {}

-- The note as written, preferring the recovered copy
local function get_note(float)
  return tablenotes[float.identifier] or float.attributes["apa-note"]
end

-- Does the raw latex of the float's content say something about itself?
local function content_says(float, text)
  local found = false
  float.content:walk {
    RawBlock = function(raw)
      if raw.format == "latex" or raw.format == "tex" then
        found = found or raw.text:find(text, 1, true) ~= nil
      end
    end
  }
  return found
end

-- Is the float's content raw latex of its own making?
local function content_is_raw(float)
  local raw = false
  float.content:walk {
    RawBlock = function(block)
      raw = raw or block.format == "latex" or block.format == "tex"
    end
  }
  return raw
end

-- A table pandoc writes, and one flextable writes, are longtables, and a
-- longtable brings its own space above it that the caption has to be pulled
-- back over. A table written as a tabular, as tinytable writes them, has no
-- such space, and the full pull back lifts it alongside its caption.
local function caption_pullback(float)
  if not content_is_raw(float) or content_says(float, "\\begin{longtable") then
    return "-20pt"
  end
  return "-6pt"
end

-- The latex for tbl-align. Table makers centre their tables, so the centring
-- they write is replaced; a longtable is moved with the lengths that hold it.
local alignments = {
  left = { "\\raggedright", "\\setlength\\LTleft{0pt}\\setlength\\LTright{\\fill}" },
  right = { "\\raggedleft", "\\setlength\\LTleft{\\fill}\\setlength\\LTright{0pt}" },
  center = { "\\centering", "\\setlength\\LTleft{\\fill}\\setlength\\LTright{\\fill}" }
}

local function align_content(float)
  local align = alignments[float.attributes["tbl-align"]]
  -- tinytable centres the tables it writes, and apa style wants them flush
  -- left, which is where they already sit in the other formats
  if not align and content_says(float, "\\begin{tblr}") then
    align = alignments.left
  end
  if not align then
    return float.content
  end

  local replaced = false
  local content = float.content:walk {
    RawBlock = function(raw)
      if (raw.format == "latex" or raw.format == "tex") and
        not replaced and raw.text:find("\\centering", 1, true) then
        replaced = true
        return pandoc.RawBlock(raw.format, (raw.text:gsub("\\centering", align[1], 1)))
      end
    end
  }
  if replaced then
    return content
  end
  return pandoc.Blocks({ pandoc.RawBlock("latex", align[2]), content })
end

local getmode = function(meta)
  local documentmode = pandoc.utils.stringify(meta["documentmode"])
  journalmode = documentmode == "jou"
  manuscriptmode = documentmode == "man"
  if meta["apa-table-notes"] then
    for id, note in pairs(meta["apa-table-notes"]) do
      tablenotes[id] = pandoc.utils.stringify(note)
    end
  end
  -- Find word for "note"
  if not meta.language["figure-table-note"] then
    if param("callout-note-title") then
      meta.language["figure-table-note"] = param("callout-note-title")
    end
  end
  noteprefix = notespacing .. "\\noindent \\emph{" .. meta.language["figure-table-note"] .. ".} "
end



-- Split string function
--function string:split(delimiter)
--  local result               = {}
--  local from                 = 1
--  local delim_from, delim_to = string.find(self, delimiter, from)
--  while delim_from do
--    from                 = delim_to + 1
--    delim_from, delim_to = string.find(self, delimiter, from)
--  end
--  table.insert(result, string.sub(self, from))
--  return result
--end

local processfloat = function(float)
  if float.attributes["disable-apaquarto-processing"] then
    if not (float.attributes["disable-apaquarto-processing"] == "false") then
      return float
    end
  end
  -- default float position
  local floatposition = "[!htbp]"
  local p = {}
  local apanotedivs = pandoc.Div(pandoc.Blocks {})
  if float.attributes["fig-pos"] then
    if pandoc.utils.stringify(float.attributes["fig-pos"]) == "false" then
      floatposition = "[!htbp]"
    else
      floatposition = "[" .. float.attributes["fig-pos"] .. "]"
    end
  end

  if float.type == "Table" then
        -- credit to @michaelzehetleitne https://github.com/wjschne/apaquarto/issues/71
        -- Long-table mode: skip float wrapper so longtable can page-break
    --quarto.log.output(float.attributes)
    if float.attributes["apa-longtable"] == "true" and not journalmode then
      local blocks = pandoc.Blocks({})
      -- Use Quarto's native longtable output (caption + label included)
      if float.__quarto_custom_node then
        blocks:insert(float.__quarto_custom_node)
      else
        blocks:insert(float.content)
      end
      -- Append apa-note if present
      if float.attributes["apa-note"] then
        local bn = ""
        if manuscriptmode then
          bn = "\\vspace{-12pt}\n"
          if float.attributes["beforenotespace"] then
            bn = "\\vspace{" .. float.attributes["beforenotespace"] .. "}\n"
          end
        end
        local npfx = pandoc.Span(pandoc.RawInline("latex", bn .. noteprefix))
        blocks:insert(utilsapa.make_note(get_note(float), npfx))
      end
      return pandoc.Div(blocks)
    end
    -- Default table environment
    local latextableenv = "table"
    -- Manuscript spacing before note needs adjustment ment
    if manuscriptmode then
      beforenote = "\\vspace{-12pt}\n"
      if float.attributes["beforenotespace"] then
        beforenote = "\\vspace{" .. float.attributes["beforenotespace"] .. "}\n"
      end
    end
    if journalmode then
      -- No spacing in before note in journalmode
      beforenote = ""
      if float.attributes["beforenotespace"] then
        beforenote = "\\vspace{" .. float.attributes["beforenotespace"] .. "}\n"
      end
      -- Table environment in journal mode
      latextableenv = "ThreePartTable"
    end

    -- Table enironment for apa-twocolumn floats
    if float.attributes then
      if float.attributes["apa-twocolumn"] then
        if float.attributes["apa-twocolumn"] == "true" then
          if journalmode then
            latextableenv = "twocolumntable"
          end
        end
      end
    end

    -- Add note
    if float.attributes["apa-note"] then
      local note_prefix = pandoc.Span(pandoc.RawInline("latex", beforenote .. noteprefix))
      apanotedivs = utilsapa.make_note(get_note(float), note_prefix)
    end

    local captionsubspan = pandoc.Span({
      pandoc.RawInline("latex", "\\label"),
      pandoc.RawInline("latex", "{"),
      pandoc.RawInline("latex", float.identifier),
      pandoc.RawInline("latex", "}")
    })

    -- Adjust space after caption in manuscript mode
    local aftercaption = ""
    if manuscriptmode then
      aftercaption = "\n\\vspace{" .. caption_pullback(float) .. "}"
      if float.attributes["after-caption-space"] then
        aftercaption = "\\vspace{" .. float.attributes["after-caption-space"] .. "}\n"
      end
    end

    -- Make caption
    local captionspan = pandoc.Span({
      pandoc.RawInline("latex", "\\caption"),
      pandoc.RawInline("latex", "{"),
      pandoc.Span(float.caption_long.content),
      captionsubspan,
      pandoc.RawInline("latex", "}" .. aftercaption)

    })


    -- Make table
    local returnblock = pandoc.Div({
      pandoc.RawBlock("latex", "\\begin{" .. latextableenv .. "}"),
      captionspan,
      align_content(float)

    }
    )
    returnblock.content:extend({ apanotedivs })


    returnblock.content:extend({ pandoc.RawBlock("latex", "\\end{" .. latextableenv .. "}") })

    if journalmode then
      returnblock = pandoc.Div({
        pandoc.RawBlock("latex", "\\begin{" .. latextableenv .. "}"),
        float.__quarto_custom_node,
        apanotedivs,
        pandoc.RawBlock("latex", "\\end{" .. latextableenv .. "}")
      })
    end

    return returnblock
  end

  if float.type == "Figure" then
    -- Don't wrap sub-figures in their own figure environment (nested figure
    -- environments are illegal in latex); render natively and append the note
    if float.parent_id then
      if float.attributes["apa-note"] then
        local subbeforenote = ""
        float.content:walk {
          Image = function(img)
            if img.attributes["beforenotespace"] then
              subbeforenote = "\\vspace{" .. img.attributes["beforenotespace"] .. "}\n"
            end
          end
        }
        local note_prefix = pandoc.Span(pandoc.RawInline("latex", subbeforenote .. noteprefix))
        local subnote = utilsapa.make_note(float.attributes["apa-note"], note_prefix)
        local newcontent = pandoc.Blocks(float.content)
        newcontent:insert(subnote)
        float.content = newcontent
      end
      return float
    end
    local hasnote = false
    local apanote
    local twocolumn = false
    local latexenv = "figure"
    -- Get apa-note from image, if possible
    float.content:walk {
      Image = function(img)
        if img.attributes["apa-note"] then
          hasnote = true
          apanote = img.attributes["apa-note"]
        end

        if img.attributes["beforenotespace"] then
          beforenote = "\\vspace{" .. img.attributes["beforenotespace"] .. "}\n"
        end
        if img.attributes["apa-twocolumn"] then
          if img.attributes["apa-twocolumn"] == "true" then
            if journalmode then
              twocolumn = true
            end
          end
        end
      end
    }

    if twocolumn then
      latexenv = "figure*"
    end

    -- A figure built out of sub-figures is laid out by quarto itself, in the
    -- grid that layout-ncol and friends ask for. Wrapping it in a figure
    -- environment by hand, the way a single figure is handled below, replaces
    -- the float with a plain div, and quarto never gets to build that grid:
    -- the panels come out stacked one per row. Hand it back instead. Its
    -- panels' notes are attached by the sub-figure branch above, and a note
    -- belonging to the whole figure by floatwithsubfigure.lua, so there is
    -- nothing left here but the caption. A float that spans both columns
    -- still needs figure*, which only the hand-built wrapper can give it, so
    -- that one goes the long way round.
    if float.attributes.hassubfigs and not twocolumn then
      -- Quarto writes no \caption for a laid-out float whose caption is
      -- empty, and the \label goes with it: the figure ends up unnumbered and
      -- every reference to it renders as "Figure ??". An empty raw inline is
      -- caption enough to bring both back.
      if float.caption_long == nil then
        float.caption_long = pandoc.Plain({ pandoc.RawInline("latex", "") })
      elseif #float.caption_long.content == 0 then
        float.caption_long.content = pandoc.Inlines({ pandoc.RawInline("latex", "") })
      end
      return float
    end

    -- Make note
    if hasnote or twocolumn then
      if hasnote then
        -- Add note
        if float.attributes["apa-note"] then
          local note_prefix = pandoc.Span(pandoc.RawInline("latex", beforenote .. noteprefix))
          apanotedivs = utilsapa.make_note(get_note(float), note_prefix)
        end
      end

      local captionsubspan = pandoc.Span({
        pandoc.RawInline("latex", "\\label"),
        pandoc.RawInline("latex", "{"),
        pandoc.Str(float.identifier),
        pandoc.RawInline("latex", "}")
      })

      local captionspan = pandoc.Span({
        pandoc.RawInline("latex", "\\caption"),
        pandoc.RawInline("latex", "{"),
        pandoc.Span(float.caption_long.content),
        captionsubspan,
        pandoc.RawInline("latex", "}")
      })

      if float.attributes.prefix ~= "" then
        floatposition = ""
      end

      -- splice content as Blocks (a layout figure's content is a list, not a Block)
      local returnblock = pandoc.Div({
        pandoc.RawBlock("latex", "\\begin{" .. latexenv .. "}" .. floatposition),
        captionspan
      })
      returnblock.content:extend(pandoc.Blocks(float.content))
      returnblock.content:insert(apanotedivs)
      returnblock.content:insert(pandoc.RawBlock("latex", "\\end{" .. latexenv .. "}"))

      return returnblock
    end
  end
end


return {
  { Meta = getmode },
  { FloatRefTarget = processfloat }
}

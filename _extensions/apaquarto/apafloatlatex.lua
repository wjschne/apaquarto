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
local noteprefix = "\\noindent \\emph{Note.} "
local beforenote = ""
local getmode = function(meta)
  local documentmode = pandoc.utils.stringify(meta["documentmode"])
  journalmode = documentmode == "jou"
  manuscriptmode = documentmode == "man"
    -- Find word for "note"
  if not meta.language["figure-table-note"] then
    if param("callout-note-title") then
      meta.language["figure-table-note"] = param("callout-note-title")
    end
  end
  noteprefix = "\\noindent \\emph{" .. meta.language["figure-table-note"] .. ".} "
  
end



-- Split string function
function string:split(delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
    from  = delim_to + 1
    delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from  ) )
  return result
end

local processfloat = function(float)
  if float.attributes["disable-apaquarto-processing"] then
    
    if not (float.attributes["disable-apaquarto-processing"] == "false") then
      
      return float
    end
  end
  -- default float position
  local floatposition = "[!htbp]"
  local p = {}
  local apanotedivs = pandoc.Div(pandoc.Blocks{})
  if float.attributes["fig-pos"] then
    if pandoc.utils.stringify(float.attributes["fig-pos"]) == "false" then
      floatposition = "[!htbp]"
    else
      floatposition = "[" .. float.attributes["fig-pos"] .. "]"
    end
  end
  
  if float.type == "Table" then
    -- Default table environment
    local latextableenv = "table"
    -- Manuscript spacing before note needs adjustment ment
    if manuscriptmode then
      beforenote = "\\vspace{-20pt}\n"
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
        note_prefix = pandoc.Span(pandoc.RawInline("latex", beforenote .. noteprefix))
        apanotedivs =  utilsapa.make_note(float.attributes["apa-note"], note_prefix)
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
        aftercaption = "\n\\vspace{-20pt}"
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
        float.content
        
      }
      )
      returnblock.content:extend({apanotedivs})

      
      returnblock.content:extend({pandoc.RawBlock("latex", "\\end{" .. latextableenv .. "}")})
      
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
           twocolumn = true
         end
        end
      end
    }
    
    if twocolumn then
      latexenv = "figure*"
    end 
    
    -- Make note
    if hasnote or twocolumn then
      if hasnote then
        -- Add note
        if float.attributes["apa-note"] then
            note_prefix = pandoc.Span(pandoc.RawInline("latex", beforenote .. noteprefix))
           apanotedivs =  utilsapa.make_note(float.attributes["apa-note"], note_prefix)
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
  
      local returnblock = pandoc.Div({
        pandoc.RawBlock("latex", "\\begin{" .. latexenv .. "}" .. floatposition),
        captionspan,
        float.content,
        apanotedivs,
        pandoc.RawBlock("latex", "\\end{" .. latexenv .. "}")
      })
  
      return returnblock
    end
    
  end
end


return {
{ Meta = getmode },
{ FloatRefTarget = processfloat }
}
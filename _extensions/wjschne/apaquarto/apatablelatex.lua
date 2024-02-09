if FORMAT ~= "latex" then
  return 
end
local journalmode = false
local getmode = function(meta)
  local documentmode = pandoc.utils.stringify(meta["documentmode"])
  journalmode = documentmode == "jou"
end

function string:split(delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( self, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from  ) )
  return result
end

local processfloat = function(float)
    local p = {}
  if float.type == "Table" then

    
    local beforenote = "\\vspace{-20pt}\n"
    if journalmode then
      beforenote = ""
    end

    if float.attributes["apa-note"] then

      p = pandoc.Span({
        pandoc.RawInline("latex", beforenote .. "\\noindent \\emph{Note.} "),
        float.attributes["apa-note"]
      })
    end
      
      local captionsubspan = pandoc.Span({
        pandoc.RawInline("latex", "\\label"),
        pandoc.RawInline("latex", "{"),
        pandoc.Str(float.identifier),
        pandoc.RawInline("latex", "}")
      })
      --captionsubspan.classes:insert("quarto-scaffold")
      
      local aftercaption = "\n\\vspace{-20pt}"
      if journalmode then
        aftercaption = ""
      end
      


      local captionspan = pandoc.Span({
        pandoc.RawInline("latex", "\\caption"),
        pandoc.RawInline("latex", "{"),
        pandoc.Span(float.caption_long.content),
        captionsubspan,
        pandoc.RawInline("latex", "}" .. aftercaption)
        
      })
      --captionspan.classes:insert("quarto-scaffold")

     
      local returnblock = pandoc.Div({
        pandoc.RawBlock("latex", "\\begin{table}"),
        captionspan,
        float.content,
        p,
        pandoc.RawBlock("latex", "\\end{table}")
      }
      )
      
      if journalmode then
        
        returnblock = pandoc.Div({
          pandoc.RawBlock("latex", "\\begin{ThreePartTable}"),
          float.__quarto_custom_node,
          p,
          pandoc.RawBlock("latex", "\\end{ThreePartTable}")
        })
    
      end
      
      return returnblock
  end
    
    if float.type == "Figure" then
      local hasnote = false
      local apanote
      float.content:walk {
        Image = function(img)
          if img.attributes["apa-note"] then
            hasnote = true
            apanote = img.attributes["apa-note"] 
          end
        end
      }

      
      if hasnote then

      p = pandoc.Span(pandoc.RawInline("latex", "\\noindent \\emph{Note.} "))
      local apanotestr = quarto.utils.string_to_inlines(apanote)
      for i, v in ipairs(apanotestr) do
        p.content:insert(v)
      end

      -- p.content:insert()

    
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
    
    local returnblock = pandoc.Div({
        pandoc.RawBlock("latex", "\\begin{figure}"),
        captionspan,
        float.content,
        p,
        pandoc.RawBlock("latex", "\\end{figure}")
      })
    
      return returnblock
    end
  end
end
    
    



return {
{ Meta = getmode },
{ FloatRefTarget = processfloat }
}
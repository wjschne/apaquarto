-- This filter creates prefixes for figures and tables in appendices.

-- List of appendix names
local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- Default prefix
local prefix = ""
-- Default pre-prefex if appendices exceed 26
local preprefix = ""
-- Prefix counter
local intprefix = 0
-- Pre-prefix counter
local intpreprefix = 0
-- Table counter
local tblnum = 0
-- Figure counter
local fignum = 0
-- Appendix counter
local appnum = 0
-- Table table
local tbl = {}
-- Figure table
local fig = {}
-- New style already used
local newsppendixstyle = true

-- Word for appendix
local appendixword = "Appendix"
getappendixword = function(meta)
  if meta.language and meta.language["crossref-apx-prefix"] then
    appendixword = pandoc.utils.stringify(meta.language["crossref-apx-prefix"])
  end
end


-- return table number associated with id
local tbllabel = function(id)
  if id ~= "" then
    -- Is id in tbl?
    if tbl[id] then
      -- Do nothing
    else
      -- Add id to tbl
      tblnum = tblnum + 1
      tbl[id] = tblnum
    end
    return tbl[id]
  end
end

-- return figure number associated with id
local figlabel = function(id, ss)
  if id ~= "" then
    -- Is id in fig?
    if fig[id] then
      -- Do nothing
    else
      if ss then
        -- Add id to fig
        fig[id] = fignum .. ss
      else
        -- increment fignum
        fignum = fignum + 1
        -- Add id to fig
        fig[id] = fignum
      end
      
      
      
    end
  end
 
  return fig[id]
end



local walkblock = function(b)
  -- Increment prefix for every level-1 header starting with Appendix
  
  if b.tag == "Header" and b.level == 1 then
    
    local headerfirstword = pandoc.utils.stringify(b.content[1])
    if headerfirstword == appendixword or headerfirstword == "Appendix"  or (b.identifier and b.identifier:find("^apx%-")) then
      
      if (headerfirstword == appendixword or headerfirstword == "Appendix") and  newsppendixstyle then
        print("This style of creating appendices is deprecated:\n\n# Appendix A\n\n#Relationship Descriptive Scale\n\nInstead, use a single descriptive level-1 heading,\nfollowed by a an identifier with the apx prefix:\n\n# Relationship Description Scale {@apx-relationship}\n")
        newsppendixstyle = false
      end
      
      
    appnum = appnum + 1
    if intprefix == 26 then
      intprefix = 0
      intpreprefix = intpreprefix + 1
      preprefix = preprefix .. pandoc.text.sub(abc,intpreprefix,intpreprefix)
    end
    intprefix = intprefix + 1
    tblnum = 0
    fignum = 0
    prefix = preprefix .. pandoc.text.sub(abc,intprefix,intprefix)
    if b.attr then
      b.attr.attributes.appendixtitle = prefix
    end
    end
end

  -- Assign prefixes and numbers
  if b.identifier then    
        
    if b.identifier:find("^tbl%-") then
      b.attributes.prefix = prefix
      b.attributes.tblnum = tbllabel(b.identifier)
    else
     
      if b.identifier:find("^fig%-") then
        

          b.attributes.prefix = prefix
          b.attributes.fignum = figlabel(b.identifier)
        b.content:walk {
            Image = function(img)
              img.attributes.prefix = prefix
              img.attributes.fignum = figlabel(b.identifier)
            end
          }
          

        
        local subfigcount = 0
        
                 -- Find subfigures
        b.content:walk {
          Block = function(bb)
            if bb.identifier then
              if bb.identifier:find("^fig%-") then
                subfigcount = subfigcount + 1
                b.attributes.hassubfigs = "true"
                bb.attributes.prefix = prefix
                bb.attributes.subfigscript = pandoc.text.sub(abc,subfigcount,subfigcount)
                bb.attributes.fignum = figlabel(bb.identifier, bb.attributes.subfigscript)
              end
            end
          end
        }

      else
        
        b:walk {
          Figure = function(fg)
            if fg.identifier then
              if fg.identifier:find("^fig%-") then
                fg.attributes.prefix = prefix
                fg.attributes.fignum = figlabel(fg.identifier)
                fg.content:walk {
                  Image = function(img)
                    img.attributes.prefix = prefix
                    img.attributes.fignum = figlabel(fg.identifier)
                  end
                  }
              end
            end
          end
            }
    end
    end
    
    if b.identifier:find("^apx%-") then
      local a = pandoc.Header(1,  appendixword .. " " .. prefix)
        return pandoc.List({a,b})
      else
        return b
    end
    
  end
end



local filter = {traverse = 'topdown',
  Meta = getappendixword,
  Block = walkblock
  }

return filter
  


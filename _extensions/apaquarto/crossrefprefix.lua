-- This filter creates prefixes for figures and tables in appendices.
--
-- It is also the one place that decides what an appendix is. Everything after
-- it reads what it leaves rather than looking at heading text again:
--
--   * the heading it writes over each appendix, "Appendix A", carries the
--     class apa-appendix (kAppendixClass below);
--   * the heading of the appendix itself carries appendixtitle, its letter;
--   * meta["apa-appendix-count"] is how many appendices there are;
--   * meta["apa-float-labels"] maps each float's identifier to the number a
--     reader sees, "A1" or "3", for the filter that writes cross references.
--
-- When there is only one appendix it is called "Appendix", with no letter.
-- That is settled here too, once the count is known.

local utilsapa = require("utilsapa")

local kAppendixClass = "apa-appendix"

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
-- Float kinds of the document's own, such as ill for an Illustration, each
-- with its own count, which starts again in every appendix
local customkinds = {}
local customnum = {}
local custom = {}
-- The number a reader sees for each float, appendix letter and all, by
-- identifier: what apafigtblappendix.lua writes into a cross reference
local labels = {}

-- Word for appendix
local appendixword = "Appendix"
local referenceword = "References"
local getappendixword = function(meta)
  appendixword = utilsapa.lang(meta, "crossref-apx-prefix", appendixword)
  referenceword = utilsapa.lang(meta, "section-title-references", referenceword)
  for kind in pairs(utilsapa.float_prefixes(meta)) do
    if kind ~= "fig" and kind ~= "tbl" then
      customkinds[kind] = true
    end
  end
end

-- The kind of a float of the document's own, from its identifier, or nil
local function custom_kind(id)
  local kind = id and id:match("^(%a+)%-")
  if kind and customkinds[kind] then return kind end
  return nil
end

-- return the number of a float of the document's own kind
local customlabel = function(id)
  if custom[id] == nil then
    local kind = custom_kind(id)
    customnum[kind] = (customnum[kind] or 0) + 1
    custom[id] = customnum[kind]
    labels[id] = prefix .. custom[id]
  end
  return custom[id]
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
      labels[id] = prefix .. tblnum
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

  if fig[id] ~= nil and labels[id] == nil then
    labels[id] = prefix .. fig[id]
  end
  return fig[id]
end


local after_reference = false
-- The older way of writing an appendix is "# Appendix A" over a heading of
-- its own: the first is the label, the second the title, and the two are one
-- appendix. After such a label, the next level-one heading is its title.
local awaiting_title = false
local walkblock = function(b)
  -- Whether an "Appendix X" heading is written over this one. Not over the
  -- label of the older style, which is one already, nor over its title.
  local write_label = true
  
  if b.tag == "Div" and b.identifier and b.identifier:find("^apx%-") then
    after_reference = true
    return nil
  end
  
  
  -- Increment prefix for every level-1 header after References
  if b.tag == "Header" and b.level == 1 then
    local headerfirstword = pandoc.utils.stringify(b.content[1])
    if headerfirstword == referenceword or headerfirstword == "References" then
      after_reference = true
      return nil
    end
    -- An older-style label is "Appendix" or "Appendix A" written as a
    -- heading of its own. A heading given an apx identifier is a new-style
    -- appendix whatever its title begins with.
    local is_label = (headerfirstword == appendixword or headerfirstword == "Appendix")
      and not (b.identifier and b.identifier:find("^apx%-"))
    if awaiting_title and not is_label then
      -- The title under an older-style label: the same appendix, so it takes
      -- the letter the label took rather than one of its own.
      awaiting_title = false
      write_label = false
      if not (b.identifier and b.identifier:find("^apx%-")) then
        b.identifier = "apx-" .. b.identifier
      end
      b.attr.attributes.appendixtitle = prefix
    elseif is_label or (b.identifier and b.identifier:find("^apx%-")) or after_reference then
      after_reference = true
      awaiting_title = is_label
      write_label = not is_label
      if not (b.identifier and b.identifier:find("^apx%-")) then
        b.identifier = "apx-" .. b.identifier
      end
      
      -- The label of the older style opens the appendix itself, and is
      -- marked as the heading that does, since no "Appendix X" is written
      -- over it.
      if is_label then
        b.classes:insert(kAppendixClass)
      end
      if is_label and newsppendixstyle then
        quarto.log.warning(
        "This style of creating appendices is deprecated:\n\n# Appendix A\n\n#Relationship Descriptive Scale\n\nInstead, use a single descriptive level-1 heading,\nfollowed by a an identifier with the apx prefix:\n\n# Relationship Description Scale {#apx-relationship}\n")
        newsppendixstyle = false
      end


      appnum = appnum + 1
      if intprefix == 26 then
        intprefix = 0
        intpreprefix = intpreprefix + 1
        preprefix = preprefix .. pandoc.text.sub(abc, intpreprefix, intpreprefix)
      end
      intprefix = intprefix + 1
      tblnum = 0
      fignum = 0
      customnum = {}
      prefix = preprefix .. pandoc.text.sub(abc, intprefix, intprefix)
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
    elseif custom_kind(b.identifier) then
      b.attributes.prefix = prefix
      b.attributes.floatnum = customlabel(b.identifier)
      local id = b.identifier
      b.content:walk {
        Image = function(img)
          img.attributes.prefix = prefix
          img.attributes.floatnum = customlabel(id)
        end
      }
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
                bb.attributes.subfigscript = pandoc.text.sub(abc, subfigcount, subfigcount)
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

    if b.identifier:find("^apx%-") and write_label then
      local a = pandoc.Header(1, appendixword .. " " .. prefix)
      a.classes:insert(kAppendixClass)
      return pandoc.List({ a, b })
    else
      return b
    end
  end
end



-- What the walk found, left for the filters after this one.
local function publish(doc)
  local published = {}
  for id, label in pairs(labels) do
    published[id] = pandoc.MetaString(label)
  end
  doc.meta["apa-appendix-count"] = pandoc.MetaString(tostring(appnum))
  doc.meta["apa-float-labels"] = pandoc.MetaMap(published)

  -- One appendix is "Appendix", not "Appendix A". The older way of writing
  -- one, "# Appendix A" over the text, is caught by its words, since it is the
  -- writer's own heading and carries no class.
  if appnum == 1 then
    local lone = appendixword .. " A"
    doc.blocks = doc.blocks:walk {
      Header = function(h)
        if h.level ~= 1 then return nil end
        local text = pandoc.utils.stringify(h.content)
        if h.classes:includes(kAppendixClass)
            or text == lone or text == "Appendix A" then
          h.content = pandoc.Inlines({ h.content[1] })
          return h
        end
      end
    }
  end
  return doc
end

-- The words are read in a pass of their own, so that they are known before
-- the first heading is looked at.
return {
  { Meta = getappendixword },
  { traverse = 'topdown', Block = walkblock },
  { Pandoc = publish },
}

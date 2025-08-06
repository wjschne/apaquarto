if FORMAT == "latex" then
  return
end

local i = 1
local tbl = {}
local fig = {}
local app = {}
local kAriaExpanded = "aria-expanded"
-- Get names for Figure and Table in language specified in lang field
local figureword = "Figure"
local tableword = "Table"
local appendixword = "Appendix"
local refhyperlinks = true
local appendixcount = 0

local function gettablefig(m)
  -- Get names for Figure and Table specified in language field
  if m.language then
    if m.language["crossref-fig-title"] then
      figureword = pandoc.utils.stringify(m.language["crossref-fig-title"])
    end

    if m.language["crossref-tbl-title"] then
      tableword = pandoc.utils.stringify(m.language["crossref-tbl-title"])
    end

    if m.language and m.language["crossref-apx-prefix"] then
      appendixword = pandoc.utils.stringify(m.language["crossref-apx-prefix"])
    end
  else

  end

  if m["ref-hyperlink"] == false then
    refhyperlinks = false
  end

  -- Create arrays with figure and table information
  while quarto._quarto.ast.custom_node_data[tostring(i)] do
    float = quarto._quarto.ast.custom_node_data[tostring(i)]
    --Is the float a table?
    if float.identifier and string.find(float.identifier, "^tbl%-") then
      -- is the table already in the array?
      if tbl[float.identifier] then
        -- Table is already in the array. Do not add.
      else
        --Add table to array
        tbl[float.identifier] = float.attributes.prefix .. float.attributes.tblnum
      end
    end
    --Is the float a figure?
    if float.identifier and string.find(float.identifier, "^fig%-") then
      -- is the figure already in the array?
      if fig[float.identifier] then
        -- Figure is already in the array. Do not add.
      else
        --Add figure to array
        fig[float.identifier] = float.attributes.prefix .. float.attributes.fignum
      end
    end
    i = i + 1
  end
end

local function getappendix(h)
  if h.attr.attributes.appendixtitle then
    app[h.identifier] = h.attr.attributes.appendixtitle
    appendixcount = appendixcount + 1
  end
end


local function figtblconvert(ct)
  local floatreftext
  --Is the citation a reference to a table?
  if #ct.citations == 1 and string.find(ct.citations[1].id, "^tbl%-") then
    if tbl[ct.citations[1].id] then
      -- Text for table reference
      floatreftext = pandoc.Inlines({ pandoc.Str(tableword), pandoc.Str('\u{a0}'), pandoc.Str(tbl[ct.citations[1].id]) })
    end
  end
  --Is the citation a reference to a figure?
  if #ct.citations == 1 and string.find(ct.citations[1].id, "^fig%-") then
    -- Text for figure reference
    if fig[ct.citations[1].id] then
      floatreftext = pandoc.Inlines({ pandoc.Str(figureword), pandoc.Str('\u{a0}'), pandoc.Str(fig[ct.citations[1].id]) })
    end
  end

  --Is the citation a reference to a section?
  if #ct.citations == 1 and string.find(ct.citations[1].id, "^sec%-") and app[ct.citations[1].id] then
    -- Text for section reference
    if appendixcount == 1 then
      floatreftext = pandoc.Inlines({ pandoc.Str(appendixword) })
    else
      floatreftext = pandoc.Inlines({ pandoc.Str(appendixword), pandoc.Str('\u{a0}'), pandoc.Str(app[ct.citations[1].id]) })
    end
  end


  --Is the citation a reference to a table or figure?
  if #ct.citations == 1 and string.find(ct.citations[1].id, "^fig%-") or string.find(ct.citations[1].id, "^tbl%-") or string.find(ct.citations[1].id, "^sec%-") then
    if floatreftext == nil then
      quarto.log.warning("Cannot find @" .. ct.citations[1].id)
      return floatreftext
    end
    if refhyperlinks then
      -- create link
      local reflink = pandoc.Link(floatreftext, "#" .. ct.citations[1].id)
      reflink.classes = { "quarto-xref" }
      reflink.attributes[kAriaExpanded] = "false"
      return reflink
    else
      return floatreftext
    end
  end
end


return {
  { Meta = gettablefig },
  { Header = getappendix },
  { Cite = figtblconvert }
}

-- Moves the floats to the end when floatsintext is false, in every format.
--
-- Tables go first and then figures, which is the order APA asks for. A float
-- of the document's own kind, such as an Illustration, goes with the figures.
-- A float inside an appendix stays there: crossrefprefix.lua has given it the
-- appendix letter as its prefix, and only a float with no prefix is in the
-- body.

local utilsapa = require("utilsapa")

-- The class crossrefprefix.lua gives the heading it writes over each appendix
local kAppendixClass = "apa-appendix"

-- Is this the heading that opens an appendix?
local function opens_appendix(block)
  return block ~= nil and block.tag == "Header" and block.level == 1
    and block.classes:includes(kAppendixClass)
end

-- A float still in the body, rather than in an appendix
local function in_body(block)
  return block.attributes ~= nil and block.attributes.prefix == ""
end

Pandoc = function(doc)
  local tbl = {}
  local fig = {}
  local movefloatstoend = true
  local documentmode = utilsapa.mode(doc.meta)
  local prefixes = utilsapa.float_prefixes(doc.meta)


  -- floatsintext always has a value: _extension.yml sets it to true for every
  -- format, and a document may set it to false. Test for nil, not
  -- truthiness: a YAML `false` arrives as Lua false.
  if doc.meta.floatsintext ~= nil
      and pandoc.utils.stringify(doc.meta.floatsintext) == "true" then
    movefloatstoend = false
  end

  -- Take the block at i out of the body and onto the front of list, each on a
  -- page of its own in the formats that have pages. Latex is left to place a
  -- float itself.
  local function take(list, i)
    if FORMAT ~= "latex" then
      local pagebreak = utilsapa.page_break(true)
      if pagebreak then table.insert(list, 1, pagebreak) end
    end
    table.insert(list, 1, doc.blocks[i])
    doc.blocks:remove(i)
  end

  if movefloatstoend then
    for i = #doc.blocks, 1, -1 do
      local block = doc.blocks[i]
      local kind = block.identifier and block.identifier:match("^(%a+)%-")
      if kind == "tbl" then
        if in_body(block) then take(tbl, i) end
      elseif kind and prefixes[kind] then
        if in_body(block) then take(fig, i) end
      elseif block.identifier then
        -- A figure inside a block of some other kind, such as the div a code
        -- cell leaves around its output, moves along with that block.
        local hasfig = false
        block:walk {
          Figure = function(fg)
            local inner = fg.identifier and fg.identifier:match("^(%a+)%-")
            if inner and inner ~= "tbl" and prefixes[inner] and in_body(fg) then
              hasfig = true
            end
          end
        }
        if hasfig then take(fig, i) end
      end
    end
  end


  -- Insert page breaks for each appendix in docx, typst and latex
  -- html does not need page breaks
  -- latex had been left out, on the understanding that the apa7 class
  -- opened the page itself. The pdf stopped being built with that class in
  -- 6.0.0 and nothing took the work over, so an appendix ran on from
  -- whatever came before it while docx and typst each began a page.
  -- Journal mode is a published article, which runs continuously: starting each
  -- appendix on a fresh page is a manuscript-submission convention, and in two
  -- columns it would strand most of a page. So jou gets no appendix breaks.
  if (FORMAT == "docx" or FORMAT == "typst" or FORMAT == "latex")
      and documentmode ~= "jou" then
    for i = #doc.blocks, 1, -1 do
      -- One heading opens each appendix, the older way of writing one --
      -- "# Appendix A" over a title of its own -- included: crossrefprefix.lua
      -- marks the label and not the title, so nothing comes between them.
      if opens_appendix(doc.blocks[i]) then
        table.insert(doc.blocks, i, utilsapa.page_break(true))
      end
    end
  end

  if movefloatstoend then
    -- Find block where appendices begin
    local appendixblock = 0
    for i = 1, #doc.blocks, 1 do
      if opens_appendix(doc.blocks[i]) then
        appendixblock = i
        break
      end
    end

    -- If there are no appendices, insert figures and tables at the end
    if appendixblock == 0 then
      if #tbl > 0 then
        doc.blocks:extend(tbl)
      end
      if #fig > 0 then
        doc.blocks:extend(fig)
      end
    else
      -- Insert figures and tables before appendices
      if #fig > 0 then
        for i = #fig, 1, -1 do
          doc.blocks:insert(appendixblock, fig[i])
        end
      end
      if #tbl > 0 then
        for i = #tbl, 1, -1 do
          doc.blocks:insert(appendixblock, tbl[i])
        end
      end
    end
  end

  return doc
end

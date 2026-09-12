if FORMAT == "latex" then
  return
end
Pandoc = function(doc)
  local tbl = {}
  local fig = {}
  local appendixword = "Appendix"
  local movefloatstoend = true
  local documentmode = doc.meta.documentmode and
    pandoc.utils.stringify(doc.meta.documentmode) or "man"
  if doc.meta.language and doc.meta.language["crossref-apx-prefix"] then
    appendixword = pandoc.utils.stringify(doc.meta.language["crossref-apx-prefix"])
  end


  -- An explicit floatsintext (true OR false) is an override and must win. Test
  -- for nil, not truthiness: a YAML `false` arrives as Lua false, so the old
  -- `if doc.meta.floatsintext` treated `floatsintext: false` as unset and let
  -- the journal default below override it.
  if doc.meta.floatsintext ~= nil then
    if pandoc.utils.stringify(doc.meta.floatsintext) == "true" then
      movefloatstoend = false
    end
  elseif FORMAT == "typst" then
    -- Journal (published-article) and document (continuous, LaTeX-article-like)
    -- modes place figures and tables inline by default, unless the author sets
    -- floatsintext. This matches the .pdf side, where these modes also keep
    -- floats in place; manuscript (man) and student (stu) modes keep the
    -- submission convention of collecting floats at the end.
    if documentmode == "jou" or documentmode == "doc" then
      movefloatstoend = false
    end
  end


  if movefloatstoend then
    for i = #doc.blocks, 1, -1 do
      if doc.blocks[i].identifier then
        if doc.blocks[i].identifier:find("^tbl%-") then
          if doc.blocks[i].attributes and doc.blocks[i].attributes.prefix == "" then
            if FORMAT == "docx" then
              table.insert(tbl, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
            end
            if FORMAT == "typst" then
              table.insert(tbl, 1, pandoc.RawBlock('typst', '#pagebreak(weak: true)'))
            end
            table.insert(tbl, 1, doc.blocks[i])
            doc.blocks:remove(i)
          end
        else
          if doc.blocks[i].identifier:find("^fig%-") then
            if doc.blocks[i].attributes and doc.blocks[i].attributes.prefix == "" then
              if FORMAT == "docx" then
                table.insert(fig, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
              end
              if FORMAT == "typst" then
                table.insert(fig, 1, pandoc.RawBlock('typst', '#pagebreak(weak: true)'))
              end
              table.insert(fig, 1, doc.blocks[i])
              doc.blocks:remove(i)
            end
          else
            local hasfig = false
            doc.blocks[i]:walk {
              Figure = function(fg)
                if fg.identifier then
                  if fg.identifier:find("^fig%-") then
                    if fg.attributes and fg.attributes.prefix == "" then
                      hasfig = true
                    end
                  end
                end
              end
            }
            if hasfig then
              if FORMAT == "docx" then
                table.insert(fig, 1, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
              end
              if FORMAT == "typst" then
                table.insert(fig, 1, pandoc.RawBlock('typst', '#pagebreak(weak: true)'))
              end
              table.insert(fig, 1, doc.blocks[i])
              doc.blocks:remove(i)
              hasfig = false
            else

            end
          end
        end
      end
    end
  end


  -- Insert page breaks for each appendix in docx and typst
  -- html does not need page breaks, and latex inserts pagebreaks automatically
  -- Journal mode is a published article, which runs continuously: starting each
  -- appendix on a fresh page is a manuscript-submission convention, and in two
  -- columns it would strand most of a page. So jou gets no appendix breaks.
  if (FORMAT == "docx" or FORMAT == "typst") and documentmode ~= "jou" then
    for i = #doc.blocks, 1, -1 do
      if doc.blocks[i].tag == "Header" then
        if doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == appendixword then
          if FORMAT == "docx" then
            table.insert(doc.blocks, i, pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'))
          end
          if FORMAT == "typst" then
            table.insert(doc.blocks, i, pandoc.RawBlock('typst', '#pagebreak(weak: true)'))
          end
        end
      end
    end
  end

  if movefloatstoend then
    -- Find block where appendices begin
    local appendixblock = 0
    for i = 1, #doc.blocks, 1 do
      if doc.blocks[i].tag == "Header" then
        if doc.blocks[i].level == 1 and doc.blocks[i].content[1].text == appendixword and appendixblock == 0 then
          appendixblock = i
        end
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

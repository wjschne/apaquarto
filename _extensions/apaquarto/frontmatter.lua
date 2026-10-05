-- Handles the frontmatter in every format: .html, .docx, typst and the pdf.
--
-- The pdf was built on the apa7 class until 6.0.0 and this filter stood down
-- for it, the class laying out the title page itself. It does not any more,
-- so every format is built out of the same blocks.


local andreplacement = "and"



local List = require 'pandoc.List'
local utilsapa = require("utilsapa")
local layout = require("frontmatterlayout")
local stringify = utilsapa.stringify

-- The paragraphs of an abstract or an impact statement, as the two divs the
-- stylesheets and the reference document expect: the first paragraph on its
-- own, flush left, and the rest under a style that indents them.
--
-- The text arrives in one of two shapes. Written in the yaml under a block
-- scalar it comes as line blocks, a paragraph to a line; written as a section
-- of the document, which abstractsection.lua allows, it comes as ordinary
-- paragraphs. Both are read here so that neither way of writing it is second
-- best.
local function paragraph_divs(blocks)
  local rest = pandoc.Div({})
  local first = pandoc.Div({})
  local counter = 1
  -- typst indents the first paragraph itself, so nothing is set apart for it
  -- and the count starts past it.
  if FORMAT == "typst" then
    counter = 2
  end

  local function add(para)
    if counter == 1 then
      first.content:extend({ para })
      first.classes:insert("AbstractFirstParagraph")
    else
      rest.content:extend({ para })
      if counter == 2 then
        rest.classes:insert("Abstract")
      end
    end
    counter = counter + 1
  end

  local has_lines = false
  blocks:walk { LineBlock = function() has_lines = true end }

  if has_lines then
    blocks:walk {
      LineBlock = function(lb)
        lb:walk {
          traverse = "topdown",
          Inlines = function(el)
            add(pandoc.Para(el))
            return el, false
          end
        }
      end
    }
  else
    for _, block in ipairs(blocks) do
      if block.t == "Para" or block.t == "Plain" then
        add(pandoc.Para(block.content))
      elseif block.t ~= "Header" then
        -- Anything else -- a block quote, a list -- is kept whole rather than
        -- taken apart, and counts as a paragraph for the styling above.
        add(block)
      end
    end
  end

  local out = pandoc.List({})
  if counter > 1 then out:insert(first) end
  if counter > 2 then out:insert(rest) end
  return out
end

local function get_and(m)
  if m.language and m.language["citation-last-author-separator"] then
    andreplacement = stringify(m.language["citation-last-author-separator"])
  end
end

-- A count of blank lines, from a field such as blank-lines-above-title: a
-- whole number of none or more, or the fallback when the field is absent. A
-- value that is not a number is warned about and the fallback used.
local function blank_lines(value, field, fallback)
  if value == nil then return fallback end
  local text = stringify(value)
  if text == "" then return fallback end
  local n = tonumber(text)
  if n == nil or n < 0 then
    quarto.log.warning(field .. " must be a whole number, and is \"" .. text ..
      "\", so " .. fallback .. " is used.")
    return fallback
  end
  return math.floor(n)
end

-- Check if meta is present or if it has length of 0
local function chkmeta(meta_item)
  local ispresent = false
  if meta_item then
    if #meta_item > 0 then
      ispresent = true
    end
  end
  return ispresent
end

-- Convert list to string with oxford comma
local function oxfordcommalister(lists)
  local lastsep = pandoc.Str(", " .. andreplacement .. " ")
  local sep = pandoc.Str(", ")

  if #lists == 2 then
    lastsep = pandoc.Str(" " .. andreplacement .. " ")
  end

  local result = List:new {}
  for i, v in ipairs(lists) do
    if i > 1 then
      if i == #lists then
        result:extend(List:new { lastsep })
      else
        result:extend(List:new { sep })
      end
    end
    result:extend(List:new { v })
  end

  return result
end




local get_author_paragraph = function(authors, different)
  local authordisplay = List:new {}
  local superii = ""
  local sep = ", "

  for i, a in ipairs(authors) do
    if i == 1 then
      sep = ""
    elseif i == #authors then
      if i == 2 then
        sep = " " .. andreplacement .. " "
      else
        sep = ", " .. andreplacement .. " "
      end
    else
      sep = ", "
    end

    authordisplay:extend({ pandoc.Str(sep .. stringify(a.apaauthordisplay)) })

    superii = ""
    if a.affiliations then
      for j, aff in ipairs(a.affiliations) do
        if j > 1 then
          superii = superii .. ","
        end
        superii = superii .. aff.number
      end
    end

    if different then
      authordisplay:extend({ pandoc.Superscript(superii) })
    end
  end
  return pandoc.Para(authordisplay)
end


local extend_paragraph = function(para, meta_item, sep)
  sep = sep or pandoc.Space()



  if meta_item and #meta_item > 0 then
    if #para.content > 1 then
      para.content:extend({ sep })
    end
    para.content:extend(meta_item)
  end
  return para
end


-- The journal running head -------------------------------------------------

-- Surname for the journal running head. Quarto's parsed name.family is used
-- when it really is the trailing surname of the displayed name, which keeps
-- compound surnames ("van der Berg") whole. When an author writes the name as
-- a given/family pair, Quarto can fold the two together and re-split on the
-- last space, leaving family as a middle initial; in that case the last word
-- of the display name is the better answer.
local function author_surname(a)
  local display = a.apaauthordisplay and stringify(a.apaauthordisplay) or ""
  local family = a.name and a.name.family and stringify(a.name.family) or ""
  if family ~= "" and display:sub(-#family) == family then
    return family
  end
  return display:match("(%S+)%s*$") or family
end

-- Running head byline: surnames with serial commas, an ampersand before the
-- last, and "et al." once there are more than three authors.
local function running_authors(byauthor)
  local names = List:new {}
  for _, a in ipairs(byauthor) do
    local surname = author_surname(a)
    if surname ~= "" then
      names:insert(surname)
    end
  end
  if #names == 0 then
    return nil
  elseif #names == 1 then
    return names[1]
  elseif #names == 2 then
    return names[1] .. " & " .. names[2]
  elseif #names == 3 then
    return names[1] .. ", " .. names[2] .. ", & " .. names[3]
  end
  return names[1] .. " et al."
end

-- Student paper title fields (course, instructor, due date, note).
local function add_student_field(body, meta, field)
  local content = meta[field]
  if not content or stringify(content) == "" then
    return
  end
  local div
  local content_type = pandoc.utils.type(content)
  if content_type == "Blocks" then
    div = pandoc.Div(content)
  elseif content_type == "Inlines" then
    div = pandoc.Div({ pandoc.Para(content) })
  else
    div = pandoc.Div({ pandoc.Para(pandoc.Inlines({ pandoc.Str(stringify(content)) })) })
  end
  div.classes:insert("Author")
  body:extend({ div })
end

-- Coerce a metadata value to Inlines (or nil if empty). Shared with the
-- latex side, which reads the journal fields through utilsapa as well.
local meta_inlines = utilsapa.meta_inlines

-- The ORCID icon the byline sets beside an author's ORCID.
local kOrcidIcon = "ORCID-iD_icon-vector.svg"

-- ---------------------------------------------------------------------------
-- The parts of the front matter, in the order they are set. Each adds its
-- blocks to ctx.body; ctx carries what they share, read once from the
-- metadata in the filter below.

-- The title, below the blank lines that set it where APA puts it on the
-- title page. Returns the heading, which the body repeats at its head.
local function title_block(ctx)
  local meta, body, newline = ctx.meta, ctx.body, ctx.newline
  local documenttitle = ""
  local intabovetitle = 2
  if meta.apatitledisplay then
    intabovetitle = blank_lines(meta["blank-lines-above-title"],
      "blank-lines-above-title", intabovetitle)
    for i = 1, intabovetitle do
      body:extend({ newline })
    end
    documenttitle = pandoc.Header(1, meta.apatitledisplay)
    documenttitle.classes = { "title", "unnumbered", "unlisted" }
    documenttitle.identifier = "title"
    if not meta["suppress-title"] then
      body:extend({ documenttitle })
    end
  end
  return documenttitle
end

local function running_head_authors(ctx)
  local meta, byauthor = ctx.meta, ctx.byauthor
  -- Byline for the journal-mode even-page running head. Left unset when
  -- authorship is masked or suppressed, and the header falls back to the
  -- short title.
  if byauthor and not meta["suppress-author"] and
      not (meta["mask"] and stringify(meta["mask"]) == "true") then
    local line = running_authors(byauthor)
    if line then
      meta["jou-running-authors"] = pandoc.MetaString(line)
    end
  end
end

-- The byline: the authors, their affiliations, and a student paper's course,
-- instructor and due date, with the draft date when there is one.
local function byline(ctx)
  local meta, body, newline = ctx.meta, ctx.body, ctx.newline
  local byauthor, affiliations = ctx.byauthor, ctx.affiliations
  local mask, student = ctx.mask, ctx.student
  local affilations_different = meta.affiliationsdifferent

  if meta["suppress-affiliation"] then
    affilations_different = false
  end

  local affiliations_str = List()

  local authordiv = pandoc.Div({})
  if not meta["suppress-author"] and byauthor then
    authordiv = pandoc.Div({
      newline,
      get_author_paragraph(byauthor, affilations_different)
    })
  end

  authordiv.classes:insert("Author")
  if affiliations then
    if byauthor then
      for i, a in ipairs(affiliations) do
        affiliations_str = List()

        local mysep = pandoc.Str("")

        if affilations_different and not meta["suppress-author"] then
          affiliations_str:extend({ pandoc.Superscript(stringify(a.number)) })
        end

        if chkmeta(a.group) then
          affiliations_str:extend(a.group)
          mysep = pandoc.Str(", ")
        end

        if chkmeta(a.department) then
          affiliations_str:extend({ mysep })
          affiliations_str:extend(a.department)
          mysep = pandoc.Str(", ")
        end

        if chkmeta(a.name) then
          affiliations_str:extend({ mysep })
          affiliations_str:extend(a.name)
          mysep = pandoc.Str(", ")
        end

        if not (chkmeta(a.group) or chkmeta(a.department) or chkmeta(a.name)) then
          mysep = pandoc.Str("")
          if chkmeta(a.city) then
            affiliations_str:extend(a.city)
            mysep = pandoc.Str(", ")
          end
          if chkmeta(a.region) then
            affiliations_str:extend({ mysep })
            affiliations_str:extend(a.region)
          end
        end
        if not meta["suppress-affiliation"] then
          authordiv.content:extend({ pandoc.Para(pandoc.Inlines(affiliations_str)) })
        end
      end
    end
  end

  if not mask then
    body:extend({ authordiv })
  end

  if student and not mask then
    add_student_field(body, meta, "course")
    add_student_field(body, meta, "professor")
    add_student_field(body, meta, "duedate")
    add_student_field(body, meta, "note")
  end

  if meta["draft-date"] then
    local draftdate = os.date("%B %d, %Y")
    if type(meta["draft-date"]) == "table" then
      draftdate = meta["draft-date"]
    end
    local draftdatediv = pandoc.Div({
      pandoc.Para(draftdate)
    })
    draftdatediv.classes:insert("Author")
    body:extend({ draftdatediv })
  end
end

-- The author note's heading, below its blank lines.
local function author_note_heading(ctx)
  local meta, body, newline = ctx.meta, ctx.body, ctx.newline
  local byauthor, authornote, mask = ctx.byauthor, ctx.authornote, ctx.mask
  local authornoteheadertext = "Author Note"
  if meta.language and meta.language["title-block-author-note"] then
    authornoteheadertext = meta.language["title-block-author-note"]
  end

  local authornoteheader = pandoc.Header(1, authornoteheadertext)
  authornoteheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
  authornoteheader.identifier = "author-note"

  local intabovenote = 2

  if not mask and not meta["suppress-author-note"] and (byauthor or authornote) then
    if authornote then
      intabovenote = blank_lines(authornote["blank-lines-above-author-note"],
        "blank-lines-above-author-note", intabovenote)
    end
    intabovenote = blank_lines(meta["blank-lines-above-author-note"],
      "blank-lines-above-author-note", intabovenote)

    for i = 1, intabovenote do
      body:extend({ newline })
    end

    body:extend({ authornoteheader })
  end
end

-- A line for each author with an ORCID.
local function orcid_lines(ctx)
  local meta, body = ctx.meta, ctx.body
  local byauthor, mask = ctx.byauthor, ctx.mask
  local img

  if byauthor then
    for i, a in ipairs(byauthor) do
      if a.orcid then
        -- The icon goes into the document rather than into raw typst,
        -- so it is written as a path from the document, which every
        -- writer reads the same way.
        --
        -- Except in plain latex, where it is not an image at all.
        -- Quarto turns an svg into a pdf by calling rsvg-convert, which
        -- it ships on windows and on a mac and not on linux, where the
        -- render stops at "Could not convert a SVG to a PDF for output"
        -- over an icon four millimetres wide. The orcidlink package
        -- draws the same mark in tex and links it to the orcid, which is
        -- what apa7 does with addORCIDlink and why apaquarto-pdf never
        -- wanted the file. apalatex.tex loads the package.
        if FORMAT == "latex" then
          img = pandoc.RawInline("latex",
            "\\orcidlink{" .. stringify(a.orcid) .. "}")
        else
          local orcidfile = utilsapa.extension_file_relative(kOrcidIcon)
          img = pandoc.Image("Orcid ID Logo: A green circle with white letters ID", orcidfile or kOrcidIcon)
          img.attr = pandoc.Attr('orcid', { 'img-fluid' }, { width = '4.23mm' })
        end
        local pp = pandoc.Para(pandoc.Str(""))
        pp.content:extend(a.apaauthordisplay)
        pp.content:extend({ pandoc.Space(), img })
        pp.content:extend({ pandoc.Space(), pandoc.Link("https://orcid.org/" .. stringify(a.orcid),
          "https://orcid.org/" .. stringify(a.orcid)) })

        if not mask and not meta["suppress-orcid"] then
          body:extend({ pp })
        end
      end
    end
  end
end

-- The author note's paragraphs on changes of status and on disclosures.
local function status_and_disclosures(ctx)
  local meta, body = ctx.meta, ctx.body
  local authornote, mask = ctx.authornote, ctx.mask
  if authornote then
    if authornote["status-changes"] then
      local second_paragraph = pandoc.Para(pandoc.Str(""))
      second_paragraph = extend_paragraph(second_paragraph,
        authornote["status-changes"]["affiliation-change"] or authornote["affiliation-change"] or
        meta["affiliation-change"])
      second_paragraph = extend_paragraph(second_paragraph,
        authornote["status-changes"].deceased or authornote.deceased or meta.deceased)

      if #second_paragraph.content > 1 then
        if not mask and not meta["suppress-status-change-paragraph"] then
          body:extend({ second_paragraph })
        end
      end
    end

    if authornote.disclosures then
      local third_paragraph = pandoc.Para(pandoc.Str(""))

      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["study-registration"] or authornote["study-registration"] or
        meta["study-registration"])
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["data-sharing"] or authornote["data-sharing"] or meta["data-sharing"])
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["related-report"] or authornote["related-report"] or meta["related-report"])
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["conflict-of-interest"] or authornote["conflict-of-interest"] or
        meta["conflict-of-interest"])
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["financial-support"] or authornote["financial-support"] or meta["financial-support"])
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures.gratitude or authornote.gratitude or meta.gratitude)
      third_paragraph = extend_paragraph(third_paragraph,
        authornote.disclosures["authorship-agreements"] or authornote["authorship-agreements"] or
        meta["authorship-agreements"])

      if #third_paragraph.content > 1 then
        if not mask and not meta["suppress-disclosures-paragraph"] then
          body:extend({ third_paragraph })
        end
      end
    end
  end
end

-- The CRediT statement of what each author did.
local function credit_statement(ctx)
  local meta, body = ctx.meta, ctx.body
  local byauthor, mask = ctx.byauthor, ctx.mask
  local credit_paragraph = pandoc.Para(pandoc.Str(""))

  if byauthor then
    for i, a in ipairs(byauthor) do
      if a.roles then
        credit_paragraph = extend_paragraph(credit_paragraph, { pandoc.Emph(a.apaauthordisplay) }, pandoc.Str(". "))
        credit_paragraph.content:extend({ pandoc.Strong(pandoc.Str(": ")) })
        local rolelist = {}
        for j, role in ipairs(a.roles) do
          if role.role == "Writing - original draft" or role.role == "writing - original draft" then
            role["vocab-term"] = "writing – original draft"
          end
          if role.role == "Writing - reviewing & editing" or role.role == "writing - reviewing & editing" then
            role["vocab-term"] = "Writing – reviewing & editing"
          end

          if role["vocab-term"] then
            role.display = role["vocab-term"]
          else
            role.display = role.role
          end

          if role["degree-of-contribution"] then
            role.display = role.display .. " (" .. role["degree-of-contribution"] .. ")"
          end
          table.insert(rolelist, pandoc.Str(role.display))
        end
        credit_paragraph.content:extend(oxfordcommalister(rolelist))
      end
    end
  end

  if #credit_paragraph.content > 1 then
    local authorroleintroduction = pandoc.Str(
    "Author roles were classified using the Contributor Role Taxonomy (CRediT; https://credit.niso.org/) as follows:")
    if meta.language and meta.language["title-block-role-introduction"] then
      authorroleintroduction = meta.language["title-block-role-introduction"]
      if type(authorroleintroduction) == "string" then
        authorroleintroduction = pandoc.Inlines(authorroleintroduction)
      end
    end

    credit_paragraph.content:insert(1, pandoc.Space())
    for i, j in pairs(authorroleintroduction) do
      credit_paragraph.content:insert(i, j)
    end
    if not mask and not meta["suppress-credit-statement"] then
      body:extend({ credit_paragraph })
    end
  end
end

-- The paragraph saying whom to write to about the article.
local function correspondence(ctx)
  local meta, body = ctx.meta, ctx.body
  local byauthor, mask = ctx.byauthor, ctx.mask
  local emailword = "Email"
  if meta.language and meta.language.email then
    emailword = stringify(meta.language.email)
  end

  local corresponding_paragraph = pandoc.Para(pandoc.Str(""))
  local check_corresponding = false
  if meta["author-note"] and meta["author-note"]["correspondence-note"] then
    corresponding_paragraph.content:extend(meta["author-note"]["correspondence-note"])
  else
    if byauthor then
      for i, a in ipairs(byauthor) do
        if a.attributes then
          if a.attributes.corresponding and stringify(a.attributes.corresponding) == "true" then
            if check_corresponding then
              error("There can only be one author marked as the corresponding author. " ..
              stringify(a.apaauthordisplay) .. " is the second author you have marked as the corresponding author.")
            end
            check_corresponding = true
            corresponding_paragraph.content:extend(a.apaauthordisplay)

            if a.affiliations then
              local address = a.affiliations[1]
              if not meta["suppress-corresponding-group"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.group, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-department"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.department,
                  pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-affiliation-name"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.name, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-address"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.address, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-city"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.city, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-region"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.region, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-postal-code"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address["postal-code"])
              end

              if not meta["suppress-corresponding-country"] then
                corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.country, pandoc.Str(", "))
              end

              if not meta["suppress-corresponding-email"] then
                if a.email then
                  corresponding_paragraph.content:extend({ pandoc.Str(", " .. emailword .. ":") })
                  corresponding_paragraph = extend_paragraph(corresponding_paragraph,
                    { pandoc.Link(stringify(a.email), "mailto:" .. stringify(a.email)) })
                end
              end
            end
          end
        end
      end
    end

    if #corresponding_paragraph.content > 1 then
      local correspondencenote = pandoc.Str("Correspondence concerning this article should be addressed to ")
      if meta.language and meta.language["title-block-correspondence-note"] then
        correspondencenote = meta.language["title-block-correspondence-note"]
        if type(correspondencenote) == "string" then
          correspondencenote = pandoc.Inlines(correspondencenote)
        end
      end
      corresponding_paragraph.content:insert(1, pandoc.Space())
      for i, j in pairs(correspondencenote) do
        corresponding_paragraph.content:insert(i, j)
      end
    end
  end

  if (not mask) and (not meta["suppress-corresponding-paragraph"]) then
    body:extend({ corresponding_paragraph })
  end
end

-- The abstract, the impact statement, the keywords, the supplemental
-- materials and the word count.
local function abstract_and_keywords(ctx)
  local meta, body = ctx.meta, ctx.body
  if meta.apaabstract and #meta.apaabstract > 0 and not meta["suppress-abstract"] then
    local abstractheadertext = pandoc.Str("Abstract")
    if meta.language and meta.language["section-title-abstract"] then
      abstractheadertext = meta.language["section-title-abstract"]
    end
    local abstractheader = pandoc.Header(1, abstractheadertext)
    abstractheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
    abstractheader.identifier = "abstract"
    if FORMAT:match 'docx' or FORMAT:match 'typst' then
      body:extend({ utilsapa.page_break() })
    end

    if FORMAT:match 'html' then
      body:extend({ pandoc.RawBlock('html', '<br>') })
    end

    body:extend({ abstractheader })
    local abstract_paragraph = pandoc.Para(pandoc.Str(""))

    if pandoc.utils.type(meta.apaabstract) == "Inlines" then
      abstract_paragraph.content:extend(meta.apaabstract or meta.abstract)
      local abstractdiv = pandoc.Div(abstract_paragraph)
      abstractdiv.classes:insert("AbstractFirstParagraph")
      body:extend({ abstractdiv })
    end

    if pandoc.utils.type(meta.apaabstract) == "Blocks" then
      body:extend(paragraph_divs(meta.apaabstract))
    end
  end

  if meta["impact-statement"] and #meta["impact-statement"] > 0 and not meta["suppress-impact-statement"] then
    local impactheadertext = pandoc.Str("Impact Statement")
    if meta.language and meta.language["title-impact-statement"] then
      impactheadertext = meta.language["title-impact-statement"]
    end
    local impactheader = pandoc.Header(1, impactheadertext)
    impactheader.classes = { "unnumbered", "unlisted", "AuthorNote" }
    impactheader.identifier = "impact"
    body:extend({ impactheader })
    local impact_paragraph = pandoc.Para(pandoc.Str(""))
    if pandoc.utils.type(meta["impact-statement"]) == "Inlines" then
      impact_paragraph.content:extend(meta["impact-statement"])
      local impactdiv = pandoc.Div(impact_paragraph)
      impactdiv.classes:insert("AbstractFirstParagraph")
      body:extend({ impactdiv })
    end

    -- An impact statement of more than one paragraph, which is what a
    -- statement written as a section of the document gives.
    if pandoc.utils.type(meta["impact-statement"]) == "Blocks" then
      body:extend(paragraph_divs(meta["impact-statement"]))
    end
  end

  if meta.keywords and not meta["suppress-keywords"] then
    local keywordsword = pandoc.Str("Keywords")
    if meta.language and meta.language["title-block-keywords"] then
      keywordsword = stringify(meta.language["title-block-keywords"])
    end

    local keywords_paragraph = pandoc.Para({ pandoc.Emph(keywordsword), pandoc.Str(":") })

    if pandoc.utils.type(meta.keywords) == "Inlines" then
      keywords_paragraph.content:extend(meta.keywords)
    else
      for i, k in ipairs(meta.keywords) do
        if i == 1 then
          keywords_paragraph = extend_paragraph(keywords_paragraph, k)
        else
          keywords_paragraph = extend_paragraph(keywords_paragraph, k, pandoc.Str(", "))
        end
      end
    end

    body:extend({ keywords_paragraph })
  end

  -- A pointer to supplemental materials (a repository, an OSF page, a data
  -- archive) sits on its own line under the keywords, labelled the way the
  -- keywords line is.
  if meta["supplemental-materials"] and
      stringify(meta["supplemental-materials"]) ~= "" and
      not meta["suppress-supplemental-materials"] then
    local supplementalword = pandoc.Str("Supplemental materials")
    if meta.language and meta.language["title-supplemental-materials"] then
      supplementalword = stringify(meta.language["title-supplemental-materials"])
    end

    local supplemental_paragraph = pandoc.Para({ pandoc.Emph(supplementalword), pandoc.Str(":"), pandoc.Space() })
    supplemental_paragraph.content:extend(meta_inlines(meta["supplemental-materials"]))
    body:extend({ supplemental_paragraph })
  end

  if meta["word-count"] then
    -- title-word-count is the key apalanguage.lua declares and options.qmd
    -- documents; this once read title-block-word-count, which nothing sets,
    -- so a translation of the label never reached the page.
    local word_count_word = utilsapa.lang(meta, "title-word-count", "Word Count")
    local word_count_paragraph = pandoc.Para({ pandoc.Emph(word_count_word), pandoc.Str(": " .. meta.wordn) })
    body:extend({ word_count_paragraph })
  end
end

-- The break that ends the title page.
local function closing_break(ctx)
  local meta, body = ctx.meta, ctx.body
  if FORMAT:match 'docx' then
    body:extend({ utilsapa.page_break() })
  end

  if FORMAT:match 'typst' then
    local pg = '#pagebreak()\n\n'
    if meta['first-page'] then
      pg = '#counter(page).update(' .. stringify(meta['first-page']) .. ' - 1)\n #pagebreak()\n\n'
    end
    body:extend({ pandoc.RawBlock('typst', pg) })
  end



  if FORMAT:match 'html' then
    body:extend({ pandoc.RawBlock('html', '<br>') })
  end
end

-- The running head, which .docx reads from the description.
local function running_head(ctx)
  local meta, student = ctx.meta, ctx.student
  local myshorttitle = ""

  if meta["apatitle"] then
    myshorttitle = meta["apatitle"]
  end

  if meta["shorttitle"] and #meta["shorttitle"] > 0 then
    myshorttitle = meta["shorttitle"]
  end

  for i, v in ipairs(myshorttitle) do
    if v.t == "Str" then
      v.text = pandoc.text.upper(v.text)
    end
  end
  -- The description is what the running head is read from in .docx: the
  -- head is a content control bound to it, and word fills the control
  -- from that binding whatever text is written into it.
  --
  -- A student paper has no running head --- APA seventh edition drops it
  -- from student work --- so there is nothing for the control to say.
  -- .docx only: the other formats take their head from elsewhere, and
  -- the description is what a browser reads a page by. Issue #166.
  if not meta["suppress-short-title"]
      and not (FORMAT == "docx" and student) then
    meta.description = myshorttitle
  else
    meta.description = " "
  end
end

-- The markers for the table of contents and the lists of figures and
-- tables, which the format's own filter writes out.
local function list_markers(ctx)
  local meta, body = ctx.meta, ctx.body
  -- list-of-contents asks for a table of contents in every format.
  -- typst also takes toc: true, which is what it has always answered to
  -- and what .html uses as well, so either will do there.
  --
  -- Not in thesis mode. A dissertation has a contents and lists of its
  -- own, built by thesisfrontmatter.lua in the shape the Graduate School
  -- asks for, and building these as well would set two of each.
  local thesis_mode = utilsapa.mode(meta) == "thesis"
  local wants_contents = not thesis_mode and meta["list-of-contents"]
    and stringify(meta["list-of-contents"]) ~= "false"

  -- The same two lists in .docx. What they are lists of is not known
  -- yet: apacaption.lua has not run, so no figure has its number or its
  -- title. A marker goes in at the place typst puts its outlines and
  -- docxcontents.lua fills it in once the captions exist.
  -- .html builds a contents and nothing else: a list of figures or of
  -- tables is a way of finding a page, and .html has no pages. Asking
  -- for one there used to leave an empty div in the body.
  --
  -- Nor does it build a contents when toc: true has already put quarto's
  -- own in the margin. Two of them on one page is one too many, and the
  -- margin is where a reader of a web page looks.
  local lists = { "list-of-contents", "list-of-figures", "list-of-tables" }
  if thesis_mode then lists = {} end
  if FORMAT == "html" and not thesis_mode then
    lists = {}
    if not PANDOC_WRITER_OPTIONS["table_of_contents"] then
      lists = { "list-of-contents" }
    end
  end

  if FORMAT == "docx" or FORMAT == "latex" or FORMAT == "html" then
    for _, which in ipairs(lists) do
      if meta[which] and stringify(meta[which]) ~= "false" then
        body:extend({ pandoc.Div({}, pandoc.Attr("", { which })) })
      end
    end
  end

  -- typst writes each of the three as an outline where its marker
  -- stands; formattypst.lua does the writing. A contents is also what
  -- toc: true asks for there, which is what typst has always answered to.
  if FORMAT:match 'typst' then
    local typst_lists = {}
    if PANDOC_WRITER_OPTIONS["table_of_contents"] or wants_contents then
      typst_lists[#typst_lists + 1] = "list-of-contents"
    end
    if meta["list-of-figures"] and not thesis_mode then
      typst_lists[#typst_lists + 1] = "list-of-figures"
    end
    if meta["list-of-tables"] and not thesis_mode then
      typst_lists[#typst_lists + 1] = "list-of-tables"
    end
    for _, which in ipairs(typst_lists) do
      body:extend({ pandoc.Div({}, pandoc.Attr("", { which })) })
    end
  end
end

-- The front matter and the body, arranged for the format and the mode, as
-- the blocks of the document.
local function arrange(ctx, blocks)
  local body = ctx.body
  if FORMAT:match 'typst' or FORMAT == "latex" then
    -- The writer lays the front matter out for the document's mode: one
    -- block after another for a manuscript, a masthead across both columns
    -- for a journal article, one flow for a typst document.
    -- typst/formattypst.lua does it for typst and formatlatex.lua for the
    -- .pdf. It is handed over in a div of its own, which the writer takes
    -- away again, so that it can tell the front matter from the body.
    body = List:new {
      pandoc.Div(body, pandoc.Attr("", { layout.kFrontMatterClass })) }
  end
  body:extend(blocks)
  return body
end

return {
  { Meta = get_and },
  {
    Pandoc = function(doc)
      local meta = doc.meta
      local newline = pandoc.LineBreak()
      if FORMAT:match 'docx' then
        newline = pandoc.SoftBreak()
      end
      local authornote = false
      if meta["author-note"] and not meta["suppress-author-note"] then
        authornote = meta["author-note"]
      end

      local ctx = {
        meta = meta,
        body = List:new {},
        newline = newline,
        -- A student paper, whatever it is being written to. The fields below
        -- were gated on typst for as long as the .pdf was built with the apa7
        -- class, which set them from the class options; the .pdf stopped
        -- using that class in 6.0.0 and nothing took the work over, so a
        -- student paper came out with no course, no instructor and no due
        -- date in every format but typst. Issue #166.
        student = meta.documentmode ~= nil
          and stringify(meta.documentmode) == "stu",
        byauthor = meta["by-author"],
        affiliations = meta["affiliations"],
        authornote = authornote,
        mask = meta["mask"] ~= nil and stringify(meta["mask"]) == "true",
      }

      -- The title is read whatever is asked for, since the head of the body
      -- repeats it, and the two parts that write into the metadata run as
      -- well: the running head is read from there.
      local documenttitle = title_block(ctx)
      running_head_authors(ctx)

      -- The rest of the title page is built only when it is going to be set.
      -- suppress-title-page leaves it out, and a dissertation, whose front
      -- matter thesisfrontmatter.lua builds in the shape the Graduate School
      -- asks for, always asks for that.
      if not meta["suppress-title-page"] then
        byline(ctx)
        author_note_heading(ctx)
        orcid_lines(ctx)
        status_and_disclosures(ctx)
        credit_statement(ctx)
        correspondence(ctx)
        abstract_and_keywords(ctx)
        closing_break(ctx)
      end
      running_head(ctx)

      if meta["suppress-title-page"] then
        ctx.body = List:new {}
      end

      list_markers(ctx)

      if meta.apatitledisplay and not meta["suppress-title-introduction"] then
        local firstpageheader = documenttitle:clone()
        firstpageheader.identifier = "firstheader"
        firstpageheader.classes = { "title", "unnumbered" }
        ctx.body:extend({ firstpageheader })
      end

      return pandoc.Pandoc(arrange(ctx, doc.blocks), meta)
    end
  }
}

-- Handle frontmatter stuff for .docx, html, and typst formats
if FORMAT:match 'latex' then
  return
end


local andreplacement = "and"



local List = require 'pandoc.List'
local utilsapa = require("utilsapa")
local stringify = utilsapa.stringify

local function get_and(m)
  if m.language and m.language["citation-last-author-separator"] then
    andreplacement = stringify(m.language["citation-last-author-separator"])
  end
end

---http://lua-users.org/wiki/StringRecipes
local function ends_with(str, ending)
   return string.sub(str.text, -1) == ending
end

local function file_exists(name)
 
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

-- Check if meta is present or if it has length of 0
local function chkmeta(meta_item)
  ispresent = false
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
   
  local result = List:new{}
  for i, v in ipairs(lists) do
    
    if i > 1 then
      if i == #lists then
        result:extend(List:new{lastsep})
      else
        result:extend(List:new{sep})
      end
      
    end
    result:extend(List:new{v})
    
  end

  return result
end




local get_author_paragraph = function(authors, different)
  
      local authordisplay = List:new{}
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

        authordisplay:extend({pandoc.Str(sep .. stringify(a.apaauthordisplay))})
        
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
          authordisplay:extend({pandoc.Superscript(superii)})
        end
        
      end
      return pandoc.Para(authordisplay)
end


local extend_paragraph = function(para, meta_item, sep)
  sep = sep or pandoc.Space()
  
  
  
        if meta_item and #meta_item > 0 then
          if #para.content > 1 then
            para.content:extend({sep})
          end
          para.content:extend(meta_item)
        end
        return para
      end


return {
  { Meta = get_and },
  {
    Pandoc = function(doc)
           
      local body = List:new{}
      local meta = doc.meta
      
      local documenttitle = ""
      local intabovetitle = 2
      local newline = pandoc.LineBreak()
      if FORMAT:match 'docx' then
         newline = pandoc.SoftBreak()
      end
      
      if meta.apatitledisplay then
        if meta["blank-lines-above-title"] and #meta["blank-lines-above-title"] > 0 then
          local possiblenumber = stringify(meta["blank-lines-above-title"])
          if type(possiblenumber) == "number" then
            local intnumber = tonumber(possiblenumber) * 1
            intabovetitle = math.floor(intnumber) or 2
          else
            intabovetitle = 2
          end
          
        end
        for i=1,intabovetitle do 
          body:extend({newline})
        end
        documenttitle = pandoc.Header(1, meta.apatitledisplay)
        documenttitle.classes = {"title", "unnumbered", "unlisted"}
        documenttitle.identifier="title"
        if not meta["suppress-title"] then
          body:extend({documenttitle})
        end 
        
      end
      

      
      local byauthor = meta["by-author"]
      local affiliations = meta["affiliations"]
      
      local authornote = false
      if meta["author-note"] and not meta["suppress-author-note"] then
        authornote = meta["author-note"]
      end
      
      local mask = false
      
      if meta["mask"] and stringify(meta["mask"]) == "true" then
        mask = true
      end
      
      
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
            
            mysep = pandoc.Str("")
            
            if affilations_different and not meta["suppress-author"] then
              affiliations_str:extend({pandoc.Superscript(stringify(a.number))})
            end
            
            if chkmeta(a.group) then
              affiliations_str:extend(a.group)
              mysep = pandoc.Str(", ")
            end
            
            
            if chkmeta(a.department) then
              affiliations_str:extend({mysep})
              affiliations_str:extend(a.department)
              mysep = pandoc.Str(", ")
            end
            
            if chkmeta(a.name) then
              affiliations_str:extend({mysep})
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
                  affiliations_str:extend({mysep})
                  affiliations_str:extend(a.region)
                end
              end
            if not meta["suppress-affiliation"] then
              authordiv.content:extend({pandoc.Para(pandoc.Inlines(affiliations_str))})
            end
          end
        end
      end
      
      

      
      if not mask then
        body:extend({authordiv})
      end
      
      if meta["draft-date"] then
        draftdate = os.date("%B %d, %Y")
        if type(meta["draft-date"]) == "table" then
          draftdate = meta["draft-date"]
        end
        draftdatediv = pandoc.Div({
            pandoc.Para(draftdate)
        })
        draftdatediv.classes:insert("Author")
        body:extend({draftdatediv})
      end
      
      local authornoteheadertext = "Author Note"
      if meta.language and meta.language["title-block-author-note"] then
        authornoteheadertext = meta.language["title-block-author-note"]
      end 

      local emailword = "Email"
      if meta.language and meta.language.email then
        emailword = stringify(meta.language.email)
      end 
      
      local authornoteheader = pandoc.Header(1, authornoteheadertext)
      authornoteheader.classes = {"unnumbered", "unlisted", "AuthorNote"}
      authornoteheader.identifier = "author-note"
      
      local intabovenote = 2
      
      local possiblenumber = 2
      

      

      if not mask and not meta["suppress-author-note"] and (byauthor or authornote) then
        
        if authornote then
          if authornote["blank-lines-above-author-note"] and #authornote["blank-lines-above-author-note"] > 0 then
            possiblenumber = stringify(authornote["blank-lines-above-author-note"])
            intabovenote = math.floor(tonumber(possiblenumber)) or 2
          end
        end
        
        if meta["blank-lines-above-author-note"] and #meta["blank-lines-above-author-note"] > 0 then
            possiblenumber = stringify(meta["blank-lines-above-author-note"])
            intabovenote = math.floor(tonumber(possiblenumber)) or 2
        end
        
        for i=1,intabovenote do 
          body:extend({newline})
        end
        
        body:extend({authornoteheader})
      end
      
      local img
      
      if byauthor then
        for i, a in ipairs(byauthor) do
          
          if a.orcid then
            local orcidfile = "_extensions/wjschne/apaquarto/ORCID-iD_icon-vector.svg"
            if not file_exists(orcidfile) then
              orcidfile = "_extensions/apaquarto/ORCID-iD_icon-vector.svg"
            end 
            img = pandoc.Image("Orcid ID Logo: A green circle with white letters ID", orcidfile)
            img.attr = pandoc.Attr('orchid', {'img-fluid'},  {width='4.23mm'})
            pp = pandoc.Para(pandoc.Str(""))
            pp.content:extend(a.apaauthordisplay)
            pp.content:extend({pandoc.Space(), img})
            pp.content:extend({pandoc.Space(), pandoc.Link("https://orcid.org/" .. stringify(a.orcid), "https://orcid.org/" .. stringify(a.orcid))})

            
            if not mask and not meta["suppress-orcid"] then
              body:extend({pp})
            end
          end 
  
        end
      end
      

      if authornote then
        if authornote["status-changes"] then
          local second_paragraph = pandoc.Para(pandoc.Str(""))
          
          second_paragraph = extend_paragraph(second_paragraph, authornote["status-changes"]["affiliation-change"] or authornote["affiliation-change"] or meta["affiliation-change"])
          second_paragraph = extend_paragraph(second_paragraph, authornote["status-changes"].deceased or authornote.deceased or meta.deceased)
      

          if #second_paragraph.content > 1 then
            if not mask and not meta["suppress-status-change-paragraph"] then
              body:extend({second_paragraph})
            end
          end
        end
        
        if authornote.disclosures then
          local third_paragraph = pandoc.Para(pandoc.Str(""))
          
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["study-registration"] or authornote["study-registration"] or meta["study-registration"])
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["data-sharing"] or authornote["data-sharing"] or meta["data-sharing"])
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["related-report"] or authornote["related-report"] or meta["related-report"])
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["conflict-of-interest"] or authornote["conflict-of-interest"] or meta["conflict-of-interest"])
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["financial-support"] or authornote["financial-support"] or meta["financial-support"])
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures.gratitude or authornote.gratitude or meta.gratitude)
          third_paragraph = extend_paragraph(third_paragraph, authornote.disclosures["authorship-agreements"] or authornote["authorship-agreements"] or meta["authorship-agreements"])
          
          if #third_paragraph.content > 1 then
            if not mask and not meta["suppress-disclosures-paragraph"] then
              body:extend({third_paragraph})
            end
          end
        end
      
      end
      
      local credit_paragraph = pandoc.Para(pandoc.Str(""))
      
      if byauthor then
        for i,a in ipairs(byauthor) do
          if a.roles then
  
            credit_paragraph = extend_paragraph(credit_paragraph, {pandoc.Emph(a.apaauthordisplay)}, pandoc.Str(". "))
            credit_paragraph.content:extend({pandoc.Strong(pandoc.Str(": "))})
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
          
          local authorroleintroduction = pandoc.Str("Author roles were classified using the Contributor Role Taxonomy (CRediT; https://credit.niso.org/) as follows:")
          if meta.language and meta.language["title-block-role-introduction"] then
            authorroleintroduction = meta.language["title-block-role-introduction"]
            if type(authorroleintroduction) == "string" then
              authorroleintroduction = pandoc.Inlines(authorroleintroduction)
            end
          end
          
          credit_paragraph.content:insert(1, pandoc.Space())
          for i,j in pairs(authorroleintroduction) do
            credit_paragraph.content:insert(i, j)
          end
          if not mask and not meta["suppress-credit-statement"] then
            body:extend({credit_paragraph})
          end
        end
      
  
      local corresponding_paragraph = pandoc.Para(pandoc.Str(""))
      local check_corresponding = false
      if meta["author-note"] and meta["author-note"]["correspondence-note"] then
        corresponding_paragraph.content:extend(meta["author-note"]["correspondence-note"])
      else
      
      if byauthor then
        for i,a in ipairs(byauthor) do
          if a.attributes then
            if a.attributes.corresponding and stringify(a.attributes.corresponding) == "true" then
              if check_corresponding then
                error("There can only be one author marked as the corresponding author. " .. stringify(a.apaauthordisplay) .. " is the second author you have marked as the corresponding author.")
              end
              check_corresponding = true
              corresponding_paragraph.content:extend(a.apaauthordisplay)
              
              if a.affiliations then
                local address = a.affiliations[1]
                if not meta["suppress-corresponding-group"] then
                  corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.group, pandoc.Str(", "))
                end
  
                if not meta["suppress-corresponding-department"] then
                  corresponding_paragraph = extend_paragraph(corresponding_paragraph, address.department, pandoc.Str(", ")) 
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
                    corresponding_paragraph.content:extend({pandoc.Str(", " .. emailword .. ":")})
                    corresponding_paragraph = extend_paragraph(corresponding_paragraph, {pandoc.Link(stringify(a.email), "mailto:" .. stringify(a.email))})
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
          for i,j in pairs(correspondencenote) do
            corresponding_paragraph.content:insert(i, j)
          end
        end
      end
      
      if (not mask) and (not meta["suppress-corresponding-paragraph"]) then
        body:extend({corresponding_paragraph})
      end
        
      if meta.apaabstract and #meta.apaabstract > 0 and not meta["suppress-abstract"] then
        local abstractheadertext = pandoc.Str("Abstract")
        if meta.language and meta.language["section-title-abstract"] then
          abstractheadertext = meta.language["section-title-abstract"]
        end
        local abstractheader = pandoc.Header(1, abstractheadertext)
        abstractheader.classes = {"unnumbered", "unlisted", "AuthorNote"}
        abstractheader.identifier = "abstract"
        if FORMAT:match 'docx' then
          body:extend({pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')})
        end
        
        if FORMAT:match 'typst' then
          body:extend({pandoc.RawBlock('typst', '#pagebreak()\n\n')})
        end
        
        if FORMAT:match 'html' then
          body:extend({pandoc.RawBlock('html', '<br>')})
        end
        
        body:extend({abstractheader})
        local abstract_paragraph = pandoc.Para(pandoc.Str(""))
        
        if pandoc.utils.type(meta.apaabstract) == "Inlines" then
          abstract_paragraph.content:extend(meta.apaabstract or meta.abstract)
          local abstractdiv = pandoc.Div(abstract_paragraph)
          abstractdiv.classes:insert("AbstractFirstParagraph")
          body:extend({abstractdiv})
        end
        
        if pandoc.utils.type(meta.apaabstract) == "Blocks" then
          local abstractdiv = pandoc.Div({})
          local abstractfirstparagraphdiv = pandoc.Div({})
          local abstractlinecounter = 1
          if FORMAT == "typst" then
            abstractlinecounter = 2
          end
          meta.apaabstract:walk {
            LineBlock = function(lb)
              lb:walk {
                traverse = "topdown",
                Inlines = function(el)
                    local lbpara = pandoc.Para(el)
                    
                    if abstractlinecounter == 1 then
                      
                      abstractfirstparagraphdiv.content:extend({lbpara})
                      abstractfirstparagraphdiv.classes:insert("AbstractFirstParagraph")
                      
                    else
                      abstractdiv.content:extend({lbpara})
                      if abstractlinecounter == 2 then
                        abstractdiv.classes:insert("Abstract")
                      end
                      
                    end
                    
                    abstractlinecounter = abstractlinecounter + 1
                    return el, false
                end
              }
            end
          }
          if abstractlinecounter > 1 then
            body:extend({abstractfirstparagraphdiv})
          end
          
          if abstractlinecounter > 2 then
            body:extend({abstractdiv})
          end
          
        end

      end
      
      if meta["impact-statement"] and #meta["impact-statement"] > 0 and not meta["supress-impact-statement"] then
        local impactheadertext = pandoc.Str("Impact Statement")
        if meta.language and meta.language["title-impact-statement"] then
          impactheadertext = meta.language["title-impact-statement"]
        end
        local impactheader = pandoc.Header(1, impactheadertext)
        impactheader.classes = {"unnumbered", "unlisted", "AuthorNote"}
        impactheader.identifier = "impact"
        body:extend({impactheader})
        local impact_paragraph = pandoc.Para(pandoc.Str(""))
        if pandoc.utils.type(meta["impact-statement"]) == "Inlines" then
          impact_paragraph.content:extend(meta["impact-statement"])
          local impactdiv = pandoc.Div(impact_paragraph)
          impactdiv.classes:insert("AbstractFirstParagraph")
          body:extend({impactdiv})
        end
      end
      
      if meta.keywords and not meta["suppress-keywords"] then
        local keywordsword = pandoc.Str("Keywords")
        if meta.language and meta.language["title-block-keywords"] then
          keywordsword = stringify(meta.language["title-block-keywords"])
        end
        
        local keywords_paragraph = pandoc.Para({pandoc.Emph(keywordsword), pandoc.Str(":")})
        
        if pandoc.utils.type(meta.keywords) == "Inlines" then
          keywords_paragraph = keywords_paragraph.content:extend(meta.keywords)
        else
          for i, k in ipairs(meta.keywords) do
            if i == 1 then
              keywords_paragraph = extend_paragraph(keywords_paragraph, k)
            else
              keywords_paragraph = extend_paragraph(keywords_paragraph, k, pandoc.Str(", "))
            end
            
          end
        end
        
        body:extend({keywords_paragraph})
      end
      
      if meta["word-count"] then
        local word_count_word = "Word Count"
        if meta.language and meta.language["title-block-word-count"] then
          word_count_word = stringify(meta.language["title-block-word-count"])
        end
        

        local word_count_paragraph = pandoc.Para({pandoc.Emph(word_count_word), pandoc.Str(": " .. meta.wordn)})
        body:extend({word_count_paragraph})
      end

        if FORMAT:match 'docx' then
          body:extend({pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')})
        end
        
        if FORMAT:match 'typst' then
          local pg = '#pagebreak()\n\n' 
          if meta['first-page'] then
            pg = '#counter(page).update(' .. stringify(meta['first-page']) .. ' - 1)\n #pagebreak()\n\n'
          end
          body:extend({pandoc.RawBlock('typst', pg)})
        end
        

        
        if FORMAT:match 'html' then
          body:extend({pandoc.RawBlock('html', '<br>')})
        end
        

  

      
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
      if not meta["suppress-short-title"] then
        meta.description = myshorttitle
      else
        meta.description = " "
      end
      
      if meta["suppress-title-page"] then
        body = List:new{}
      end
      
      ---- print(PANDOC_WRITER_OPTIONS["table_of_contents"])
      
      if FORMAT:match 'typst' and PANDOC_WRITER_OPTIONS["table_of_contents"] then
        body:extend({pandoc.RawBlock('typst', '\n\n#outline(title: [Table of Contents], indent: 1.5em)\n\n')})
        body:extend({pandoc.RawBlock('typst', '#pagebreak()\n\n')})
      end
      
      if FORMAT:match 'typst' and meta["list-of-figures"] then
        body:extend({pandoc.RawBlock('typst', '\n\n#outline(title: [List of Figures], target: figure.where(kind: "quarto-float-fig"),)\n\n')})
        body:extend({pandoc.RawBlock('typst', '#pagebreak()\n\n')})
      end
      
      if FORMAT:match 'typst' and meta["list-of-tables"] then
        body:extend({pandoc.RawBlock('typst', '\n\n#outline(title: [List of Tables], target: figure.where(kind: "quarto-float-tbl"),)\n\n')})
        body:extend({pandoc.RawBlock('typst', '#pagebreak()\n\n')})
      end

      if meta.apatitledisplay and not meta["suppress-title-introduction"] then
        local firstpageheader = documenttitle:clone()
        firstpageheader.identifier = "firstheader"
        firstpageheader.classes = {"title", "unnumbered", "unlisted"}
        body:extend({firstpageheader})
      end
      

      

      
      body:extend(doc.blocks)
      return pandoc.Pandoc(body, meta)
    end
  }
}

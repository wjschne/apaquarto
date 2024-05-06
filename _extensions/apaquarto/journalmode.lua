-- Sets journalmode in latex. Latex templates only read logical values.
if FORMAT:match 'latex' then
-- Sets journal mode
function Meta(m)
  if m.documentmode then
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      m.journalmode = true
      m.manuscriptmode = false
    end
    if pandoc.utils.stringify(m.documentmode) == 'man' then 
      m.journalmode = false
      m.manuscriptmode = true
    end 
    if pandoc.utils.stringify(m.documentmode) == 'doc' then
      m.journalmode = false
      m.manuscriptmode = false
    end
  else
    m.journalmode = false
    m.manuscriptmode = true
  end
  return m
end

end
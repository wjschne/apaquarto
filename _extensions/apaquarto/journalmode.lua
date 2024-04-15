-- Sets journalmode in latex. Latex templates only read logical values.
if FORMAT:match 'latex' then
-- Sets journal mode
function Meta(m)
  if m.documentmode then
    if pandoc.utils.stringify(m.documentmode) == 'jou' then 
      m.journalmode = true
      return m
    end
  else
    m.journalmode = false
    return m
  end
end

end
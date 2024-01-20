if FORMAT:match 'latex' then

function Meta(m)
  if pandoc.utils.stringify(m.documentmode) == 'jou' then 
    m.journalmode = true
    return m
  end
end

end
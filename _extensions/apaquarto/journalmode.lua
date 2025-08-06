-- Sets journalmode in latex. Latex templates only read logical values.
if FORMAT:match 'latex' then
  -- Sets journal mode
  function Meta(m)
    if m.documentmode then
      if pandoc.utils.stringify(m.documentmode) == 'jou' then
        m.journalmode = true
        m.manuscriptmode = false
        m.docmode = false
        m.studentmode = false
      end
      if pandoc.utils.stringify(m.documentmode) == 'man' then
        m.journalmode = false
        m.manuscriptmode = true
        m.docmode = false
        m.studentmode = false
      end
      if pandoc.utils.stringify(m.documentmode) == 'doc' then
        m.journalmode = false
        m.manuscriptmode = false
        m.docmode = true
        m.studentmode = false
      end
      if pandoc.utils.stringify(m.documentmode) == 'stu' then
        m.journalmode = false
        m.manuscriptmode = false
        m.docmode = false
        m.studentmode = true
      end
    else
      m.journalmode = false
      m.manuscriptmode = true
    end
    return m
  end
end

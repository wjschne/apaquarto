Str = function(str)
  if str.text:match("^{apafg%-") or  str.text:match("^{apatb%-") then
    error("A previous version of this extension used the apafg- prefix for figure chunk labels and apatb- prefix for tables. Replace all instances of apafg- with the standard Quarto prefix fig-. Likewise, replace the non-standard apatb- prefix with the standard Quarto prefix tbl-. Also replace all text references to figures and tables using standard Quarto syntax. For example, {apafg-myplot} should now be @fig-myplot instead.")
  end
end
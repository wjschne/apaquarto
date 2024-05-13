#show: document => $documentmode$(
$if(suppress-short-title)$
$else$
$if(shorttitle)$
  runninghead: "$shorttitle$",
$else$
$if(title)$
  runninghead: "$title$",
$endif$
$endif$
$endif$
$if(paper)$
  paper: "$paper$",
$endif$
$if(margin)$
  margin: ($for(margin/pairs)$$margin.key$: $margin.value$,$endfor$),
$endif$
$if(mainfont)$
  font: ("$mainfont$",),
$endif$
$if(fontsize)$
  fontsize: $fontsize$,
$endif$
$if(leading)$
  leading: $leading$,
  spacing: $leading$,
$endif$
$if(spacing)$
  spacing: $spacing$,
  leading: $leading$
$endif$
$if(lang)$
  lang: "$lang$",
$endif$
$if(cols)$
  cols: $cols$,
$endif$
  document,
)

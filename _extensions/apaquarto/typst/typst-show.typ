#show: doc => article(
$if(shorttitle)$
  running-head: "$shorttitle$",
$else$
$if(title)$
  running-head: "$title$",
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
$if(cols)$
  cols: $cols$,
$endif$
  doc,
)

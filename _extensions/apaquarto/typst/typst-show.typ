#show: doc => article(
$if(running-head)$
  running-head: "$running-head$",
$endif$
$if(paper)$
  paper: "$paper$",
$endif$
$if(margin)$
  margin: ($for(margin/pairs)$$margin.key$: $margin.value$,$endfor$),
$endif$
$if(font)$
  font: ("$font$",),
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

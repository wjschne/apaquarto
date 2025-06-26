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
$if(papersize)$
  paper: "$papersize$",
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
$if(toc)$
  toc: "true",
$endif$
$if(first-page)$
  first-page: $first-page$,
$endif$
$if(numbersections)$
  numbersections: $numbersections$,
$endif$
$if(number-depth)$
  numberdepth: $number-depth$,
$endif$
$if(suppress-title-page)$
  suppresstitlepage: $suppress-title-page$,
$endif$
  document,
)

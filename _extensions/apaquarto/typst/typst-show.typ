#show: document => $if(documentmode)$$documentmode$$else$man$endif$(
$if(title)$
  title: [$title$],
$endif$
$if(suppress-author)$
$else$
$if(by-author)$
  authors: ($for(by-author)$$if(it.apaauthordisplay)$[$it.apaauthordisplay$],$endif$$endfor$),
$endif$
$endif$
$if(keywords)$
  keywords: ($for(keywords)$"$keywords$",$endfor$),
$endif$
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
$if(jou-running-authors)$
  runningauthors: "$jou-running-authors$",
$endif$
$if(papersize)$
  paper: "$papersize$",
$endif$
$if(margin)$
  margin: ($for(margin/pairs)$$margin.key$: $margin.value$,$endfor$),
$endif$
$if(mainfont)$
  font: ($for(mainfont)$"$mainfont$",$endfor$),
$endif$
$if(monofont)$
  monofont: ($for(monofont)$"$monofont$",$endfor$),
$endif$
$if(fontsize)$
  fontsize: $fontsize$,
$endif$
$if(leading)$
  leading: $leading$,
$endif$
$if(spacing)$
  spacing: $spacing$,
$else$
$if(leading)$
  spacing: $leading$,
$endif$
$endif$
$if(lang)$
  lang: "$lang$",
$endif$
$if(cols)$
  cols: $cols$,
$endif$
$if(toc)$
  toc: true,
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

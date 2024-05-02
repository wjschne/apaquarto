#let appendixcounter = counter("appendix")
#let article(
  title: none,
  running-head: none,
  authors: none,
  affiliations: none,
  authornote: none,
  abstract: none,
  keywords: none,
  margin: (x: 1in, y: 1in),
  paper: "us-letter",
  font: ("Times New Roman"),
  fontsize: 12pt,
  leading: 18pt,
  spacing: 18pt,
  first-line-indent: 0.5in,
  toc: false,
  floatsintext: true,
  cols: 1,
  doc,
) = {

  set page(
    paper: paper,
    margin: margin,
    header-ascent: 50%,
    header: grid(
      columns: (9fr, 1fr),
      align(left)[#upper[#running-head]],
      align(right)[#counter(page).display()]
    )
  )

set table(
  stroke: (_, y) => (
      top: if y <= 1 { 0.5pt } else { 0pt },
      bottom: 1pt,
    )
)

  set par(
    justify: false, 
    leading: leading,
    first-line-indent: first-line-indent
  )

  // Also "leading" space between paragraphs
  set block(spacing: spacing, above: spacing, below: spacing)

  set text(
    font: font,
    size: fontsize
  )

show figure.where(kind: "quarto-float-fig"): it => [

    #if appendixcounter.get().at(0) > 0 [
      #heading(level: 2)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2)[#it.supplement #it.counter.display()]
    ]
    
    #par[#emph[#it.caption.body]]
    #align(center)[#it.body]
  
]

show figure.where(kind: "quarto-float-tbl"): it => [
  
    #if appendixcounter.get().at(0) > 0 [
      #heading(level: 2)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2)[#it.supplement #it.counter.display()]
    ]
    
    #par[#emph[#it.caption.body]]
    #block[#it.body]
    
]

 // Redefine headings up to level 5 
  show heading.where(
    level: 1
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(center)
    #set text(size: fontsize)
    #it.body
  ]
  

  show heading.where(
    level: 2
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(left)
    #set text(size: fontsize)
    #it.body
  ]
  
  show heading.where(
    level: 3
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(left)
    #set text(size: fontsize, style: "italic")
    #it.body
  ]

  show heading.where(
    level: 4
  ): it => text(
    size: 1em,
    weight: "bold",
    it.body
  )

  show heading.where(
    level: 5
  ): it => text(
    size: 1em,
    weight: "bold",
    style: "italic",
    it.body
  )

  if cols == 1 {
    doc
  } else {
    columns(cols, gutter: 4%, doc)
  }



  
}

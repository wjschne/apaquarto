//#assert(sys.version.at(1) >= 11 or sys.version.at(0) > 0, message: "This template requires Typst Version 0.11.0 or higher. The version of Quarto you are using uses Typst version is " + str(sys.version.at(0)) + "." + str(sys.version.at(1)) + "." + str(sys.version.at(2)) + ". You will need to upgrade to Quarto 1.5 or higher to use apaquarto-typst.")

// counts how many appendixes there are
#let appendixcounter = counter("appendix")
// make latex logo
// https://github.com/typst/typst/discussions/1732#discussioncomment-11286036
#let TeX = {
  set text(font: "New Computer Modern",)
  let t = "T"
  let e = text(baseline: 0.22em, "E")
  let x = "X"
  box(t + h(-0.14em) + e + h(-0.14em) + x)
}

#let LaTeX = {
  set text(font: "New Computer Modern")
  let l = "L"
  let a = text(baseline: -0.35em, size: 0.66em, "A")
  box(l + h(-0.32em) + a + h(-0.13em) + TeX)
}

#let firstlineindent=0.5in



// documentmode: man
#let man(
  title: none,
  runninghead: none,
  margin: (x: 1in, y: 1in),
  paper: "us-letter",
  font: ("Times", "Times New Roman"),
  fontsize: 12pt,
  leading: 18pt,
  spacing: 18pt,
  firstlineindent: 0.5in,
  toc: false,
  lang: "en",
  cols: 1,
  doc,
) = {

  set page(
    margin: margin,
    paper: paper,
    header-ascent: 50%,
    header: grid(
      columns: (9fr, 1fr),
      align(left)[#upper[#runninghead]],
      align(right)[#context counter(page).display()]
    )
  )


 

  set table(    
    stroke: (x, y) => (
        top: if y <= 1 { 0.5pt } else { 0pt },
        bottom: .5pt,
      )
  )

  set par(
    justify: false, 
    leading: leading,
    first-line-indent: firstlineindent
  )

  // Also "leading" space between paragraphs
  set block(spacing: spacing, above: spacing, below: spacing)

  set text(
    font: font,
    size: fontsize,
    lang: lang
  )

  show link: set text(blue)

  show quote: set pad(x: 0.5in)
  show quote: set par(leading: leading)
  show quote: set block(spacing: spacing, above: spacing, below: spacing)
  // show LaTeX
  show "TeX": TeX
  show "LaTeX": LaTeX

  // format figure captions
  show figure.where(kind: "quarto-float-fig"): it => block(width: 100%, breakable: false)[
    #if int(appendixcounter.display().at(0)) > 0 [
      #heading(level: 2, outlined: false)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2, outlined: false)[#it.supplement #it.counter.display()]
    ]
    #align(left)[#par[#emph[#it.caption.body]]]
    #align(center)[#it.body]
  ]
  
  // format table captions
  show figure.where(kind: "quarto-float-tbl"): it => block(width: 100%, breakable: false)[#align(left)[
  
    #if int(appendixcounter.display().at(0)) > 0 [
      #heading(level: 2, outlined: false)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2, outlined: false)[#it.supplement #it.counter.display()]
    ]
    #par[#emph[#it.caption.body]]
    #block[#it.body]
  ]]

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


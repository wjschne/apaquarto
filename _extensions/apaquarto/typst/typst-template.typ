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

// How far the blank paragraph that formattypst.lua puts before a first
// paragraph is pulled back up. It cancels the height of that blank
// paragraph, so it follows the leading, and journal mode resets it.
#let apafirstparshift = -18pt

// Shared APA layout for every document mode. man/jou/doc/stu (defined below the
// function) are thin presets that override only the parameters that differ —
// spacing, column count, justification, body font — while this function holds
// everything they have in common.
#let apa-layout(
  title: none,
  authors: (),
  keywords: (),
  runninghead: none,
  margin: (x: 1in, y: 1in),
  paper: "us-letter",
  font: ("Times", "Times New Roman"),
  // typst's own default monospace font
  monofont: ("DejaVu Sans Mono",),
  fontsize: 12pt,
  leading: 18pt,
  spacing: 18pt,
  firstlineindent: 0.5in,
  quoteinset: 0.5in,
  toc: false,
  lang: "en",
  cols: 1,
  justify: false,
  headerstyle: "running",
  pagenumbering: none,
  numbersections: false,
  numberdepth: 3,
  first-page: 1,
  suppresstitlepage: false,
  updatepagecounter: false,
  doc,
) = {

  // Document metadata for pdf accessibility. A pdf has no title without
  // this, which is one of the things pdf/ua conformance asks for.
  set document(title: title, keywords: keywords)
  set document(author: authors.map(content-to-string)) if authors != ()

  // Manuscript modes set the first page via the front-matter page break; journal
  // and document modes have no such break, so honor first-page directly here.
  if suppresstitlepage or updatepagecounter {counter(page).update(first-page)}
  
  // code blocks and inline code
  show raw: set text(font: monofont)

   show raw.where(block: true): set par(
    spacing: 6pt,
    leading: 6pt
  )
  
  show raw.where(block: true): set text(
    size: 10pt
  )

  // Page header per mode: running head (man), page number only (stu), running
  // head suppressed on the first page (jou), or none (doc, which numbers pages
  // at the foot instead).
  let pageheader = if headerstyle == "pagenum" {
    align(right)[#context counter(page).display()]
  } else if headerstyle == "jou" {
    context {
      if counter(page).get().at(0) > first-page {
        grid(
          columns: (9fr, 1fr),
          align(left)[#upper[#runninghead]],
          align(right)[#counter(page).display()],
        )
      }
    }
  } else if headerstyle == "none" {
    none
  } else {
    grid(
      columns: (9fr, 1fr),
      align(left)[#upper[#runninghead]],
      align(right)[#context counter(page).display()],
    )
  }

  set page(
    margin: margin,
    paper: paper,
    columns: cols,
    numbering: pagenumbering,
    header-ascent: 50%,
    header: pageheader,
  )
  

  

 

  set table(    
    stroke: (x, y) => (
        top: if y <= 1 { 0.5pt } else { 0pt },
        bottom: .5pt,
      )
  )

  set par(
    justify: justify,
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
  show "al.'s": "al.\u{2019}s"

  show quote: set pad(x: quoteinset)
  show quote: set par(leading: leading)
  show quote: set block(spacing: spacing, above: spacing, below: spacing)
  // show LaTeX
  show "TeX": TeX
  show "LaTeX": LaTeX

  // format figure captions
  show figure.where(kind: "quarto-float-fig"): it => block(width: 100%, breakable: false)[
  #if type(it.numbering) == function [
      #it
    ] else [
    #if int(appendixcounter.display().at(0)) > 0 [
      #heading(level: 2, outlined: false)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2, outlined: false)[#it.supplement #it.counter.display()]
    ]
    #align(left)[#par[#emph[#it.caption.body]]]
    #align(center)[#it.body]
    
  ]]
  
  // format table captions
  // skip custom formatting for sub-figures inside quarto_super (their numbering is set to a function)
  show figure.where(kind: "quarto-float-tbl"): it => {
    if type(it.numbering) == function {
      it
    } else {
      block(width: 100%, breakable: false)[#align(left)[

        #if int(appendixcounter.display().at(0)) > 0 [
          #heading(level: 2, outlined: false, numbering: none)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
        ] else [
          #heading(level: 2, outlined: false, numbering: none)[#it.supplement #it.counter.display()]
        ]
        #par[#emph[#it.caption.body]]
        #block[#it.body]
      ]]
    }
  }
  
    set heading(numbering: "1.1")
    
    show heading: set text(size: fontsize)


 // Redefine headings up to level 5 
  show heading.where(
    level: 1
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(center)
    #if(numbersections and it.outlined and numberdepth > 0 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]
  
  show heading.where(
    level: 2
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(left)
    #if(numbersections and it.outlined and numberdepth > 1 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]
  
  show heading.where(
    level: 3
  ): it => block(width: 100%, below: leading, above: leading)[
    #set align(left)
    #set text(style: "italic")
    #if(numbersections and it.outlined and numberdepth > 2 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]

  show heading.where(
    level: 4
  ): it => text(
    weight: "bold",
    it.body
  )

  show heading.where(
    level: 5
  ): it => text(
    weight: "bold",
    style: "italic",
    it.body
  )
  
  

  // Column layout is set at the page level (set page(columns: ...)) rather than
  // with the columns() container, because the title page and abstract use
  // pagebreaks, which are not permitted inside a container.
  doc
}

// documentmode: man — APA manuscript: double-spaced, single column. This is the
// default mode and uses apa-layout's defaults unchanged.
#let man(..args) = apa-layout(..args)

// documentmode: jou — APA published-article style: two columns, justified,
// single-spaced, smaller body font, tighter margins. The running head is
// suppressed on the first page. The full-width title/abstract masthead (so it
// spans both columns) is assembled in frontmatter.lua.
#let jou(..args) = apa-layout(
  margin: (x: 0.75in, y: 0.8in),
  fontsize: 10pt,
  leading: 11pt,
  spacing: 5pt,
  firstlineindent: 0.15in,
  quoteinset: 0.25in,
  cols: 2,
  justify: true,
  headerstyle: "jou",
  updatepagecounter: true,
  ..args,
)

// documentmode: doc — a plain, continuous one-column document: justified, no
// title page or running head, page numbers at the foot. For notes and reports
// that do not need full manuscript formatting.
#let doc(..args) = apa-layout(
  leading: 14pt,
  spacing: 8pt,
  firstlineindent: 0.25in,
  justify: true,
  headerstyle: "none",
  pagenumbering: "1",
  updatepagecounter: true,
  ..args,
)

// documentmode: stu — student paper. Manuscript page layout, but the header is
// the page number only (no running head); student-specific title-page fields
// (course, professor, due date, note) are added in the front matter.
#let stu(..args) = apa-layout(
  headerstyle: "pagenum",
  ..args,
)


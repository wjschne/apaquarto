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
// The body first-line indent for the modes that do not use the manuscript's
// half inch. formattypst.lua names one of these when it has to restore the
// body indent after a block that suspends it, so the value lives in one place.
#let joufirstlineindent = 0.15in
#let docfirstlineindent = 0.25in

// first-line-indent takes a plain length before typst 0.13 and accepts a
// dictionary from 0.13 on, where all: true indents the paragraph that opens a
// section as well as the ones that follow. Everything that sets the indent
// goes through here so the two forms stay in one place.
#let apaparindent(amount, all: false) = if all and sys.version >= version(0, 13, 0) {
  (amount: amount, all: true)
} else {
  amount
}

// Masthead metrics for journal mode, following what apa7 does there. apa7 jou
// loads article at a 10pt base, so its size commands come out as: title
// \LARGE = 17.28pt, the byline \large = 12pt, affiliations \normalsize = 10pt,
// and the abstract \small = 9pt. apa7 sets the abstract in a 4.6875in parbox,
// which is why the abstract and impact statement are narrower than the
// masthead around them. frontmatter.lua reads these when it builds the jou
// masthead.
#let joutitlesize = 17.28pt
#let jouauthorsize = 12pt
#let jouaffiliationsize = 10pt
// apa7 jou sets 10pt text on a 12pt baseline. Typst's leading is the gap
// between lines rather than the baseline-to-baseline distance, so the 11pt
// this once said produced about 17.5pt of line spacing, half again what a
// journal article uses; 5.5pt measures as the 12pt apa7 gives. Named because
// the block quotations run their paragraphs on at exactly this spacing.
#let jouleading = 5.5pt
#let jouabstractsize = 9pt
#let jouabstractwidth = 4.6875in
// Kept in em so it tracks the smaller abstract text at the same ratio the jou
// body uses. Measures as the 11pt baseline apa7 gives its \small abstract.
#let jouabstractleading = 0.55em

// The byline and the affiliation lines under it are single spaced, the way
// apa7 stacks them, rather than taking the space the body puts between
// paragraphs.
#let joubylinepar = (leading: 0.55em, spacing: 0.55em, first-line-indent: 0pt)

// Paragraph settings for the journal-mode author note: every paragraph
// indented, and separated by nothing more than the line spacing, so the note
// reads as continuous text. Typst only gained the dictionary form of
// first-line-indent, which indents the opening paragraph as well, in 0.13, so
// the plain length is kept as a fallback and the whole set is spread into the
// set rule. (Journal mode already needs 0.12 for place(scope: "parent").)
#let jounotepar = if sys.version >= version(0, 13, 0) {
  (leading: 0.55em, spacing: 0.55em,
   first-line-indent: (amount: joufirstlineindent, all: true))
} else {
  (leading: 0.55em, spacing: 0.55em, first-line-indent: joufirstlineindent)
}

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
  // Surnames for the journal even-page running head, already assembled by
  // frontmatter.lua. none falls back to the short title on those pages.
  runningauthors: none,
  // Size of the running head. none follows the body.
  headersize: none,
  // Size of the page number, which a journal sets larger than the running head
  // beside it. none follows the running head.
  pagenumsize: none,
  // How far the header is raised off the top of the text block, either as a
  // share of the top margin or as an absolute length. 0% sits it at the foot of
  // the margin, just above the text.
  headerascent: 50%,
  margin: (x: 1in, y: 1in),
  paper: "us-letter",
  font: ("Times", "Times New Roman"),
  // typst's own default monospace font
  monofont: ("DejaVu Sans Mono",),
  fontsize: 12pt,
  leading: 18pt,
  spacing: 18pt,
  firstlineindent: 0.5in,
  // Indent the paragraph that opens a section too, not just the ones after
  // another paragraph. Journal mode wants every body paragraph indented.
  indentall: false,
  // Size of the level 1 to 3 section headings, and the space above and below
  // them. none means follow the body: fontsize and leading.
  headingsize: none,
  headingspace: none,
  quoteinset: 0.5in,
  // Block quotations. none follows the body: its size, its line spacing, its
  // space above and below a block, and its rule about whether the paragraph
  // that opens a block is indented. quoteparspace is the exception: none
  // leaves the space between the paragraphs of a quotation to typst rather
  // than setting it to anything of ours.
  quotesize: none,
  quoteleading: none,
  quoteparspace: none,
  quotespace: none,
  quoteindentall: none,
  // Space above a figure or table, ahead of its "Figure 1" / "Table 1" title.
  // none follows the body's space between blocks. Typst takes the larger of
  // this and whatever the element above asks for below itself, so a float
  // after a section heading keeps the heading's space.
  floatspace: none,
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
    // A published article carries the short title on odd pages and the author
    // surnames on even ones, centered and in caps, with the page number in the
    // outer corner: left on even (verso) pages, right on odd (recto) ones. The
    // opening page carries none of it.
    context {
      let pg = counter(page).get().at(0)
      if pg > first-page {
        let verso = calc.even(pg)
        let middle = if verso and runningauthors != none {
          runningauthors
        } else {
          runninghead
        }
        let hs = if headersize == none { fontsize } else { headersize }
        let num = text(size: if pagenumsize == none { hs } else { pagenumsize })[
          #counter(page).display()
        ]
        set text(size: hs)
        grid(
          columns: (1fr, auto, 1fr),
          // The three cells sit on a common baseline, so the larger page
          // number lines up with the running head rather than riding above it.
          align(bottom + left)[#if verso [#num]],
          align(bottom + center)[#upper[#middle]],
          align(bottom + right)[#if not verso [#num]],
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
    header-ascent: headerascent,
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
    first-line-indent: apaparindent(firstlineindent, all: indentall)
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

  // A block quotation takes the body's measurements unless a mode overrides
  // them. quotespace is the space that sets the quotation off from the text
  // around it; the paragraphs inside it are separated by their own leading
  // and nothing more, so a quotation of several paragraphs reads as one
  // passage rather than as a run of separate blocks.
  let qsize = if quotesize == none { fontsize } else { quotesize }
  let qleading = if quoteleading == none { leading } else { quoteleading }
  let qspace = if quotespace == none { spacing } else { quotespace }
  let qindentall = if quoteindentall == none { indentall } else { quoteindentall }
  let fspace = if floatspace == none { spacing } else { floatspace }

  show quote: set pad(x: quoteinset)
  show quote: set text(size: qsize)
  // The gap between two paragraphs is par's spacing, not block's: a paragraph
  // is not a block, so a set block rule never reaches it. Setting spacing to
  // the leading is what runs the paragraphs of a quotation on, the way the
  // author note is run on in journal mode. It is only set at all when a mode
  // asks for it, because naming it at the body's value is not the same as
  // leaving it alone: typst's own default is 1.2em, which is what a quotation
  // takes when nothing here says otherwise.
  let qpar = (
    leading: qleading,
    first-line-indent: apaparindent(firstlineindent, all: qindentall)
  )
  let qpar = if quoteparspace == none { qpar } else {
    qpar + (spacing: quoteparspace)
  }
  show quote: set par(..qpar)
  show quote: set block(spacing: qspace, above: qspace, below: qspace)
  // show LaTeX
  show "TeX": TeX
  show "LaTeX": LaTeX

  // format figure captions
  show figure.where(kind: "quarto-float-fig"): it => block(width: 100%, breakable: false, above: fspace)[
  #if type(it.numbering) == function [
      #it
    ] else [
    #if int(appendixcounter.display().at(0)) > 0 [
      #heading(level: 2, outlined: false)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    ] else [
      #heading(level: 2, outlined: false)[#it.supplement #it.counter.display()]
    ]
    #align(left)[#par(first-line-indent: 0pt)[#emph[#it.caption.body]]]
    #align(center)[#it.body]
    
  ]]
  
  // format table captions
  // skip custom formatting for sub-figures inside quarto_super (their numbering is set to a function)
  show figure.where(kind: "quarto-float-tbl"): it => {
    if type(it.numbering) == function {
      it
    } else {
      block(width: 100%, breakable: false, above: fspace)[#align(left)[

        #if int(appendixcounter.display().at(0)) > 0 [
          #heading(level: 2, outlined: false, numbering: none)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
        ] else [
          #heading(level: 2, outlined: false, numbering: none)[#it.supplement #it.counter.display()]
        ]
        #par(first-line-indent: 0pt)[#emph[#it.caption.body]]
        #block[#it.body]
      ]]
    }
  }
  
    set heading(numbering: "1.1")

    show heading: set text(size: fontsize)

  // Section headings may be set larger than the body and given their own space
  // above and below. Only headings that are outlined get it: the float labels
  // ("Figure 1", "Table 1") and the masthead headings are level 1 to 3 headings
  // too, but they are not outlined, and they carry sizes of their own that
  // frontmatter.lua sets. The size goes in a set rule on the heading rather
  // than inside the block below, because a set rule inside the block would be
  // the innermost one and would override those.
  let hsize = if headingsize == none { fontsize } else { headingsize }
  let headspace = it => if it.outlined {
    if headingspace == none { leading } else { headingspace }
  } else { leading }

  show heading.where(level: 1, outlined: true): set text(size: hsize)
  show heading.where(level: 2, outlined: true): set text(size: hsize)
  show heading.where(level: 3, outlined: true): set text(size: hsize)


 // Redefine headings up to level 5 
  // Levels 1 to 3 are set ragged right with hyphenation off, even where the
  // body is justified. Stretching a two-line heading to the column edge, or
  // breaking a word in it, is not something a journal does.
  show heading.where(
    level: 1
  ): it => block(width: 100%, below: headspace(it), above: headspace(it))[
    #set align(center)
    #set par(justify: false)
    #set text(hyphenate: false)
    #if(numbersections and it.outlined and numberdepth > 0 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]
  
  show heading.where(
    level: 2
  ): it => block(width: 100%, below: headspace(it), above: headspace(it))[
    #set align(left)
    #set par(justify: false)
    #set text(hyphenate: false)
    #if(numbersections and it.outlined and numberdepth > 1 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]
  
  show heading.where(
    level: 3
  ): it => block(width: 100%, below: headspace(it), above: headspace(it))[
    #set align(left)
    #set par(justify: false)
    #set text(hyphenate: false, style: "italic")
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
  margin: (x: 0.75in, y: 1in),
  // 10pt body text, against the 12pt the other modes take from apa-layout.
  fontsize: 10pt,
  leading: jouleading,
  spacing: 5pt,
  firstlineindent: joufirstlineindent,
  // Every body paragraph is indented in a journal article, including the one
  // that opens a section.
  indentall: true,
  // Section headings stand above the 10pt body, with a fixed 9pt of air on
  // either side rather than the body's tighter leading.
  headingsize: 11pt,
  headingspace: 9pt,
  quoteinset: 0.25in,
  // apa7 sets a block quotation smaller than the text around it. The
  // paragraph that opens the quotation runs flush left and the ones after it
  // are indented, the way a quoted passage is set, and they are separated by
  // nothing more than the line spacing so the passage reads as one quotation.
  // The quotation as a whole is given the same 9 points of air the section
  // headings get.
  quotesize: 9pt,
  quoteparspace: jouleading,
  quotespace: 9pt,
  quoteindentall: false,
  // A figure or table title stands off the text above it by the same 9 points
  // the section headings and the block quotations get, rather than by the
  // body's tighter space between paragraphs.
  floatspace: 9pt,
  cols: 2,
  justify: true,
  headerstyle: "jou",
  headersize: 8pt,
  pagenumsize: 10pt,
  // Sit the running head in the top margin, 12pt clear of the text block.
  headerascent: 12pt,
  updatepagecounter: true,
  ..args,
)

// documentmode: doc — a plain, continuous one-column document: justified, no
// title page or running head, page numbers at the foot. For notes and reports
// that do not need full manuscript formatting.
#let doc(..args) = apa-layout(
  leading: 14pt,
  spacing: 8pt,
  firstlineindent: docfirstlineindent,
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


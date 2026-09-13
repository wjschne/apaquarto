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
// The masthead of a published article, following the Journal of Educational
// Psychology: the journal's name set larger than the body at the right of the
// page, the logo opposite it, a rule under both, and the issue and the
// copyright in small type on either side beneath. Measured off that journal,
// whose own page is narrower than letter: a 12pt name over 6pt metadata on an
// 8pt body. The metadata is set at the 8pt this template already gives the
// running head rather than at 6pt, which is smaller than anything else here
// and hard to read on the wider page.
#let joujournalsize = 12pt
#let joumastheadsize = 8pt
// A band the logo is fitted to, whatever its proportions.
#let joulogoheight = 0.5in

// A journal sets its masthead high on the page, above where the text of the
// page begins. The masthead is lifted into the top margin by half of it, which
// puts the head of the first page about where the journals put it. Lifting it
// rather than giving the document a shorter margin leaves every page after the
// first as the mode set it, running head and all. Half of whatever the margin
// is, so that a document setting its own margin is followed rather than
// overruled.
#let joumastheadlift() = context {
  let m = page.margin
  let top = if type(m) == dictionary {
    m.at("top", default: m.at("y", default: 1in))
  } else {
    m
  }
  v(-top / 2)
}
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

// The journal-mode author note. apa7 sets it at the foot of the first column,
// under a thin rule, and that is where a note of ordinary length goes here.
// A long note fills that column and leaves the article with nowhere to start:
// the body text is pushed into what little is left above it while the second
// column stands empty. Past a third of the column the note runs across the
// foot of the page in two columns instead, which is what the journals
// themselves do with a long note. cols overrides that reading: 1 keeps the
// note in one column however long it runs, 2 sends it across the page however
// short it is, and auto measures it.
//
// The two-column block is given half the height the note takes in one column.
// Both columns are that same width, so the note breaks into the same lines
// either way and half its height is what each column needs; naming that
// height is also what makes typst fill the first column and carry the rest
// into the second, since columns of automatic height put everything in the
// first.
//
// Half of a height is rarely a whole number of lines, though, and the line the
// first column cannot fit has to go somewhere: too little height does not clip
// the note, it spills it up across the rule. That rounding is a line or so
// however long the note is, which against the fifteen lines or more it takes
// to reach two columns on its own comes out in the wash, but against the four
// or five lines of a short note somebody has asked for in two columns is the
// difference between setting and spilling. So a short note is given two lines
// to round into and a long one is left to balance exactly.
#let jounotethreshold = 1 / 3

// One column as a share of the width of the text, with the 4% gutter typst
// puts between columns by default.
#let jounotecolumn = 0.48

#let jouauthornote(body, cols: auto) = context {
  let m = page.margin
  let mx = if type(m) == dictionary { m.at("x", default: 1in) } else { m }
  let my = if type(m) == dictionary { m.at("y", default: 1in) } else { m }
  let textwidth = page.width - 2 * mx
  let textheight = page.height - 2 * my
  let columnwidth = jounotecolumn * textwidth

  // The note as it is set: smaller than the body, its paragraphs indented and
  // run on. The styling goes inside the measured content, so that the height
  // measured is the height the note will take.
  let note = {
    set text(size: 9pt)
    set par(..jounotepar)
    set block(spacing: 0.55em)
    body
  }

  let ruled(content) = block(
    width: 100%, above: 0.5em, below: 0.8em,
    // 3pt more than the 0.4em the note used to sit under, which put the
    // ascenders of its first line very nearly on the rule.
    inset: (top: 0.4em + 3pt), stroke: (top: 0.5pt),
    content
  )

  let height = measure(block(width: columnwidth, note)).height
  let line = measure(block(width: columnwidth, {
    set text(size: 9pt)
    [X]
  })).height

  // Long enough to fill a column on its own, which is both what sends a note
  // across the page when nobody has said otherwise and what makes its halves
  // round cleanly.
  let long = height > textheight * jounotethreshold
  let twocolumn = if cols == auto { long } else { cols == 2 }
  let slack = if long { 0pt } else { 2 * line }

  if twocolumn {
    // scope: "parent" spans the page rather than the column. It only works
    // from the flow itself, so this is written inside context and never
    // inside layout, which would tie the float back to its column.
    // place(bottom, ..) hands its alignment down to what it holds, which
    // would settle both columns against the foot of the block and leave the
    // shorter of the two starting lower than the other. The columns are
    // pinned to the top so that they begin level, whatever slack is left at
    // the foot of the second.
    place(bottom, scope: "parent", float: true,
      ruled(block(width: 100%, height: height / 2 + slack,
        align(top, columns(2, gutter: 4%, note)))))
  } else {
    place(bottom, float: true, ruled(note))
  }
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


// Simple numbering for non-book documents
#let equation-numbering = "(1)"
#let callout-numbering = "1"
#let subfloat-numbering(n-super, subfloat-idx) = {
  numbering("1a", n-super, subfloat-idx)
}

// Theorem configuration for theorion
// Simple numbering for non-book documents (no heading inheritance)
#let theorem-inherited-levels = 0

// Theorem numbering format (can be overridden by extensions for appendix support)
// This function returns the numbering pattern to use
#let theorem-numbering(loc) = "1.1"

// Default theorem render function
#let theorem-render(prefix: none, title: "", full-title: auto, body) = {
  if full-title != "" and full-title != auto and full-title != none {
    strong[#full-title.]
    h(0.5em)
  }
  body
}
// Some definitions presupposed by pandoc's typst output.
#let content-to-string(content) = {
  if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(content-to-string).join("")
  } else if content.has("body") {
    content-to-string(content.body)
  } else if content == [ ] {
    " "
  }
}

#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#let endnote(num, contents) = [
  #stack(dir: ltr, spacing: 3pt, super[#num], contents)
]

#show terms.item: it => block(breakable: false)[
  #text(weight: "bold")[#it.term]
  #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
]

// Some quarto-specific definitions.

#show raw.where(block: true): set block(
    fill: luma(230),
    width: 100%,
    inset: 8pt,
    radius: 2pt
  )

#let block_with_new_content(old_block, new_content) = {
  let fields = old_block.fields()
  let _ = fields.remove("body")
  if fields.at("below", default: none) != none {
    // TODO: this is a hack because below is a "synthesized element"
    // according to the experts in the typst discord...
    fields.below = fields.below.abs
  }
  block.with(..fields)(new_content)
}

#let empty(v) = {
  if type(v) == str {
    // two dollar signs here because we're technically inside
    // a Pandoc template :grimace:
    v.matches(regex("^//s*$")).at(0, default: none) != none
  } else if type(v) == content {
    if v.at("text", default: none) != none {
      return empty(v.text)
    }
    for child in v.at("children", default: ()) {
      if not empty(child) {
        return false
      }
    }
    return true
  }

}

// Subfloats
// This is a technique that we adapted from https://github.com/tingerrr/subpar/
#let quartosubfloatcounter = counter("quartosubfloatcounter")

#let quarto_super(
  kind: str,
  caption: none,
  label: none,
  supplement: str,
  position: none,
  subcapnumbering: "(a)",
  body,
) = {
  context {
    let figcounter = counter(figure.where(kind: kind))
    let n-super = figcounter.get().first() + 1
    set figure.caption(position: position)
    [#figure(
      kind: kind,
      supplement: supplement,
      caption: caption,
      {
        show figure.where(kind: kind): set figure(numbering: _ => {
          let subfloat-idx = quartosubfloatcounter.get().first() + 1
          subfloat-numbering(n-super, subfloat-idx)
        })
        show figure.where(kind: kind): set figure.caption(position: position)

        show figure: it => {
          let num = numbering(subcapnumbering, n-super, quartosubfloatcounter.get().first() + 1)
          show figure.caption: it => block({
            num.slice(2) // I don't understand why the numbering contains output that it really shouldn't, but this fixes it shrug?
            [ ]
            it.body
          })

          quartosubfloatcounter.step()
          it
          counter(figure.where(kind: it.kind)).update(n => n - 1)
        }

        quartosubfloatcounter.update(0)
        body
      }
    )#label]
  }
}

// callout rendering
// this is a figure show rule because callouts are crossreferenceable
#show figure: it => {
  if type(it.kind) != str {
    return it
  }
  let kind_match = it.kind.matches(regex("^quarto-callout-(.*)")).at(0, default: none)
  if kind_match == none {
    return it
  }
  let kind = kind_match.captures.at(0, default: "other")
  kind = upper(kind.first()) + kind.slice(1)
  // now we pull apart the callout and reassemble it with the crossref name and counter

  // when we cleanup pandoc's emitted code to avoid spaces this will have to change
  let old_callout = it.body.children.at(1).body.children.at(1)
  let old_title_block = old_callout.body.children.at(0)
  let children = old_title_block.body.body.children
  let old_title = if children.len() == 1 {
    children.at(0)  // no icon: title at index 0
  } else {
    children.at(1)  // with icon: title at index 1
  }

  // TODO use custom separator if available
  // Use the figure's counter display which handles chapter-based numbering
  // (when numbering is a function that includes the heading counter)
  let callout_num = it.counter.display(it.numbering)
  let new_title = if empty(old_title) {
    [#kind #callout_num]
  } else {
    [#kind #callout_num: #old_title]
  }

  let new_title_block = block_with_new_content(
    old_title_block,
    block_with_new_content(
      old_title_block.body,
      if children.len() == 1 {
        new_title  // no icon: just the title
      } else {
        children.at(0) + new_title  // with icon: preserve icon block + new title
      }))

  align(left, block_with_new_content(old_callout,
    block(below: 0pt, new_title_block) +
    old_callout.body.children.at(1)))
}

// <date>: #fa-icon("fa-info") is not working, so we'll eval "#fa-info()" instead
#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false,
    fill: background_color,
    stroke: (paint: icon_color, thickness: 0.5pt, cap: "round"),
    width: 100%,
    radius: 2pt,
    block(
      inset: 1pt,
      width: 100%,
      below: 0pt,
      block(
        fill: background_color,
        width: 100%,
        inset: 8pt)[#if icon != none [#text(icon_color, weight: 900)[#icon] ]#title]) +
      if(body != []){
        block(
          inset: 1pt,
          width: 100%,
          block(fill: body_background_color, width: 100%, inset: 8pt, body))
      }
    )
}



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

// A dissertation sets its body double spaced, but a block quotation and the
// entries of its reference list single spaced, all as the .pdf does. Typst
// counts leading from the bottom of one line to the top of the next, so a
// line stands its leading plus about 8pt (the height of a capital at 12pt)
// below the one above: 16pt sets the .pdf's 24pt double spacing, and 0.5em
// its 14pt single spacing (measured in tests/layout-thesis.qmd). They were
// 18pt and typst's own 0.65em, which set 26pt and 16pt.
#let thesissingleleading = 0.5em
#let thesisleading = 16pt

// The entries of a dissertation's reference list: single spaced within an
// entry, with a double space between one entry and the next, which is the
// space the body's own lines stand apart. formattypst.lua wraps the list in
// this rather than setting the spacing around it, so that the settings reach
// the entries and stop there --- an appendix follows the references and takes
// the body's spacing again.
#let thesisreferences(body) = {
  set par(leading: thesissingleleading, spacing: thesisleading)
  body
}

// first-line-indent takes a plain length before typst 0.13 and accepts a
// dictionary from 0.13 on, where all: true indents the paragraph that opens a
// section as well as the ones that follow. Everything that sets the indent
// goes through here so the two forms stay in one place.
//
// From 0.13 on, all: false is said in so many words rather than left to a
// plain length. A plain length set inside something whose surroundings say
// all: true changes only the amount and keeps that all: true, so a journal's
// block quotation, whose body indents every paragraph, had its first
// paragraph indented whenever it had a second one, an attribution included.
// A block that stays on the page with the start of the block after it, as a
// heading does: a figure's number and caption with its picture, and the
// picture with the first line of its note. sticky is Typst 0.12's; before
// that the block simply has nothing to hold it.
#let apasticky = if sys.version >= version(0, 12, 0) { (sticky: true) } else { (:) }

#let apaparindent(amount, all: false) = if sys.version >= version(0, 13, 0) {
  (amount: amount, all: all)
} else {
  amount
}

// Masthead metrics for journal mode, following what apa7 does there. apa7 jou
// loads article at a 10pt base, so its size commands come out as: title
// /LARGE = 17.28pt, the byline /large = 12pt, affiliations /normalsize = 10pt,
// and the abstract /small = 9pt. apa7 sets the abstract in a 4.6875in parbox,
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

// --- documentmode: doc ------------------------------------------------------
// A plain document has no title page, so the title is marked out by its size
// rather than by weight: apa7 sets it large and unemphasised there, and a bold
// title in a continuous document reads as a heading over the paragraph under
// it. 1.44x the body text, which is the size the journal title takes too.
#let doctitlesize = 17.28pt

// The abstract is inset from both margins. Set at the full measure it reads as
// one more body paragraph; apa7 insets it by about an eighth of the text block
// on each side, which is what this comes to.
#let docabstractwidth = 77%


// The line spacing of document mode, named so that the space after the
// abstract can be two lines of it rather than a number that has to be kept in
// step by hand.
#let docleading = 14pt

#let apadoctitle(body) = {
  set align(center)
  text(size: doctitlesize, weight: "regular")[#body]
}

#let apadocabstract(body) = {
  set align(center)
  block(width: docabstractwidth)[#align(left)[#body]]
}

// Two lines clear of the abstract before the body starts.
#let apadocabstractgap() = v(2 * docleading, weak: true)

// How much the author note is stepped down from the body. Applied on top of
// the size typst already gives a footnote, which together come to about the
// size apa7 sets the note at. It is not only a matter of looks: a note set
// larger than this takes enough lines out of the foot of the first page that
// typst moves the paragraph carrying its mark to the second page, and the note
// goes with it.
#let docauthornotesize = 0.83em

// The rule that sets the author note apart from the body above it. A third of
// the measure, which is what typst draws for a footnote by default and close to
// what latex draws for one.
#let docauthornoterule = line(length: 33%, stroke: 0.5pt)

// A footnote rather than a floating placement at the foot of the page.
//
// A float goes to the foot of the page if it fits and to the next page if it
// does not, and the first page of a document with a long abstract has no room
// left: the note came out at the foot of page two. A footnote is tied to the
// page its mark is on, so it stays on the first page whatever else is there.
//
// The mark itself is numbered to nothing, so neither the empty superscript in
// the front matter nor a number in front of the note is shown; APA's author
// note carries no footnote number.
#let apadocauthornote(body) = footnote(
  numbering: _ => "",
)[#text(size: docauthornotesize)[#body]]
// Kept in em so it tracks the smaller abstract text at the same ratio the jou
// body uses. Measures as the 11pt baseline apa7 gives its /small abstract.
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
// The face the line numbers take when numbered-lines asks for them.
//
// apa7 numbers with lineno, which sets its numbers in a sans face. Typst
// bundles exactly one sans -- DejaVu Sans Mono -- and naming any family it
// cannot find draws a warning for that family on every render, whether or not
// a later name in the list resolves. There is no way to quiet that warning in
// typst 0.14: there is no allow(), no flag on typst compile, and quarto's own
// --quiet would hide real errors along with it. So the default names only the
// family typst is certain to have, which is silent on every machine and sets
// the same numbers everywhere.
//
// Monospaced digits are no loss in a margin, where the numbers are set flush
// right and a fixed width lines them up.
//
// linenumber-font names another, for a writer who knows the machine has it:
//
//   linenumber-font: Helvetica
//   linenumber-font: [Helvetica, Arial]
#let linenumberfont = ("DejaVu Sans Mono",)


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
  // How far the footer is set below the text block. Only journal mode has one.
  footerdescent: 11pt,
  margin: (x: 1in, y: 1in),
  paper: "us-letter",
  font: ("Times", "Times New Roman"),
  // typst's own default monospace font
  monofont: ("DejaVu Sans Mono",),
  fontsize: 12pt,
  // Double spacing: 24pt from one baseline to the next at 12pt, which is the
  // .pdf's. Typst counts leading from the bottom of one line to the top of the
  // next, so 16pt here is the 24pt on the page (measured in
  // tests/layout-manuscript.qmd). It was 18pt, which set 26pt.
  leading: 16pt,
  spacing: 16pt,
  firstlineindent: 0.5in,
  // Indent the paragraph that opens a section too, not just the ones after
  // another paragraph. Journal mode wants every body paragraph indented.
  indentall: false,
  // Size of the level 1 to 3 section headings, and the space above and below
  // them. none means follow the body: fontsize and leading.
  headingsize: none,
  // How much larger than the body a heading is when headingsize is none, so
  // that a mode can keep its headings a step above whatever size the body is
  // set at.
  headinggrow: 0pt,
  headingspace: none,
  // The space above them alone, where a mode wants more there than below.
  // none means headingspace.
  headingabove: none,
  quoteinset: 0.5in,
  // How far a block quotation stands in from the right margin: not at all,
  // in every mode, as in the .pdf, .docx and .html. none means quoteinset,
  // the same as from the left.
  quoteinsetright: 0pt,
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
  // Numbered notes. none leaves a footnote as typst sets one: its number in a
  // box of its own at the head of the entry, and the entries a little apart.
  // noteindent is how far in a note's first line begins, its turned lines
  // running to the margin; notegap is the space between one note and the next.
  noteindent: none,
  notegap: none,
  // Space above and below a figure or table, ahead of its "Figure 1" /
  // "Table 1" title and after its note. none is a blank line of the body's
  // spacing, as APA asks of a manuscript. Typst takes the larger of
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

  // The opening page of a published article carries its number at the centre
  // of the bottom margin, where the running head has not started yet. Every
  // journal APA prints does this; the Journal of Educational Psychology, which
  // the rest of this mode is measured against, sets it at the running head's
  // own size rather than the larger size it gives the number in the head.
  //
  // The opening page only. From the second page on the number is in the head,
  // in the outer corner, and a second one at the foot would be one too many.
  let pagefooter = if headerstyle == "jou" {
    context {
      let pg = counter(page).get().at(0)
      if pg <= first-page {
        set text(size: if headersize == none { fontsize } else { headersize })
        align(center)[#counter(page).display()]
      }
    }
  } else {
    // auto, not none. A page told outright that it has no footer shows no
    // page number either, whatever its numbering says, so pagenumbering did
    // nothing at all in the modes that set one: doc numbered no page, and
    // neither did thesis. auto leaves typst to draw the number it was asked
    // for, at the centre of the foot, and shows nothing where the numbering
    // is none.
    auto
  }

  set page(
    margin: margin,
    paper: paper,
    columns: cols,
    numbering: pagenumbering,
    header-ascent: headerascent,
    header: pageheader,
    footer: pagefooter,
    // The number sits a line or so under the text block, which is where the
    // Journal of Educational Psychology puts it: eleven points under, against
    // the three typst leaves of its own accord.
    footer-descent: footerdescent,
  )






  set table(
    stroke: (x, y) => (
        top: if y <= 1 { 0.5pt } else { 0pt },
        bottom: .5pt,
      )
  )

  // The space between two paragraphs is the space between two lines, so
  // that a double-spaced manuscript is double spaced throughout and a journal
  // page marks a new paragraph by its indent alone. Since Typst 0.12 that
  // space is par's spacing, which a set block rule does not reach; left
  // unset it was Typst's own 1.2em, 2pt short of double spacing in a
  // manuscript, 7pt of extra air between the paragraphs of a journal, and
  // deaf to a document's own leading.
  set par(
    justify: justify,
    leading: leading,
    spacing: leading,
    first-line-indent: apaparindent(firstlineindent, all: indentall)
  )

  // A cell takes the alignment of its column and nothing else. set par reaches
  // inside a table as it does everywhere, so in the modes whose body is
  // justified -- jou and doc -- a cell long enough to wrap was justified too,
  // and a column the writer had asked to be left aligned came out with its
  // gaps stretched to the column edge. APA sets no table that way.
  show table: set par(justify: false)

  // The space above and below a block: a quotation, a list, a figure, code.
  // Not the space between paragraphs, which is par's (above).
  set block(spacing: spacing, above: spacing, below: spacing)

  // A note, where a mode asks for measurements of its own. Gathered and spread
  // rather than named one by one: naming either at typst's own value is not
  // the same as leaving it alone, since typst works both out from the size a
  // note is set at, and a set rule written inside an if reaches only as far as
  // that block.
  let noteargs = (:)
  if noteindent != none { noteargs.insert("indent", noteindent) }
  if notegap != none { noteargs.insert("gap", notegap) }
  set footnote.entry(..noteargs)

  set text(
    font: font,
    size: fontsize,
    lang: lang
  )

  show link: set text(blue)
  show "al.'s": "al./u{2019}s"

  // A block quotation takes the body's measurements unless a mode overrides
  // them. quotespace is the space that sets the quotation off from the text
  // around it; the paragraphs inside it are separated by their own leading
  // and nothing more, so a quotation of several paragraphs reads as one
  // passage rather than as a run of separate blocks.
  let qsize = if quotesize == none { fontsize } else { quotesize }
  let qleading = if quoteleading == none { leading } else { quoteleading }
  let qspace = if quotespace == none { spacing } else { quotespace }
  let qindentall = if quoteindentall == none { indentall } else { quoteindentall }
  // A blank line between a figure or table and the text above and below it,
  // as APA asks of a manuscript: "If text appears on the same page as a table
  // or figure, add a double-spaced blank line between the text and the table
  // or figure." That is the space between two paragraphs and a line more.
  // Typst sets a line its leading plus the height of a capital (about 0.66em
  // in Times) below the one before, so in a manuscript this is 40pt, which
  // stands the float 48pt from the text, as the .pdf's /addvspace does
  // (tests/layout-float-space.qmd). It had been the paragraph spacing alone,
  // a line and no blank line. Journal mode gives its own.
  let fspace = if floatspace == none { spacing + leading + 0.66em } else { floatspace }

  let qright = if quoteinsetright == none { quoteinset } else { quoteinsetright }
  // A block quotation is set in a pad of apaquarto's own rather than in the
  // one typst's quote brings. A set rule on pad reached the left of that one,
  // but typst kept an inset of its own on the right, so a quotation could not
  // run to the margin the way a journal's does.
  show quote.where(block: true): it => block(width: 100%,
    pad(left: quoteinset, right: qright, it.body))
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

  // How a float is set: its number on a line of its own, the caption under it
  // in italics, and the float itself below that. APA sets a figure and a table
  // this way and so does every other kind of float a document declares for
  // itself under crossref.custom --- an Illustration is the one apaquarto
  // ships. A table is set flush left throughout; everything else centres what
  // it holds.
  //
  // One rule for all of them, dispatching on the kind, rather than a rule per
  // kind: a rule per kind would have to name every kind a document might
  // declare, and the ones it did not name would fall back on typst's own
  // caption, which runs the number and the caption together on one line.
  //
  // A sub-figure inside a multipanel float has its numbering set to a
  // function, and is left alone: quarto keeps the count on the panels and
  // apaquarto labels them itself.
  let apafloatlabel(it) = {
    if int(appendixcounter.display().at(0)) > 0 {
      heading(level: 2, outlined: false, numbering: none)[#it.supplement #appendixcounter.display("A")#it.counter.display()]
    } else {
      heading(level: 2, outlined: false, numbering: none)[#it.supplement #it.counter.display()]
    }
  }

  // The float may break across pages; what may not be parted is held
  // together inside it. The number and caption are one block that stays with
  // the start of the body. formattypst.lua sets the body's picture or table in
  // a block that cannot break, and, when a note follows, stays with the
  // note's first line, while the note itself may run on to the next page. A
  // float that could not break at all had a note too long for the rest of a
  // page set past the foot of it and cut off (wjschne/apaquarto#171,
  // tests/layout-figure-note-break.qmd).
  //
  // A figure is laid out inside a block of its own, around whatever the rule
  // below returns, and that block cannot break unless it is told it can: with
  // the inner block breakable and nothing else changed, the note still went
  // over to the next page whole.
  show figure: set block(breakable: true)
  show figure: it => {
    if (type(it.numbering) == function or type(it.kind) != str or
        not it.kind.starts-with("quarto-float-")) {
      it
    } else if it.kind == "quarto-float-tbl" {
      block(width: 100%, breakable: true, above: fspace, below: fspace)[#align(left)[
        #block(breakable: false, ..apasticky)[
          #apafloatlabel(it)
          #par(first-line-indent: 0pt)[#emph[#it.caption.body]]
        ]
        #block[#it.body]
      ]]
    } else {
      block(width: 100%, breakable: true, above: fspace, below: fspace)[
        #block(breakable: false, ..apasticky)[
          #apafloatlabel(it)
          #align(left)[#par(first-line-indent: 0pt)[#emph[#it.caption.body]]]
        ]
        #align(center)[#it.body]
      ]
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
  let hsize = if headingsize == none { fontsize + headinggrow } else { headingsize }
  let headspace = it => if it.outlined {
    if headingspace == none { leading } else { headingspace }
  } else { leading }
  let headabove = it => if it.outlined and headingabove != none {
    headingabove
  } else { headspace(it) }

  show heading.where(level: 1, outlined: true): set text(size: hsize)
  show heading.where(level: 2, outlined: true): set text(size: hsize)
  show heading.where(level: 3, outlined: true): set text(size: hsize)


 // Redefine headings up to level 5
  // Levels 1 to 3 are set ragged right with hyphenation off, even where the
  // body is justified. Stretching a two-line heading to the column edge, or
  // breaking a word in it, is not something a journal does.
  show heading.where(
    level: 1
  ): it => block(width: 100%, below: headspace(it), above: headabove(it))[
    #set align(center)
    #set par(justify: false)
    #set text(hyphenate: false)
    #if(numbersections and it.outlined and numberdepth > 0 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]

  show heading.where(
    level: 2
  ): it => block(width: 100%, below: headspace(it), above: headabove(it))[
    #set align(left)
    #set par(justify: false)
    #set text(hyphenate: false)
    #if(numbersections and it.outlined and numberdepth > 1 and counter(heading).get().at(0) > 0) [#counter(heading).display()] #it.body
  ]

  show heading.where(
    level: 3
  ): it => block(width: 100%, below: headspace(it), above: headabove(it))[
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
  // Levels one to three the way the Journal of Educational Psychology sets
  // them (measured from its pages; JEP.pdf at the repository root): a point
  // larger than the body, so 11pt over the 10pt body, with 26pt from the
  // baseline above to the heading's and 18pt from the heading's to the first
  // line under it. apalatex.tex's /apajouheadings sets the same for the .pdf.
  // Typst measures a block's space from the edge of the text rather than its
  // baseline: above from the top of the heading's capitals (26pt less 7pt)
  // and below to the top of the next line's (18pt less 7.5pt), as measured on
  // the page.
  headinggrow: 1pt,
  headingabove: 19pt,
  headingspace: 10.5pt,
  // A journal indents a block quotation on the left only; it runs to the
  // column edge on the right. apalatex.tex's /apajouquote does the same.
  quoteinset: 16pt,
  quoteinsetright: 0pt,
  // apa7 sets a block quotation smaller than the text around it. The
  // paragraph that opens the quotation runs flush left and the ones after it
  // are indented, the way a quoted passage is set, and they are separated by
  // nothing more than the line spacing so the passage reads as one quotation.
  // The quotation as a whole is given 9 points of air above and below.
  quotesize: 9pt,
  quoteparspace: jouleading,
  quotespace: 9pt,
  quoteindentall: false,
  // A figure or table title stands off the text above it by the same 9 points
  // the block quotations get, rather than by the body's tighter space between
  // paragraphs.
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
  leading: docleading,
  spacing: 8pt,
  firstlineindent: docfirstlineindent,
  justify: true,
  headerstyle: "none",
  pagenumbering: "1",
  updatepagecounter: true,
  ..args,
)

// documentmode: thesis — a Temple University dissertation or thesis.
// Manuscript layout, with the margins the Graduate School asks for: 1.5" at
// the left, where the work is bound, and 1" elsewhere. The front matter --
// the title page first -- is built in thesisfrontmatter.lua, the same way for
// all four formats.
#let thesis(..args) = apa-layout(
  margin: (left: 1.5in, right: 1in, top: 1in, bottom: 1in),
  // No running head: the Graduate School asks for the page number and nothing
  // else. Numbered in lower-case roman, which is what the front matter takes;
  // the body begins again at 1 in arabic, set where the front matter ends.
  headerstyle: "none",
  pagenumbering: "i",
  leading: thesisleading,
  // A block quotation is single spaced and indented half an inch on the left,
  // as in every mode, which quoteinset already is.
  quoteleading: thesissingleleading,
  // A note's first line begins half an inch in, its turned lines running to
  // the margin, and a double space stands between one note and the next. A
  // note is set smaller than the body, so what reads as a double space there
  // is not the body's leading: typst measures a gap from the depth of one entry
  // to the cap height of the next, and 17.25pt is what leaves the first line
  // of a note two of its own lines below the last line of the one above it.
  noteindent: 0.5in,
  notegap: 17.25pt,
  ..args,
)

// documentmode: stu — student paper. Manuscript page layout, but the header is
// the page number only (no running head); student-specific title-page fields
// (course, professor, due date, note) are added in the front matter.
#let stu(..args) = apa-layout(
  headerstyle: "pagenum",
  ..args,
)

#let brand-color = (:)
#let brand-color-background = (:)
#let brand-logo = (:)

#set page(
  paper: "us-letter",
  margin: (x: 1.25in, y: 1.25in),
  numbering: "1",
  columns: 1,
)

#show: document => thesis(
  title: [The Typography a Dissertation Asks For],
  authors: ([A B],),
  runninghead: "THESIS TYPOGRAPHY",
  runningauthors: "B",
  font: (<fonts>),
  numberdepth: 3,
  suppresstitlepage: true,
  document,
)

#let apatocline(indent, number, body, target, roman, dots) = context {
  let found = if target == none { () } else { query(target) }
  let dest = if found.len() > 0 { found.first().location() } else { none }
  let pg = if dest == none { none } else {
    let n = counter(page).at(dest).first()
    if roman { numbering("i", n) } else { numbering("1", n) }
  }
  block(above: 19.4pt, below: 0pt, inset: (left: indent), width: 100%)[
    #set text(fill: rgb("#000000"))
    // A show rule as well as the set: typst-template.typ sets its own blue
    // over every link, and a set does not reach inside a link that rule has
    // already coloured. This one stands nearer and wins.
    #show link: set text(fill: rgb("#000000"))
    #par(leading: 0.65em, hanging-indent: if number == none { 0pt } else { 0.25in })[
      #if number != none [#box(width: 0.25in)[#number]]
      #if dest == none { body } else { link(dest)[#body] }
      #if dots [#box(width: 1fr, repeat[.]) #pg]
    ]
  ]
}
#page(margin: (left: 1.00in, right: 1.00in, top: 1.00in, bottom: 1.00in), header: none, footer: none, numbering: none)[
#[
#set par(first-line-indent: 0pt, justify: false)
#set block(spacing: 0pt)
#v(70.0pt, weak: false)
#align(center)[#par(leading: 0.65em)[#strong[THE TYPOGRAPHY A DISSERTATION ASKS FOR]]]
#v(21.0pt, weak: false)
#align(center)[#line(length: 5.50in, stroke: 0.5pt)]
#v(21.0pt, weak: false)
#align(center)[#par(leading: 0.65em)[A Thesis /
Submitted to /
the Temple University Graduate Board]]
#v(21.0pt, weak: false)
#align(center)[#line(length: 5.50in, stroke: 0.5pt)]
#v(21.0pt, weak: false)
#align(center)[#par(leading: 0.65em)[In Partial Fulfillment /
of the Requirements for the Degree /
Master of Arts]]
#v(21.0pt, weak: false)
#align(center)[#line(length: 5.50in, stroke: 0.5pt)]
#v(21.0pt, weak: false)
#align(center)[#par(leading: 0.65em)[by /
A B /
May 2027]]
]
]
#page(margin: (left: 1.50in, right: 1.00in, top: 1.00in, bottom: 1.00in))[
#[
#set par(first-line-indent: 0pt, justify: false)
#set block(spacing: 0pt)
#v(289.0pt, weak: false)
#align(center)[© Copyright 2027 by A B /
All Rights Reserved]
]
]
#page(margin: (left: 1.50in, right: 1.00in, top: 1.00in, bottom: 1.00in))[
#[
#set par(first-line-indent: 0pt, justify: false)
#set block(spacing: 0pt)
#align(center)[#par(leading: 0.65em)[#strong[TABLE OF CONTENTS]]]
#v(27.6pt, weak: false)
#align(right)[#par(leading: 0.65em)[Page]]
#apatocline(0.00in, none, [CHAPTER], none, false, false)
#apatocline(0.00in, [1.], [AN INTRODUCTION WHOSE TITLE IS LONG ENOUGH TO TURN OVER ONTO A SECOND
LINE OF THE TABLE OF CONTENTS], <an-introduction-whose-title-is-long-enough-to-turn-over-onto-a-second-line-of-the-table-of-contents>, false, true)
#apatocline(0.00in, none, [REFERENCES], <references>, false, true)
]
]

#set page(numbering: "1")
#counter(page).update(1)
#heading(level: 1, outlined: false, numbering: none)[CHAPTER 1]
= AN INTRODUCTION WHOSE TITLE IS LONG ENOUGH TO TURN OVER ONTO A SECOND LINE OF THE TABLE OF CONTENTS
<an-introduction-whose-title-is-long-enough-to-turn-over-onto-a-second-line-of-the-table-of-contents>
#[#set par.line(numbering: none)
#par()[#text(size:0.5em)[#h(0.0em)]]]
#context v(-par.spacing)
The body is double spaced, and runs on for long enough here that its line spacing can be measured against the quotation and the references below it without any guessing about which line belongs to what.

#quote(block: true)[
A block quotation is single spaced and indented half an inch from the left margin, running to the right margin as the body does; the indent and the single spacing are what mark it out as quoted rather than written.
]

#[#set par.line(numbering: none)
#par()[#text(size:0.5em)[#h(0.0em)]]]
#context v(-par.spacing)
Some text after the quotation (#link(<ref-austenMansfieldPark1990>)[Austen, 1814/1990]/; #link(<ref-schneiderCattellHornCarrollTheoryCognitive2018>)[Schneider & McGrew, 2018]), so that the list below has two entries and the space between them can be measured as well as the space inside them.

A sentence carrying a note.#footnote[A note is a numbered entry, single spaced within itself and long enough here to run onto a second line so that its spacing can be measured.] And a second one.#footnote[The note after it, so that the space between two notes can be measured as well.]

#pagebreak(weak: true)
= REFERENCES
<references>
#thesisreferences[#set par(first-line-indent: 0in, hanging-indent: 0.5in)
#block[
#block[
Austen, J. (1990). #emph[Mansfield Park]. Oxford University Press. (Original work published 1814)

] <ref-austenMansfieldPark1990>
#block[
Schneider, W. J., & McGrew, K. S. (2018). The cattell-horn-carroll theory of cognitive abilities. In D. P. Flanagan & E. M. McDonough (Eds.), #emph[Contemporary intellectual assessment: Theories, tests, and issues] (4th ed., pp. 73--130). Guilford Press. #link("https://www.guilford.com/books/Contemporary-Intellectual-Assessment/Flanagan-McDonough/9781462552030")

] <ref-schneiderCattellHornCarrollTheoryCognitive2018>
] <refs>
]




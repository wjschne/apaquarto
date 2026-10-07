# apaquarto architecture

How apaquarto turns a `.qmd` into an APA-style document, written so that a
maintainer or an AI assistant can find the right filter without reading all of
them. The run order below is the one in `_extensions/apaquarto/_extension.yml`;
when the two disagree, the yml is right and this file is stale.

## The shape of it

apaquarto is a Quarto extension made of Lua filters, three templates and a
reference `.docx`. It has no class or package of its own: every format is
ordinary Quarto output, reshaped by filters.

```
.qmd ─► knitr/jupyter ─► Pandoc parse
         ─► [pre-ast]      11 filters   raw markdown AST; floats are plain Div/Table/Figure
         ─► Quarto normalize            floats become FloatRefTarget custom nodes
         ─► [post-ast]      1 filter
         ─► [pre-quarto]    6 filters   title page is built here (frontmatter.lua)
         ─► Quarto crossref, layout     numbering, subfigure layout
         ─► [post-quarto]   9 filters   typst writer and docx styler run HERE
         ─► Quarto renders floats       FloatRefTarget → html Divs / docx table / typst #figure
         ─► [post-render]  20 filters   notes, captions, citeproc, then the LaTeX writer
         ─► Pandoc writer + template     typst-*.typ, apalatex.tex, apaquarto.docx, apa.scss
```

The formats are not finished at the same point, which matters more than
anything else here:

- **typst** is written by `typst/formattypst.lua` at post-quarto. It runs
  before every common post-render filter, so it never sees what `apanote`,
  `apacaption` or `citeprocr` add.
- **docx** styling starts at post-quarto (`docxstyler`, `docxlisting`) and
  finishes at post-render (`docxreferencedoc`, `docxcontents`,
  `docxlinkcolor`).
- **latex** is written by `formatlatex.lua` near the end of post-render, so
  it sees everything.
- **html** has no writer filter; `apa.css`/`apa.scss` style the classes the
  filters leave behind.
- **thesis** mode (`documentmode: thesis`) has its own front matter,
  `thesisfrontmatter.lua`, which runs last of all. `thesispages.lua` builds
  the pages once as a format-neutral list (gaps, rules, paragraphs, anchors,
  contents lines, prose), and `thesislatex`, `thesistypst`, `thesishtml` or
  `thesisdocx` sets that list in its format.

## Files

| Path | What it is |
|---|---|
| `_extensions/apaquarto/_extension.yml` | Formats, defaults, and the filter list in run order |
| `_extensions/apaquarto/*.lua` | The filters (below) |
| `_extensions/apaquarto/utilsapa.lua` | Shared helpers, loaded with `require("utilsapa")` |
| `_extensions/apaquarto/thesispages.lua` | Module that builds a dissertation's front-matter pages as a format-neutral list, for `thesisfrontmatter`; not a filter |
| `_extensions/apaquarto/thesislatex.lua`, `thesistypst.lua`, `thesishtml.lua`, `thesisdocx.lua` | One renderer each for those pages, chosen by `thesisfrontmatter`; not filters |
| `_extensions/apaquarto/thesistitle.lua`, `thesiscontents.lua` | Modules for the title lines and the contents entries, loaded by `thesispages` and `thesisfrontmatter`; not filters |
| `_extensions/apaquarto/referencedoc.lua` | Module that reads and writes the Word reference doc, and builds the link-colour styles, for `docxreferencedoc`, `docxlinkcolor`, `docxcontents` and `thesisdocx`; not a filter |
| `_extensions/apaquarto/floatrecord.lua` | Module that reads a float once (caption, content, note, columns, panels) for `floatlatex` and `formattypst`; not a filter |
| `_extensions/apaquarto/frontmatterlayout.lua` | Module that reads the front matter's shape for a journal or document layout (the journal split, spacing, list markers, ORCID lines, impact box), for `frontmatter` (latex jou) and `typstfrontmatter`; not a filter |
| `_extensions/apaquarto/typst/typstfrontmatter.lua` | Module `formattypst` runs first: lays the typst front matter out by mode, writes the list outlines and the link-colour rule; not a filter |
| `_extensions/apaquarto/typst/` | `formattypst.lua`, plus the `typst-show.typ` and `typst-template.typ` partials |
| `_extensions/apaquarto/apalatex.tex` | The LaTeX definitions `formatlatex.lua` writes against; Quarto's own pdf template is used unmodified |
| `_extensions/apaquarto/apaquarto.docx` | Reference doc; its styles are the docx half of the class vocabulary |
| `_extensions/apaquarto/apa.scss`, `apa.css`, `title-block.html` | html styling; `title-block.html` is deliberately empty |
| `_extensions/apanote/` | A second extension that only names `apaextractfigure`, `embednote` and `apanote` from its sibling, so a non-apaquarto document can have figure notes |
| `tests/` | Fixtures, `expectations.yml` and snapshots; see `tests/README.md` |
| `options.qmd`, `options.yml`, `options-helpers.R` | The options page of the website: `options.yml` holds every documented option and the R helper writes it into the page as definition lists; `tests/check-options.R` holds it to the fields the filters read |
| `.quartoignore` | What `quarto use template` leaves out of a new project. Quarto reads each line as a glob exactly as written (a comment on the same line breaks the pattern) and already leaves out dotfiles, `README.md`, `LICENSE` and `_extensions`, which it installs on its own |
| `JEP.pdf` | An article from the Journal of Educational Psychology, the measure journal mode's headings are set to; copyrighted, so kept at the repository root locally and in `.gitignore`, not committed |
| `quote.pdf` | An article from Group Dynamics, with a block quotation on its page 6: the measure journal mode's block quotations are set to; kept locally the same way |

## Shared helpers

`utilsapa.lua` holds what more than one filter needs. Use these rather than
writing another copy:

| Helper | What it gives |
|---|---|
| `lang(meta, key, fallback)` | A word from `meta.language`; always pass the English fallback, since the `apanote` extension runs without `apalanguage.lua` |
| `mode(meta)` | `documentmode` as its short code, `man` when unset |
| `flag(meta, key)` | A yes/no field: off when absent or `false`, on otherwise |
| `attr_true(el, name)` | Whether an element's attribute says true, however it was written |
| `page_break(weak)` | A raw page break for docx, latex or typst; nil for html |
| `float_prefixes(meta)`, `is_float(id, prefixes)` | Every float kind, `fig`, `tbl` and the document's own such as `ill` |
| `table_notes(meta)` | The markdown notes of markdown tables, by identifier |
| `make_note(text, prefix)`, `note_inlines(text)` | A note's blocks and inlines from its markdown |
| `link_fields`, `link_field(target)` | The four link colour fields, and which one a link asks for |
| `contents_headings(blocks, depth)` | The headings a table of contents lists |
| `colour_hex(value)`, `toc_depth(meta, fallback)` | A colour as six hex digits; the contents depth |
| `xml_escape`, `trim`, `upper`, `stringify` | Small string and inline helpers |
| `docx_runs(inlines, bold, italic, colour)`, `docx_bookmark_name(id)` | Inlines as Word runs for raw openxml; the bookmark name pandoc gives a heading (hashed past 40 characters) |
| `length_in_inches(value)`, `margin_sides(value, warn)` | A length (`in`, `cm`, `mm`, `pt`) as inches; the `margin` field, read the way typst reads it (one length, or `x`, `y`, `rest` and the sides), as inches per side |
| `geometry_sides(value)`, `asked_margins(meta, warn)` | The sides LaTeX geometry options name; the margins a document asks for in the format being written (`margin`, and in the .pdf `geometry` over it) |
| `thesis_margins`, `thesis_body_margins(meta)`, `thesis_page_one_margins(meta)`, `thesis_measure(margins)` | A dissertation's margins: the handbook's, the handbook's with the document's laid over them (every page but the title page), the title page's (`thesis: title-margin`), and the measure a set of margins leaves |

## Filters in run order

`all` means html, docx, latex and typst. A filter can be listed for all formats
and still return early; the formats column says where it does real work.

### pre-ast: before Quarto touches the AST

| Filter | Formats | Job |
|---|---|---|
| `documentmode.lua` | all | Turns journal/manuscript/document/student/dissertation into `jou`/`man`/`doc`/`stu`/`thesis`; thesis turns on `suppress-title-page` |
| `apalanguage.lua` | all | Fills `meta.language.*` from the document's `language:` or top-level key, then `crossref.*`, then Quarto's translation for `lang`, then its own English defaults. It holds the only list of those defaults; `_extension.yml` deliberately has no `language:` block, so no apaquarto default can override a Quarto translation |
| `abstractsection.lua` | all | Moves an `# Abstract` / `# Impact Statement` section into `meta.abstract` / `meta["impact-statement"]` |
| `introductionheading.lua` | all | Removes a leading level-1 "Introduction" heading (not in thesis mode) |
| `markdowntable.lua` | all | Parses a markdown table caption's `{#tbl-x ...}` into id, classes and attributes, and keeps its `apa-note` as written in `meta["apa-table-notes"]`, before Quarto flattens the caption |
| `crossrefprefix.lua` | all | The one appendix detector. Letters appendices and numbers figures, tables and custom floats (`ill-`) per appendix; writes `prefix`, `fignum`/`tblnum`/`floatnum`, `hassubfigs`, `appendixtitle`; inserts an "Appendix X" heading with class `apa-appendix`; publishes `apa-appendix-count` and `apa-float-labels`; calls a lone appendix "Appendix" |
| `apafloatstoend.lua` | all | With `floatsintext: false`, moves floats before the first appendix; page breaks before appendices |
| `apatwocolumntypstcollect.lua` | typst jou | Puts `// apaquarto-wide-float:<id>` before a block marked `apa-twocolumn` |
| `apapapersize.lua` | latex | Reduces `papersize` to the name LaTeX's class option expects |
| `apaciteappendix.lua` | all | `@sec-`/`@apx-` references to appendices become "Appendix A" links (every appendix reference, in every format) |
| `apaomitrefsdiv.lua` | all | Adds a References heading and `#refs` div if missing; one appendix is "Appendix", not "Appendix A" |

### post-ast

| Filter | Formats | Job |
|---|---|---|
| `apamasked.lua` | all | With `mask: true`, replaces the ids of `masked-citations` with `maskedreference` |

### pre-quarto

| Filter | Formats | Job |
|---|---|---|
| `apaheader.lua` | all | Periods after level-4/5 headings; in docx marks them `apa-runin` for `docxcontents` to write |
| `apastriptitle.lua` | all | Copies title/author/date/abstract to `apa*` keys and builds `apaauthordisplay`; in docx clears the originals |
| `wordcount.lua` | all | `meta.wordn` for the title page |
| `frontmatter.lua` | all | Title page, byline, author note, abstract, impact statement, keywords and list markers, as classed blocks for every format, one function per part. For latex and typst wraps the front matter in `Div.apa-frontmatter` for the writer to lay out |
| `apaquote.lua` | all | A block quote's last paragraph that begins with an em dash becomes a `quote-attribution` div (unless inside a `no-attribution` div); in docx, `NextBlockText` for the paragraphs after the first |
| `apafigtblappendix.lua` | html, docx, typst | `@fig-`/`@tbl-`/`@ill-` become "Figure A1" links, from `meta["apa-float-labels"]`, which it then removes |

### post-quarto

| Filter | Formats | Job |
|---|---|---|
| `floatwithsubfigure.lua` | html, docx, latex | Laid-out figures: "Panel A" labels, whole-figure note inside the float, explicit layout matrix |
| `floatnote.lua` | html, docx | Every other float's note inside the float, from `floatrecord`; each panel's note inside the panel as `SubPanelNote`; copies a code cell's note down to its one float |
| `thesisfloats.lua` | thesis | Records every float in `meta["apathesis-floats"]` for the thesis lists |
| `floatlatex.lua` | latex | Each figure and table as a complete APA float in raw LaTeX |
| `apaoneauthoraffiliation.lua` | all | Stops the render when there are no authors, an author has no affiliation, or no author is corresponding |
| `apatinytablehtml.lua` | html | Aligns tinytable tables by `tbl-align` |
| `docxstyler.lua` | docx | Copies a Div's or Span's first class into `custom-style` when it is on its list. Of the filters' own blocks only `Author`, `Abstract` and `AbstractFirstParagraph` reach it; the rest of the list serves divs authors write themselves, such as `::: {.NoIndent}` |
| `docxlisting.lua` | docx | Code listings flush left |
| `typst/formattypst.lua` | typst | The typst writer: the front matter by mode (through `typstfrontmatter`), fonts, float notes, panel `#grid`, `NoIndent`, hanging references, line numbers |

### post-render

| Filter | Formats | Job |
|---|---|---|
| `apaextractfigure.lua` | docx | Unwraps the one-cell table Quarto puts around docx floats |
| `embednote.lua` | html, docx, typst | Recovers the `apa-note` of an `{{< embed >}}` float from its notebook |
| `apanote.lua` | all | Writes the notes no earlier filter could: a figure embedded from a notebook (its note recovered by `embednote`), a div that is not a float, a cell holding several floats. Skips anything carrying this document's `apa-note-written` mark |
| `apafloat.lua` | all | `FigureWithNote` / `FigureWithoutNote` on top-level floats |
| `apacaption.lua` | html, docx | Splits Quarto's `Figure 1: caption` into `FigureTitle` and `Caption` |
| `apaafternote.lua` | all | `AfterWithoutNote` on the paragraph after a float with no note |
| `docxlayout.lua` | docx | Rebuilds multipanel figures as one table, panel captions above; only a layout grid (one holding images or tables) takes `FigureLayout`, and data tables keep the reference doc's `Table` rules |
| `apatwocolumntypst.lua` | typst jou | Wraps the block after a wide-float marker in `#place(top, scope: "parent")` |
| `citeprocr.lua` | all | Runs citeproc itself (the yml sets `citeproc: false`), meta-analysis asterisks, masked references |
| `apaandcite.lua` | all | "&" to "and" in narrative citations, possessives, strips meta-analysis asterisks |
| `crossreflink.lua` | latex | The whole "Figure 1" is the link |
| `formatlatex.lua` | latex | The LaTeX writer: sets the page by mode (`geometry`: the mode's options, then the document's `margin`, then its own `geometry`; see Page layout across formats), lays out the front matter by mode (the journal masthead and its parts, from `frontmatterlayout`), then wraps the class vocabulary in `apalatex.tex` commands |
| `apapdfstandard.lua` | latex | Warns when a PDF standard needs tagging and flextable is in use |
| `thesisfrontmatter.lua` | thesis | Dissertation front matter for every format; last so nothing downstream rewrites it |
| `htmlcontents.lua` | html | Fills the `list-of-contents` marker |
| `htmllinkcolor.lua` | html | Link colours as scoped CSS |
| `docxformatlatexsymbol.lua` | docx | `\LaTeX` and `\TeX` math as plain text |
| `docxreferencedoc.lua` | docx | The one writer of the reference doc, once a render: fonts, paper size, margins (thesis, then the document's `margin`), line numbers, running head, link-colour styles |
| `docxcontents.lua` | docx | Table of contents and lists of figures/tables as openxml fields, and the run-in level-4/5 headings (`apa-runin`) with their formatting and bookmarks; after `docxreferencedoc`, whose page size it measures |
| `docxlinkcolor.lua` | docx | Gives each link the character style for its kind (the styles are written by `docxreferencedoc`) |

The yml lists the common filters and each format's own filters separately.
Within one stage, this file assumes the common ones run first; that has not
been checked against Quarto's source.

## Contracts between filters

These names carry state from one filter to another. Renaming one, or moving a
filter across a stage boundary, breaks a consumer that may be far away.

| Marker | Written by | Read by |
|---|---|---|
| `documentmode` short codes | `documentmode.lua` | nearly every filter; typst uses the code as a template function name |
| `meta.language.*` | `apalanguage.lua` | nearly every filter |
| `prefix`, `fignum`, `tblnum`, `floatnum` attributes | `crossrefprefix` | `apafloatstoend` (`prefix == ""` means in the body), `floatlatex`, `thesisfloats`, `apacaption` |
| `meta["apa-float-labels"]` (id → "A1") | `crossrefprefix` | `apafigtblappendix`, which removes it |
| `apa-appendix` class on the heading that opens an appendix | `crossrefprefix` (its inserted "Appendix X", and an old-style "# Appendix A") | `apafloatstoend`, `apaomitrefsdiv` |
| `meta["apa-appendix-count"]` | `crossrefprefix` | `apaciteappendix`, `apaomitrefsdiv` |
| `appendixtitle` attribute | `crossrefprefix` | `apaciteappendix`, `thesiscontents` |
| `hassubfigs` attribute | `crossrefprefix` | `floatwithsubfigure` |
| `meta["apa-table-notes"]` | `markdowntable` | `apanote`, `floatlatex`, `formattypst`, through `utilsapa.table_notes` |
| `apa-note-written` attribute | `floatwithsubfigure`, `floatnote`, `apanote`, all with `utilsapa.note_mark()` (a digest of this document's path) | `apanote`, `floatnote`, `floatlatex` |
| `// apaquarto-wide-float:<id>` raw typst | `apatwocolumntypstcollect` | `apatwocolumntypst` (wraps the next block; the id is not checked) |
| `apatitle`, `apatitledisplay`, `apaauthor`, `apaabstract`, `by-author[].apaauthordisplay` | `apastriptitle` | `frontmatter`, `thesisfrontmatter`, `typst-show.typ` |
| `meta.wordn` | `wordcount` | `frontmatter` |
| `meta.description` (running head) | `frontmatter` | `docxreferencedoc` |
| `jou-running-authors` | `frontmatter` | `typst-show.typ`, `formatlatex` |
| `.list-of-contents`, `.list-of-figures`, `.list-of-tables` Divs | `frontmatter` | `htmlcontents`, `docxcontents`, `formatlatex`, `typstfrontmatter` |
| `Div.apa-frontmatter` (latex, typst) | `frontmatter` | `formatlatex` and `typstfrontmatter`, which lay it out and remove it |
| `FigureNote`, `NoIndent` | `utilsapa.make_note` (via `apanote`, `floatwithsubfigure`, `floatlatex`, `formattypst`) | `formatlatex`, css, reference doc, `docxlayout`, `apatwocolumntypst` |
| `quote-attribution` div (custom-style `QuoteAttribution`), `meta["apa-quote-attribution"]` | `apaquote` | `formatlatex` (`apaquoteattribution` environment), `formattypst` (right-aligned), `apa.css`, `docxreferencedoc` (writes the `QuoteAttribution` style, through `referencedoc.patch_attribution_style`, only when the field is set) |
| `FigureTitle`, `Caption` | `apacaption` | `docxlayout`, `docxcontents`, css, reference doc |
| `FigureWithNote`, `FigureWithoutNote` | `apafloat` | `apaafternote`, `docxlayout` |
| `citations[1].hash` = 1 (possessive), 2 (`&`), 3 (both) | `citeprocr` | `apaandcite` |
| `meta["apathesis-floats"]` | `thesisfloats` | `thesisfrontmatter` |

The class vocabulary each writer understands:

- **latex** (`formatlatex`): Header `.title` (ids `title`, `firstheader`),
  Header `.AuthorNote`, Div `.Author`, `.AbstractFirstParagraph`,
  `.list-of-*`, `.FigureNote`, and `Div.apa-frontmatter`, which it sorts
  itself into `.JournalMasthead`, `.JournalWide`, `.JournalNarrow` and
  `.JournalNote` in journal mode.
- **typst** (`formattypst`): Div `.Author`, `.NoIndent`, `#refs`, float
  attributes `apa-note` and `layout-*`, `meta["apa-table-notes"]`.
- **docx**: `custom-style` values set by the producers themselves
  (`FigureTitle`, `Caption`, `FigureNote`, `SubPanelNote`, `FigureWithNote`,
  `FigureWithoutNote`, `AfterWithoutNote`, `NextBlockText`,
  `ApaUnlistedHeadingN`, `Apa*Color`), plus whatever `docxstyler` maps from
  a first class (`Author`, `Abstract`, `AbstractFirstParagraph`, and
  author-written divs such as `NoIndent`). Each must exist as a style in
  `apaquarto.docx` or be added by `docxreferencedoc`.
- **html**: the same class names, styled in `apa.css`.

## A figure with an apa-note, by format

All formats share the pre-ast steps: `markdowntable` (for
markdown tables), `crossrefprefix`, `apafloatstoend`, then `apafigtblappendix`
at pre-quarto.

- **html**: `floatwithsubfigure` (laid-out figures) → `floatnote` writes
  the note inside the float → Quarto renders → `apafloat` → `apacaption`
  re-parses the rendered caption → `apaafternote` → css.
- **docx**: `floatwithsubfigure` → `floatnote` → `docxstyler` → Quarto
  renders a one-cell table → `apaextractfigure` unwraps it → `apafloat` →
  `apacaption` → `apaafternote` → `docxlayout` → `docxcontents` lists it.
- **latex**: `floatwithsubfigure` → `floatlatex` writes the whole float,
  note included, as raw LaTeX → the common post-render float filters run but
  find nothing → `formatlatex` turns `FigureNote` into `apafloatnote`.
  A code chunk's `apa-note` (and `apa-twocolumn`) sits on the cell Div, not
  the float; `floatlatex` copies it down to the cell's one float first, then
  clears it from the cell once written (`tests/layout-chunk-note.qmd`).
  A table outside journal mode is set in the text flow, not a float, and
  longtable breaks the page ahead of itself when its head and first row do
  not fit; so its label, title, caption and list-of-tables line are boxed
  between `\apatablekeep` and `\apatablekeepend`, which ends the page first
  unless the box and three lines more fit (`tests/layout-table-keep.qmd`).
  A figure asked to stay in place (`floatsintext`, outside `jou`) is set in
  the flow too, not an `[H]` float: its title, caption and picture are boxed
  the same way and kept with the note's first two lines (`\apafigurekeepend`),
  and a long note runs on to the next page instead of being cut off at the
  foot of an unbreakable float (#171, `tests/layout-figure-note-break.qmd`).
  A short table (`short_table`: one pandoc-written table of 15 rows or fewer,
  no package's own latex) is set as a tabular with `\apalongtableastabular`,
  boxed whole with its title and caption and kept with its note the same way,
  so it moves to the next page whole rather than breaking after a row; a
  longer one stays a longtable (`tests/layout-table-whole.qmd`).
- **typst**: `floatwithsubfigure` skips typst → `formattypst` writes the note
  inside the float, whether it was given on the float, its image or a chunk's
  cell (a cell holding one float hands its note down and is marked written),
  and its own panel `#grid`, wrapping the picture, table or grid in an
  unbreakable block that is `sticky` (via `apasticky`) when a note follows →
  Quarto renders `#figure`, which the template lets break
  (`show figure: set block(breakable: true)`), its number and caption a sticky
  block of their own, so a long note runs on to the next page (#171) → `apanote` writes any note
  `formattypst` left (a cell drawing several figures) → `apatwocolumntypst`
  in journal mode.

So every format writes a float's note inside the float at post-quarto, from
`floatrecord`: `floatnote` (html, docx), `floatlatex`, `formattypst`, and
`floatwithsubfigure` for the whole-figure note of a laid-out float. `apanote`
writes only what those cannot see. Panels are laid out three ways (LaTeX
minipages, typst `#grid`, docx table merging), and two filters parse Quarto's
rendered output back apart (`apacaption`, `apaextractfigure`).

## Citations

1. `citeproc: false` in the yml stops Quarto running citeproc after the
   filters.
2. `apamasked` (post-ast) swaps masked ids for `maskedreference` before
   anything resolves them.
3. Note filters (post-quarto and post-render) parse `apa-note` text, which
   can create new `Cite` elements. This is why citeproc has to run late.
4. `citeprocr` (post-render) removes the `'s` and `&` suffix tokens, records
   them in `citations[1].hash`, adds the references, and calls
   `pandoc.utils.citeproc`. In typst it also sets `citeproc = true` and drops
   `csl`.
5. `apaandcite` reads `hash` to write "and" and possessives, strips the
   meta-analysis asterisk, and in typst unwraps the `Cite`.

## Dependencies on Quarto internals

These break silently when Quarto changes. Look here first after a Quarto
upgrade. The two that would otherwise go unnoticed have guard fixtures,
`tests/caption-shape.qmd` and `tests/citation-hash.qmd`, which fail when the
shape changes.

- `quarto._quarto.ast.custom_node_data` and `__quarto_custom_id`:
  `floatrecord.float_behind`, the one place that reads them.
- Quarto rebuilding a markdown table's attributes from its caption, which
  is why `markdowntable` keeps the note in the metadata.
- The `QUARTO_FILTER_PARAMS` environment variable: `apalanguage`.
- The rendered html and docx caption shape `Figure`, nbsp, number, `:` : `apacaption`
  (guarded by `caption-shape.qmd`).
- The citation `hash` field surviving `pandoc.utils.citeproc`: `citeprocr`
  sets it, `apaandcite` reads it (guarded by `citation-hash.qmd`).
- The docx one-cell wrapper table and per-panel tables: `apaextractfigure`,
  `docxlayout`.
- LaTeX `Word~\ref{...}`: `crossreflink`.
- Classes `cell`, `quarto-layout-cell`, `quarto-layout-cell-subref`,
  `quarto-layout-panel`, `quarto-embed-nb-cell`, attribute `ref-parent`:
  `apanote`, `embednote`.
- `PANDOC_WRITER_OPTIONS.reference_doc`: `docxreferencedoc` rewrites that
  file on disk (through `referencedoc.lua`), which is usually the installed
  `_extensions/apaquarto/apaquarto.docx`. Never commit it straight after a
  docx render; `make test` checks for this.

## Known structural debt

Recorded so a change does not make it worse. Roughly in order of payoff.

1. **Captions in html and docx.** `apacaption` re-parses the caption Quarto
   has rendered, `Figure`, nbsp, number, `:`, into a title and a caption.
   This cannot move to post-quarto: Quarto writes that caption after the last
   filter point, and writes a "Figure 1" of its own even for a float whose
   caption has been emptied. It breaks if Quarto changes how it renders a
   caption; `tests/caption-shape.qmd` fails when it does.
2. **The reference doc is patched in place.** This is deliberate:
   Pandoc reads `PANDOC_WRITER_OPTIONS.reference_doc` after the filters run,
   so there is nowhere else to put fonts, page size, line numbers and link
   colours. The original values are kept in `apaquarto-original-*` comments
   and the next render restores them, and `check_reference_doc()` in
   `tests/run-tests.R` stops a mid-patch file from being committed. Every
   read and write goes through `referencedoc.lua`, and only
   `docxreferencedoc` writes, once a render. What is left: two renders at
   once against the same installed file can still race on it.
3. **Two front-matter systems**: `frontmatter.lua` and `thesisfrontmatter.lua`
   each lay out a first page. In thesis mode `frontmatter.lua` now builds
   only the title and the running head (both still needed) and skips the
   rest of the title page. The thesis pages are kept apart from the format
   writers on purpose: their markup (page geometry, leader-dot contents
   lines, Word sections) is used by nothing else, so it lives in the four
   `thesis*` renderers rather than in `formatlatex` or `formattypst`.
4. **The citation `hash` side channel** uses an undocumented Pandoc field;
   `tests/citation-hash.qmd` fails if it stops surviving citeproc.

## Page layout across formats

The .pdf and typst are meant to set the same page, and .docx the same
margins. What each format reads, and where:

- **Margins.** One field, `margin` (typst's shape), in every format.
  - typst reads it itself, after each mode's layout in `typst-template.typ`, so it wins.
  - `formatlatex.lua` writes the mode's geometry, then `margin` as geometry options, then the document's own `geometry`, which wins where both name a side.
  - `docxreferencedoc.lua` writes it into the reference doc's section.
  - `utilsapa.asked_margins` is the one reading of what a document asked for.
- **Dissertations.** `thesispages.lua` sets every page but the title page on `utilsapa.thesis_body_margins` (the handbook's 1.5in left and 1in elsewhere, with the document's sides over them), and the title page on `thesis_page_one_margins` (1in, or `thesis: title-margin`). The title's line breaks, the committee indent and the rule width (5.5in or the measure, whichever is narrower) follow from the title page's measure, worked out per document in `set_geometry`.
- **Typst spacing.** In `apa-layout`, `leading` is the space between lines (16pt in manuscript and student mode, which is 24pt baseline to baseline, the .pdf's double spacing) and, since `set par(spacing: leading)`, between paragraphs too; `spacing` is the space around blocks (quotations, lists, figures). Typst 0.12 moved paragraph spacing from `block` to `par`, which is why a `set block` rule alone no longer reaches it.
- **Space around a figure or table.** Outside journal mode, a blank line of the text's spacing above and below, as APA asks of a manuscript and a student paper: the .pdf's in-flow group adds `\addvspace{\baselineskip}` on either side, for figures as for tables; typst's `floatspace` defaults to `spacing + leading + 0.66em` (a line is its leading plus a capital's height) and is used above and below; .docx has it in the reference doc's styles, 552 twips (a Word double-spaced line) before `FigureTitle` and after `FigureNote` (with `contextualSpacing`, so only a note's last paragraph carries it) or `FigureWithoutNote`, and before `AfterWithoutNote` for a table without a note, which `apaafternote.lua` marks, or, when a heading or list follows such a table, before a one-point spacer paragraph it inserts (Word drops space before at the top of a page, so the spacer leaves no gap there); .html gives `.FigureWithNote, .FigureWithoutNote` a 2em margin. Journal mode sets its own 9pt. A .pdf table in the flow is set flush left (`\LTleft` 0) with no `\LTpost` or `\apatablenotegap`, so its note is the next line under its rule. `tests/layout-float-space.qmd`.
- **Headings outside journal mode.** No space above or below any level, in the .pdf as in typst: a heading takes one line in the text's own spacing, as APA asks. The .pdf's `\titlespacing` "before" is 0pt; it was `\baselineskip`, which titlesec adds on top of the line spacing, so every heading had a blank line above it. `tests/layout-manuscript.qmd` measures body line to body line across a heading (48pt), since pdftools boxes bold a point or two taller than roman.
- **Journal headings.** Levels 1 to 3 match between the .pdf and typst and follow `JEP.pdf`: a point larger than the body, 26pt baseline to baseline above, 18pt below, lines a point deeper than the body's. The .pdf sets them in `\apajouheadings` (`apalatex.tex`); typst with `headinggrow`, `headingabove` and `headingspace` in the `jou` layout. The two use different numbers for the same page because titlesec adds space to a line while typst measures from the edge of the text: measure the page, not the source.
- **Block quotations.** Indented on the left only, in every format and mode: 0.5in, and 16pt in `jou`, as the Group Dynamics article in `quote.pdf` sets one. The .pdf sets them in `\apaquote`, `\apajouquote` and `\apathesisquote`, each with `\parsep` at 0 so that a quotation's paragraphs and its attribution are spaced like its lines; typst with `quoteinset` and `quoteinsetright` (0 by default); .docx in the reference doc's Block Text and `QuoteAttribution` styles; .html in `apa.css`. Typst's own `quote` keeps a right inset that a `set pad` rule does not reach, so block quotes are shown in a `pad` of apaquarto's own. A dissertation's quotation (`\apathesisquote`, typst's `thesisleading` and `thesissingleleading`) is single spaced at 14pt and stands a double space (24pt) from the body on either side in both, measured in `tests/layout-thesis.qmd`. In typst, `apaparindent` says `all` outright from Typst 0.13: a bare length set inside something set `all: true` keeps that `all: true`, which had indented the first paragraph of a journal's quotation.
- **The spacer before a first paragraph.** In every mode but `jou`, `formattypst.lua` puts an invisible paragraph before the first paragraph after a heading or other block, so that it takes its first-line indent, and takes the space it brought back with `v(-par.spacing)`. That was a fixed `-18pt`, wrong in any mode not spaced at 18pt.

`tests/layout-journal.qmd`, `layout-journal-quote.qmd`, `layout-manuscript.qmd`,
`layout-document.qmd` and the `margins*.qmd` fixtures measure all of this on
the rendered page. Re-measure after any
change to these files, and after a Quarto, Typst or LaTeX upgrade.

## Testing

`make test` renders every fixture in `tests/` against a fresh copy of the
extension and checks the output against `tests/expectations.yml` and the
`.tex`/`.typ` snapshots. It needs `Rscript` on the PATH. It renders up to
four fixtures at a time (`--jobs 1` for one at a time), which takes a full
run of about 165 jobs about 6 minutes. Docx renders take turns, since each
rewrites the shared `apaquarto.docx` in place. Run it before and after any change to
a filter. See `tests/README.md` for adding a fixture.

A snapshot catches a change to the source a format writes; it cannot tell
whether the page still looks the same. `layout` checks measure the rendered
.pdf (spacing, margins, sizes, to within a point) for that.

`options.qmd` is written from `options.yml` by `options-helpers.R` when the
site renders. `tests/check-options.R` (`make check-options`, and first in
`make test`) fails when `options.yml` and the fields the filters read
disagree.

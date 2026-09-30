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
         ─► [post-quarto]   8 filters   typst writer and docx styler run HERE
         ─► Quarto renders floats       FloatRefTarget → html Divs / docx table / typst #figure
         ─► [post-render]  21 filters   notes, captions, citeproc, then the LaTeX writer
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
  `thesisfrontmatter.lua`, which runs last of all and renders for each format
  itself.

## Files

| Path | What it is |
|---|---|
| `_extensions/apaquarto/_extension.yml` | Formats, defaults, and the filter list in run order |
| `_extensions/apaquarto/*.lua` | The filters (below) |
| `_extensions/apaquarto/utilsapa.lua` | Shared helpers, loaded with `require("utilsapa")` |
| `_extensions/apaquarto/thesistitle.lua`, `thesiscontents.lua` | Modules loaded by `thesisfrontmatter.lua`; not filters |
| `_extensions/apaquarto/typst/` | `formattypst.lua`, plus the `typst-show.typ` and `typst-template.typ` partials |
| `_extensions/apaquarto/apalatex.tex` | The LaTeX definitions `formatlatex.lua` writes against; Quarto's own pdf template is used unmodified |
| `_extensions/apaquarto/apaquarto.docx` | Reference doc; its styles are the docx half of the class vocabulary |
| `_extensions/apaquarto/apa.scss`, `apa.css`, `title-block.html` | html styling; `title-block.html` is deliberately empty |
| `_extensions/apanote/` | A second extension that only names `apaextractfigure`, `embednote` and `apanote` from its sibling, so a non-apaquarto document can have figure notes |
| `tests/` | Fixtures, `expectations.yml` and snapshots; see `tests/README.md` |

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
| `apaheader.lua` | all | Periods after level-4/5 headings; in docx, run-in raw openxml headings |
| `apastriptitle.lua` | all | Copies title/author/date/abstract to `apa*` keys and builds `apaauthordisplay`; in docx clears the originals |
| `wordcount.lua` | all | `meta.wordn` for the title page |
| `frontmatter.lua` | all | Title page, byline, author note, abstract, impact statement, keywords, contents markers, journal layout. Emits classed blocks for docx/html/latex and raw typst for typst |
| `apaquote.lua` | docx | `NextBlockText` for the paragraphs after the first in a block quote |
| `apafigtblappendix.lua` | html, docx, typst | `@fig-`/`@tbl-`/`@ill-` become "Figure A1" links, from `meta["apa-float-labels"]`, which it then removes |

### post-quarto

| Filter | Formats | Job |
|---|---|---|
| `floatwithsubfigure.lua` | html, docx, latex | Laid-out figures: "Panel A" labels, whole-figure note inside the float, explicit layout matrix |
| `thesisfloats.lua` | thesis | Records every float in `meta["apathesis-floats"]` for the thesis lists |
| `floatlatex.lua` | latex | Each figure and table as a complete APA float in raw LaTeX |
| `apaoneauthoraffiliation.lua` | all | Stops the render when there are no authors, an author has no affiliation, or no author is corresponding |
| `apatinytablehtml.lua` | html | Aligns tinytable tables by `tbl-align` |
| `docxstyler.lua` | docx | Copies a Div's or Span's first class into `custom-style` when it is on its list. Of the filters' own blocks only `Author`, `Abstract` and `AbstractFirstParagraph` reach it; the rest of the list serves divs authors write themselves, such as `::: {.NoIndent}` |
| `docxlisting.lua` | docx | Code listings flush left |
| `typst/formattypst.lua` | typst | The typst writer: fonts, float notes, panel `#grid`, `NoIndent`, hanging references, line numbers |

### post-render

| Filter | Formats | Job |
|---|---|---|
| `apaextractfigure.lua` | docx | Unwraps the one-cell table Quarto puts around docx floats |
| `embednote.lua` | html, docx, typst | Recovers the `apa-note` of an `{{< embed >}}` float from its notebook |
| `apanote.lua` | all | Writes any remaining `apa-note` as a `FigureNote` block |
| `apafloat.lua` | all | `FigureWithNote` / `FigureWithoutNote` on top-level floats |
| `subpanelnote.lua` | html, docx | A panel's own note becomes `SubPanelNote` |
| `apacaption.lua` | html, docx | Splits Quarto's `Figure 1: caption` into `FigureTitle` and `Caption` |
| `apaafternote.lua` | all | `AfterWithoutNote` on the paragraph after a float with no note |
| `docxlayout.lua` | docx | Rebuilds multipanel figures as one table, panel captions above |
| `apatwocolumntypst.lua` | typst jou | Wraps the block after a wide-float marker in `#place(top, scope: "parent")` |
| `citeprocr.lua` | all | Runs citeproc itself (the yml sets `citeproc: false`), meta-analysis asterisks, masked references |
| `apaandcite.lua` | all | "&" to "and" in narrative citations, possessives, strips meta-analysis asterisks |
| `crossreflink.lua` | latex | The whole "Figure 1" is the link |
| `formatlatex.lua` | latex | The LaTeX writer: wraps the class vocabulary in `apalatex.tex` commands |
| `apapdfstandard.lua` | latex | Warns when a PDF standard needs tagging and flextable is in use |
| `thesisfrontmatter.lua` | thesis | Dissertation front matter for every format; last so nothing downstream rewrites it |
| `htmlcontents.lua` | html | Fills the `list-of-contents` marker |
| `htmllinkcolor.lua` | html | Link colours as scoped CSS |
| `docxformatlatexsymbol.lua` | docx | `\LaTeX` and `\TeX` math as plain text |
| `docxreferencedoc.lua` | docx | Patches the reference doc: fonts, paper size, margins, line numbers, running head |
| `docxcontents.lua` | docx | Table of contents and lists of figures/tables as openxml fields; after `docxreferencedoc`, whose page size it measures |
| `docxlinkcolor.lua` | docx | A character style per link kind; patches `styles.xml` |

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
| `hassubfigs` attribute | `crossrefprefix` | `floatwithsubfigure`, `subpanelnote` |
| `meta["apa-table-notes"]` | `markdowntable` | `apanote`, `floatlatex`, `formattypst`, through `utilsapa.table_notes` |
| `apa-note-written` attribute | `floatwithsubfigure` (`"true"`), `apanote` (a hash of the input path) | `apanote`, `floatlatex` |
| `// apaquarto-wide-float:<id>` raw typst | `apatwocolumntypstcollect` | `apatwocolumntypst` (wraps the next block; the id is not checked) |
| `apatitle`, `apatitledisplay`, `apaauthor`, `apaabstract`, `by-author[].apaauthordisplay` | `apastriptitle` | `frontmatter`, `thesisfrontmatter`, `typst-show.typ` |
| `meta.wordn` | `wordcount` | `frontmatter` |
| `meta.description` (running head) | `frontmatter` | `docxreferencedoc` |
| `jou-running-authors` | `frontmatter` | `typst-show.typ`, `formatlatex` |
| `.list-of-contents`, `.list-of-figures`, `.list-of-tables` Divs | `frontmatter` | `htmlcontents`, `docxcontents`, `formatlatex` (typst builds `#outline` in `frontmatter` instead) |
| `FigureNote`, `NoIndent` | `utilsapa.make_note` (via `apanote`, `floatwithsubfigure`, `floatlatex`, `formattypst`) | `formatlatex`, css, reference doc, `docxlayout`, `apatwocolumntypst` |
| `FigureTitle`, `Caption` | `apacaption` | `docxlayout`, `docxcontents`, css, reference doc |
| `FigureWithNote`, `FigureWithoutNote` | `apafloat` | `subpanelnote`, `apaafternote`, `docxlayout` |
| `citations[1].hash` = 1 (possessive), 2 (`&`), 3 (both) | `citeprocr` | `apaandcite` |
| `meta["apathesis-floats"]` | `thesisfloats` | `thesisfrontmatter` |

The class vocabulary each writer understands:

- **latex** (`formatlatex`): Header `.title` (ids `title`, `firstheader`),
  Header `.AuthorNote`, Div `.Author`, `.AbstractFirstParagraph`,
  `.JournalMasthead`, `.JournalWide`, `.JournalNarrow`, `.JournalNote`,
  `.list-of-*`, `.FigureNote`.
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

- **html**: `floatwithsubfigure` (laid-out figures only) → Quarto renders →
  `apanote` writes the note → `apafloat` → `subpanelnote` → `apacaption`
  re-parses the rendered caption → `apaafternote` → css.
- **docx**: `floatwithsubfigure` → `docxstyler` → Quarto renders a one-cell
  table → `apaextractfigure` unwraps it → `apanote` writes the note →
  `apafloat` → `subpanelnote` → `apacaption` → `apaafternote` → `docxlayout`
  → `docxcontents` lists it.
- **latex**: `floatwithsubfigure` → `floatlatex` writes the whole float,
  note included, as raw LaTeX → the common post-render float filters run but
  find nothing → `formatlatex` turns `FigureNote` into `apafloatnote`.
- **typst**: `floatwithsubfigure` skips typst → `formattypst` writes the note
  and its own panel `#grid` → Quarto renders `#figure` → `apanote` writes
  any note `formattypst` left → `apatwocolumntypst` in journal mode.

So a note is written in four places (`floatwithsubfigure`, `floatlatex`,
`formattypst`, `apanote`), panels are laid out three ways (LaTeX minipages,
typst `#grid`, docx table merging), and two filters parse Quarto's rendered
output back apart (`apacaption`, `apaextractfigure`).

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
upgrade.

- `quarto._quarto.ast.custom_node_data` and `__quarto_custom_id`:
  `floatlatex`, `formattypst`.
- Quarto rebuilding a markdown table's attributes from its caption, which
  is why `markdowntable` keeps the note in the metadata.
- The `QUARTO_FILTER_PARAMS` environment variable: `apalanguage`.
- The rendered html caption shape `Figure`, nbsp, number, `:` : `apacaption`.
- The docx one-cell wrapper table and per-panel tables: `apaextractfigure`,
  `docxlayout`.
- LaTeX `Word~\ref{...}`: `crossreflink`.
- Classes `cell`, `quarto-layout-cell`, `quarto-layout-cell-subref`,
  `quarto-layout-panel`, `quarto-embed-nb-cell`, attribute `ref-parent`:
  `apanote`, `subpanelnote`, `embednote`.
- `PANDOC_WRITER_OPTIONS.reference_doc`: `docxreferencedoc` and
  `docxlinkcolor` rewrite that file on disk, which is usually the installed
  `_extensions/apaquarto/apaquarto.docx`. Never commit it straight after a
  docx render; `make test` checks for this.

## Known structural debt

Recorded so a change does not make it worse. Roughly in order of payoff.

1. **Floats.** There is no single representation of a float. Resolving each
   `FloatRefTarget` once at post-quarto into one record (kind, id, label,
   title, caption, note, panels, rows, twocolumn) and writing the note inside
   the float for every format would retire three of the four note writers and
   `apacaption`'s re-parsing.
2. **Writers.** About 500 lines of raw typst layout live in `frontmatter.lua`
   rather than `formattypst.lua`. LaTeX already has the intended shape:
   `frontmatter` emits classed blocks and `formatlatex` writes them.
3. **The reference doc is patched in place, twice.** This is deliberate:
   Pandoc reads `PANDOC_WRITER_OPTIONS.reference_doc` after the filters run,
   so there is nowhere else to put fonts, page size, line numbers and link
   colours. The original values are kept in `apaquarto-original-*` comments
   and the next render restores them, and `check_reference_doc()` in
   `tests/run-tests.R` stops a mid-patch file from being committed. The debt
   is that `docxreferencedoc` and `docxlinkcolor` each unzip and rewrite the
   file separately (and `docxcontents` reads it a third time), and two renders
   at once can race on it.
4. **Custom floats are not in every list.** `docxcontents` and the lists
   of figures and tables know figures and tables only, so an Illustration is
   numbered and cross-referenced everywhere but listed nowhere outside
   thesis mode.
5. **Two front-matter systems**: `frontmatter.lua` and `thesisfrontmatter.lua`
   each have their own author, title, abstract, page-break and contents code,
   and in thesis mode `frontmatter.lua` builds a title page only for it to be
   discarded.
6. **The citation `hash` side channel** uses an undocumented Pandoc field.

## Testing

`make test` renders every fixture in `tests/` against a fresh copy of the
extension and checks the output against `tests/expectations.yml` and the
`.tex`/`.typ` snapshots. It needs `Rscript` on the PATH. Run it before and
after any change to a filter. See `tests/README.md` for adding a fixture.

# Tests

Each `.qmd` here is a small document that once went wrong, with a comment at
the top saying how. `expectations.yml` says what its output should and should
not contain, and `run-tests.R` renders them all and checks.

```bash
make test                 # render everything and check
make test-update          # accept the current .tex and .typ as snapshots
Rscript tests/run-tests.R --filter typst
Rscript tests/run-tests.R --no-snapshots
```

A run says how many jobs it has at the start, numbers each one as it
begins (`[12/122]`), and after each prints a bar with how many are done,
passed and failed, and roughly how long the rest will take.

Fixtures are rendered several at a time, by worker copies of `run-tests.R`:
one fewer than the machine has cores, and no more than four. `--jobs 1`
renders one at a time, and `--jobs N` asks for N. A fixture's own jobs always
run one after another in the same worker, since they write the same files,
and so do fixtures that embed the same document. Results are printed in the
order the jobs finish. A worker's own output is in
`_results/_workers/worker-N.log`, which is where to look if a job reports
"no result".

A render that fails only because a sync client such as Dropbox was holding a
file (`os error 32`) is tried once more before it counts as a failure.

You need Quarto, R, and the packages named in `DESCRIPTION`
(`pak::pak(".")` or `remotes::install_deps(dependencies = TRUE)` installs
them). PDF fixtures need a LaTeX installation.

## Why the output is read rather than just rendered

A render that finishes is not a render that is right. Nearly everything that
has gone wrong in apaquarto rendered perfectly well: a panel's note missing, a
caption below the figure instead of above it, a note printed twice, panels
stacked one per row instead of side by side. Exit codes catch none of that, so
every fixture is read after it is rendered.

## Adding a test

1. Write the smallest document that shows the problem, and say in a comment
   what should happen and what used to happen instead.
2. Add an entry to `expectations.yml` naming the fixture, the format, and what should be in the output.
3. Run `make test`. It should fail before your fix and pass after it.

Assert the thing the fixture is for. A check that merely restates what the
renderer happens to do today breaks on every harmless change and teaches
everyone to ignore the suite.

### What can be read

| Key | Read from | Good for |
|-----|-----------|----------|
| `html` | the `.html` | words, class names |
| `docx` | the `.docx` | words, with the markup taken away |
| `docx-xml` | the `.docx` | style names, table properties |
| `docx-styles` | the `.docx` | the stylesheet: what a style is defined as |
| `pdf` | the `.pdf` | words, whatever produced it |
| `tex` | the `.tex` | structure: environments, labels |
| `typ` | the `.typ` | structure: grids, alignment |
| `layout` | the `.pdf`, measured | where lines sit: spacing, margins, sizes |

Under each but `layout`: `contains`, `absent`, `count` (text, and exactly how many times), and `order` (a list of texts that must appear in that order, each after the one before it). All of them are matched literally, never as a regular expression, so keep the strings in single quotes and write a backslash as a backslash.

### Measuring the page

`layout` measures the rendered `.pdf` from the position of each word, which is what a snapshot of the `.tex` or `.typ` cannot see. The source can stay the same while the page changes under it: Typst 0.12 moved the space between paragraphs from `block` to `par`, and every typst document lost its even spacing without a character of its `.typ` changing. A `layout` check runs for a `.pdf` from either the pdf or the typst format.

```yaml
- fixture: layout-journal.qmd
  to: apaquarto-typst
  expect:
    layout:
      - gap: [Betaone, Headone]   # baseline to baseline, in points
        is: 26
      - left: Alphaone            # from the paper's left edge, in points
        is: 64
      - size: Headone             # the font size, in points
        is: 11
```

A word is found by its text (a full stop or comma after it is allowed), at its first appearance; a `gap` looks for its second word on the first word's page. Make the words up for the fixture (Alphaone, Headtwo) so that each appears once. `within` sets how far off a measure may be. It is 1 by default, and 0.2 for a size. pdftools gives a position to the whole point, so a gap that is truly 26pt reads as 25 or 27 now and then, and a change of one point cannot be told from that; one of two points or more can. A YAML anchor (`&journal-layout`, then `*journal-layout`) holds two formats to the same list.

## Known failures

A job may carry `known_failure:` with a sentence saying what is wrong and why
it is not fixed here. There is one at the moment: in `.docx` the panels of a
multipanel figure are set one under the other when they carry labels of their
own, rather than side by side. Its checks still run and are still printed, but they do
not bring the build down. A job that passes while carrying the flag *does*
fail, so the flag gets taken off rather than left to rot.

## Snapshots

The `.tex` and `.typ` of each fixture are kept in `_snapshots/`, with paths and
dates taken out of them. They catch a structural change nobody asked for --- a
figure inside a figure, a grid that lost a column --- which no single string
check would have noticed. They are compared on Linux only: the same document
gives a slightly different file on another platform, and that is not a fault.

A `.pdf` is never compared byte for byte. It carries the date it was built and
the fonts of the machine that built it, so it differs on every run.

The snapshots committed here were made on Windows. If the first CI run reports
differences, look at them before doing anything: what should be there is the
same document written with Linux paths and whatever fonts that machine found,
and nothing else. The `.actual` files are in the run's `test-output` artifact,
or run `make test-update` on Linux and commit the result.

## The options page

`check-options.R` compares `options.yml`, which `options.qmd` is written
from, with the fields the filters read. It renders nothing and takes a few
seconds; `make test` runs it first, and so does CI. It fails when an option is
documented but no longer read, when a filter reads a field `options.yml` does
not document, and the same for the `language` keys.

A field that is read on purpose but does not belong on the options page ---
one apaquarto passes between its own filters, or one of Quarto's own --- goes
on one of the lists at the top of the script, each of which says what it is
for. `known_gaps` and `known_language_gaps` hold fields that should be
documented and are not yet; every run prints them, and a name comes off the
list when its entry is written. The script also fails when a name on any list
no longer needs to be there, so the lists cannot quietly go stale.

## Continuous integration

| Workflow | When | What |
|----------|------|------|
| `test.yml` | every push and pull request | Linux, current Quarto, fixtures + `example.qmd` |
| `cross-platform.yml` | pull request into `main`, release | Windows, macOS and Linux |
| `quarto-versions.yml` | weekly | the oldest supported Quarto, the current one, and the pre-release |

The weekly one matters most. Quarto 1.10 changed how a Typst document's
bibliography reaches a filter, which left every citation in every
apaquarto-typst document unresolved, and the release was months old before
anyone noticed.

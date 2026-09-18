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
2. Add an entry to `expectations.yml` naming the fixture, the format, and what
   should be in the output.
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
| `pdf` | the `.pdf` | words, whatever produced it |
| `tex` | the `.tex` | structure: environments, labels |
| `typ` | the `.typ` | structure: grids, alignment |

Under each: `contains`, `absent`, and `count` (text, and exactly how many
times). All of them are matched literally, never as a regular expression, so
keep the strings in single quotes and write a backslash as a backslash.

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

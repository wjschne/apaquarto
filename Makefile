SOURCE = example.qmd

all: pdf typst docx

# The fixtures in tests/ render against tests/_extensions, not the extension at
# the repo root. That copy is gitignored and nothing keeps it current, so once
# it falls behind, a test result describes old filters instead of the ones being
# worked on.
#
# Clear out the old files before copying, so a filter deleted from the extension
# also disappears from the copy instead of lingering and still running. Only
# files are removed, never the directories: on Windows a syncing client keeps a
# handle on the folder often enough that "rm -rf" on the directory itself fails
# partway and leaves the copy gutted. An emptied directory that no longer exists
# upstream is harmless by comparison.
.PHONY: sync-tests
sync-tests:
	mkdir -p tests/_extensions/apaquarto
	find tests/_extensions/apaquarto -mindepth 1 -type f -delete
	cp -R _extensions/apaquarto/. tests/_extensions/apaquarto/

pdf: pdf-man pdf-doc pdf-jou
typst: typst-man typst-doc typst-stu typst-jou

pdf-man: $(SOURCE)
	quarto render $< --to apaquarto-pdf \
	--output example-$@.pdf \
	-M documentmode:man

pdf-doc: $(SOURCE)
	quarto render $< --to apaquarto-pdf \
	--output example-$@.pdf \
	-M documentmode:doc

pdf-jou: $(SOURCE)
	quarto render $< --to apaquarto-pdf \
	--output example-$@.pdf \
	-M documentmode:jou

docx: $(SOURCE)
	quarto render $< --to apaquarto-docx \
	--output example-$@.docx

typst-man: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf \
	-M documentmode:man

typst-doc: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf \
	-M documentmode:doc

typst-stu: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf \
	-M documentmode:stu

typst-jou: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf \
	-M documentmode:jou

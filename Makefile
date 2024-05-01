SOURCE = example.qmd

tests: pdf-man pdf-doc pdf-jou docx typst-man

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
	--output example-$@.pdf

# Don't know yet how to use the documentmode: X trick with Typst
# https://github.com/quarto-dev/quarto-cli/discussions/3733

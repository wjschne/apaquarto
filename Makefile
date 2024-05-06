SOURCE = example.qmd

tests: pdf typst

pdf: pdf-man pdf-doc pdf-jou docx 
typst: typst-man typst-doc typst-jou

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
	
typst-doc: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf

typst-jou: $(SOURCE)
	quarto render $< --to apaquarto-typst \
	--output example-$@.pdf

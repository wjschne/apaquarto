


# Implemented Features

## Front Matter

If I were more knowledgeable about lua, I would have done everything with a lua filter. As things stand, I used an `include` statement to insert the front matter in the `_apa_title.qmd` file, which processes metadata with R. 


### Title

The title is extracted from the yaml metadata and then inserted both in the title page and as the first heading of the introduction.

### Running Header

I could not find a pure Quarto/Pandoc solution to insert a running header into a .docx file. Thankfully David Gohel's [officer package]{https://davidgohel.github.io/officer/} exists. The _apa_title.qmd file uses officer to search for "Running Header" in the `apaquarto.docx` reference file and replace it with whatever is specified in the `shorttitle` field of the metadata (converted to all caps). If nothing is specified, it will use the whole title in all caps. 

The document is saved with the file name `apa_processed.docx`. This file then serves as the reference document. If you want to adjust the reference document, you need to make changes in the `apaquarto.docx` file because `apa_processed.docx` is re-written with every render.

### Authors and Affilations

The R code that processes the authors and affiliations metadata works for me, but I am guessing that it is fragile and incomplete. I expect that changes will be necessary to account for different variations.

## Author Notes

The author notes have many optional parts.

## Abstract


## Captions and References for Figures and Tables

Figure titles, captions, and notes are composed with a custom knitr hook called `apa-figtab`. 

* APA style figures are specified for chunks that start with apafg- (e.g., agafg-myfigure). 
* Any chunk with a apatb- prefix will be set inside an APA style table environment. 
* Captions for either apagf- or apatb- chunks are set with the apa-cap chunk option. 
* A note under a figure or a table is set with the apa-note chunk option. 

```{r}
#| label: apafg-myfigure
#| apa-cap: This is my figure's caption.
#| apa-note: This is 

# Code for figure goes here

```

I would have preferred to use the standard quarto fig- and tbl- prefixes, but quarto does some automatic formatting that I could find a way to convert to APA style. I believe a full quarto solution is in the works, but my hacky workaround will do for now.

A reference to {apafg-myfigure} will be replaced by "Figure 1" (or "Figure 2", "Figure 3", etc.). Again, I would have liked to use the standard quarto reference system (i.e., {@apafg-myfigure}), but I could not any way around this problem.

## APA Level 4 and 5 Headings Appear with Subsequent Text

Level 4 and 5 Headings remain as true headings that appear in the navigation tab in MS Word. Yet they appear as if they are in the same paragraph with subsequent text. This feature was implemented with apaquarto.lua filter that inserts openxml tags in the headers: 

```openxml

<w:vanish/><w:specVanish/>

```
This creates a *Style Separator* character that you can see in MS Word by clicking the Show/Hide ¶ button. BTW, the CTRL+ALT+Enter keyboard shortcut in Word will insert a style separator. See https://www.cadmanediting.com/the-style-separator-a-hidden-gem-in-ms-word

## Automatically convert css class tags to docx custom style tags

The docxstyler.lua filter converts an expandable list css tags to custom styles automatically. It was adapted from a function in a blog post by James Adams: https://jmablog.com/post/pandoc-filters/

Normally, custom styles in the .docx template can be added with Pandoc's custom-style tag. Suppose our reference .docx file has a custome style called `FigureNote`. We can get Pandoc to use this style like so:

```markdown

:::{custom-style="FigureNote"}
some text
:::

```

This is nice but involves more typing than I prefer. And it is less readable if we want css styles for other formats. For example, 

```markdown

:::{.FigureNote custom-style="FigureNote"}
some text
:::

```
With the docxstyler.lua filter, we need only write this:

```markdown

:::{.FigureNote}
some text
:::

```

I did not want **every** css class to be converted, so I restricted the conversion to what is in the `customclasses` table. Feel free to expand the list as needed.


## Replace ampersands with "and" in all in-text citations

The apa7.csl file works great, except that in-text citations separate author names with ampersands instead of the word *and*. The apaand.lua filter fixes that problem.

The filter was taken from code posted by [Samuel Dodson]{https://github.com/citation-style-language/styles/issues/3748#issuecomment-430871259}.





# Desired Improvements

* Running header is placed in the .docx template by officer. A Pandoc solution would be better.
* Figure and Table labels using Quarto's `fig-` and `tbl-` prefixes.
* Figure and Tables in .pdf jou mode do not fit automatically.

# Missing Features

* For .docx and .html, there is no option to place intermingled tables and figures at the end like there is in .pdf documents. I imagine that a lua filter solution is possible.
* Create landscape pages for wide figures and tables.
* Masked references

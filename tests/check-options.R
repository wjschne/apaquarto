#!/usr/bin/env Rscript
# Does options.yml document the options apaquarto reads, and only those?
#
# options.qmd is written from options.yml, so the two cannot disagree; what
# can drift is options.yml against the filters. This reads both and fails
# when
#
#   1. a top-level option is documented but nothing in the extension
#      mentions it any more (it was renamed or removed);
#   2. a filter reads a top-level field that is documented nowhere and is
#      not on one of the lists below;
#   3. a language key is read or declared but documented nowhere, or
#      documented but neither read nor declared;
#   4. a name on one of the lists below no longer needs to be there.
#
# The lists are for fields that are read on purpose but do not belong on
# options.qmd: apaquarto's own handoffs between filters, and Quarto's and
# Pandoc's fields, which their documentation covers. known_gaps is the
# exception: user-facing fields that should be documented and are not yet.
# They are printed on every run rather than failing it; take a name off the
# list when its entry is written.
#
# Run from the repository root: Rscript tests/check-options.R. `make test`
# runs it before rendering the fixtures.

args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grep("^--file=", args)])
root <- if (length(script)) normalizePath(file.path(dirname(script), "..")) else getwd()

options_yml <- yaml::read_yaml(file.path(root, "options.yml"))
ext_dir <- file.path(root, "_extensions", "apaquarto")

# Fields apaquarto's filters set for one another, or that Quarto fills in
# from a user's own fields, rather than ones a user writes.
internal <- c(
  "affiliationsdifferent", "apa-appendix-count", "apa-float-labels",
  "apa-table-notes", "apaabstract", "apaauthor", "apadate", "apasubtitle",
  "apatitle", "apatitledisplay", "by-author", "description",
  "jou-running-authors", "references", "wordn", "zerocitations",
  # set by apaquote.lua for docxreferencedoc.lua
  "apa-quote-attribution"
)

# Quarto's and Pandoc's own fields, which apaquarto reads but their
# documentation covers.
quarto <- c(
  "author", "citeproc", "classoption", "crossref", "csl", "lang",
  "link-citations", "nocite", "number-depth", "numbersections",
  "ref-hyperlink", "subtitle", "toc", "toc-depth"
)

# Quarto's own language keys (share/language/_language.yml in a Quarto
# install), which apaquarto reads and Quarto documents. options.qmd lists a
# few of the most useful in the language-quarto group as well.
quarto_language <- c(
  "crossref-apx-prefix", "crossref-eq-prefix", "crossref-fig-title",
  "crossref-lof-title", "crossref-lot-title", "crossref-tbl-title",
  "section-title-abstract", "section-title-references",
  "title-block-keywords", "toc-title-document"
)

# Parents whose children are documented, and alternative spellings the
# documentation mentions in prose rather than as entries of their own.
in_prose <- c(
  "acknowledgements", "affiliations", "author-note", "language", "thesis",
  # apaquarto's old spelling of section-title-appendices, still accepted
  "section-title-appendixes"
)

# Read, meant for users, and not documented yet.
known_gaps <- character()

# Language keys that are not documented yet.
known_language_gaps <- character()

# Groups of options.yml whose entries are top-level fields, and those that
# name language keys. The others (affiliations, thesis, author-note fields,
# author roles) are fields inside another field.
top_groups <- c("general", "docx-typst", "pdf", "contents", "link-colours",
                "suppress")
language_groups <- c("language-apaquarto", "language-quarto",
                     "language-thesis")

# --------------------------------------------------------------------------

codes_in <- function(md) {
  gsub("`", "", regmatches(md, gregexpr("`[^`]+`", md))[[1]])
}

# The names a group documents: an entry's name, or the code in its term.
documented_in <- function(groups) {
  unique(unlist(lapply(options_yml[groups], function(group) {
    unlist(lapply(group, function(entry) {
      if (!is.null(entry$name)) entry$name else codes_in(entry$term)
    }))
  })))
}

read_files <- function(pattern) {
  files <- list.files(ext_dir, pattern = pattern, recursive = TRUE,
                      full.names = TRUE)
  paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
}
lua <- read_files("\\.lua$")
typst <- read_files("\\.typ$")
apalanguage <- paste(readLines(file.path(ext_dir, "apalanguage.lua"),
                               warn = FALSE), collapse = "\n")

matches <- function(text, pattern) {
  found <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  unique(sub(pattern, "\\1", found, perl = TRUE))
}

# Fields a filter reads: meta.x, meta["x"], flag(meta, "x"), and what
# typst-show.typ hands the template with $if(x)$.
meta_names <- "\\b(?:meta|m|doc\\.meta|metadata)"
read_fields <- unique(c(
  matches(lua, paste0(meta_names, "\\s*\\[\\s*\"([^\"]+)\"\\s*\\]")),
  matches(lua, paste0(meta_names, "\\.([A-Za-z_][A-Za-z0-9_]*)")),
  matches(lua, "flag\\(\\s*[A-Za-z_.]+\\s*,\\s*\"([^\"]+)\""),
  matches(typst, "\\$if\\(([A-Za-z0-9_-]+)\\)\\$")
))

# Language keys: declared in apalanguage.lua, read with lang() or
# language(), or read straight off meta.language.
read_language <- unique(c(
  matches(apalanguage, "field\\s*=\\s*\"([^\"]+)\""),
  matches(lua, "\\b(?:lang|language)\\(\\s*[A-Za-z_.]+\\s*,\\s*\"([^\"]+)\""),
  matches(lua, "language\\[\\s*\"([^\"]+)\"\\s*\\]")
))

# Whether the extension mentions a field at all: as a quoted name, as
# member access, or as a template variable. Looser than read_fields on
# purpose, since a field can be read through a list of names.
mentioned <- function(name) {
  grepl(paste0("\"", name, "\""), lua, fixed = TRUE) ||
    grepl(paste0("\\.", gsub("-", "\\-", name, fixed = TRUE), "\\b"), lua,
          perl = TRUE) ||
    grepl(paste0("$", name, "$"), typst, fixed = TRUE) ||
    grepl(paste0("$if(", name, ")$"), typst, fixed = TRUE)
}

# --------------------------------------------------------------------------

problems <- character()
problem <- function(...) problems <<- c(problems, paste0(...))

documented <- documented_in(names(options_yml))
documented_top <- documented_in(top_groups)
documented_language <- documented_in(language_groups)
allowed <- c(internal, quarto, in_prose, known_gaps)

for (name in documented_top) {
  if (!mentioned(name)) {
    problem("documented in options.yml but read nowhere: ", name)
  }
}

for (name in sort(setdiff(read_fields, c(documented, allowed)))) {
  problem("read by a filter but not documented in options.yml: ", name)
}

# Keys the code builds rather than writes out whole. The patterns above see
# only the part written out, ending in a hyphen; this says what the whole key
# begins with. thesispages.lua names a list's heading "thesis-" and the field
# that asks for the list, list-of-tables, so every such key begins
# thesis-list-of-. A key that begins so is read; one is documented when a
# documented key begins so.
built <- c("thesis-" = "thesis-list-of-")
for (part in setdiff(names(built), read_language)) {
  problem("listed as a built key in check-options.R but no longer read; ",
          "take it off the list: ", part)
}
read_language <- c(setdiff(read_language, names(built)),
                   unname(built[names(built) %in% read_language]))
built_prefixes <- unname(built)
language_documented <- function(key) {
  known <- c(documented_language, quarto_language, known_language_gaps,
             in_prose)
  if (endsWith(key, "-")) any(startsWith(known, key)) else key %in% known
}
language_read <- function(key) {
  key %in% read_language || mentioned(key) ||
    any(startsWith(key, built_prefixes))
}

for (name in sort(read_language)) {
  if (!language_documented(name)) {
    problem("language key read but not documented in options.yml: ", name)
  }
}

# Only apaquarto's own keys: Quarto reads the ones in language-quarto.
for (name in documented_in(c("language-apaquarto", "language-thesis"))) {
  if (!language_read(name)) {
    problem("language key documented in options.yml but read nowhere: ", name)
  }
}

# Lists that have gone stale.
for (name in intersect(c(allowed, known_language_gaps),
                       c(documented, documented_language))) {
  problem("listed in check-options.R but documented now; take it off the ",
          "list: ", name)
}
for (name in setdiff(c(internal, quarto, known_gaps), read_fields)) {
  problem("listed in check-options.R but no longer read; take it off the ",
          "list: ", name)
}
for (name in intersect(known_language_gaps, quarto_language)) {
  problem("listed as a language gap but Quarto documents it; take it off ",
          "the list: ", name)
}
for (name in setdiff(known_language_gaps, read_language)) {
  problem("listed in check-options.R but no longer read; take it off the ",
          "list: ", name)
}

# --------------------------------------------------------------------------

gaps <- c(known_gaps, known_language_gaps)
cat(sprintf("options.yml: %d names documented, %d fields and %d language keys read\n",
            length(unique(c(documented, documented_language))),
            length(read_fields), length(read_language)))
if (length(gaps)) {
  cat(sprintf("not documented yet (known, %d): %s\n", length(gaps),
              paste(gaps, collapse = ", ")))
}
if (length(problems)) {
  cat(paste0("  FAIL ", problems, "\n"), sep = "")
  cat(sprintf("%d option check(s) failed\n", length(problems)))
  quit(status = 1)
}
cat("options.yml agrees with the filters\n")

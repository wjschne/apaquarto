# Writes the option lists of options.qmd out of options.yml.
#
# options.qmd calls apa_options("group") in a chunk with `results: asis`, and
# each entry of that group in options.yml comes out as one item of a
# markdown definition list: the option's name, and under it its default and
# its description. The lists are written fresh on every render, so there is
# no table in the page for an editor to reflow.

options_data <- yaml::read_yaml("options.yml")

# An option documented in more than one group (papersize, say) gets an anchor
# that names its group as well, so that every anchor on the page is unique.
option_names <- unlist(lapply(options_data, function(group) {
  unlist(lapply(group, function(entry) entry$name))
}))
repeated_names <- unique(option_names[duplicated(option_names)])

option_anchor <- function(group, name) {
  if (name %in% repeated_names) {
    paste0("opt-", group, "-", name)
  } else {
    paste0("opt-", name)
  }
}

# Every line after the first indented by four spaces, which is what puts a
# paragraph, a list or a fenced code block inside a definition.
indent_definition <- function(text) {
  text <- sub("\\s+$", "", text)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  rest <- ifelse(lines[-1] == "", "", paste0("    ", lines[-1]))
  paste(c(paste0(":   ", lines[1]), rest), collapse = "\n")
}

apa_options <- function(group) {
  entries <- options_data[[group]]
  if (is.null(entries)) stop("options.yml has no group called ", group)

  items <- vapply(entries, function(entry) {
    term <- if (!is.null(entry$name)) {
      sprintf("[`%s`]{#%s}", entry$name, option_anchor(group, entry$name))
    } else {
      # A definition list's term is one line, so several names written on
      # lines of their own are set side by side.
      gsub("\\s*\n\\s*", " ", trimws(entry$term))
    }
    definition <- entry$description
    if (!is.null(entry$default)) {
      definition <- paste0("Default: ", entry$default, "\n\n", definition)
    }
    paste0(term, "\n\n", indent_definition(definition))
  }, character(1))

  # In a div of its own so that the site's stylesheet can set the list apart
  # (.option-list in apaquarto.scss).
  cat("\n::: {.option-list}\n\n", paste(items, collapse = "\n\n"),
      "\n\n:::\n\n", sep = "")
}

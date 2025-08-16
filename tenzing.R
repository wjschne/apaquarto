library(tidyverse)

#' Generate human readable report of the conflict of interest statements
#' 
#' The functions generates the conflict of interest statement section of the manuscript.
#' The output is generated from an contributors_table based on the [contributors_table_template()].
#' 
#' @family output functions
#' 
#' @param contributors_table validated contributors_table
#' @param initials Logical. If true initials will be included instead of full
#'   names in the output
#'   
#' @return The function returns a string.
#' @export
#' @examples 
#' example_contributors_table <- read_contributors_table(
#' contributors_table = system.file("extdata",
#' "contributors_table_example.csv", package = "tenzing", mustWork = TRUE))
#' print_conflict_statement(contributors_table = example_contributors_table, initials = FALSE)
#' 
#' @importFrom rlang .data
print_conflict_statement <- function(contributors_table, initials = FALSE) {
  # Validate input ---------------------------
  if (all(is.na(contributors_table[["Conflict of interest"]]))) stop("There are no conflict of interest statements provided for any of the contributors.")
  
  # Restructure dataframe ---------------------------
  if (initials) {
    coi_data <-
      contributors_table %>% 
      dplyr::mutate_at(
        dplyr::vars(.data$Firstname, .data$`Middle name`, .data$Surname),
        as.character) %>% 
      add_initials() %>% 
      dplyr::rename(Name = .data$abbrev_name)
  } else {
    coi_data <-
      contributors_table %>% 
      abbreviate_middle_names_df() %>%
      dplyr::mutate(Name = dplyr::if_else(is.na(.data$`Middle name`),
                                          paste(.data$Firstname, .data$Surname),
                                          paste(.data$Firstname, .data$`Middle name`, .data$Surname)))
  }
  
  coi_data <- 
    coi_data %>% 
    dplyr::select(.data$Name, .data[["Conflict of interest"]]) %>% 
    dplyr::filter(!is.na(.data[["Conflict of interest"]]) & .data[["Conflict of interest"]] != "") %>% 
    dplyr::group_by(.data[["Conflict of interest"]]) %>% 
    dplyr::summarise(Names = glue_oxford_collapse(.data$Name),
                     n_names = dplyr::n())
  
  # Format output string ---------------------------
  res <-
    coi_data %>% 
    dplyr::transmute(
      out = glue::glue("{Names} {dplyr::if_else(n_names > 1, 'declare', 'declares')} {`Conflict of interest`}")) %>% 
    dplyr::summarise(out = glue::glue_collapse(.data$out, sep = "; ")) %>% 
    dplyr::mutate(out = stringr::str_c(.data$out, "."))
  
  res %>% 
    dplyr::pull(.data$out)
}



#' Collapse a character vector with oxford comma
#' 
#' Collapses a character vector into a length 1 vector,
#' by using ", " as a separator and adding the oxford comma
#' if there original character vector length is longer than 3.
#' The function is from the cli package: https://github.com/jonocarroll/cli/blob/2d3fbc4b41327df82df1102cdfc0a5c99822809b/R/inline.R
#' 
#' @param x character, the vector to be collapsed
#' 
#' @return The function returns a vector of length 1.
#' 
#' @keywords internal
glue_oxford_collapse <- function(x) {
  if (length(x) >= 3) {
    glue::glue_collapse(x, sep = ", ", last = ", and ")
  } else {
    glue::glue_collapse(x, sep = ", ", last = " and ")
  }
}



#' Add initials to the contributors_table
#' 
#' This function adds the initials to the contributors_table based on the Firstname,
#' Middle name and Surname. The function uses whitespaces and hypens to
#' detect the separate names. Also, the function is case sensitive.
#' 
#' @param contributors_table the imported contributors_table
#' 
#' @return The function returns the contributors_table with the initials in
#'   an additional column
#' @export
#' 
#' @importFrom rlang .data
add_initials <- function(contributors_table) {
  contributors_table %>% 
    # If first name contains -, abbreviate both, else, abbreviate all separate names
    dplyr::mutate(fir = abbreviate(.data$Firstname, collapse = ""),
                  mid = abbreviate(.data$`Middle name`, collapse = ""),
                  las = abbreviate(.data$Surname, collapse = ""),
                  abbrev_name = stringr::str_glue("{fir}{mid}{las}", .na = "")) %>% 
    # Get duplicated abbreviations
    dplyr::add_count(.data$abbrev_name, name = "dup_abr") %>% 
    # If abbreviation has multiple instances, add full surname
    dplyr::mutate(abbrev_name = dplyr::if_else(.data$dup_abr > 1,
                                               stringr::str_glue("{fir}{mid} {Surname}", .na = ""),
                                               .data$abbrev_name))
}

#' Abbreviate names
#'
#' Abbreviates multiple words to first letters
#'
#' @param string Character. A character vector with the names
#' @param collapse Character. A string that will be used to separate names
#'
#' @return Returns a character vector with one element.
#' @export
#'
#' @examples
#' tenzing:::abbreviate("Franz Jude Wayne", collapse = "")
abbreviate <- function(string, collapse) {
  string <- string[string != ""]
  if(length(string) > 0) {
    res <- 
      string %>% 
      # Separate the strings by keeping the hyphen
      stringr::str_extract_all("\\w+|-")  %>% 
      # Keep only the first letter
      purrr::map(stringr::str_sub, 1, 1) %>% 
      # Add dots after only letters not the hyphen
      purrr::map(stringr::str_replace, "(?<=^\\w)", ".") %>% 
      # Collapse them to one string
      purrr::map_chr(stringr::str_c, collapse = collapse) %>% 
      # Drop spaces around hyphens
      stringr::str_replace_all("\\s+(?=\\p{Pd})|(?<=\\p{Pd})\\s+", "")
  } else {
    res <- NULL
  }
  res
}

#' Abbreviate middle names in a dataframe
#' 
#' The function calls the [abbreviate()] function to
#' abbreviate middle names in the `Middle name` variable in a
#' dataframe if they are present. The function requires a valid
#' `contributors_table` as an input to work.
#' 
#' @param contributors_table the imported contributors_table
#' 
#' @return The function returns a dataframe with abbreviated middle
#' names.
#' @export
#' 
#' @importFrom rlang .data
abbreviate_middle_names_df <- function(contributors_table) {
  contributors_table %>%
    dplyr::mutate_at(
      dplyr::vars(.data$Firstname, .data$`Middle name`, .data$Surname),
      as.character) %>% 
    dplyr::rowwise() %>% 
    dplyr::mutate(
      `Middle name` = dplyr::if_else(
        is.na(.data$`Middle name`),
        NA_character_,
        abbreviate(.data$`Middle name`, collapse = " ")
      )
    ) %>%
    dplyr::ungroup()
}

#' Generate human readable report of the funding information
#' 
#' The functions generates the funding information section of the manuscript.
#' The output is generated from an contributors_table based on the [contributors_table_template()].
#' 
#' @family output functions
#' 
#' @param contributors_table validated contributors_table
#' @param initials Logical. If true initials will be included instead of full
#'   names in the output
#'   
#' @return The function returns a string.
#' @export
#' @examples 
#' example_contributors_table <- read_contributors_table(
#' contributors_table = system.file("extdata",
#' "contributors_table_example.csv", package = "tenzing", mustWork = TRUE))
#' print_funding(contributors_table = example_contributors_table, initials = FALSE)
#' 
#' @importFrom rlang .data
print_funding <- function(contributors_table, initials = FALSE) {
  # Validate input ---------------------------
  if (all(is.na(contributors_table$Funding))) stop("There is no funding information provided for any of the contributors.")
  
  # Restructure dataframe ---------------------------
  if (initials) {
    funding_data <-
      contributors_table %>% 
      dplyr::mutate_at(
        dplyr::vars(.data$Firstname, .data$`Middle name`, .data$Surname),
        as.character) %>% 
      add_initials() %>% 
      dplyr::rename(Name = .data$abbrev_name)
  } else {
    funding_data <-
      contributors_table %>% 
      abbreviate_middle_names_df() %>%
      dplyr::mutate(Name = dplyr::if_else(is.na(.data$`Middle name`),
                                          paste(.data$Firstname, .data$Surname),
                                          paste(.data$Firstname, .data$`Middle name`, .data$Surname)))
  }
  
  funding_data <- 
    funding_data %>% 
    dplyr::select(.data$Name, .data$Funding) %>% 
    dplyr::filter(!is.na(.data$Funding) & .data$Funding != "") %>% 
    dplyr::group_by(.data$Funding) %>% 
    dplyr::summarise(Names = glue_oxford_collapse(.data$Name),
                     n_names = dplyr::n())
  
  # Format output string ---------------------------
  res <-
    funding_data %>% 
    dplyr::transmute(
      out = glue::glue("{Names} {dplyr::if_else(n_names > 1, 'were', 'was')} supported by {Funding}")) %>% 
    dplyr::summarise(out = glue::glue_collapse(.data$out, sep = "; ")) %>% 
    dplyr::mutate(out = stringr::str_c(.data$out, "."))
  
  res %>% 
    dplyr::pull(.data$out)
}





print_apaquarto_author <- function(contributors_table) {
  v_credit <- c(
    `Conceptualization` = "conceptualization",
    `Data curation` = "data curation",
    `Formal analysis` = "formal analysis",
    `Funding acquisition` = "funding acquisition",
    `Investigation` = "investigation",
    `Methodology` = "methodology",
    `Project administration` = "project administration",
    `Resources` = "resources",
    `Software` = "software",
    `Supervision` = "supervision",
    `Validation` = "validation",
    `Visualization` = "visualization",
    `Writing - original draft` = "writing",
    `Writing - review & editing` = "editing"
  )
  
  author_list <- contributors_table |> 
    arrange(`Order in publication`) |> 
    filter(!is.na(Surname)) |> 
    rename(corresponding = `Corresponding author?`,
           orcid = `ORCID iD`,
           email = `Email address`) |> 
    mutate(across(Firstname:Surname, \(x) tidyr::replace_na(x, replace = ""))) |> 
    unite(name, Firstname, `Middle name`, Surname, sep = " ") |> 
    mutate(name = str_squish(name)) |> 
    pivot_longer(Conceptualization:`Writing - review & editing`, names_to = "credit") |> 
    mutate(credit = str_replace_all(credit, v_credit)) |> 
    nest(credit = c(value, credit)) |> 
    mutate(credit = map(credit, \(x) {
      filter(x, value) |> pull(credit)
    })) |> 
    pivot_longer(starts_with("Affiliation "), names_to = "affiliation_column", values_to = "affiliation") |> 
    select(-affiliation_column) |> 
    nest(affiliation = affiliation) |> 
    mutate(affiliation = map(affiliation, \(x) {
      x[!is.na(x)]
    })) |> 
    select(name, orcid, email, corresponding, credit, affiliation) |> 
    mutate(corresponding = ifelse(corresponding, TRUE, NA)) |> 
    mutate(person = name) |> 
    nest(author = -person) |> 
    select(-person) |> 
    mutate(author = map(author, \(x) {
      isempty = apply(x, MARGIN = 2, \(xx) all(is.na(xx)))
      x$credit <- list(x$credit[[1]])
      x$affiliation <- list(x$affiliation[[1]])
      # as.list(x[, !isempty])
      l <- as.list(x[, !isempty])
      if (!all(is.na(x$credit))) {
        l$credit <- x$credit[[1]]
      }
      if (!all(is.na(x$affiliation))) {
        l$affiliation <- x$affiliation[[1]]
      }
      l
    }))
  
  author_list[[1]]
  
}



create_apaquarto_qmd <- function(contributors_table, file = "apaquarto_paper.qmd") {
  
  if (tools::file_ext(file) == "") {
    file <- paste0(file, ".qmd")
  }
  
  apaquarto_list <- list(
    title = "Your Title",
    shorttitle = NULL,
    author = print_apaquarto_author(contributors_table),
    `blank-lines-above-author-note` = 2L,
    `author-note` = list(
      `status-changes` = list(
        `affiliation-change` = NULL,
        deceased = NULL
      ),
      disclosures = list(
        `financial-support` = print_funding(contributors_table),
        `conflict-of-interest` = print_conflict_statement(contributors_table),
        `study-registration` = NULL,
        `data-sharing` = NULL,
        `related-report` = NULL,
        gratitude = NULL,
        `authorship-agreements` = NULL
      )
    ),
    abstract = "Summary of paper",
    `impact-statement` = NULL,
    keywords = list("Keyword 1", "Keyword 2", "Keyword 3"),
    `word-count` = "false",
    floatsintext = TRUE,
    `numbered-lines` = FALSE,
    bibliography = "bibliography.bib",
    `suppress-title-page` = FALSE,
    `link-citations` = TRUE,
    mask = FALSE,
    `masked-citations` = NULL,
    nocite = NULL,
    `draft-date` = FALSE,
    lang = "en",
    language = list(
      `citation-last-author-separator` = "and",
      `citation-masked-author` = "Masked Citation",
      `citation-masked-date` = "n.d",
      `citation-masked-title` = "Masked Title",
      email = "Email",
      `title-block-author-note` = "Author Note",
      `title-block-correspondence-note` = "Correspondence concerning this article should be addressed to",
      `title-block-role-introduction` = "Author roles were classified using the Contributor Role Taxonomy (CRediT; [credit.niso.org](https://credit.niso.org)) as follows:",
      `title-impact-statement` = "Impact Statement",
      `references-meta-analysis` = "References marked with an asterisk indicate studies included in the meta-analysis."
    ),
    `no-ampersand-parenthetical` = FALSE,
    format = list(
      `apaquarto-html` = list(toc = TRUE),
      `apaquarto-docx` = list(toc = FALSE),
      `apaquarto-typst` = list(`keep-typ` = TRUE,
                               `list-of-figures` = FALSE,
                               `list-of-tables` = FALSE,
                               toc = FALSE, 
                               papersize = "us-letter"),
      `apaquarto-pdf` = list(documentmode = "man",
                             `keep-tex` = TRUE)
      
    )
  )
  

  
  # Make .qmd file
  cat(paste0(
    "---\n", 
    yaml::as.yaml(
      apaquarto_list, 
      indent.mapping.sequence = TRUE,
      handlers = list(
        logical = function(x) {
          result <- ifelse(x, "true", "false")
          class(result) <- "verbatim"
          return(result)
        })) |> 
      gsub(pattern = "'false'", replacement = "false") |> 
      gsub(pattern = "'true'", replacement = "true"),
    "---\n\n",
    "<!-- The introduction should not have a level-1 heading such as Introduction. -->\n\n",
    "## Section in Introduction\n\n",
    "## Another Section in Introduction\n\n",
    "# Method\n\n",
    "## Participants\n\n",
    "## Measures\n\n",
    "## Procedure\n\n",
    "# Results\n\n",
    "# Discussion\n\n",
    "## Limitations and Future Directions\n\n",
    "## Conclusion\n\n",
    "# References\n\n", 
    "<!-- References will auto-populate in the refs div below -->\n\n", 
    "::: {#refs}\n", 
    ":::\n\n", 
    "# This Section Is an Appendix {#apx-a}\n\n", 
    "# Another Appendix {#apx-b}\n"),
    file = file)
  
}


# import table
contributors_table <- readxl::read_excel("contributors_table_template_tenzing.xlsx")

create_apaquarto_qmd(contributors_table,
                     file = "my_paper.qmd")


# Renders the fixtures in this directory and checks what comes out.
#
# A render that finishes without an error says very little. Most of what has
# gone wrong in apaquarto rendered perfectly well and was simply wrong: a
# panel's note missing, a caption below the figure instead of above it, a note
# printed twice, panels stacked one per row instead of side by side. So every
# fixture here is rendered and then read, and the text of the output is checked
# against what tests/expectations.yml says should and should not be in it.
#
# Written in R because R is installed for the renders anyway, and because
# pdftools reads a .pdf without needing poppler on the path -- which matters on
# the windows and macos runners, where pdftotext is not there to be had.
#
# Usage, from anywhere:
#
#     Rscript tests/run-tests.R                  every job
#     Rscript tests/run-tests.R --filter typst   jobs whose id matches
#     Rscript tests/run-tests.R --update-snapshots
#     Rscript tests/run-tests.R --no-snapshots   content checks only
#
# Exits 1 if any check fails, which is what continuous integration reads.

suppressWarnings(suppressMessages({
  library(yaml)
}))

# ---------------------------------------------------------------- arguments --

args <- commandArgs(trailingOnly = TRUE)
opt_update <- "--update-snapshots" %in% args
opt_nosnap <- "--no-snapshots" %in% args
filter_at <- match("--filter", args)
opt_filter <- if (!is.na(filter_at) && length(args) > filter_at) {
  args[filter_at + 1]
} else {
  NULL
}

# --------------------------------------------------------------- locations --

# The script is run from the repository root as often as from tests/, so the
# directories are worked out from the script's own path rather than from the
# working directory.
script_path <- local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/")
  } else {
    normalizePath("tests/run-tests.R", winslash = "/")
  }
})
tests_dir <- dirname(script_path)
root_dir <- dirname(tests_dir)
results_dir <- file.path(tests_dir, "_results")
snapshot_dir <- file.path(tests_dir, "_snapshots")

# ------------------------------------------------------------------ helpers --

bold <- function(x) x
pass_mark <- "PASS"
fail_mark <- "FAIL"

say <- function(...) cat(..., "\n", sep = "")

# The extensions the fixtures render against are a copy, kept out of git. A
# stale copy makes every result describe filters that are no longer being
# worked on, so it is rebuilt at the start of every run. Files are deleted
# rather than whole directories: on windows a syncing client holds a handle on
# a folder often enough that removing the directory itself fails partway and
# leaves the copy gutted.
sync_extensions <- function() {
  for (name in c("apaquarto", "apaquarto-latex")) {
    from <- file.path(root_dir, "_extensions", name)
    if (!dir.exists(from)) next
    to <- file.path(tests_dir, "_extensions", name)
    dir.create(to, recursive = TRUE, showWarnings = FALSE)
    old <- list.files(to, recursive = TRUE, full.names = TRUE, all.files = TRUE,
                      no.. = TRUE)
    unlink(old[!dir.exists(old)])
    file.copy(list.files(from, full.names = TRUE, all.files = TRUE,
                         no.. = TRUE),
              to, recursive = TRUE, overwrite = TRUE)
  }
}

quarto_bin <- function() {
  found <- Sys.which("quarto")
  if (nzchar(found)) return(unname(found))
  stop("quarto is not on the path")
}

# What each key in an expectation is read from. Two of them look at the same
# .docx: "docx" reads the words, which is what a check about wording wants, and
# "docx-xml" reads the markup underneath, which is where a style name lives.
# `squash` runs every stretch of whitespace together into one space, which the
# three readers that look at words want and the three that look at structure do
# not. A .pdf wraps a table cell over as many lines as it needs and pads the
# columns out with spaces, so a check for a phrase would otherwise have to know
# where the renderer happened to break it.
readers <- list(
  html     = list(ext = "html", how = "html", squash = TRUE),
  docx     = list(ext = "docx", how = "docx-text", squash = TRUE),
  "docx-xml" = list(ext = "docx", how = "docx-xml", squash = FALSE),
  pdf      = list(ext = "pdf",  how = "pdf", squash = TRUE),
  tex      = list(ext = "tex",  how = "plain", squash = FALSE),
  typ      = list(ext = "typ",  how = "plain", squash = FALSE)
)

# Everything a render might leave behind, for one fixture.
artifacts_of <- function(stem) {
  exts <- c("html", "docx", "pdf", "tex", "typ")
  paths <- file.path(tests_dir, paste0(stem, ".", exts))
  stats::setNames(paths, exts)
}

docx_xml <- function(path) {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  files <- utils::unzip(path, exdir = tmp)
  doc <- grep("word/document\\.xml$", files, value = TRUE)
  if (length(doc) == 0) return("")
  paste(readLines(doc[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

# The words of a .docx, with the markup taken away. Word splits a sentence over
# as many runs as it likes, so the runs are joined before anything is looked
# for in them; a check for a phrase would otherwise fail on where word happened
# to break it.
docx_text <- function(path) {
  xml <- docx_xml(path)
  xml <- gsub("</w:p>", "\n", xml, fixed = TRUE)
  matches <- regmatches(xml, gregexpr("<w:t[^>]*>[^<]*</w:t>", xml))[[1]]
  text <- gsub("<[^>]*>", "", matches)
  text <- paste(text, collapse = "")
  text
}

# The readable text of an output file, with the spaces apaquarto makes
# unbreakable turned back into ordinary ones. A note is written with a
# non-breaking space after its "Note." prefix, and a check reading "Note. A
# note ..." should not have to know that.
text_of <- function(path, how, squash = FALSE) {
  if (!file.exists(path)) return(NULL)
  text <- switch(
    how,
    "docx-text" = docx_text(path),
    "docx-xml" = docx_xml(path),
    "pdf" = {
      if (!requireNamespace("pdftools", quietly = TRUE)) {
        stop("the pdftools package is needed to read .pdf output")
      }
      paste(pdftools::pdf_text(path), collapse = "\n")
    },
    paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  )
  if (how == "html") text <- gsub("&nbsp;", " ", text, fixed = TRUE)
  text <- gsub("\u{00a0}", " ", text)
  text <- gsub("\u{202f}", " ", text)
  if (squash) text <- gsub("[[:space:]]+", " ", text)
  text
}

count_of <- function(haystack, needle) {
  at <- gregexpr(needle, haystack, fixed = TRUE)[[1]]
  # gregexpr answers a single -1 when it found nothing.
  sum(at > 0)
}

# A .tex or .typ with everything machine-specific taken out of it, so that the
# same document gives the same text on another machine and in another checkout.
normalize <- function(text) {
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  text <- gsub("\\", "/", text, fixed = TRUE)
  for (dir in c(root_dir, tests_dir, tempdir())) {
    text <- gsub(gsub("\\", "/", dir, fixed = TRUE), "<dir>", text,
                 fixed = TRUE)
  }
  # Any remaining absolute path, and the dates and identifiers quarto writes
  # afresh on every render.
  # A drive letter, but not the "s:" of an https:// url, which is part of the
  # document and should show up in a comparison if it changes.
  text <- gsub("(?<![A-Za-z0-9])[A-Za-z]:/[^\"'} \t\n]*", "<path>", text,
               perl = TRUE)
  text <- gsub("/(Users|home|tmp|var)/[^\"'} \t\n]*", "<path>", text)
  text <- gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}", "<date>", text)
  text <- gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
               "<uuid>", text)
  text <- gsub("[ \t]+\n", "\n", text)
  text
}

# ---------------------------------------------------------------- the jobs --

jobs <- yaml::read_yaml(file.path(tests_dir, "expectations.yml"))

job_id <- function(job) paste0(tools::file_path_sans_ext(job$fixture), "__",
                               job$to)

# Two jobs can name the same fixture and format -- one holding the checks that
# pass and one holding a known failure -- so a repeated id is numbered. The id
# names a log file and tells one job's results from another's.
local({
  ids <- vapply(jobs, job_id, character(1))
  for (name in unique(ids[duplicated(ids)])) {
    at <- which(ids == name)
    for (n in seq_along(at)) {
      jobs[[at[n]]]$id_suffix <<- paste0("-", n)
    }
  }
})
job_id <- local({
  plain <- job_id
  function(job) paste0(plain(job), if (is.null(job$id_suffix)) "" else
    job$id_suffix)
})

if (!is.null(opt_filter)) {
  jobs <- Filter(function(job) grepl(opt_filter, job_id(job)), jobs)
}

if (length(jobs) == 0) stop("no jobs to run")

sync_extensions()
# Quarto is given a fixture by name and resolves its images and bibliography
# beside it, so the renders are run from the tests directory whatever directory
# the script was called from.
setwd(tests_dir)
dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(snapshot_dir, recursive = TRUE, showWarnings = FALSE)

failures <- character(0)
known <- character(0)

# A job may carry `known_failure:` with a sentence saying what is wrong and why
# it is not fixed here. Its checks still run and are still printed, but they do
# not bring the build down. A job that passes while carrying the flag does fail,
# so that the flag is taken off rather than left to rot.
current_known <- NULL
note_failure <- function(id, message) {
  if (!is.null(current_known)) {
    known <<- c(known, paste0(id, ": ", message))
    say("  KNOWN ", message)
    return(invisible(NULL))
  }
  failures <<- c(failures, paste0(id, ": ", message))
  say("  ", fail_mark, " ", message)
}

for (job in jobs) {
  id <- job_id(job)
  stem <- tools::file_path_sans_ext(job$fixture)
  current_known <- job$known_failure
  say("")
  say(bold(id))
  if (!is.null(current_known)) say("  known failure: ", current_known)

  # Anything a previous run left behind, so that a render that quietly produces
  # nothing cannot be read as a pass on the last run's output.
  unlink(unname(artifacts_of(stem)))

  rendered <- system2(
    quarto_bin(),
    # Not quoted: system2 passes each element as one argument, and a shell
    # quote of its own is taken literally by cmd.exe on windows.
    c("render", job$fixture, "--to", job$to,
      "-M", "keep-tex:true", "-M", "keep-typ:true"),
    stdout = TRUE, stderr = TRUE
  )
  status <- attr(rendered, "status")
  log_file <- file.path(results_dir, paste0(id, ".log"))
  writeLines(rendered, log_file)

  if (!is.null(status) && status != 0) {
    note_failure(id, paste0("render failed (exit ", status, "); see ",
                            basename(log_file)))
    next
  }

  produced <- artifacts_of(stem)
  produced <- produced[file.exists(produced)]
  if (length(produced) == 0) {
    note_failure(id, "render produced no output")
    next
  }
  say("  rendered: ", paste(names(produced), collapse = ", "))

  # ------------------------------------------------------ content checks --
  for (key in names(job$expect)) {
    wanted <- job$expect[[key]]
    reader <- readers[[key]]
    if (is.null(reader)) {
      note_failure(id, paste0("expectations.yml asks for \"", key,
                              "\", which is not one of: ",
                              paste(names(readers), collapse = ", ")))
      next
    }
    ext <- reader$ext
    path <- artifacts_of(stem)[[ext]]
    if (!file.exists(path)) {
      note_failure(id, paste0("expected a .", ext, " and there is none"))
      next
    }
    text <- text_of(path, reader$how, reader$squash)

    for (needle in wanted$contains) {
      if (!grepl(needle, text, fixed = TRUE)) {
        note_failure(id, paste0(key, " is missing: ", needle))
      }
    }
    for (needle in wanted$absent) {
      if (grepl(needle, text, fixed = TRUE)) {
        note_failure(id, paste0(key, " should not contain: ", needle))
      }
    }
    for (needle in names(wanted$count)) {
      expected <- as.integer(wanted$count[[needle]])
      actual <- count_of(text, needle)
      if (actual != expected) {
        note_failure(id, paste0(key, " has ", actual, " of [", needle,
                                "], expected ", expected))
      }
    }
  }

  # ----------------------------------------------------------- snapshots --
  # Only the .tex and the .typ, which are text quarto writes the same way every
  # time. A .pdf is not comparable: it carries the date it was built and the
  # fonts of the machine that built it, so a byte comparison reports a
  # difference on every run and on every platform.
  if (!opt_nosnap) {
    for (ext in intersect(c("tex", "typ"), names(produced))) {
      path <- produced[[ext]]
      snapshot <- file.path(snapshot_dir, paste0(id, ".", ext))
      current <- normalize(text_of(path, ext))
      if (opt_update || !file.exists(snapshot)) {
        writeLines(current, snapshot)
        say("  snapshot written: ", basename(snapshot))
      } else {
        saved <- paste(readLines(snapshot, warn = FALSE, encoding = "UTF-8"),
                       collapse = "\n")
        if (!identical(trimws(saved), trimws(current))) {
          diff_file <- file.path(results_dir, paste0(id, ".", ext, ".actual"))
          writeLines(current, diff_file)
          note_failure(id, paste0(".", ext,
                                  " differs from its snapshot; compare ",
                                  basename(snapshot), " with ",
                                  basename(diff_file)))
        }
      }
    }
  }

  job_failed <- any(startsWith(failures, paste0(id, ":"))) ||
    any(startsWith(known, paste0(id, ":")))
  if (!job_failed) {
    say("  ", pass_mark)
    if (!is.null(current_known)) {
      current_known <- NULL
      note_failure(id, paste0("marked known_failure but every check passed; ",
                              "take the flag off"))
    }
  }
}

say("")
if (length(known) > 0) {
  say(length(known), " known failure(s), not counted against this run:")
  for (item in known) say("  - ", item)
  say("")
}
if (length(failures) > 0) {
  say(length(failures), " check(s) failed:")
  for (failure in failures) say("  - ", failure)
  quit(status = 1)
}
say("all checks passed")

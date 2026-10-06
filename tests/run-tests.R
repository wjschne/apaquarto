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
#     Rscript tests/run-tests.R --jobs 1         one render at a time
#
# Fixtures are rendered several at a time, each by a worker copy of this
# script; --jobs says how many (by default one fewer than the machine has
# cores, and no more than four).
#
# Exits 1 if any check fails, which is what continuous integration reads.

suppressWarnings(suppressMessages({
  library(yaml)
}))

# ---------------------------------------------------------------- arguments --

args <- commandArgs(trailingOnly = TRUE)
opt_update <- "--update-snapshots" %in% args
opt_nosnap <- "--no-snapshots" %in% args
value_of <- function(flag) {
  at <- match(flag, args)
  if (!is.na(at) && length(args) > at) args[at + 1] else NULL
}
# A worker is this same script, started by the main one with --worker and the
# directory the two share; it runs fixtures and reports on each, and leaves
# the rest -- the extension copy, the progress, the summary -- to the main one.
opt_worker <- value_of("--worker")
opt_worker_id <- value_of("--worker-id")
opt_jobs <- local({
  asked <- suppressWarnings(as.integer(value_of("--jobs")))
  if (!is.na(asked) && length(asked) == 1) return(max(1L, asked))
  cores <- suppressWarnings(parallel::detectCores())
  if (is.na(cores)) cores <- 2L
  as.integer(min(4, max(1, cores - 1)))
})
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

# In a worker, what would be printed is kept instead, and handed to the main
# process with the job's result, which prints it.
say_buffer <- NULL
say <- function(...) {
  line <- paste(unlist(list(...)), collapse = "")
  if (!is.null(say_buffer)) {
    say_buffer <<- c(say_buffer, line)
  } else {
    cat(line, "\n", sep = "")
  }
}

# The extensions the fixtures render against are a copy, kept out of git. A
# stale copy makes every result describe filters that are no longer being
# worked on, so it is rebuilt at the start of every run. Files are deleted
# rather than whole directories: on windows a syncing client holds a handle on
# a folder often enough that removing the directory itself fails partway and
# leaves the copy gutted.
sync_extensions <- function() {
  managed <- c("apaquarto")
  # An extension that is no longer shipped has to go from the copy as well.
  # apaquarto-latex lived here while the plain latex format was being written,
  # and a copy left behind is one quarto will still resolve a format from:
  # renders then come from code the repository no longer has, which is a hard
  # thing to notice from the results alone.
  for (stale in setdiff(list.dirs(file.path(tests_dir, "_extensions"),
                                  full.names = FALSE, recursive = FALSE),
                        managed)) {
    here <- file.path(tests_dir, "_extensions", stale)
    unlink(list.files(here, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, no.. = TRUE), recursive = TRUE)
    unlink(here, recursive = TRUE)
  }
  for (name in managed) {
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

# What each key in an expectation is read from. Three of them look at the same
# .docx: "docx" reads the words, which is what a check about wording wants,
# "docx-xml" the markup of the document underneath, which is where a style a
# paragraph or a run is given lives, and "docx-styles" the stylesheet, which
# is where the style itself is defined.
# `squash` runs every stretch of whitespace together into one space, which the
# three readers that look at words want and the three that look at structure do
# not. A .pdf wraps a table cell over as many lines as it needs and pads the
# columns out with spaces, so a check for a phrase would otherwise have to know
# where the renderer happened to break it.
readers <- list(
  html     = list(ext = "html", how = "html", squash = TRUE),
  docx     = list(ext = "docx", how = "docx-text", squash = TRUE),
  "docx-xml" = list(ext = "docx", how = "docx-xml", squash = FALSE),
  "docx-styles" = list(ext = "docx", how = "docx-styles", squash = FALSE),
  pdf      = list(ext = "pdf",  how = "pdf", squash = TRUE),
  tex      = list(ext = "tex",  how = "plain", squash = FALSE),
  typ      = list(ext = "typ",  how = "plain", squash = FALSE),
  # Not a file the render leaves beside the fixture but what it said while
  # running, which is where a message meant for whoever asked for the render
  # belongs -- the notice about Word's page numbers is one.
  log      = list(ext = "log",  how = "plain", squash = TRUE),
  # Where the words of the .pdf sit on the page, rather than what they say:
  # see layout_failures() below.
  layout   = list(ext = "pdf",  how = "layout", squash = FALSE)
)

# Layout checks ---------------------------------------------------------------
#
# A layout check measures the rendered .pdf, from the position pdftools gives
# every word: the space between two lines, how far in a word starts, the size
# a word is set at. These are what a snapshot of the .tex or .typ cannot see.
# The source of a document can stay the same while what it sets changes under
# it -- Typst 0.12 moved the space between paragraphs from block to par, and
# every typst document lost its even spacing with not a character of its .typ
# different -- so the page itself is measured.
#
# Each check names a word by its text (a full stop or comma after it is
# allowed) and the first place it appears:
#
#   gap: [first, second]   baseline to baseline, in points, from the first
#                          word to the second, on the first word's page
#   left: word             how far the word's left edge is from the paper's
#                          left edge, in points
#   right: word            how far the right end of the line the word is on
#                          is from the paper's left edge, in points
#   size: word             the size of the word's font, in points
#   is: number             what the measure should be
#   within: number         how far off it may be: 1 by default for gap and
#                          left, since pdftools gives positions to the whole
#                          point, and 0.2 for size
#
# A word is best made up for the fixture (Alphaone, Headtwo) so that it
# appears once and is easy to find.
layout_words <- function(path) {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop("the pdftools package is needed to measure a .pdf")
  }
  pages <- pdftools::pdf_data(path, font_info = TRUE)
  for (p in seq_along(pages)) pages[[p]]$page <- rep(p, nrow(pages[[p]]))
  words <- do.call(rbind, pages)
  words$bare <- sub("[.,:;]$", "", words$text)
  words$baseline <- words$y + words$height
  words
}

layout_failures <- function(path, checks) {
  words <- layout_words(path)
  find <- function(text, page = NULL) {
    hit <- words[words$bare == text, ]
    if (!is.null(page)) hit <- hit[hit$page == page, ]
    if (nrow(hit) == 0) return(NULL)
    hit[1, ]
  }
  failures <- character()
  for (check in checks) {
    if (!is.null(check$gap)) {
      label <- paste0("gap from ", check$gap[[1]], " to ", check$gap[[2]])
      first <- find(check$gap[[1]])
      second <- if (!is.null(first)) find(check$gap[[2]], first$page)
      actual <- if (!is.null(second)) second$baseline - first$baseline
      tolerance <- if (is.null(check$within)) 1 else check$within
    } else if (!is.null(check$left)) {
      label <- paste0("left edge of ", check$left)
      word <- find(check$left)
      actual <- if (!is.null(word)) word$x
      tolerance <- if (is.null(check$within)) 1 else check$within
    } else if (!is.null(check$right)) {
      # The right end of the line the word is on: its last word's right edge.
      label <- paste0("right end of the line with ", check$right)
      word <- find(check$right)
      actual <- if (!is.null(word)) {
        line <- words[words$page == word$page &
                        abs(words$baseline - word$baseline) < 1, ]
        max(line$x + line$width)
      }
      tolerance <- if (is.null(check$within)) 1 else check$within
    } else if (!is.null(check$size)) {
      label <- paste0("size of ", check$size)
      word <- find(check$size)
      actual <- if (!is.null(word)) word$font_size
      tolerance <- if (is.null(check$within)) 0.2 else check$within
    } else {
      failures <- c(failures, paste0("layout check names no measure (gap, ",
                                     "left, right or size): ",
                                     paste(names(check), collapse = ", ")))
      next
    }
    if (is.null(actual)) {
      failures <- c(failures, paste0("layout: could not find the words for ",
                                     label))
    } else if (abs(actual - check$is) > tolerance) {
      failures <- c(failures, sprintf("layout: %s is %gpt, expected %gpt (within %g)",
                                      label, round(actual, 2), check$is, tolerance))
    }
  }
  failures
}

# Everything a render might leave behind, for one fixture.
artifacts_of <- function(stem) {
  exts <- c("html", "docx", "pdf", "tex", "typ")
  paths <- file.path(tests_dir, paste0(stem, ".", exts))
  stats::setNames(paths, exts)
}

# One part of a .docx, as its xml. The stylesheet is a part of its own, and
# not one docx_xml reads, so a check about a style definition needs this.
docx_part <- function(path, part) {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  files <- utils::unzip(path, exdir = tmp)
  found <- grep(part, files, value = TRUE)
  if (length(found) == 0) return("")
  paste(readLines(found[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n")
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
    "docx-styles" = docx_part(path, "word/styles[.]xml$"),
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
  # The font list quarto writes into a .typ is resolved against the fonts
  # the machine has, not fixed by quarto: a document asking for Times New
  # Roman gets ("Times New Roman",) where that font exists, and
  # ("Times New Roman","Liberation Serif","Nimbus Roman",) on a linux box,
  # which substitutes the metric-compatible faces it does have. One quarto,
  # two machines, two answers -- the machine-specific noise the lines above
  # take out, and why every typst snapshot failed on CI while every latex
  # one passed.
  #
  # Only the list quarto generates, which it writes with a trailing comma
  # inside the parentheses. The template's own default, font: ("Times",
  # "Times New Roman"), has none there and is apaquarto's to get right, so
  # a change to it still shows. The leading class keeps monofont: out.
  text <- gsub("(^|[^[:alnum:]_-])font: \\([^)]*,\\)",
               "\\1font: (<fonts>)", text)
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

# docxreferencedoc.lua patches the reference document in place -- pandoc reads
# it when it writes the output, so there is nowhere else to put the fonts, the
# page size and the line numbering. A render with numbered-lines: true
# therefore leaves <w:lnNumType> in _extensions/apaquarto/apaquarto.docx, and
# the marker recording what was there before it. The next render restores the
# shipped state, so the file is only ever wrong in between -- but that window
# is long enough to git add it, which is how it reached a37f8de and cdb162b
# before it. A commit carrying one of those markers would ship line numbers to
# every docx that does not ask for them.
check_reference_doc <- function() {
  refdoc <- file.path(root_dir, "_extensions", "apaquarto", "apaquarto.docx")
  if (!file.exists(refdoc)) return(invisible())
  tmp <- tempfile()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  # Two parts of the reference document are written into by a render and put
  # back by the next one: the section properties, which carry the page size,
  # the margins and the line numbering, and the stylesheet, which carries the
  # link colours. Each leaves a marker behind while it is patched, and a
  # marker in the committed file means a render's leavings were committed
  # with it.
  parts <- c("word/document.xml", "word/styles.xml")
  markers <- c("apaquarto-original-", "apaquarto-link-styles")
  for (part in parts) {
    xml <- tryCatch(
      readLines(unzip(refdoc, part, exdir = tmp), warn = FALSE),
      error = function(e) character()
    )
    for (marker in markers) {
      if (any(grepl(marker, xml, fixed = TRUE))) {
        stop("_extensions/apaquarto/apaquarto.docx was committed mid-patch: ",
             part, " still carries a ", marker, " marker left by a docx ",
             "render. Render any document to docx, with no colour fields and ",
             "no numbered-lines and not in thesis mode, to restore it, then ",
             "commit that.")
      }
    }
  }
  invisible()
}

if (is.null(opt_worker)) {
  check_reference_doc()
  sync_extensions()
}
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

# ----------------------------------------------------------------- progress --
# How far the run has got, printed after every job: a bar, the jobs done out
# of all of them, how many passed and failed, and a guess at the time left
# from the average so far. Written as a line of its own rather than redrawn
# in place, so that it reads the same in a log as in a terminal.
total_jobs <- length(jobs)
done_jobs <- 0
passed_jobs <- 0
failed_jobs <- 0
known_jobs <- 0
run_started <- Sys.time()

duration <- function(seconds) {
  seconds <- round(seconds)
  if (seconds < 60) return(paste0(seconds, " s"))
  paste0(seconds %/% 60, " min ", seconds %% 60, " s")
}

progress <- function(id) {
  done_jobs <<- done_jobs + 1
  if (any(startsWith(failures, paste0(id, ":")))) {
    failed_jobs <<- failed_jobs + 1
  } else if (any(startsWith(known, paste0(id, ":")))) {
    known_jobs <<- known_jobs + 1
  } else {
    passed_jobs <<- passed_jobs + 1
  }
  width <- 30
  filled <- round(width * done_jobs / total_jobs)
  elapsed <- as.numeric(difftime(Sys.time(), run_started, units = "secs"))
  left <- elapsed / done_jobs * (total_jobs - done_jobs)
  say("  [", strrep("#", filled), strrep("-", width - filled), "] ",
      done_jobs, "/", total_jobs, " done: ", passed_jobs, " passed, ",
      failed_jobs, " failed",
      if (known_jobs > 0) paste0(", ", known_jobs, " known") else "",
      if (done_jobs < total_jobs) paste0(", about ", duration(left), " left")
      else paste0(", in ", duration(elapsed)))
}

# One job: the render and every check on what it made. Its failures go
# through note_failure, and what it has to say through say.
run_job <- function(job) {
  id <- job_id(job)
  stem <- tools::file_path_sans_ext(job$fixture)
  current_known <<- job$known_failure
  if (!is.null(current_known)) say("  known failure: ", current_known)

  # Anything a previous run left behind, so that a render that quietly produces
  # nothing cannot be read as a pass on the last run's output.
  unlink(unname(artifacts_of(stem)))

  # unlink() reports nothing useful on windows, where a file another process
  # holds open -- a sync client, a virus scanner, a pdf viewer -- simply stays.
  # A survivor is worse than a missing file: the fixtures that share a stem
  # across formats would hand the next job the last one's output, and a
  # apaquarto-latex-pdf job was checked against a .typ that its sibling typst
  # job had written and against a snapshot of the same accident.
  stuck <- artifacts_of(stem)
  stuck <- stuck[file.exists(stuck)]
  if (length(stuck)) {
    note_failure(id, paste0("could not clear ", paste(names(stuck), collapse = ", "),
                            " left by an earlier render; another process is ",
                            "holding it open"))
    return(invisible())
  }

  # docxreferencedoc.lua rewrites _extensions/apaquarto/apaquarto.docx in
  # place, and every worker renders against the same copy, so two docx renders
  # at once could each read the other's half-written zip. Pandoc then stopped
  # with "error, called at ... Data.Binary.Get", one docx job in every few
  # runs. Each docx render begins by putting the reference document into the
  # state its own document needs, so docx renders are safe one at a time and
  # are taken in turn; every other format still runs alongside them. The turn
  # is a directory, which only one process can create, as a claim is.
  docx_lock <- if (!is.null(opt_worker) && grepl("docx", job$to, fixed = TRUE)) {
    file.path(opt_worker, "docx.lock")
  }
  take_docx_turn <- function() {
    if (is.null(docx_lock)) return(invisible())
    while (!dir.create(docx_lock, showWarnings = FALSE)) Sys.sleep(0.1)
  }
  end_docx_turn <- function() {
    if (!is.null(docx_lock)) unlink(docx_lock, recursive = TRUE)
  }

  render <- function() {
    take_docx_turn()
    on.exit(end_docx_turn(), add = TRUE)
    system2(
      quarto_bin(),
      # Not quoted: system2 passes each element as one argument, and a shell
      # quote of its own is taken literally by cmd.exe on windows.
      c("render", job$fixture, "--to", job$to,
        "-M", "keep-tex:true", "-M", "keep-typ:true"),
      stdout = TRUE, stderr = TRUE
    )
  }
  rendered <- render()
  status <- attr(rendered, "status")
  # A sync client such as Dropbox holds a file for a moment after it changes,
  # and quarto, clearing out a folder it made, stops at the first file it
  # cannot remove: "The process cannot access the file because it is being
  # used by another process (os error 32)". Nothing in the document is wrong,
  # so the render is given one more go.
  if (!is.null(status) && status != 0 &&
      any(grepl("os error 32", rendered, fixed = TRUE))) {
    Sys.sleep(3)
    rendered <- render()
    status <- attr(rendered, "status")
  }
  log_file <- file.path(results_dir, paste0(id, ".log"))
  writeLines(rendered, log_file)

  if (!is.null(status) && status != 0) {
    note_failure(id, paste0("render failed (exit ", status, "); see ",
                            basename(log_file)))
    return(invisible())
  }

  produced <- artifacts_of(stem)
  produced <- produced[file.exists(produced)]
  if (length(produced) == 0) {
    note_failure(id, "render produced no output")
    return(invisible())
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
    path <- if (ext == "log") log_file else artifacts_of(stem)[[ext]]
    if (!file.exists(path)) {
      note_failure(id, paste0("expected a .", ext, " and there is none"))
      next
    }
    if (reader$how == "layout") {
      for (failure in layout_failures(path, wanted)) note_failure(id, failure)
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
    # Each string after the one before it: a note under its figure and above
    # the link that follows both, say. Every string is looked for from where
    # the last one was found, so the check reads the document top to bottom.
    if (length(wanted$order) > 0) {
      from <- 1L
      for (needle in wanted$order) {
        rest <- substring(text, from)
        at <- regexpr(needle, rest, fixed = TRUE)
        if (at < 0) {
          note_failure(id, paste0(key, " is missing, in order: ", needle))
          break
        }
        from <- from + at + attr(at, "match.length") - 1L
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
      current_known <<- NULL
      note_failure(id, paste0("marked known_failure but every check passed; ",
                              "take the flag off"))
    }
  }
}

# The fixtures in the groups the workers take one at a time. A fixture's jobs
# stay together and run in order, since they write the same files -- a typst
# render and a .pdf render both leave a .pdf -- and so do fixtures that embed
# the same document, since quarto renders that document for each of them.
job_groups <- function(jobs) {
  groups <- list()
  for (i in seq_along(jobs)) {
    fixture <- jobs[[i]]$fixture
    key <- tools::file_path_sans_ext(fixture)
    text <- tryCatch(readLines(file.path(tests_dir, fixture), warn = FALSE),
                     error = function(e) character())
    embed <- regmatches(text, regexpr("\\{\\{<\\s*embed\\s+[^#\\s>]+", text,
                                      perl = TRUE))
    if (length(embed) > 0) {
      key <- paste0("embed-", tools::file_path_sans_ext(basename(
        sub("^\\{\\{<\\s*embed\\s+", "", embed[1], perl = TRUE))))
    }
    groups[[key]] <- c(groups[[key]], i)
  }
  groups
}

# ------------------------------------------------------------------ workers --
# A worker takes the next group no other worker has claimed -- a claim is a
# directory, which only one process can create -- runs its jobs, and leaves the
# result of each in done/ for the main process to pick up.
run_worker <- function(dir) {
  exit_file <- file.path(dir, paste0("exit-", opt_worker_id))
  on.exit(writeLines("done", exit_file), add = TRUE)
  groups <- job_groups(jobs)
  for (key in names(groups)) {
    if (!dir.create(file.path(dir, "claims", key), showWarnings = FALSE)) next
    for (i in groups[[key]]) {
      say_buffer <<- character(0)
      failures <<- character(0)
      known <<- character(0)
      tryCatch(run_job(jobs[[i]]), error = function(e) {
        note_failure(job_id(jobs[[i]]),
                     paste0("the runner stopped: ", conditionMessage(e)))
      })
      result <- list(index = i, id = job_id(jobs[[i]]), lines = say_buffer,
                     failures = failures, known = known)
      tmp <- file.path(dir, "done", paste0(i, ".tmp"))
      saveRDS(result, tmp)
      file.rename(tmp, file.path(dir, "done", paste0(i, ".rds")))
    }
  }
}

if (!is.null(opt_worker)) {
  run_worker(opt_worker)
  quit(status = 0)
}

say(total_jobs, " jobs to run", if (opt_jobs > 1) paste0(", ", opt_jobs,
    " at a time") else "")

previous_id <- NULL
if (opt_jobs <= 1) {
  for (job in jobs) {
    # The last job's line of progress, now that nothing more can go wrong in
    # it. It is written here rather than after run_job because a job can stop
    # partway.
    if (!is.null(previous_id)) progress(previous_id)
    id <- job_id(job)
    previous_id <- id
    say("")
    say("[", done_jobs + 1, "/", total_jobs, "] ", bold(id))
    run_job(job)
  }
} else {
  # The workers, each a copy of this script given the directory they share.
  # Their own output goes to a log each, which is where to look when one stops.
  work_dir <- file.path(results_dir, "_workers")
  unlink(work_dir, recursive = TRUE)
  dir.create(file.path(work_dir, "claims"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(work_dir, "done"), recursive = TRUE, showWarnings = FALSE)
  rscript <- file.path(R.home("bin"),
                       if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (.Platform$OS.type == "windows") rscript <- utils::shortPathName(rscript)
  passed_on <- args
  jobs_at <- match("--jobs", passed_on)
  if (!is.na(jobs_at)) passed_on <- passed_on[-c(jobs_at, jobs_at + 1)]
  workers <- min(opt_jobs, length(job_groups(jobs)))
  for (k in seq_len(workers)) {
    log <- file.path(work_dir, paste0("worker-", k, ".log"))
    system2(rscript, c(script_path, passed_on, "--worker", work_dir,
                       "--worker-id", k),
            wait = FALSE, stdout = log, stderr = log)
  }

  # Each job's report as it arrives, in the order the jobs finish.
  seen <- rep(FALSE, total_jobs)
  repeat {
    for (file in list.files(file.path(work_dir, "done"), "[.]rds$",
                            full.names = TRUE)) {
      result <- readRDS(file)
      if (seen[result$index]) next
      seen[result$index] <- TRUE
      say("")
      say("[", done_jobs + 1, "/", total_jobs, "] ", bold(result$id))
      for (line in result$lines) say(line)
      failures <- c(failures, result$failures)
      known <- c(known, result$known)
      progress(result$id)
    }
    if (all(seen)) break
    exits <- list.files(work_dir, "^exit-")
    if (length(exits) >= workers && !any(file.exists(
        file.path(work_dir, "done", paste0(which(!seen), ".rds"))))) {
      # Every worker has stopped and some jobs never reported: a worker died.
      for (i in which(!seen)) {
        failures <- c(failures, paste0(job_id(jobs[[i]]),
          ": no result; see the worker logs in ", work_dir))
      }
      break
    }
    Sys.sleep(1)
  }
  previous_id <- NULL
}

if (!is.null(previous_id)) progress(previous_id)

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

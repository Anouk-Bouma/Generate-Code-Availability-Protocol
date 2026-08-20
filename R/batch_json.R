# R/batch_json.R
#
# Shared logic for building the coder-facing batch JSON (papers + records)
# that gets uploaded at the index.html login screen. Matches the structure
# of pilot_batch.json — in particular, the "records" array is what fills in
# the protocol's metadata fields (meta_authors, meta_year, meta_journal, ...)
# for each paper; without it, a coder gets an empty metadata block to fill in
# by hand.
#
# Sourced by both 2_link_and_keyword_extraction.qmd's export chunk and
# generate_coder_batch.R, so the two never drift apart.

# "Last, First; Last, First" from one paper's author vector.
format_authors_string <- function(authors) {
  authors <- authors[!is.na(authors) & nzchar(authors)]
  if (length(authors) == 0) return("")
  paste(authors, collapse = "; ")
}

# Short citation label used for the sidebar and as papers[].title, e.g.
# "Minor (2026)", "Sass & Sanchez (2026)", "Li et al. (2026)".
format_short_label <- function(authors, year) {
  last_names <- trimws(sub(",.*$", "", authors))
  last_names <- last_names[!is.na(last_names) & nzchar(last_names)]
  who <- if (length(last_names) == 0) {
    "Unknown"
  } else if (length(last_names) == 1) {
    last_names[1]
  } else if (length(last_names) == 2) {
    paste(last_names[1], "&", last_names[2])
  } else {
    paste(last_names[1], "et al.")
  }
  sprintf("%s (%s)", who, if (is.na(year)) "n.d." else as.character(year))
}

# Builds and writes the batch JSON for a filtered data frame `df`, which must
# have columns: ID, title, authors (list-col — a character vector of "Last,
# First" per paper), year, journal, DOI. coder_id is optional and, if given,
# pre-fills the login screen's Coder ID field for whoever opens this batch.
write_batch_json <- function(df, path, coder_id = "") {
  papers <- lapply(seq_len(nrow(df)), function(i) {
    list(id = df$ID[i], title = format_short_label(df$authors[[i]], df$year[i]))
  })

  records <- lapply(seq_len(nrow(df)), function(i) {
    label <- format_short_label(df$authors[[i]], df$year[i])
    list(
      coder_id = coder_id,
      paper_id = df$ID[i],
      paper_title = label,
      meta_id = df$ID[i],
      meta_year = if (is.na(df$year[i])) "" else as.character(df$year[i]),
      meta_authors = format_authors_string(df$authors[[i]]),
      meta_title = df$title[i],
      meta_journal = if (is.na(df$journal[i])) "" else df$journal[i],
      meta_doi = df$DOI[i],
      meta_reproducer = "",
      meta_date = ""
    )
  })

  batch <- list(
    coder_id = coder_id,
    exported = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    papers = papers,
    records = records
  )

  jsonlite::write_json(batch, path, auto_unbox = TRUE, pretty = TRUE)
}

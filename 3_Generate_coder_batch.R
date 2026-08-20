# 3_Generate_coder_batch.R
#
# Assembles everything a coder needs for one batch of papers into a single
# self-contained folder (and a matching .zip): only the PDFs for that batch,
# the filtered links-and-keywords report, index.html, and the papers_batch.json
# to upload there.
#
# This is step 3 of the pipeline you actually run, in order:
#   1_pdf_to_XML.qmd, 2_link_and_keyword_extraction.qmd, then this script.
# R/report_template.qmd is NOT a step you run yourself — it's an internal
# template this script renders on your behalf (see the "Render" section
# below), which is why it isn't numbered alongside 1/2/3.
#
# Does NOT re-run script 1 (GROBID XML generation) or the bib-parsing / XML-
# parsing / keyword-extraction part of script 2 — those are assumed already
# done. This script only reads the already-merged auto_report_input_data.rds
# and packages a filtered subset of it.
#
# Run with the working directory set to the project root (same assumption as
# scripts 1-2).

library(dplyr)
library(jsonlite)
library(quarto)

source("R/batch_json.R")

project_root <- getwd()

# ── Edit these per batch ─────────────────────────────────────────────────────

coder_id  <- "coder01"

# Papers to include: an explicit ID vector. Use sprintf() for a contiguous
# range, or list specific IDs directly.
batch_ids <- sprintf("P%03d", 1:100)
# batch_ids <- c("P003", "P017", "P204")

pdf_path <- "Articles All Records/files"  # real (nested) PDF corpus — the one
                                           # thing here that's actually
                                           # machine/setup-dependent

# ── Internal wiring — shouldn't normally need to change ─────────────────────
# All fixed names coming from, or feeding into, the rest of the pipeline.

data_file   <- "auto_report_input_data.rds"          # script 2's merged output
report_qmd  <- "R/report_template.qmd"
index_file  <- "index.html"
batches_dir <- "Batches"

# ── Load and filter ──────────────────────────────────────────────────────────

if (!file.exists(data_file)) stop("Data file not found: ", data_file)
articles <- readRDS(data_file)

missing_ids <- setdiff(batch_ids, articles$ID)
if (length(missing_ids) > 0)
  warning("Requested IDs not found in ", data_file, ": ", paste(missing_ids, collapse = ", "))

batch <- articles %>% filter(ID %in% batch_ids)
if (nrow(batch) == 0) stop("None of the requested IDs were found in ", data_file)

message("Packaging ", nrow(batch), " of ", length(batch_ids), " requested papers for ", coder_id)

# ── Create output folder ─────────────────────────────────────────────────────

folder_name <- sprintf("%s_%s-%s", coder_id, batch$ID[1], batch$ID[nrow(batch)])
out_dir <- file.path(batches_dir, folder_name)
pdf_dir <- file.path(out_dir, "pdfs")
dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)

# ── Copy only the needed PDFs, flattened by doi_no_slash ────────────────────

pdf_files  <- list.files(pdf_path, pattern = "\\.pdf$", recursive = TRUE, full.names = TRUE)
pdf_lookup <- setNames(pdf_files, tools::file_path_sans_ext(basename(pdf_files)))

missing_pdfs <- character(0)
for (doi in batch$doi_no_slash) {
  src <- pdf_lookup[doi]
  if (is.na(src)) {
    missing_pdfs <- c(missing_pdfs, doi)
    next
  }
  file.copy(src, file.path(pdf_dir, paste0(doi, ".pdf")), overwrite = TRUE)
}
if (length(missing_pdfs) > 0)
  warning("No PDF found for these doi_no_slash values: ", paste(missing_pdfs, collapse = ", "))

message("Copied ", nrow(batch) - length(missing_pdfs), " of ", nrow(batch), " PDFs")

# ── Render the filtered report ───────────────────────────────────────────────
# batch_ids and pdf_link_dir are passed as Quarto params (see the template's
# YAML) so the report is filtered to this batch and its PDF links point at
# the flat pdfs/ folder above, instead of the template's default full-corpus
# behavior. execute_dir is set explicitly to the project root because
# report_qmd now lives in R/ — without it, the template's own relative paths
# (data_file, pdf_path) would resolve relative to R/ instead and fail.
#
# Note: execute_dir only affects where *code* runs, not where the *output
# file* lands — quarto always writes output_file next to the input .qmd
# (i.e. into R/), regardless of execute_dir. So the rendered file has to be
# looked up there before it can be copied into the batch folder.

tmp_report <- "_batch_render_tmp.html"
quarto_render(
  input = report_qmd,
  output_file = tmp_report,
  execute_dir = project_root,
  execute_params = list(batch_ids = batch$ID, pdf_link_dir = "pdfs")
)
rendered_path <- file.path(dirname(report_qmd), tmp_report)
file.copy(rendered_path, file.path(out_dir, "support_file.html"), overwrite = TRUE)
file.remove(rendered_path)

# ── Write the papers batch JSON (upload target for index.html) ──────────────
# Matches pilot_batch.json's structure: papers[] (short "Author (Year)"
# labels for the sidebar) plus records[] (pre-fills each paper's metadata
# fields in the protocol form — authors, year, journal, title, DOI).

write_batch_json(batch, file.path(out_dir, paste0("papers_batch_", coder_id, ".json")), coder_id = coder_id)

# ── Copy index.html ──────────────────────────────────────────────────────────

file.copy(index_file, file.path(out_dir, "index.html"), overwrite = TRUE)

# ── Zip it up ─────────────────────────────────────────────────────────────────
# Shells out to a zip executable rather than using the zip package's zip()/
# utils::zip() — both reliably segfault on OneDrive-synced folders on this
# machine (likely the NTFS security-descriptor metadata OneDrive attaches to
# synced files, which their bundled libzip binding chokes on). The plain
# zip.exe CLI (either on PATH, or the copy the zip package ships internally)
# handles the same folder without issue.

find_zip_exe <- function() {
  on_path <- Sys.which("zip")
  if (nzchar(on_path)) return(unname(on_path))
  bundled <- system.file("bin", "x64", "zip.exe", package = "zip")
  if (nzchar(bundled) && file.exists(bundled)) return(bundled)
  NA_character_
}

zip_exe  <- find_zip_exe()
zip_path <- file.path(batches_dir, paste0(folder_name, ".zip"))

if (is.na(zip_exe)) {
  warning("No zip executable found (checked PATH and the 'zip' package) — ",
          "skipping .zip creation. The folder at ", out_dir, " is still complete.")
  zip_path <- NA_character_
} else {
  old_wd <- setwd(batches_dir)
  on.exit(setwd(old_wd), add = TRUE)
  zip_status <- system2(zip_exe, args = c("-r", "-q",
    shQuote(paste0(folder_name, ".zip"), type = "cmd"),
    shQuote(folder_name, type = "cmd")))
  setwd(old_wd)
  if (zip_status != 0) {
    warning("zip exited with status ", zip_status, " — check the folder at ", out_dir, " directly.")
    zip_path <- NA_character_
  }
}

# ── Summary ───────────────────────────────────────────────────────────────────

message("\nBatch ready for ", coder_id, ":")
message("  Folder: ", out_dir)
message("  Zip:    ", if (is.na(zip_path)) "(not created — see warning above)" else zip_path)
message("  Papers: ", nrow(batch), " / ", length(batch_ids), " requested")
if (length(missing_ids) > 0)  message("  Missing from data: ", paste(missing_ids, collapse = ", "))
if (length(missing_pdfs) > 0) message("  Missing PDFs:      ", paste(missing_pdfs, collapse = ", "))

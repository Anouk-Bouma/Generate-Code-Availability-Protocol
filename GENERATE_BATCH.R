# GENERATE_BATCH.R
#
# THIS IS THE ONLY SCRIPT YOU RUN to generate coder batches. Change the
# settings below, then run the whole script (in RStudio: open the .Rproj, then
# click "Source").
#
# It runs the pipeline steps in the pipeline/ folder in order, each with the
# settings from this file:
#   1. pipeline/1_pdf_to_XML.qmd                   PDFs -> TEI-XML via GROBID
#                                                   (only PDFs without an XML yet)
#   2. pipeline/2_link_and_keyword_extraction.qmd  XML + BibTeX -> one data file
#                                                   with paper IDs (P001, P002,
#                                                   ...), links and keyword matches
#   3. pipeline/3_Batch_Generation.R               one folder + .zip per coder in
#                                                   batches_dir, with the PDFs, the
#                                                   Links and Keywords Report,
#                                                   index.html, the printable
#                                                   instructions and the batch JSON
# You don't need to open, edit or run the scripts in pipeline/ or R/.

# ══ Settings ══════════════════════════════════════════════════════════════════

# ── Papers and input files ────────────────────────────────────────────────────

pdf_folder <- "Pilot3/files"   # folder with the PDFs (subfolders are searched too)
xml_folder <- "Pilot3"         # folder for the XML files (step 1 writes, step 2 reads)
bib_file   <- "Pilot3.bib"     # BibTeX export (e.g. from Zotero) with the papers' metadata

# Only keep the papers marked as included (column `included`) in an inclusion
# file? FALSE keeps every paper in the BibTeX file that has a DOI.
use_inclusion_file <- FALSE
inclusion_file     <- "all_articles.rds"   # needs columns doi_no_slash and included

# ── The batch ─────────────────────────────────────────────────────────────────

# One batch is made per coder, all with the same papers.
coder_ids <- c("CoderRvA")
# coder_ids <- c("CoderAB", "CoderLV", "CoderMvA", "CoderRvA")

# Papers in the batch, by ID. Use sprintf() for a range, or list IDs directly.
batch_ids <- sprintf("P%03d", 1:15)
# batch_ids <- c("P003", "P017", "P204")

# ── Which steps to run ────────────────────────────────────────────────────────

# Step 1 (PDF -> XML). Only converts PDFs without an XML in xml_folder, so it is
# quick when nothing is new. Needs the GROBID server below to be online.
run_pdf_to_xml <- TRUE

# Step 2 (build the data file). Note: paper IDs are assigned by position in the
# BibTeX file (and inclusion file). If you change those inputs after sending out
# batches, IDs can shift; set this to FALSE to keep the existing data file.
run_extraction <- TRUE

# ── Advanced (normally no need to change) ─────────────────────────────────────

grobid_url  <- "https://grobid.hti.ieis.tue.nl"  # other servers: https://www.scienceverse.org/metacheck/convert.json
data_file   <- "auto_report_input_data.rds"      # data file written by step 2, read by step 3
batches_dir <- "Batches"                         # where batch folders and .zip files are written

# ══ Run ═══════════════════════════════════════════════════════════════════════
# Nothing below needs editing.

if (!file.exists("index.html") || !file.exists("pipeline/3_Batch_Generation.R"))
  stop("Run this script with the project folder as working directory ",
       "(open Generate-Code-Availability-Protocol.Rproj in RStudio first).")

for (f in c(if (run_pdf_to_xml) pdf_folder, if (run_extraction) c(xml_folder, bib_file),
            if (run_extraction && use_inclusion_file) inclusion_file))
  if (!file.exists(f)) stop("Not found: ", f, " (check the settings at the top of GENERATE_BATCH.R)")

# Runs the R code of a Quarto (.qmd) script, as when running all its chunks
run_qmd <- function(path) {
  r_file <- knitr::purl(path, output = tempfile(fileext = ".R"), quiet = TRUE, documentation = 0)
  source(r_file, local = new.env(parent = globalenv()), echo = FALSE)
}

# The step scripts read their settings from `batch_settings`; it is removed
# again at the end, so running a step script on its own later uses its own
# defaults instead of stale settings from here.
batch_settings <- list(
  pdf_folder = pdf_folder, xml_folder = xml_folder, bib_file = bib_file,
  use_inclusion_file = use_inclusion_file, inclusion_file = inclusion_file,
  batch_ids = batch_ids, grobid_url = grobid_url, data_file = data_file,
  batches_dir = batches_dir
)

tryCatch({
  if (run_pdf_to_xml) {
    message("\n══ Step 1: PDF -> XML ══")
    run_qmd("pipeline/1_pdf_to_XML.qmd")
  }
  if (run_extraction) {
    message("\n══ Step 2: links and keyword extraction ══")
    run_qmd("pipeline/2_link_and_keyword_extraction.qmd")
  }
  if (!file.exists(data_file))
    stop("Data file not found: ", data_file, " (run step 2 by setting run_extraction <- TRUE)")

  for (coder in coder_ids) {
    message("\n══ Step 3: batch for ", coder, " ══")
    batch_settings$coder_id <- coder
    source("pipeline/3_Batch_Generation.R", local = new.env(parent = globalenv()), echo = FALSE)
  }
  message("\nDone: ", length(coder_ids), " batch(es) in ", normalizePath(batches_dir))
}, finally = rm(batch_settings, envir = globalenv()))

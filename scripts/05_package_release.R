#!/usr/bin/env Rscript
library(readr)
library(digest)
library(jsonlite)
source("R/project_utils.R")
audit <- read_json("validation/source_verification.json", simplifyVector = TRUE)
stopifnot(all(audit$checks$passed),
  all(vapply(names(audit$file_sha256), sha256_file, character(1)) == unlist(audit$file_sha256)))
dir.create("dist", showWarnings = FALSE)
make_zip <- function(path, files) {
  stopifnot(all(file.exists(files)))
  if (file.exists(path)) unlink(path)
  status <- utils::zip(path, files = sort(files), flags = "-q -X")
  stopifnot(status == 0, file.exists(path))
}
frozen <- read_csv("references/frozen_files.csv", show_col_types = FALSE)
stopifnot(all(vapply(frozen$path, sha256_file, character(1)) == frozen$sha256))
source_archive <- "dist/sources-vehicules-v1.0.0.zip"
make_zip(source_archive, frozen$path)
write_csv(data.frame(
  url = "https://github.com/AurelienNicosiaULaval/vehicules-quebec/releases/download/v1.0.0/sources-vehicules-v1.0.0.zip",
  bytes = file.info(source_archive)$size, sha256 = sha256_file(source_archive)),
  "references/release_sources.csv")

full_files <- c(list.files("data_clean", full.names = TRUE, pattern = "[.]csv$"),
                "data_intermediate/join_candidates.csv", "data_intermediate/unmatched_saaq.csv",
                "data_intermediate/join_summary.csv", "DATA_LICENSES.md", "references/frozen_files.csv",
                "validation/build_manifest.json")
full_archive <- "dist/donnees-completes-vehicules-v1.0.0.zip"
make_zip(full_archive, full_files)

portable_files <- c(
  "README.md", "NEWS.md", "LICENSE", "CITATION.cff", "DATA_LICENSES.md",
  "vehicules-quebec.Rproj", "_quarto.yml", "renv.lock", "data_dictionary.csv",
  list.files("R", full.names = TRUE, pattern = "[.]R$"),
  list.files("scripts", full.names = TRUE, pattern = "[.]R$"),
  list.files("tests", full.names = TRUE, pattern = "[.]R$"),
  list.files("examples", full.names = TRUE, pattern = "[.]R$"),
  list.files("config", full.names = TRUE),
  list.files("schemas", full.names = TRUE),
  list.files("references", full.names = TRUE, pattern = "[.](csv|md)$"),
  "references/catalogue_checks_20260907/saaq.json",
  "data_source/rncan_2025_snapshot.json",
  "data_clean/vehicules_canada_2025.csv", "data_clean/vehicules_canada_2025_dictionary.csv",
  "data_clean/vehicules_canada_2025_provenance.csv", "data_clean/parc_quebec_2022.csv",
  "data_clean/parc_quebec_2022_dictionary.csv", "data_clean/vehicules_quebec_small.csv",
  "data_clean/vehicules_quebec_dictionary.csv",
  "docs/explorer_les_vehicules.qmd", "docs/explorer_les_vehicules.html",
  "docs/validation_report.qmd", "docs/validation_report.html", "docs/reproduction.md",
  "validation/source_verification.json", "validation/teaching_manifest.json",
  "validation/release_checks.csv", "validation/portable_checks.csv",
  "validation/release_profile.csv", "validation/full_class_profile.csv",
  "validation/teaching_selection.csv", "validation/teaching_selection_summary.csv",
  "validation/cote_combinee_review.csv", "validation/saaq_scope_counts.csv",
  "validation/session_info.txt")
portable_files <- sort(unique(portable_files))
stopifnot(all(file.exists(portable_files)))
writeLines(paste(vapply(portable_files, sha256_file, character(1)), portable_files, sep = "  "),
           "checksums_repo.txt")
package <- "dist/vehicules-quebec-v1.0.0.zip"
make_zip(package, c(portable_files, "checksums_repo.txt"))
assets <- c(package, full_archive, source_archive,
            "docs/explorer_les_vehicules.html", "docs/validation_report.html")
writeLines(paste(vapply(assets, sha256_file, character(1)), basename(assets), sep = "  "),
           "dist/SHA256SUMS.txt")
cat("Trousse :", length(portable_files) + 1L, "fichiers;", file.info(package)$size, "octets.\n")

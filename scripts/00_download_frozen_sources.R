#!/usr/bin/env Rscript
library(readr)
library(digest)
source("R/project_utils.R")
manifest <- read_csv("references/frozen_files.csv", show_col_types = FALSE)
existing <- file.exists(manifest$path)
if (any(existing) && any(vapply(manifest$path[existing], sha256_file, character(1)) != manifest$sha256[existing])) {
  stop("Un fichier brut existant diffère de la version figée; aucun remplacement automatique.")
}
if (!all(existing)) {
  release <- read_csv("references/release_sources.csv", show_col_types = FALSE)
  archive <- tempfile(fileext = ".zip")
  download.file(release$url[[1]], archive, method = "curl", mode = "wb",
                extra = "--fail --location --retry 2")
  if (!identical(sha256_file(archive), release$sha256[[1]])) stop("Archive source non conforme.")
  files <- unzip(archive, list = TRUE)$Name
  if (any(grepl("^/|(^|/)\\.\\.(/|$)", files))) stop("Chemin inattendu dans l'archive.")
  if (!setequal(files, manifest$path)) stop("Contenu inattendu dans l'archive source.")
  unzip(archive, files = manifest$path[!existing], exdir = ".")
  unlink(archive)
}
stopifnot(all(vapply(manifest$path, sha256_file, character(1)) == manifest$sha256))
cat("Sources figées présentes et vérifiées.\n")

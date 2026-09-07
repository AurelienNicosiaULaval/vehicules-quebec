library(readr)
library(dplyr)
library(tibble)
library(jsonlite)
source("R/project_utils.R")
source("R/normalize_vehicle_text.R")
source("R/clean_rncan.R")
stopifnot(identical(classify_vehicle_class(c("Camionnette : petite", "Véhicule utilitaire sport", "Familiale : petite", "Sous-compacte")),
                    c("pickup", "suv", "wagon", "passenger_car")))
stopifnot(identical(decode_transmission_type(c("AM8", "M6", "AV7")),
                    c("automated_manual", "manual", "continuously_variable")))
stopifnot(classify_powertrain("rncan_standard", "regular_gasoline", "Modèle Hybride") == "HEV_text_derived")
expect_failure <- function(expr, pattern) {
  error <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
fixture <- tempfile("rncan-pages-")
dir.create(fixture)
page <- file.path(fixture, "page_000000000.json")
write_json(list(success = TRUE, result = list(records = data.frame(`_id` = c(1L, 1L), value = c("a", "b"), check.names = FALSE))),
           page, auto_unbox = TRUE)
write_json(list(resource_id = "test", total_records_reported = 2L,
                page_files = basename(page), page_sha256 = sha256_file(page)),
           file.path(fixture, "collection_metadata.json"), auto_unbox = TRUE)
expect_failure(read_ckan_pages(fixture, "test"), "dupliqués")
cat("\n", file = page, append = TRUE)
expect_failure(read_ckan_pages(fixture, "test"), "Empreinte")
unlink(fixture, recursive = TRUE)
stopifnot(identical(parse_kwh_per_100km_annotation(c("2.5 (22.3 kWh/100 km)", "5.1 ([45.4 kWh + 0.0 L]/100 km)")), c(22.3, 45.4)))
stopifnot(identical(parse_blended_l_per_100km_annotation(c("2.5 (22.3 kWh/100 km)", "5.1 ([45.4 kWh + 0.0 L]/100 km)")), c(NA_real_, 0)))
cat("7 contrats de transformation vérifiés.\n")

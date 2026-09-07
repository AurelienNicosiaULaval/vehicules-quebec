#!/usr/bin/env Rscript
# Mode portable : contrôle du petit jeu directement contre le JSON RNCan livré.
# --from-source ajoute le rapprochement du parc avec les lignes brutes SAAQ.
library(readr)
library(dplyr)
library(tibble)
library(jsonlite)
library(digest)
source("R/project_utils.R")
from_source <- "--from-source" %in% commandArgs(trailingOnly = TRUE)
checks <- list()
check <- function(name, value) {
  ok <- isTRUE(value)
  checks[[length(checks) + 1L]] <<- tibble(check = name, passed = ok)
  if (!ok) stop("Échec : ", name, call. = FALSE)
}
same <- function(a, b) isTRUE(all.equal(a, b, check.attributes = FALSE, tolerance = 1e-10))
x <- read_csv("data_clean/vehicules_canada_2025.csv", show_col_types = FALSE,
              col_types = cols(.default = col_guess(), vehicle_id = col_character()))
dictionary <- read_csv("data_clean/vehicules_canada_2025_dictionary.csv", show_col_types = FALSE)
provenance <- read_csv("data_clean/vehicules_canada_2025_provenance.csv",
                      col_types = cols(.default = col_character()), show_col_types = FALSE)
raw <- read_json("data_source/rncan_2025_snapshot.json", simplifyVector = TRUE)$result$records
manifest <- read_json("validation/teaching_manifest.json", simplifyVector = TRUE)
check("64 configurations, 19 variables", identical(dim(x), c(64L, 19L)))
check("Aucune valeur manquante dans le jeu principal", !anyNA(x))
check("Identifiants uniques", !anyDuplicated(x$vehicle_id))
check("Un modèle nommé par marque", !anyDuplicated(paste(x$make, x$model)))
check("Une seule année modèle : 2025", all(x$model_year == 2025))
check("Deux carburants essence documentés", all(x$fuel_type %in% c("regular_gasoline", "premium_gasoline")))
check("Dictionnaire aligné sur les colonnes", identical(dictionary$variable, names(x)))
check("Empreinte du petit jeu", identical(sha256_file("data_clean/vehicules_canada_2025.csv"), manifest$small_sha256))
check("Empreinte du JSON source", identical(sha256_file("data_source/rncan_2025_snapshot.json"), manifest$rncan_source_sha256))
check("693 lignes source avec identifiants uniques", nrow(raw) == 693L && !anyDuplicated(raw$`_id`))
check("Provenance dans le même ordre", identical(provenance$vehicle_id, x$vehicle_id))
source_row <- raw[match(provenance$rncan_source_row_id, as.character(raw$`_id`)), ]
check("64 lignes retrouvées dans la source", nrow(source_row) == 64L && !anyNA(source_row$`_id`))
mapping <- c(make = "Make", model = "Model", model_year = "Model year",
  vehicle_class = "Vehicle class", engine_size_l = "Engine size (L)",
  cylinders = "Cylinders", transmission = "Transmission",
  city_l_per_100km = "City (L/100 km)", highway_l_per_100km = "Highway (L/100 km)",
  combined_l_per_100km = "Combined (L/100 km)",
  combined_mpg_imperial = "Combined (mpg)", co2_g_per_km = "CO2 emissions (g/km)",
  co2_rating = "CO2 rating", smog_rating = "Smog rating")
for (variable in names(mapping)) {
  expected <- source_row[[mapping[[variable]]]]
  if (is.numeric(x[[variable]])) expected <- as.numeric(expected)
  check(paste("Concordance source :", variable), same(x[[variable]], expected))
}
expected_fuel <- unname(c(X = "regular_gasoline", Z = "premium_gasoline")[source_row$`Fuel type`])
check("Décodage du carburant source", identical(x$fuel_type, expected_fuel))
class_map <- read_csv("references/rncan_vehicle_classes.csv", col_types = "ccc", show_col_types = FALSE)
check("Correspondance des classes", identical(x$vehicle_class_group,
  class_map$vehicle_class_group[match(x$vehicle_class, class_map$source_label)]))
check("Conversion en gallon américain", same(x$combined_mpg_us,
  round((100 * 3.785411784 / 1.609344) / x$combined_l_per_100km, 4)))
combined_review <- x |>
  mutate(weighted_from_published = 0.55 * city_l_per_100km + 0.45 * highway_l_per_100km,
         difference = combined_l_per_100km - weighted_from_published) |>
  filter(abs(difference) > 0.10000001) |>
  select(vehicle_id, make, model, city_l_per_100km, highway_l_per_100km,
         combined_l_per_100km, weighted_from_published, difference)
write_csv(combined_review, "validation/cote_combinee_review.csv")
check("Écart ville-route connu et conservé tel que publié",
      nrow(combined_review) == 1L && combined_review$make == "Ford" &&
        combined_review$model == "Maverick Hybrid" &&
        same(combined_review$difference, 0.105))
check("Bornes positives et cotes ordinales", all(x$engine_size_l > 0 & x$cylinders > 0 &
  x$combined_l_per_100km > 0 & x$co2_g_per_km > 0 & x$co2_rating %in% 1:10 & x$smog_rating %in% 1:10))
qc <- read_csv("data_clean/parc_quebec_2022.csv", show_col_types = FALSE,
  col_types = cols(.default = col_guess(), region_qc = col_character(), saaq_fuel_code = col_character()))
check("Empreinte du parc québécois", identical(sha256_file("data_clean/parc_quebec_2022.csv"), manifest$qc_sha256))
check("Grain région-carburant unique", !anyDuplicated(qc[c("saaq_snapshot_year", "region_qc", "saaq_fuel_code")]))
check("Comptes entiers positifs en 2022", all(qc$number_registered_qc > 0 &
  qc$number_registered_qc == round(qc$number_registered_qc) & qc$saaq_snapshot_year == 2022))
check("Aucun compte québécois attribué au jeu canadien", !"number_registered_qc" %in% names(x))
selection <- read_csv("validation/teaching_selection_summary.csv", show_col_types = FALSE)
check("Bilan de sélection complet", sum(selection$n) == 30811L &&
  selection$n[selection$reason == "retained"] == nrow(x))

bound_files <- c("data_clean/vehicules_canada_2025.csv",
  "data_clean/vehicules_canada_2025_dictionary.csv",
  "data_clean/vehicules_canada_2025_provenance.csv",
  "data_clean/parc_quebec_2022.csv", "data_clean/parc_quebec_2022_dictionary.csv",
  "data_source/rncan_2025_snapshot.json", "references/rncan_vehicle_classes.csv",
  "references/saaq_fuel_codes.csv")
if (from_source) {
  library(data.table)
  frozen <- read_csv("references/frozen_files.csv", show_col_types = FALSE)
  check("Empreintes de tous les fichiers bruts",
        all(vapply(frozen$path, sha256_file, character(1)) == frozen$sha256))
  saaq_path <- frozen$path[grepl("Vehicule_En_Circulation_2022.csv$", frozen$path)]
  saaq <- fread(saaq_path, select = c("AN", "NOSEQ_VEH", "CLAS", "TYP_VEH_CATEG_USA", "REG_ADM", "TYP_CARBU"),
                 colClasses = "character", na.strings = c("", "NA"), showProgress = FALSE)
  check("Identifiants SAAQ uniques et complets", !anyNA(saaq$NOSEQ_VEH) && !anyDuplicated(saaq$NOSEQ_VEH))
  check("Année SAAQ brute conforme", all(saaq$AN == "2022"))
  selected_saaq <- saaq[TYP_VEH_CATEG_USA == "AU" & CLAS %in% c("PAU", "CAU", "RAU")]
  counts <- selected_saaq[, .(n_source = .N), by = c("REG_ADM", "TYP_CARBU")]
  compared <- full_join(qc, as_tibble(counts),
    by = c("region_qc" = "REG_ADM", "saaq_fuel_code" = "TYP_CARBU"), na_matches = "na")
  check("Chaque compte régional correspond aux véhicules bruts",
    nrow(compared) == nrow(qc) && !anyNA(compared$number_registered_qc) &&
      !anyNA(compared$n_source) && all(compared$number_registered_qc == compared$n_source))
  check("Comptes du périmètre SAAQ conservés", sum(qc$number_registered_qc) == nrow(selected_saaq))
  full <- read_csv("data_clean/vehicules_quebec.csv", show_col_types = FALSE)
  check("30 811 configurations dans les sources figées", nrow(full) == 30811L)
  check("Configurations complètes sans identifiants dupliqués", !anyNA(full$vehicle_id) && !anyDuplicated(full$vehicle_id))
  check("Aucune jointure Québec prétendue", all(is.na(full$number_registered_qc)) &&
    all(full$qc_presence_status == "unconfirmed"))
  check("Unités des véhicules électriques séparées", all(is.na(full$combined_l_per_100km[full$rncan_source_family == "rncan_bev"])))
  phev <- full |> filter(rncan_source_family == "rncan_phev")
  check("Consommation électrique disponible pour les 400 PHEV", nrow(phev) == 400L && !anyNA(phev$combined_kwh_per_100km))
  check("361 composantes liquides PHEV explicitement publiées", sum(!is.na(phev$blended_l_per_100km)) == 361L && all(phev$blended_l_per_100km >= 0, na.rm = TRUE))
  check("Aucune classe non reconnue", !anyNA(full$vehicle_class_group) && !any(full$vehicle_class_group == "other"))
  suspect <- read_csv("validation/suspect_rows.csv", show_col_types = FALSE)
  check("Aucune anomalie dans les contrôles numériques définis", nrow(suspect) == 0L)
  profile <- tibble(metric = c("rncan_rows", "rncan_makes", "rncan_min_year", "rncan_max_year",
    "qc_confirmed_configurations", "saaq_raw_rows", "saaq_scope_rows", "saaq_scope_missing_region", "core_rows", "core_columns"),
    value = c(nrow(full), n_distinct(full$make), min(full$model_year), max(full$model_year), 0,
      nrow(saaq), nrow(selected_saaq), sum(is.na(selected_saaq$REG_ADM)), nrow(x), ncol(x)))
  write_csv(profile, "validation/release_profile.csv")
  write_csv(full |> count(rncan_source_id, rncan_source_family, vehicle_class_group),
            "validation/full_class_profile.csv")
  audit <- list(version = "1.0.0", validated_on = as.character(Sys.Date()),
    checks = bind_rows(checks),
    file_sha256 = as.list(setNames(vapply(bound_files, sha256_file, character(1)), bound_files)),
    saaq_source_sha256 = sha256_file(saaq_path))
  write_json(audit, "validation/source_verification.json", pretty = TRUE, auto_unbox = TRUE)
  writeLines(capture.output(sessionInfo()), "validation/session_info.txt")
} else {
  audit <- read_json("validation/source_verification.json", simplifyVector = TRUE)
  check("Certificat des contrôles complets réussi", all(audit$checks$passed))
  check("Fichiers identiques à ceux de la validation complète",
    all(vapply(names(audit$file_sha256), sha256_file, character(1)) == unlist(audit$file_sha256)))
}
results <- bind_rows(checks)
write_csv(results, if (from_source) "validation/release_checks.csv" else "validation/portable_checks.csv")
cat(nrow(results), "contrôles réussis; mode", if (from_source) "sources brutes" else "portable", "\n")

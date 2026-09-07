#!/usr/bin/env Rscript

required_packages <- c(
  "fs", "readr", "readxl", "janitor", "stringr", "stringi", "dplyr",
  "tidyr", "purrr", "tibble", "arrow", "data.table", "yaml", "jsonlite",
  "digest", "cli"
)

source("R/project_utils.R")
assert_packages(required_packages)
source("R/normalize_vehicle_text.R")
source("R/clean_rncan.R")
source("R/clean_saaq.R")
source("R/join_vehicle_data.R")
source("R/sample_small.R")
source("R/validate_vehicle_data.R")

root <- project_root()
create_project_dirs(root)
args <- commandArgs(trailingOnly = TRUE)
overwrite_clean <- has_flag("--overwrite-clean", args)

source_config_path <- file.path(root, "config", "sources.yml")
project_config_path <- file.path(root, "config", "project.yml")
source_config <- yaml::read_yaml(source_config_path)
project_config <- yaml::read_yaml(project_config_path)
sources <- source_config$sources
release <- project_config$project$release %||% "0.1.0"

target_n <- as.integer(flag_value(
  "--small-n",
  default = as.character(project_config$cleaning$small_sample_target_n %||% 64L),
  args = args
))
if (is.na(target_n) || target_n < 1L) {
  stop("--small-n doit être un entier positif.", call. = FALSE)
}
strict_small <- isTRUE(project_config$cleaning$strict_small_sample_qc_only) ||
  has_flag("--strict-small-qc", args)

light_type_codes <- unlist(
  project_config$cleaning$saaq_light_vehicle_type_codes %||% "AU",
  use.names = FALSE
)
light_class_codes <- unlist(
  project_config$cleaning$saaq_light_vehicle_class_codes %||%
    c("PAU", "CAU", "RAU"),
  use.names = FALSE
)

cli::cli_h1("Construction de vehicules-quebec")
cli::cli_alert_info("Lecture et normalisation des ressources RNCan.")
rncan <- read_all_rncan(root, sources) |>
  dplyr::mutate(dataset_release = release, .after = vehicle_id)

saaq_source <- purrr::detect(sources, ~ identical(.x$id, "saaq_vehicles_2022"))
saaq_expected_filename <- if (is.null(saaq_source)) {
  NULL
} else {
  saaq_source$filename %||% NULL
}
saaq_expected_snapshot_year <- if (is.null(saaq_source)) {
  NULL
} else {
  saaq_source$snapshot_year %||% NULL
}

cli::cli_alert_info("Agrégation du fichier SAAQ; aucune ligne individuelle n'est publiée.")
saaq <- read_saaq_summaries(
  root,
  expected_filename = saaq_expected_filename,
  expected_snapshot_year = saaq_expected_snapshot_year,
  light_vehicle_type_codes = light_type_codes,
  light_vehicle_class_codes = light_class_codes
)

crosswalk <- read_verified_crosswalk(root)
if (nrow(crosswalk) == 0L) {
  cli::cli_alert_warning(
    "Aucune table saaq_make_model_crosswalk.csv vérifiée : les comptes québécois resteront manquants dans le fichier principal."
  )
}

saaq_source_url <- if (is.null(saaq_source)) {
  NA_character_
} else {
  saaq_source$resource_page %||% saaq_source$url %||% NA_character_
}

engine_tolerance <- project_config$cleaning$engine_size_tolerance_l %||% 0.11
derive_mpg <- isTRUE(project_config$cleaning$derive_missing_combined_mpg)
mpg_constant <- project_config$cleaning$imperial_mpg_constant %||% 282.48

cli::cli_alert_info("Application des règles de jointure auditées.")
joined <- join_saaq_rncan(
  rncan = rncan,
  saaq = saaq$global,
  crosswalk = crosswalk,
  saaq_source_url = saaq_source_url,
  engine_tolerance_l = engine_tolerance,
  derive_missing_mpg = derive_mpg,
  mpg_constant = mpg_constant
)

main <- joined$main |>
  dplyr::mutate(dataset_release = release, .after = vehicle_id) |>
  dplyr::relocate(
    dplyr::any_of(c(
      "vehicle_id", "dataset_release", "dataset_scope",
      "make", "model", "model_year", "vehicle_class", "vehicle_class_group",
      "vehicle_size_group", "fuel_type", "fuel_type_code_rncan",
      "fuel_type_code_rncan_2", "powertrain_group", "engine_size_l",
      "cylinders", "motor_kw", "transmission", "transmission_type",
      "transmission_gears", "drive_type", "drive_type_origin", "body_type",
      "body_type_origin", "city_l_per_100km", "highway_l_per_100km",
      "combined_l_per_100km", "combined_mpg_source", "combined_mpg",
      "combined_mpg_origin", "city_kwh_per_100km", "highway_kwh_per_100km",
      "combined_kwh_per_100km", "blended_l_per_100km", "city_le_per_100km", "highway_le_per_100km",
      "combined_le_per_100km", "electric_range_km", "secondary_range_km",
      "recharge_time_h", "co2_g_per_km", "co2_rating", "smog_rating",
      "number_registered_qc", "registration_count_grain", "region_qc",
      "saaq_snapshot_year", "saaq_class_code", "saaq_vehicle_type_code",
      "saaq_make_code", "saaq_model_code", "saaq_fuel_code",
      "saaq_mass_net_kg_mean", "saaq_mass_net_kg_min",
      "saaq_mass_net_kg_max", "saaq_group_count", "saaq_group_id",
      "join_method", "join_quality", "join_candidate_count",
      "qc_presence_status", "source_saaq", "source_rncan", "source_other",
      "rncan_source_family", "rncan_source_id", "rncan_resource_id",
      "rncan_source_row_id", "make_key", "model_key",
      "data_quality_flag", "notes"
    ))
  ) |>
  dplyr::arrange(.data$model_year, .data$make, .data$model, .data$vehicle_id)

small <- make_balanced_small_sample(
  main,
  target_n = target_n,
  strict_qc_only = strict_small
)
coverage <- small_sample_coverage(small)

rncan_specs <- add_combined_mpg(rncan, derive_mpg, mpg_constant) |>
  dplyr::mutate(dataset_release = release, .after = vehicle_id)

candidates <- joined$candidates
if (ncol(candidates) == 0L) {
  candidates <- tibble::tibble(
    saaq_group_id = character(),
    vehicle_id = character(),
    candidate_status = character(),
    candidate_is_admissible = logical(),
    admissible_candidate_count = integer(),
    all_candidate_count = integer(),
    number_registered_qc = integer(),
    note = character()
  )
}

unmatched <- joined$unmatched_saaq
if (ncol(unmatched) == 0L) {
  unmatched <- tibble::tibble(
    saaq_group_id = character(),
    unmatched_reason = character(),
    number_registered_qc = integer()
  )
}

missingness <- missingness_table(main)
suspects <- flag_suspect_rows(main, project_config)
validation <- validation_summary(main, candidates, unmatched)

dictionary_path <- file.path(root, "data_dictionary.csv")
if (!file.exists(dictionary_path)) {
  stop("Dictionnaire absent : ", dictionary_path, call. = FALSE)
}
dictionary <- readr::read_csv(
  dictionary_path, show_col_types = FALSE, progress = FALSE
)
undocumented_main <- setdiff(names(main), dictionary$variable)
undocumented_small <- setdiff(names(small), dictionary$variable)
if (length(c(undocumented_main, undocumented_small)) > 0L) {
  stop(
    "Variables non documentées dans data_dictionary.csv : ",
    paste(unique(c(undocumented_main, undocumented_small)), collapse = ", "),
    call. = FALSE
  )
}

output_paths <- c(
  file.path(root, "data_clean", "vehicules_quebec.csv"),
  file.path(root, "data_clean", "vehicules_quebec_small.csv"),
  file.path(root, "data_clean", "vehicules_quebec_dictionary.csv"),
  file.path(root, "data_clean", "rncan_vehicle_specs.csv"),
  file.path(root, "data_clean", "saaq_registration_summary.csv"),
  file.path(root, "data_clean", "saaq_registration_summary_by_region.csv"),
  file.path(root, "data_intermediate", "join_candidates.csv"),
  file.path(root, "data_intermediate", "unmatched_saaq.csv"),
  file.path(root, "data_intermediate", "join_summary.csv"),
  file.path(root, "validation", "validation_summary.csv"),
  file.path(root, "validation", "missingness.csv"),
  file.path(root, "validation", "suspect_rows.csv"),
  file.path(root, "validation", "small_sample_coverage.csv")
)
outputs <- stats::setNames(
  list(
    main, small, dictionary, rncan_specs, saaq$global, saaq$regional,
    candidates, unmatched, joined$summary, validation, missingness,
    suspects, coverage
  ),
  output_paths
)
manifest_path <- file.path(root, "validation", "build_manifest.json")

existing <- c(names(outputs), manifest_path)
existing <- existing[file.exists(existing)]
if (length(existing) > 0L && !overwrite_clean) {
  stop(
    "Sorties existantes détectées; aucun fichier n'a été remplacé :\n- ",
    paste(existing, collapse = "\n- "),
    "\nRelancez avec --overwrite-clean après vérification.",
    call. = FALSE
  )
}

purrr::iwalk(outputs, function(data, path) {
  write_csv_guarded(data, path, overwrite = overwrite_clean)
  cli::cli_alert_success("Écrit : {path}")
})

saaq_raw_sha256 <- if (!is.na(saaq$source_path) && file.exists(saaq$source_path)) {
  sha256_file(saaq$source_path)
} else {
  NA_character_
}
run_manifest <- list(
  generated_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  project_release = release,
  source_manifest_verified_on = source_config$verified_on,
  source_config_sha256 = sha256_file(source_config_path),
  project_config_sha256 = sha256_file(project_config_path),
  dictionary_sha256 = sha256_file(dictionary_path),
  collection_script_sha256 = sha256_file(
    file.path(root, "scripts", "01_collect_vehicle_sources.R")
  ),
  cleaning_script_sha256 = sha256_file(
    file.path(root, "scripts", "02_clean_vehicle_data.R")
  ),
  saaq_raw_path = if (is.na(saaq$source_path)) NA_character_ else as.character(fs::path_rel(saaq$source_path, root)),
  saaq_raw_sha256 = saaq_raw_sha256,
  verified_crosswalk_rows = nrow(crosswalk),
  small_sample_target_n = target_n,
  strict_small_sample_qc_only = strict_small,
  output_rows = list(
    vehicules_quebec = nrow(main),
    vehicules_quebec_small = nrow(small),
    rncan_vehicle_specs = nrow(rncan_specs),
    saaq_registration_summary = nrow(saaq$global),
    join_candidates = nrow(candidates),
    unmatched_saaq = nrow(unmatched),
    suspect_rows = nrow(suspects)
  ),
  output_sha256 = as.list(vapply(names(outputs), sha256_file, character(1))),
  session = utils::capture.output(sessionInfo())
)
names(run_manifest$output_sha256) <- basename(names(outputs))
write_json_guarded(
  run_manifest,
  manifest_path,
  overwrite = overwrite_clean
)

cli::cli_alert_info("Rapport : quarto render docs/validation_report.qmd")
cli::cli_alert_info(
  "Les valeurs manquantes et les cas ambigus ont été conservés; aucune imputation n'a été effectuée."
)

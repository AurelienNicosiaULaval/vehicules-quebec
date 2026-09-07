normalize_vehicle_text <- function(x) {
  x <- as.character(x)
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- stringr::str_to_upper(x, locale = "en")
  x <- stringr::str_replace_all(x, "&", " AND ")
  x <- stringr::str_replace_all(x, "[^A-Z0-9]+", " ")
  x <- stringr::str_squish(x)
  dplyr::na_if(x, "")
}

apply_make_aliases <- function(make_key, aliases_path) {
  if (!file.exists(aliases_path)) return(make_key)
  aliases <- readr::read_csv(aliases_path, show_col_types = FALSE, progress = FALSE)
  required <- c("source_value", "target_value", "authority", "source_url")
  missing <- setdiff(required, names(aliases))
  if (length(missing) > 0L) {
    stop(
      "Colonnes manquantes dans make_aliases.csv : ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (nrow(aliases) == 0L) return(make_key)

  aliases <- aliases |>
    dplyr::transmute(
      source_key = normalize_vehicle_text(.data$source_value),
      target_key = normalize_vehicle_text(.data$target_value),
      authority = dplyr::na_if(stringr::str_squish(as.character(.data$authority)), ""),
      source_url = dplyr::na_if(stringr::str_squish(as.character(.data$source_url)), "")
    ) |>
    dplyr::filter(
      !is.na(.data$source_key), !is.na(.data$target_key),
      !is.na(.data$authority), !is.na(.data$source_url)
    )

  conflicts <- aliases |>
    dplyr::group_by(.data$source_key) |>
    dplyr::summarise(
      n_targets = dplyr::n_distinct(.data$target_key),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n_targets > 1L)
  if (nrow(conflicts) > 0L) {
    stop(
      "Alias de marque contradictoires pour : ",
      paste(conflicts$source_key, collapse = ", "),
      call. = FALSE
    )
  }

  aliases <- aliases |>
    dplyr::distinct(.data$source_key, .data$target_key, .keep_all = TRUE)

  lookup <- stats::setNames(aliases$target_key, aliases$source_key)
  replacement <- unname(lookup[make_key])
  dplyr::coalesce(replacement, make_key)
}

normalize_make_key <- function(x, aliases_path = "references/make_aliases.csv") {
  apply_make_aliases(normalize_vehicle_text(x), aliases_path)
}

normalize_model_key <- function(x) {
  # Conserver les désignations de version, de rouage et de carrosserie.
  # Les retirer augmenterait artificiellement le taux de jointure.
  normalize_vehicle_text(x)
}

decode_rncan_fuel <- function(code) {
  code <- normalize_vehicle_text(code)
  dplyr::case_when(
    code == "X" ~ "regular_gasoline",
    code == "Z" ~ "premium_gasoline",
    code == "D" ~ "diesel",
    code == "E" ~ "e85",
    code == "B" ~ "electricity",
    code == "N" ~ "natural_gas",
    is.na(code) ~ NA_character_,
    TRUE ~ paste0("unknown_code_", code)
  )
}

decode_transmission_type <- function(transmission) {
  x <- normalize_vehicle_text(transmission)
  dplyr::case_when(
    stringr::str_detect(x, "^AM") ~ "automated_manual",
    stringr::str_detect(x, "^AS") ~ "automatic_select_shift",
    stringr::str_detect(x, "^AV") ~ "continuously_variable",
    stringr::str_detect(x, "^A") ~ "automatic",
    stringr::str_detect(x, "^M") ~ "manual",
    is.na(x) ~ NA_character_,
    TRUE ~ "unknown"
  )
}

extract_transmission_gears <- function(transmission) {
  x <- normalize_vehicle_text(transmission)
  suppressWarnings(as.integer(stringr::str_extract(x, "[0-9]+$")))
}

extract_drive_type <- function(model) {
  x <- normalize_vehicle_text(model)
  dplyr::case_when(
    stringr::str_detect(x, "(^| )AWD($| )") ~ "AWD",
    stringr::str_detect(x, "(^| )4WD($| )") ~ "4WD",
    stringr::str_detect(x, "(^| )4X4($| )") ~ "4X4",
    stringr::str_detect(x, "(^| )FWD($| )") ~ "FWD",
    stringr::str_detect(x, "(^| )RWD($| )") ~ "RWD",
    TRUE ~ NA_character_
  )
}

vehicle_class_lookup <- function(vehicle_class) {
  lookup <- readr::read_csv("references/rncan_vehicle_classes.csv",
                            show_col_types = FALSE, col_types = "ccc")
  lookup[match(vehicle_class, lookup$source_label), ]
}

classify_vehicle_class <- function(vehicle_class) {
  vehicle_class_lookup(vehicle_class)$vehicle_class_group
}

classify_vehicle_size <- function(vehicle_class) {
  vehicle_class_lookup(vehicle_class)$vehicle_size_group
}

classify_powertrain <- function(source_family, fuel_type, model) {
  model_key <- normalize_vehicle_text(model)
  dplyr::case_when(
    source_family == "rncan_bev" ~ "BEV",
    source_family == "rncan_phev" ~ "PHEV",
    stringr::str_detect(model_key, "(^| )(HYBRID|HYBRIDE|HEV)($| )") ~ "HEV_text_derived",
    fuel_type == "diesel" ~ "diesel",
    fuel_type %in% c("regular_gasoline", "premium_gasoline") ~ "gasoline",
    fuel_type == "e85" ~ "flex_fuel_e85",
    fuel_type == "natural_gas" ~ "natural_gas",
    fuel_type == "electricity" ~ "BEV",
    is.na(fuel_type) ~ "unknown",
    TRUE ~ "other"
  )
}

model_year_era <- function(model_year) {
  dplyr::case_when(
    is.na(model_year) ~ "unknown",
    model_year <= 2004 ~ "1995_2004",
    model_year <= 2014 ~ "2005_2014",
    model_year <= 2018 ~ "2015_2018",
    model_year <= 2022 ~ "2019_2022",
    TRUE ~ "2023_plus"
  )
}

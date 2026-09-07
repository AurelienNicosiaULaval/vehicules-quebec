pick_column <- function(data, candidates, default = NA_character_) {
  hit <- candidates[candidates %in% names(data)]
  if (length(hit) == 0L) return(rep(default, nrow(data)))
  data[[hit[[1L]]]]
}


has_any_column <- function(data, candidates) {
  any(candidates %in% names(data))
}

assert_rncan_source_schema <- function(data, source_family, source_id) {
  groups <- list(
    model_year = c("model_year", "year", "annee_modele", "annee_du_modele", "annee"),
    make = c("make", "manufacturer", "marque", "fabricant"),
    model = c("model", "modele"),
    vehicle_class = c(
      "vehicle_class", "class", "classe_de_vehicule", "classe_du_vehicule",
      "categorie_de_vehicule", "categorie_du_vehicule", "classe"
    )
  )

  family_groups <- switch(
    source_family,
    rncan_standard = list(
      engine_size_l = c("engine_size_l", "engine_size", "cylindree_l", "cylindree_du_moteur_l", "taille_du_moteur_l"),
      cylinders = c("cylinders", "number_of_cylinders", "nombre_de_cylindres", "cylindres"),
      transmission = c("transmission", "trans", "boite_de_vitesses", "boite_vitesses"),
      fuel_type = c("fuel_type", "type_de_carburant"),
      city_l_per_100km = c("city_l_100_km", "city_l_per_100_km", "ville_l_100_km", "ville_l_par_100_km"),
      highway_l_per_100km = c("highway_l_100_km", "hwy_l_100_km", "highway_l_per_100_km", "route_l_100_km", "autoroute_l_100_km"),
      combined_l_per_100km = c("combined_l_100_km", "comb_l_100_km", "combined_l_per_100_km", "combinee_l_100_km", "combine_l_100_km"),
      co2_g_per_km = c("co2_emissions_g_km", "co2_emission_g_km", "co2_g_km", "emissions_de_co2_g_km", "emission_de_co2_g_km")
    ),
    rncan_bev = list(
      motor_kw = c("motor_kw", "motor_k_w", "electric_motor_kw", "moteur_kw", "moteur_k_w"),
      transmission = c("transmission", "trans", "boite_de_vitesses", "boite_vitesses"),
      fuel_type = c("fuel_type", "fuel_type_1", "type_de_carburant", "type_de_carburant_1"),
      combined_kwh_per_100km = c("combined_kwh_100_km", "combined_k_wh_100_km", "comb_kwh_100_km", "combinee_kwh_100_km", "combinee_k_wh_100_km", "combine_kwh_100_km"),
      combined_le_per_100km = c("combined_le_100_km", "combined_l_e_100_km", "comb_le_100_km", "combinee_le_100_km", "combinee_l_e_100_km", "combine_le_100_km"),
      electric_range_km = c("range_km", "range_1_km", "electric_range_km", "autonomie_km", "autonomie_1_km", "autonomie_electrique_km"),
      recharge_time_h = c("recharge_time_h", "recharge_time_hours", "temps_de_recharge_h", "duree_de_recharge_h"),
      co2_g_per_km = c("co2_emissions_g_km", "co2_emission_g_km", "co2_g_km", "emissions_de_co2_g_km", "emission_de_co2_g_km")
    ),
    rncan_phev = list(
      motor_kw = c("motor_kw", "motor_k_w", "electric_motor_kw", "moteur_kw", "moteur_k_w"),
      engine_size_l = c("engine_size_l", "engine_size", "cylindree_l", "cylindree_du_moteur_l", "taille_du_moteur_l"),
      cylinders = c("cylinders", "number_of_cylinders", "nombre_de_cylindres", "cylindres"),
      transmission = c("transmission", "trans", "boite_de_vitesses", "boite_vitesses"),
      fuel_type_1 = c("fuel_type_1", "type_de_carburant_1"),
      combined_le_per_100km = c("combined_le_100_km", "combined_l_e_100_km", "comb_le_100_km", "combinee_le_100_km", "combinee_l_e_100_km", "combine_le_100_km"),
      range_1_km = c("range_1_km", "electric_range_km", "autonomie_1_km", "autonomie_electrique_km"),
      recharge_time_h = c("recharge_time_h", "recharge_time_hours", "temps_de_recharge_h", "duree_de_recharge_h"),
      fuel_type_2 = c("fuel_type_2", "type_de_carburant_2"),
      city_l_per_100km = c("city_l_100_km", "city_l_per_100_km", "ville_l_100_km", "ville_l_par_100_km"),
      highway_l_per_100km = c("highway_l_100_km", "hwy_l_100_km", "highway_l_per_100_km", "route_l_100_km", "autoroute_l_100_km"),
      combined_l_per_100km = c("combined_l_100_km", "comb_l_100_km", "combined_l_per_100_km", "combinee_l_100_km", "combine_l_100_km"),
      range_2_km = c("range_2_km", "autonomie_2_km"),
      co2_g_per_km = c("co2_emissions_g_km", "co2_emission_g_km", "co2_g_km", "emissions_de_co2_g_km", "emission_de_co2_g_km")
    ),
    list()
  )

  groups <- c(groups, family_groups)
  missing_groups <- names(groups)[!vapply(
    groups,
    function(candidates) has_any_column(data, candidates),
    logical(1)
  )]
  if (length(missing_groups) > 0L) {
    stop(
      "Schéma RNCan incomplet ou modifié pour ", source_id,
      " (", source_family, "). Groupes de champs absents : ",
      paste(missing_groups, collapse = ", "),
      ". Colonnes observées : ", paste(names(data), collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

read_ckan_pages <- function(version_dir, expected_resource_id = NULL) {
  metadata_path <- file.path(version_dir, "collection_metadata.json")
  if (!file.exists(metadata_path)) {
    stop(
      "Collecte RNCan incomplète (collection_metadata.json absent) : ",
      version_dir,
      call. = FALSE
    )
  }
  metadata <- jsonlite::fromJSON(metadata_path, simplifyVector = TRUE)
  if (!is.null(expected_resource_id) &&
      !identical(as.character(metadata$resource_id), as.character(expected_resource_id))) {
    stop(
      "La ressource RNCan collectée ne correspond pas au manifeste : ",
      version_dir,
      call. = FALSE
    )
  }

  pages <- fs::dir_ls(
    version_dir,
    regexp = "/page_[0-9]+[.]json$",
    type = "file",
    fail = FALSE
  )
  if (length(pages) == 0L) {
    stop("Aucune page CKAN trouvée dans : ", version_dir, call. = FALSE)
  }
  pages <- sort(pages)

  if (!identical(basename(pages), as.character(metadata$page_files)) ||
      !identical(unname(vapply(pages, sha256_file, character(1))),
                 as.character(metadata$page_sha256))) {
    stop("Empreinte des pages RNCan différente de la collecte : ", version_dir,
         call. = FALSE)
  }

  result <- purrr::map_dfr(pages, function(path) {
    object <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
    if (!isTRUE(object$success)) {
      stop("Réponse CKAN non réussie dans : ", path, call. = FALSE)
    }
    records <- object$result$records
    if (is.null(records) || length(records) == 0L) return(tibble::tibble())
    tibble::as_tibble(records) |>
      dplyr::mutate(
        raw_page_file = basename(path),
        raw_page_record_index = dplyr::row_number(),
        .before = 1
      )
  })

  expected_total <- suppressWarnings(as.integer(
    metadata$total_records_reported %||% NA_integer_
  ))
  if (!is.na(expected_total) && nrow(result) != expected_total) {
    stop(
      "Nombre de lignes RNCan incohérent : ", nrow(result),
      " lues, ", expected_total, " annoncées dans le manifeste de collecte.",
      call. = FALSE
    )
  }
  if (!"_id" %in% names(result) || anyNA(result$`_id`) ||
      anyDuplicated(result$`_id`)) {
    stop("Identifiants source RNCan absents ou dupliqués : ", version_dir,
         call. = FALSE)
  }
  result
}

normalise_rncan_resource <- function(raw, source) {
  if (nrow(raw) == 0L) return(tibble::tibble())
  data <- janitor::clean_names(raw)

  source_family <- source$source_family %||% NA_character_
  source_id <- source$id %||% NA_character_
  resource_id <- source$resource_id %||% NA_character_

  assert_rncan_source_schema(data, source_family, source_id)

  source_row_original <- as.character(pick_column(data, c("id", "record_id")))
  raw_page <- as.character(pick_column(data, c("raw_page_file")))
  raw_index <- safe_parse_integer(pick_column(data, c("raw_page_record_index")))
  fallback_locator <- dplyr::if_else(
    !is.na(raw_page) & !is.na(raw_index),
    paste0(raw_page, "#", raw_index),
    NA_character_
  )
  source_row <- dplyr::coalesce(
    dplyr::na_if(stringr::str_squish(source_row_original), ""),
    fallback_locator
  )

  model_year <- safe_parse_integer(pick_column(
    data,
    c("model_year", "year", "annee_modele", "annee_du_modele", "annee")
  ))
  make <- as.character(pick_column(data, c("make", "manufacturer", "marque", "fabricant")))
  model <- as.character(pick_column(data, c("model", "modele")))
  vehicle_class <- as.character(pick_column(
    data,
    c(
      "vehicle_class", "class", "classe_de_vehicule", "classe_du_vehicule",
      "categorie_de_vehicule", "categorie_du_vehicule", "classe"
    )
  ))

  if (all(is.na(model_year)) || all(is.na(make) | !nzchar(stringr::str_squish(make))) ||
      all(is.na(model) | !nzchar(stringr::str_squish(model)))) {
    stop(
      "Schéma RNCan non reconnu pour ", source_id,
      ". Colonnes observées : ", paste(names(data), collapse = ", "),
      call. = FALSE
    )
  }

  if (anyNA(classify_vehicle_class(vehicle_class))) {
    stop("Classe RNCan non documentée : ",
         paste(unique(vehicle_class[is.na(classify_vehicle_class(vehicle_class))]),
               collapse = ", "), call. = FALSE)
  }

  engine_size_l <- safe_parse_double(pick_column(
    data,
    c(
      "engine_size_l", "engine_size", "cylindree_l", "cylindree_du_moteur_l",
      "taille_du_moteur_l"
    )
  ))
  cylinders <- safe_parse_integer(pick_column(
    data,
    c("cylinders", "number_of_cylinders", "nombre_de_cylindres", "cylindres")
  ))
  motor_kw <- safe_parse_double(pick_column(
    data,
    c("motor_kw", "motor_k_w", "electric_motor_kw", "moteur_kw", "moteur_k_w")
  ))
  transmission <- as.character(pick_column(
    data,
    c("transmission", "trans", "boite_de_vitesses", "boite_vitesses")
  ))

  fuel_code_1 <- as.character(pick_column(
    data,
    c("fuel_type_1", "fuel_type", "type_de_carburant_1", "type_de_carburant")
  ))
  fuel_code_2 <- as.character(pick_column(
    data,
    c("fuel_type_2", "type_de_carburant_2")
  ))
  decoded_fuel <- decode_rncan_fuel(fuel_code_1)
  fuel_type <- if (identical(source_family, "rncan_bev")) {
    rep("electricity", length(decoded_fuel))
  } else if (identical(source_family, "rncan_phev")) {
    rep("plug_in_hybrid", length(decoded_fuel))
  } else {
    decoded_fuel
  }

  city_l <- safe_parse_double(pick_column(
    data,
    c("city_l_100_km", "city_l_per_100_km", "ville_l_100_km", "ville_l_par_100_km")
  ))
  highway_l <- safe_parse_double(pick_column(
    data,
    c(
      "highway_l_100_km", "hwy_l_100_km", "highway_l_per_100_km",
      "route_l_100_km", "autoroute_l_100_km"
    )
  ))
  combined_l <- safe_parse_double(pick_column(
    data,
    c(
      "combined_l_100_km", "comb_l_100_km", "combined_l_per_100_km",
      "combinee_l_100_km", "combine_l_100_km"
    )
  ))
  combined_mpg_source <- safe_parse_double(pick_column(
    data,
    c("combined_mpg", "comb_mpg", "combinee_mi_gal", "combine_mi_gal", "combined_mi_gal")
  ))

  city_kwh <- safe_parse_double(pick_column(
    data,
    c(
      "city_kwh_100_km", "city_k_wh_100_km", "city_kwh_per_100_km",
      "ville_kwh_100_km", "ville_k_wh_100_km"
    )
  ))
  highway_kwh <- safe_parse_double(pick_column(
    data,
    c(
      "highway_kwh_100_km", "highway_k_wh_100_km", "hwy_kwh_100_km",
      "route_kwh_100_km", "route_k_wh_100_km"
    )
  ))
  combined_kwh_direct <- safe_parse_double(pick_column(
    data,
    c(
      "combined_kwh_100_km", "combined_k_wh_100_km", "comb_kwh_100_km",
      "combinee_kwh_100_km", "combinee_k_wh_100_km", "combine_kwh_100_km"
    )
  ))

  city_le <- safe_parse_double(pick_column(
    data,
    c(
      "city_le_100_km", "city_l_e_100_km", "city_le_per_100_km",
      "ville_le_100_km", "ville_l_e_100_km"
    )
  ))
  highway_le <- safe_parse_double(pick_column(
    data,
    c(
      "highway_le_100_km", "highway_l_e_100_km", "hwy_le_100_km",
      "route_le_100_km", "route_l_e_100_km"
    )
  ))
  combined_electric_equivalent_raw <- pick_column(
    data,
    c(
      "combined_le_100_km", "combined_l_e_100_km", "comb_le_100_km",
      "combinee_le_100_km", "combinee_l_e_100_km", "combine_le_100_km"
    )
  )
  # Dans la ressource PHEV, la valeur peut être publiée sous la forme
  # « 2.5 (22.3 kWh/100 km) ». Les deux nombres sont observés dans la même
  # cellule source et sont extraits séparément, sans conversion d’unité.
  combined_le <- parse_annotated_first_double(combined_electric_equivalent_raw)
  combined_kwh <- dplyr::coalesce(
    combined_kwh_direct,
    parse_kwh_per_100km_annotation(combined_electric_equivalent_raw)
  )

  range_1 <- safe_parse_double(pick_column(
    data,
    c(
      "range_1_km", "range_km", "electric_range_km",
      "autonomie_1_km", "autonomie_km", "autonomie_electrique_km"
    )
  ))
  range_2 <- safe_parse_double(pick_column(data, c("range_2_km", "autonomie_2_km")))
  recharge_time <- safe_parse_double(pick_column(
    data,
    c(
      "recharge_time_h", "recharge_time_hours", "temps_de_recharge_h",
      "duree_de_recharge_h"
    )
  ))

  co2 <- safe_parse_double(pick_column(
    data,
    c(
      "co2_emissions_g_km", "co2_emission_g_km", "co2_g_km",
      "emissions_de_co2_g_km", "emission_de_co2_g_km"
    )
  ))
  co2_rating <- safe_parse_double(pick_column(
    data,
    c("co2_rating", "cote_co2", "cote_de_co2", "indice_de_co2")
  ))
  smog_rating <- safe_parse_double(pick_column(
    data,
    c("smog_rating", "cote_smog", "cote_de_smog", "indice_de_smog")
  ))

  make_key <- normalize_make_key(make)
  model_key <- normalize_model_key(model)
  drive_type <- extract_drive_type(model)
  vehicle_id <- stable_hash(
    source_id, source_row, source_family, model_year, make_key, model_key,
    vehicle_class, engine_size_l, cylinders, motor_kw, transmission,
    fuel_code_1, fuel_code_2, city_l, highway_l, combined_l,
    combined_mpg_source, city_kwh, highway_kwh, combined_kwh,
    city_le, highway_le, combined_le, range_1, range_2, recharge_time,
    co2, co2_rating, smog_rating,
    n = 24L
  )

  tibble::tibble(
    vehicle_id = paste0("vq_", vehicle_id),
    dataset_scope = "canadian_market_specification_with_quebec_linkage_status",
    make = dplyr::na_if(stringr::str_squish(make), ""),
    model = dplyr::na_if(stringr::str_squish(model), ""),
    model_year = model_year,
    vehicle_class = dplyr::na_if(stringr::str_squish(vehicle_class), ""),
    vehicle_class_group = classify_vehicle_class(vehicle_class),
    vehicle_size_group = classify_vehicle_size(vehicle_class),
    fuel_type = fuel_type,
    fuel_type_code_rncan = normalize_vehicle_text(fuel_code_1),
    fuel_type_code_rncan_2 = normalize_vehicle_text(fuel_code_2),
    powertrain_group = classify_powertrain(source_family, fuel_type, model),
    engine_size_l = engine_size_l,
    cylinders = cylinders,
    motor_kw = motor_kw,
    transmission = dplyr::na_if(stringr::str_squish(transmission), ""),
    transmission_type = decode_transmission_type(transmission),
    transmission_gears = extract_transmission_gears(transmission),
    drive_type = drive_type,
    drive_type_origin = dplyr::if_else(
      is.na(drive_type), NA_character_, "derived_from_explicit_model_token"
    ),
    city_l_per_100km = city_l,
    highway_l_per_100km = highway_l,
    combined_l_per_100km = combined_l,
    combined_mpg_source = combined_mpg_source,
    city_kwh_per_100km = city_kwh,
    highway_kwh_per_100km = highway_kwh,
    combined_kwh_per_100km = combined_kwh,
    blended_l_per_100km = parse_blended_l_per_100km_annotation(combined_electric_equivalent_raw),
    city_le_per_100km = city_le,
    highway_le_per_100km = highway_le,
    combined_le_per_100km = combined_le,
    electric_range_km = range_1,
    secondary_range_km = range_2,
    recharge_time_h = recharge_time,
    co2_g_per_km = co2,
    co2_rating = co2_rating,
    smog_rating = smog_rating,
    body_type = NA_character_,
    body_type_origin = "unknown_core_sources",
    make_key = make_key,
    model_key = model_key,
    rncan_source_family = source_family,
    rncan_source_id = source_id,
    rncan_resource_id = resource_id,
    rncan_source_row_id = source_row,
    source_rncan = source$resource_page %||% source$dataset_page %||% NA_character_,
    source_saaq = NA_character_,
    source_other = NA_character_
  )
}

read_all_rncan <- function(root, sources) {
  rncan_sources <- sources[vapply(
    sources,
    function(x) isTRUE(x$enabled) &&
      startsWith(x$source_family %||% "", "rncan_") &&
      identical(x$method, "ckan_datastore"),
    logical(1)
  )]

  if (length(rncan_sources) == 0L) {
    stop("Aucune source RNCan activée dans config/sources.yml.", call. = FALSE)
  }

  version_paths <- purrr::map_chr(rncan_sources, function(source) {
    path <- latest_version_dir(
      root, source$id, required_file = "collection_metadata.json"
    )
    if (is.null(path)) NA_character_ else path
  })
  missing_sources <- vapply(rncan_sources[is.na(version_paths)], `[[`, character(1), "id")
  if (length(missing_sources) > 0L) {
    stop(
      "Collectes RNCan complètes absentes : ",
      paste(missing_sources, collapse = ", "),
      ". Exécutez scripts/01_collect_vehicle_sources.R et corrigez tout échec avant le nettoyage.",
      call. = FALSE
    )
  }

  tables <- purrr::map2(rncan_sources, version_paths, function(source, version_dir) {
    raw <- read_ckan_pages(version_dir, expected_resource_id = source$resource_id)
    normalise_rncan_resource(raw, source)
  })

  result <- dplyr::bind_rows(tables) |>
    dplyr::arrange(.data$model_year, .data$make, .data$model, .data$vehicle_id)

  duplicate_ids <- result |>
    dplyr::count(.data$vehicle_id, name = "n") |>
    dplyr::filter(.data$n > 1L)
  if (nrow(duplicate_ids) > 0L) {
    stop(
      "Identifiants RNCan dupliqués après normalisation; vérifier les localisateurs de lignes brutes.",
      call. = FALSE
    )
  }
  result
}

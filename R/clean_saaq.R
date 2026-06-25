empty_saaq_summary <- function() {
  tibble::tibble(
    saaq_snapshot_year = integer(),
    saaq_class_code = character(),
    saaq_vehicle_type_code = character(),
    saaq_make_code = character(),
    saaq_model_code = character(),
    model_year = integer(),
    saaq_cylinders_code = character(),
    saaq_cylinders = integer(),
    saaq_engine_size_cm3 = double(),
    saaq_engine_size_l = double(),
    saaq_fuel_code = character(),
    saaq_fuel_type = character(),
    region_qc = character(),
    number_registered_qc = integer(),
    saaq_mass_net_kg_mean = double(),
    saaq_mass_net_kg_min = double(),
    saaq_mass_net_kg_max = double(),
    saaq_group_id = character(),
    is_light_vehicle_scope = logical()
  )
}

find_saaq_csv <- function(
    root,
    source_id = "saaq_vehicles_2022",
    expected_filename = NULL) {
  dirs <- version_dirs(root, source_id)
  if (length(dirs) == 0L) return(NULL)

  for (version_dir in dirs) {
    files <- fs::dir_ls(version_dir, glob = "*.csv", type = "file", fail = FALSE)
    files <- files[!grepl("collection_log", basename(files), ignore.case = TRUE)]

    if (!is.null(expected_filename) && !is.na(expected_filename)) {
      files <- files[basename(files) == expected_filename]
    } else if (length(files) > 1L) {
      stop(
        "Plusieurs CSV SAAQ sont présents sans nom de fichier épinglé : ",
        version_dir,
        call. = FALSE
      )
    }

    if (length(files) == 1L) return(files[[1L]])
    if (length(files) > 1L) {
      stop(
        "Plusieurs fichiers portent le nom SAAQ attendu dans : ",
        version_dir,
        call. = FALSE
      )
    }
  }
  NULL
}

saaq_arrow_aggregate <- function(dataset, by_region = FALSE, include_mass = TRUE) {
  if (by_region) {
    query <- dataset |>
      dplyr::select(
        AN, CLAS, TYP_VEH_CATEG_USA, MARQ_VEH, MODEL_VEH, ANNEE_MOD,
        MASSE_NETTE, NB_CYL, CYL_VEH, TYP_CARBU, REG_ADM
      ) |>
      dplyr::group_by(
        AN, CLAS, TYP_VEH_CATEG_USA, MARQ_VEH, MODEL_VEH, ANNEE_MOD,
        NB_CYL, CYL_VEH, TYP_CARBU, REG_ADM
      )
  } else {
    query <- dataset |>
      dplyr::select(
        AN, CLAS, TYP_VEH_CATEG_USA, MARQ_VEH, MODEL_VEH, ANNEE_MOD,
        MASSE_NETTE, NB_CYL, CYL_VEH, TYP_CARBU
      ) |>
      dplyr::group_by(
        AN, CLAS, TYP_VEH_CATEG_USA, MARQ_VEH, MODEL_VEH, ANNEE_MOD,
        NB_CYL, CYL_VEH, TYP_CARBU
      )
  }

  if (isTRUE(include_mass)) {
    query <- query |>
      dplyr::summarise(
        number_registered_qc = dplyr::n(),
        saaq_mass_net_kg_mean = mean(MASSE_NETTE, na.rm = TRUE),
        saaq_mass_net_kg_min = min(MASSE_NETTE, na.rm = TRUE),
        saaq_mass_net_kg_max = max(MASSE_NETTE, na.rm = TRUE)
      )
  } else {
    query <- query |>
      dplyr::summarise(number_registered_qc = dplyr::n())
  }

  dplyr::collect(query)
}

saaq_data_table_aggregates <- function(csv_path) {
  required <- c(
    "AN", "CLAS", "TYP_VEH_CATEG_USA", "MARQ_VEH", "MODEL_VEH",
    "ANNEE_MOD", "MASSE_NETTE", "NB_CYL", "CYL_VEH", "TYP_CARBU", "REG_ADM"
  )

  data <- data.table::fread(
    csv_path,
    select = required,
    na.strings = c("", "NA"),
    showProgress = TRUE
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop("Colonnes SAAQ manquantes : ", paste(missing, collapse = ", "), call. = FALSE)
  }

  data[, MASSE_NETTE := suppressWarnings(as.numeric(MASSE_NETTE))]

  global_cols <- c(
    "AN", "CLAS", "TYP_VEH_CATEG_USA", "MARQ_VEH", "MODEL_VEH",
    "ANNEE_MOD", "NB_CYL", "CYL_VEH", "TYP_CARBU"
  )
  regional_cols <- c(global_cols, "REG_ADM")

  aggregate_by <- function(columns) {
    out <- data[, .(
      number_registered_qc = .N,
      saaq_mass_net_kg_mean = mean(MASSE_NETTE, na.rm = TRUE),
      saaq_mass_net_kg_min = min(MASSE_NETTE, na.rm = TRUE),
      saaq_mass_net_kg_max = max(MASSE_NETTE, na.rm = TRUE)
    ), by = columns]
    mass_columns <- c(
      "saaq_mass_net_kg_mean",
      "saaq_mass_net_kg_min",
      "saaq_mass_net_kg_max"
    )
    for (column in mass_columns) {
      data.table::set(
        out,
        i = which(!is.finite(out[[column]])),
        j = column,
        value = NA_real_
      )
    }
    out
  }

  list(
    global_raw = aggregate_by(global_cols),
    regional_raw = aggregate_by(regional_cols)
  )
}

standardise_saaq_summary <- function(
    data,
    root,
    by_region = FALSE,
    light_vehicle_type_codes = "AU",
    light_vehicle_class_codes = c("PAU", "CAU", "RAU")) {

  fuel_codes <- readr::read_csv(
    file.path(root, "references", "saaq_fuel_codes.csv"),
    show_col_types = FALSE,
    progress = FALSE,
    na = character()
  ) |>
    dplyr::transmute(
      saaq_fuel_code = dplyr::na_if(stringr::str_squish(as.character(.data$code)), ""),
      saaq_fuel_type = .data$label_fr
    ) |>
    dplyr::distinct(.data$saaq_fuel_code, .keep_all = TRUE)

  if (!"saaq_mass_net_kg_mean" %in% names(data)) data$saaq_mass_net_kg_mean <- NA_real_
  if (!"saaq_mass_net_kg_min" %in% names(data)) data$saaq_mass_net_kg_min <- NA_real_
  if (!"saaq_mass_net_kg_max" %in% names(data)) data$saaq_mass_net_kg_max <- NA_real_

  result <- data |>
    janitor::clean_names() |>
    dplyr::transmute(
      saaq_snapshot_year = safe_parse_integer(.data$an),
      saaq_class_code = dplyr::na_if(stringr::str_squish(as.character(.data$clas)), ""),
      saaq_vehicle_type_code = dplyr::na_if(
        stringr::str_squish(as.character(.data$typ_veh_categ_usa)), ""
      ),
      saaq_make_code = dplyr::na_if(stringr::str_squish(as.character(.data$marq_veh)), ""),
      saaq_model_code = dplyr::na_if(stringr::str_squish(as.character(.data$model_veh)), ""),
      model_year = safe_parse_integer(.data$annee_mod),
      saaq_cylinders_code = dplyr::na_if(
        stringr::str_squish(as.character(.data$nb_cyl)), ""
      ),
      saaq_cylinders = dplyr::if_else(
        .data$saaq_cylinders_code %in% as.character(1:8),
        as.integer(.data$saaq_cylinders_code),
        NA_integer_
      ),
      saaq_engine_size_cm3 = safe_parse_double(.data$cyl_veh),
      saaq_engine_size_l = dplyr::if_else(
        is.na(.data$saaq_engine_size_cm3),
        NA_real_,
        .data$saaq_engine_size_cm3 / 1000
      ),
      saaq_fuel_code = dplyr::na_if(
        stringr::str_squish(as.character(.data$typ_carbu)), ""
      ),
      region_qc = if (by_region) {
        dplyr::na_if(stringr::str_squish(as.character(.data$reg_adm)), "")
      } else {
        "ALL_QC"
      },
      number_registered_qc = safe_parse_integer(.data$number_registered_qc),
      saaq_mass_net_kg_mean = safe_parse_double(.data$saaq_mass_net_kg_mean),
      saaq_mass_net_kg_min = safe_parse_double(.data$saaq_mass_net_kg_min),
      saaq_mass_net_kg_max = safe_parse_double(.data$saaq_mass_net_kg_max)
    ) |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(c(
          "saaq_mass_net_kg_mean",
          "saaq_mass_net_kg_min",
          "saaq_mass_net_kg_max"
        )),
        ~ dplyr::if_else(is.finite(.x), .x, NA_real_)
      )
    ) |>
    dplyr::left_join(fuel_codes, by = "saaq_fuel_code", na_matches = "na") |>
    dplyr::mutate(
      saaq_fuel_type = dplyr::case_when(
        !is.na(.data$saaq_fuel_type) ~ .data$saaq_fuel_type,
        is.na(.data$saaq_fuel_code) ~ "Non précisé",
        TRUE ~ paste0("Code inconnu: ", .data$saaq_fuel_code)
      ),
      is_light_vehicle_scope =
        .data$saaq_vehicle_type_code %in% light_vehicle_type_codes &
        .data$saaq_class_code %in% light_vehicle_class_codes,
      saaq_group_id = paste0(
        "saaq_",
        stable_hash(
          .data$saaq_snapshot_year, .data$saaq_class_code,
          .data$saaq_vehicle_type_code, .data$saaq_make_code,
          .data$saaq_model_code, .data$model_year,
          .data$saaq_cylinders_code, .data$saaq_engine_size_cm3,
          .data$saaq_fuel_code, .data$region_qc,
          n = 24L
        )
      )
    ) |>
    dplyr::relocate(saaq_fuel_type, .after = saaq_fuel_code)

  result
}

read_saaq_summaries <- function(
    root,
    source_id = "saaq_vehicles_2022",
    expected_filename = NULL,
    expected_snapshot_year = NULL,
    light_vehicle_type_codes = "AU",
    light_vehicle_class_codes = c("PAU", "CAU", "RAU")) {

  csv_path <- find_saaq_csv(
    root,
    source_id = source_id,
    expected_filename = expected_filename
  )
  if (is.null(csv_path)) {
    warning(
      "Aucun CSV SAAQ brut trouvé. Les colonnes québécoises resteront manquantes; ",
      "consultez references/MANUAL_DOWNLOAD.md.",
      call. = FALSE
    )
    empty <- empty_saaq_summary()
    return(list(global = empty, regional = empty, source_path = NA_character_))
  }

  data_table_aggregates <- saaq_data_table_aggregates(csv_path)
  global_raw <- data_table_aggregates$global_raw
  regional_raw <- data_table_aggregates$regional_raw

  global <- standardise_saaq_summary(
    global_raw, root, by_region = FALSE,
    light_vehicle_type_codes = light_vehicle_type_codes,
    light_vehicle_class_codes = light_vehicle_class_codes
  )
  regional <- standardise_saaq_summary(
    regional_raw, root, by_region = TRUE,
    light_vehicle_type_codes = light_vehicle_type_codes,
    light_vehicle_class_codes = light_vehicle_class_codes
  )

  if (!is.null(expected_snapshot_year) && !is.na(expected_snapshot_year)) {
    expected_snapshot_year <- as.integer(expected_snapshot_year)
    observed_years <- sort(unique(stats::na.omit(c(
      global$saaq_snapshot_year,
      regional$saaq_snapshot_year
    ))))
    if (length(observed_years) != 1L ||
        !identical(as.integer(observed_years), expected_snapshot_year)) {
      stop(
        "Le millésime SAAQ observé ne correspond pas au manifeste. Attendu : ",
        expected_snapshot_year,
        "; observé : ",
        if (length(observed_years) == 0L) "aucun" else paste(observed_years, collapse = ", "),
        call. = FALSE
      )
    }
  }

  list(global = global, regional = regional, source_path = csv_path)
}

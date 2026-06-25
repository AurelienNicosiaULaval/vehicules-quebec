read_verified_crosswalk <- function(root) {
  path <- file.path(root, "references", "saaq_make_model_crosswalk.csv")
  required <- c(
    "saaq_make_code", "saaq_model_code", "make", "model",
    "model_year_min", "model_year_max", "verification_status",
    "verification_method", "source_url", "source_accessed_at",
    "verified_by", "notes"
  )

  if (!file.exists(path)) {
    return(tibble::tibble(
      saaq_make_code = character(), saaq_model_code = character(),
      make = character(), model = character(), model_year_min = integer(),
      model_year_max = integer(), verification_status = character(),
      verification_method = character(), source_url = character(),
      source_accessed_at = character(), verified_by = character(), notes = character(),
      make_key = character(), model_key = character()
    ))
  }

  crosswalk <- readr::read_csv(
    path, show_col_types = FALSE, progress = FALSE, na = c("", "NA")
  )
  missing <- setdiff(required, names(crosswalk))
  if (length(missing) > 0L) {
    stop(
      "Colonnes absentes de la table de correspondance : ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  result <- crosswalk |>
    dplyr::mutate(
      saaq_make_code = dplyr::na_if(
        stringr::str_squish(as.character(.data$saaq_make_code)), ""
      ),
      saaq_model_code = dplyr::na_if(
        stringr::str_squish(as.character(.data$saaq_model_code)), ""
      ),
      model_year_min = safe_parse_integer(.data$model_year_min),
      model_year_max = safe_parse_integer(.data$model_year_max),
      verification_status = stringr::str_to_lower(
        stringr::str_squish(.data$verification_status)
      ),
      verification_method = dplyr::na_if(
        stringr::str_squish(as.character(.data$verification_method)), ""
      ),
      source_url = dplyr::na_if(
        stringr::str_squish(as.character(.data$source_url)), ""
      ),
      source_accessed_at = dplyr::na_if(
        stringr::str_squish(as.character(.data$source_accessed_at)), ""
      ),
      verified_by = dplyr::na_if(
        stringr::str_squish(as.character(.data$verified_by)), ""
      ),
      make_key = normalize_make_key(.data$make),
      model_key = normalize_model_key(.data$model)
    ) |>
    dplyr::filter(
      .data$verification_status == "verified",
      !is.na(.data$saaq_make_code), !is.na(.data$saaq_model_code),
      !is.na(.data$make_key), !is.na(.data$model_key),
      !is.na(.data$verification_method), !is.na(.data$source_url),
      !is.na(.data$source_accessed_at), !is.na(.data$verified_by)
    ) |>
    dplyr::distinct(
      .data$saaq_make_code, .data$saaq_model_code,
      .data$model_year_min, .data$model_year_max,
      .data$make_key, .data$model_key,
      .keep_all = TRUE
    )

  invalid_ranges <- result |>
    dplyr::filter(
      !is.na(.data$model_year_min), !is.na(.data$model_year_max),
      .data$model_year_min > .data$model_year_max
    )
  if (nrow(invalid_ranges) > 0L) {
    stop(
      "La table de correspondance contient une plage d'années inversée.",
      call. = FALSE
    )
  }
  result
}

fuel_compatible <- function(saaq_code, rncan_fuel, powertrain_group) {
  dplyr::case_when(
    is.na(saaq_code) | is.na(rncan_fuel) ~ NA,
    saaq_code == "E" ~ rncan_fuel %in% c("regular_gasoline", "premium_gasoline"),
    saaq_code == "D" ~ rncan_fuel == "diesel",
    saaq_code == "L" ~ powertrain_group == "BEV",
    saaq_code == "W" ~ powertrain_group == "PHEV",
    saaq_code == "H" & powertrain_group == "HEV_text_derived" ~ TRUE,
    saaq_code == "H" & powertrain_group %in% c(
      "BEV", "PHEV", "diesel", "natural_gas", "flex_fuel_e85"
    ) ~ FALSE,
    saaq_code == "H" ~ NA,
    saaq_code == "T" ~ rncan_fuel == "e85",
    saaq_code == "N" ~ rncan_fuel == "natural_gas",
    saaq_code %in% c("A", "C", "M", "P", "S") ~ NA,
    TRUE ~ NA
  )
}

prepare_crosswalked_saaq <- function(saaq, crosswalk) {
  if (nrow(saaq) == 0L || nrow(crosswalk) == 0L) return(tibble::tibble())

  joined <- suppressWarnings(dplyr::left_join(
    saaq,
    crosswalk,
    by = c("saaq_make_code", "saaq_model_code"),
    na_matches = "never"
  ))

  joined |>
    dplyr::filter(
      !is.na(.data$make_key), !is.na(.data$model_key),
      is.na(.data$model_year_min) |
        (!is.na(.data$model_year) & .data$model_year >= .data$model_year_min),
      is.na(.data$model_year_max) |
        (!is.na(.data$model_year) & .data$model_year <= .data$model_year_max)
    ) |>
    dplyr::mutate(
      crosswalk_mapping_key = paste(.data$make_key, .data$model_key, sep = "|")
    ) |>
    dplyr::group_by(.data$saaq_group_id) |>
    dplyr::mutate(
      crosswalk_mapping_count = dplyr::n_distinct(.data$crosswalk_mapping_key)
    ) |>
    dplyr::ungroup() |>
    dplyr::distinct(
      .data$saaq_group_id, .data$make_key, .data$model_key,
      .keep_all = TRUE
    )
}

build_join_candidates <- function(rncan, saaq_mapped, engine_tolerance_l = 0.11) {
  if (nrow(saaq_mapped) == 0L || nrow(rncan) == 0L) return(tibble::tibble())

  unique_mappings <- saaq_mapped |>
    dplyr::filter(
      .data$crosswalk_mapping_count == 1L,
      !is.na(.data$model_year), !is.na(.data$make_key), !is.na(.data$model_key)
    )
  if (nrow(unique_mappings) == 0L) return(tibble::tibble())

  candidates <- suppressWarnings(dplyr::inner_join(
    unique_mappings,
    rncan,
    by = c("model_year", "make_key", "model_key"),
    suffix = c("_saaq", "_rncan"),
    na_matches = "never"
  ))

  candidates |>
    dplyr::mutate(
      fuel_agreement = fuel_compatible(
        .data$saaq_fuel_code, .data$fuel_type, .data$powertrain_group
      ),
      cylinders_agreement = dplyr::case_when(
        is.na(.data$saaq_cylinders) | is.na(.data$cylinders) ~ NA,
        TRUE ~ .data$saaq_cylinders == .data$cylinders
      ),
      engine_size_difference_l = dplyr::if_else(
        is.na(.data$saaq_engine_size_l) | is.na(.data$engine_size_l),
        NA_real_,
        abs(.data$saaq_engine_size_l - .data$engine_size_l)
      ),
      engine_size_agreement = dplyr::case_when(
        is.na(.data$engine_size_difference_l) ~ NA,
        TRUE ~ .data$engine_size_difference_l <= engine_tolerance_l
      ),
      has_contradiction =
        (!is.na(.data$fuel_agreement) & !.data$fuel_agreement) |
        (!is.na(.data$cylinders_agreement) & !.data$cylinders_agreement) |
        (!is.na(.data$engine_size_agreement) & !.data$engine_size_agreement),
      available_agreement_count =
        as.integer(!is.na(.data$fuel_agreement)) +
        as.integer(!is.na(.data$cylinders_agreement)) +
        as.integer(!is.na(.data$engine_size_agreement)),
      candidate_is_admissible = !.data$has_contradiction
    ) |>
    dplyr::group_by(.data$saaq_group_id) |>
    dplyr::mutate(
      admissible_candidate_count = sum(.data$candidate_is_admissible, na.rm = TRUE),
      all_candidate_count = dplyr::n()
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      candidate_status = dplyr::case_when(
        .data$has_contradiction ~ "rejected_specification_contradiction",
        .data$admissible_candidate_count == 1L &
          .data$available_agreement_count == 3L ~ "admissible_unique_full_specs",
        .data$admissible_candidate_count == 1L ~ "admissible_unique_partial_specs",
        .data$admissible_candidate_count > 1L ~ "ambiguous_multiple_rncan_configurations",
        TRUE ~ "no_admissible_candidate"
      )
    )
}

add_combined_mpg <- function(data, derive_missing = TRUE, constant = 282.48) {
  derived <- dplyr::if_else(
    isTRUE(derive_missing) & is.na(data$combined_mpg_source) &
      !is.na(data$combined_l_per_100km) & data$combined_l_per_100km > 0,
    constant / data$combined_l_per_100km,
    NA_real_
  )
  data |>
    dplyr::mutate(
      combined_mpg = dplyr::coalesce(.data$combined_mpg_source, derived),
      combined_mpg_origin = dplyr::case_when(
        !is.na(.data$combined_mpg_source) ~ "observed_rncan",
        !is.na(derived) ~ "derived_282.48_divided_by_combined_l_per_100km",
        TRUE ~ "unknown"
      )
    )
}

weighted_mean_or_na <- function(x, w) {
  keep <- is.finite(x) & is.finite(w) & w >= 0
  if (!any(keep) || sum(w[keep]) <= 0) return(NA_real_)
  stats::weighted.mean(x[keep], w[keep])
}

min_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else min(x)
}

max_or_na <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else max(x)
}

collapse_unique_or_na <- function(x) {
  x <- sort(unique(stats::na.omit(as.character(x))))
  x <- x[nzchar(x)]
  if (length(x) == 0L) NA_character_ else paste(x, collapse = ";")
}

attach_exact_registration_counts <- function(
    rncan,
    candidates,
    saaq_source_url,
    derive_missing_mpg = TRUE,
    mpg_constant = 282.48) {

  base <- add_combined_mpg(rncan, derive_missing_mpg, mpg_constant)

  if (nrow(candidates) == 0L) {
    out <- base |>
      dplyr::mutate(
        number_registered_qc = NA_integer_,
        registration_count_grain = NA_character_,
        region_qc = NA_character_,
        saaq_snapshot_year = NA_integer_,
        saaq_class_code = NA_character_,
        saaq_vehicle_type_code = NA_character_,
        saaq_make_code = NA_character_,
        saaq_model_code = NA_character_,
        saaq_fuel_code = NA_character_,
        saaq_mass_net_kg_mean = NA_real_,
        saaq_mass_net_kg_min = NA_real_,
        saaq_mass_net_kg_max = NA_real_,
        saaq_group_count = NA_integer_,
        saaq_group_id = NA_character_,
        join_method = "not_attempted_no_verified_crosswalk_or_no_saaq_data",
        join_quality = "not_matched",
        join_candidate_count = NA_integer_,
        qc_presence_status = "unconfirmed",
        source_saaq = NA_character_
      )
  } else {
    exact <- candidates |>
      dplyr::filter(
        .data$candidate_is_admissible,
        .data$admissible_candidate_count == 1L
      ) |>
      dplyr::group_by(.data$vehicle_id) |>
      dplyr::summarise(
        number_registered_qc = if (any(is.na(.data$number_registered_qc))) {
          NA_integer_
        } else {
          as.integer(sum(.data$number_registered_qc))
        },
        saaq_snapshot_year = if (dplyr::n_distinct(
          .data$saaq_snapshot_year, na.rm = TRUE
        ) == 1L) {
          dplyr::first(stats::na.omit(.data$saaq_snapshot_year))
        } else {
          NA_integer_
        },
        region_qc = "ALL_QC",
        saaq_mass_net_kg_mean = weighted_mean_or_na(
          .data$saaq_mass_net_kg_mean, .data$number_registered_qc
        ),
        saaq_mass_net_kg_min = min_or_na(.data$saaq_mass_net_kg_min),
        saaq_mass_net_kg_max = max_or_na(.data$saaq_mass_net_kg_max),
        saaq_group_count = dplyr::n_distinct(.data$saaq_group_id),
        saaq_group_id = collapse_unique_or_na(.data$saaq_group_id),
        saaq_class_code = collapse_unique_or_na(.data$saaq_class_code),
        saaq_vehicle_type_code = collapse_unique_or_na(.data$saaq_vehicle_type_code),
        saaq_make_code = collapse_unique_or_na(.data$saaq_make_code),
        saaq_model_code = collapse_unique_or_na(.data$saaq_model_code),
        saaq_fuel_code = collapse_unique_or_na(.data$saaq_fuel_code),
        join_quality = dplyr::if_else(
          all(.data$candidate_status == "admissible_unique_full_specs"),
          "exact_unique_full_specs",
          "exact_unique_partial_specs"
        ),
        join_candidate_count = max(.data$all_candidate_count, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        registration_count_grain =
          "unique_rncan_configuration_after_verified_saaq_code_crosswalk",
        join_method =
          "verified_saaq_code_crosswalk+model_year+normalized_make_model+noncontradictory_specs",
        qc_presence_status = "confirmed_by_exact_audited_join",
        source_saaq = saaq_source_url
      )

    out <- base |>
      dplyr::left_join(exact, by = "vehicle_id") |>
      dplyr::mutate(
        join_method = dplyr::coalesce(
          .data$join_method, "verified_join_attempted_no_unique_match"
        ),
        join_quality = dplyr::coalesce(
          .data$join_quality, "not_matched_or_ambiguous"
        ),
        qc_presence_status = dplyr::coalesce(
          .data$qc_presence_status, "unconfirmed"
        ),
        source_saaq = dplyr::coalesce(
          .data$source_saaq.y, .data$source_saaq.x
        )
      ) |>
      dplyr::select(-dplyr::any_of(c("source_saaq.x", "source_saaq.y")))
  }

  out |>
    dplyr::mutate(
      data_quality_flag = collapse_flags(
        dplyr::if_else(
          is.na(.data$make) | is.na(.data$model) | is.na(.data$model_year),
          "missing_identity", NA_character_
        ),
        dplyr::if_else(
          .data$powertrain_group != "BEV" & is.na(.data$combined_l_per_100km),
          "missing_combined_fuel_consumption", NA_character_
        ),
        dplyr::if_else(
          .data$powertrain_group == "BEV" &
            is.na(.data$combined_kwh_per_100km) &
            is.na(.data$combined_le_per_100km),
          "missing_combined_electric_consumption", NA_character_
        ),
        dplyr::if_else(
          .data$qc_presence_status != "confirmed_by_exact_audited_join",
          "quebec_presence_unconfirmed", NA_character_
        ),
        dplyr::if_else(
          .data$join_quality %in% c("not_matched", "not_matched_or_ambiguous"),
          "join_not_unique_or_absent", NA_character_
        ),
        dplyr::if_else(
          is.na(.data$rncan_source_row_id),
          "missing_rncan_source_row_locator", NA_character_
        )
      ),
      notes = dplyr::case_when(
        .data$qc_presence_status == "confirmed_by_exact_audited_join" ~
          "Compte SAAQ attribué seulement après appariement unique et audité.",
        TRUE ~
          "Spécification RNCan réelle; présence ou nombre d'immatriculations au Québec non confirmé au niveau de cette configuration."
      )
    )
}

build_unmatched_saaq <- function(saaq, crosswalk, candidates) {
  if (nrow(saaq) == 0L) {
    return(saaq |> dplyr::mutate(unmatched_reason = character()))
  }
  if (nrow(crosswalk) == 0L) {
    return(saaq |> dplyr::mutate(unmatched_reason = "no_verified_make_model_crosswalk"))
  }

  mapped <- prepare_crosswalked_saaq(saaq, crosswalk)
  mapped_ids <- unique(mapped$saaq_group_id)
  conflicting_ids <- unique(
    mapped$saaq_group_id[mapped$crosswalk_mapping_count > 1L]
  )

  candidate_summary <- if (nrow(candidates) == 0L) {
    tibble::tibble(saaq_group_id = character(), unmatched_reason = character())
  } else {
    candidates |>
      dplyr::group_by(.data$saaq_group_id) |>
      dplyr::summarise(
        unmatched_reason = dplyr::case_when(
          any(
            .data$candidate_is_admissible &
              .data$admissible_candidate_count == 1L
          ) ~ "matched_unique",
          any(.data$admissible_candidate_count > 1L) ~
            "ambiguous_multiple_rncan_configurations",
          all(.data$has_contradiction) ~ "all_candidates_contradict_specs",
          TRUE ~ "no_admissible_candidate"
        ),
        .groups = "drop"
      )
  }

  saaq |>
    dplyr::left_join(candidate_summary, by = "saaq_group_id") |>
    dplyr::mutate(
      unmatched_reason = dplyr::case_when(
        .data$saaq_group_id %in% conflicting_ids ~
          "conflicting_verified_crosswalk_mappings",
        !.data$saaq_group_id %in% mapped_ids ~
          "no_verified_crosswalk_for_code_and_year",
        is.na(.data$unmatched_reason) ~
          "mapped_code_but_no_rncan_make_model_candidate",
        TRUE ~ .data$unmatched_reason
      )
    ) |>
    dplyr::filter(.data$unmatched_reason != "matched_unique")
}

sum_or_na <- function(x) {
  if (length(x) == 0L || all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
}

join_saaq_rncan <- function(
    rncan,
    saaq,
    crosswalk,
    saaq_source_url,
    engine_tolerance_l = 0.11,
    derive_missing_mpg = TRUE,
    mpg_constant = 282.48) {

  saaq_scope <- saaq |>
    dplyr::filter(.data$is_light_vehicle_scope)
  mapped <- prepare_crosswalked_saaq(saaq_scope, crosswalk)
  candidates <- build_join_candidates(rncan, mapped, engine_tolerance_l)
  main <- attach_exact_registration_counts(
    rncan, candidates, saaq_source_url,
    derive_missing_mpg, mpg_constant
  )
  unmatched <- build_unmatched_saaq(saaq_scope, crosswalk, candidates)

  matched_group_ids <- if (nrow(candidates) == 0L) {
    character()
  } else {
    unique(candidates$saaq_group_id[
      candidates$candidate_is_admissible &
        candidates$admissible_candidate_count == 1L
    ])
  }
  ambiguous_group_ids <- if (nrow(candidates) == 0L) {
    character()
  } else {
    unique(candidates$saaq_group_id[candidates$admissible_candidate_count > 1L])
  }
  conflicting_crosswalk_groups <- if (nrow(mapped) == 0L) {
    0L
  } else {
    dplyr::n_distinct(mapped$saaq_group_id[mapped$crosswalk_mapping_count > 1L])
  }

  total_groups <- nrow(saaq_scope)
  matched_groups <- length(matched_group_ids)
  total_registered <- sum_or_na(saaq_scope$number_registered_qc)
  matched_registered <- if (length(matched_group_ids) == 0L) {
    0
  } else {
    sum_or_na(
      saaq_scope$number_registered_qc[
        saaq_scope$saaq_group_id %in% matched_group_ids
      ]
    )
  }
  confirmed_configurations <- sum(
    main$qc_presence_status == "confirmed_by_exact_audited_join",
    na.rm = TRUE
  )

  summary <- tibble::tibble(
    metric = c(
      "rncan_configurations",
      "rncan_configurations_qc_confirmed",
      "saaq_light_vehicle_groups",
      "saaq_registered_vehicles_in_scope",
      "verified_crosswalk_rows",
      "conflicting_crosswalk_groups",
      "candidate_rows",
      "unique_matched_saaq_groups",
      "ambiguous_saaq_groups",
      "unmatched_saaq_groups",
      "matched_registered_vehicles",
      "saaq_group_join_rate_pct",
      "saaq_vehicle_weighted_join_rate_pct",
      "rncan_configuration_confirmation_rate_pct"
    ),
    value = c(
      nrow(rncan),
      confirmed_configurations,
      total_groups,
      total_registered,
      nrow(crosswalk),
      conflicting_crosswalk_groups,
      nrow(candidates),
      matched_groups,
      length(ambiguous_group_ids),
      nrow(unmatched),
      matched_registered,
      if (total_groups == 0L) NA_real_ else 100 * matched_groups / total_groups,
      if (is.na(total_registered) || total_registered == 0) {
        NA_real_
      } else {
        100 * matched_registered / total_registered
      },
      if (nrow(rncan) == 0L) {
        NA_real_
      } else {
        100 * confirmed_configurations / nrow(rncan)
      }
    )
  )

  list(
    main = main,
    candidates = candidates,
    unmatched_saaq = unmatched,
    summary = summary
  )
}

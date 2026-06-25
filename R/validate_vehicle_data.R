missingness_table <- function(data) {
  n <- nrow(data)
  tibble::tibble(
    variable = names(data),
    n_missing = vapply(data, function(x) sum(is.na(x)), integer(1)),
    pct_missing = vapply(
      data,
      function(x) if (n == 0L) NA_real_ else mean(is.na(x)) * 100,
      numeric(1)
    )
  ) |>
    dplyr::arrange(dplyr::desc(.data$pct_missing), .data$variable)
}

flag_suspect_rows <- function(data, config) {
  current_year <- as.integer(format(Sys.Date(), "%Y"))
  year_min <- config$validation$model_year_min %||% 1900
  future_tol <- config$validation$model_year_future_tolerance %||% 1
  engine_min <- config$validation$engine_size_l_min %||% 0.1
  engine_max <- config$validation$engine_size_l_max %||% 10
  fuel_min <- config$validation$fuel_l_per_100km_min %||% 0.5
  fuel_max <- config$validation$fuel_l_per_100km_max %||% 50
  co2_min <- config$validation$co2_g_per_km_min %||% 0
  co2_max <- config$validation$co2_g_per_km_max %||% 1000
  mpg_constant <- config$cleaning$imperial_mpg_constant %||% 282.48

  data |>
    dplyr::mutate(
      validation_flag = collapse_flags(
        dplyr::if_else(
          !is.na(.data$model_year) &
            (.data$model_year < year_min | .data$model_year > current_year + future_tol),
          "model_year_outside_review_range", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$engine_size_l) &
            (.data$engine_size_l < engine_min | .data$engine_size_l > engine_max),
          "engine_size_outside_review_range", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$combined_l_per_100km) &
            (.data$combined_l_per_100km < fuel_min |
               .data$combined_l_per_100km > fuel_max),
          "combined_l_per_100km_outside_review_range", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$combined_kwh_per_100km) &
            .data$combined_kwh_per_100km <= 0,
          "nonpositive_combined_kwh_per_100km", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$combined_le_per_100km) &
            .data$combined_le_per_100km <= 0,
          "nonpositive_combined_le_per_100km", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$co2_g_per_km) &
            (.data$co2_g_per_km < co2_min | .data$co2_g_per_km > co2_max),
          "co2_outside_review_range", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$co2_rating) & !(.data$co2_rating %in% 1:10),
          "co2_rating_outside_1_10", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$smog_rating) & !(.data$smog_rating %in% 1:10),
          "smog_rating_outside_1_10", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$city_l_per_100km) &
            !is.na(.data$highway_l_per_100km) &
            !is.na(.data$combined_l_per_100km) &
            (.data$combined_l_per_100km <
               pmin(.data$city_l_per_100km, .data$highway_l_per_100km) - 0.2 |
             .data$combined_l_per_100km >
               pmax(.data$city_l_per_100km, .data$highway_l_per_100km) + 0.2),
          "combined_consumption_outside_city_highway_interval", NA_character_
        ),
        dplyr::if_else(
          .data$combined_mpg_origin ==
            "derived_282.48_divided_by_combined_l_per_100km" &
            !is.na(.data$combined_l_per_100km) &
            !is.na(.data$combined_mpg) &
            abs(.data$combined_mpg - mpg_constant / .data$combined_l_per_100km) > 1e-8,
          "derived_mpg_formula_mismatch", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$number_registered_qc) &
            (.data$number_registered_qc < 0 |
               .data$number_registered_qc != round(.data$number_registered_qc)),
          "invalid_registration_count", NA_character_
        ),
        dplyr::if_else(
          !is.na(.data$number_registered_qc) &
            .data$qc_presence_status != "confirmed_by_exact_audited_join",
          "registration_count_without_confirmed_join", NA_character_
        ),
        dplyr::if_else(
          is.na(.data$number_registered_qc) &
            .data$qc_presence_status == "confirmed_by_exact_audited_join",
          "confirmed_join_without_registration_count", NA_character_
        ),
        dplyr::if_else(
          .data$powertrain_group == "BEV" & !is.na(.data$engine_size_l),
          "bev_with_thermal_engine_size", NA_character_
        ),
        dplyr::if_else(
          duplicated(.data$vehicle_id) |
            duplicated(.data$vehicle_id, fromLast = TRUE),
          "duplicate_vehicle_id", NA_character_
        )
      )
    ) |>
    dplyr::filter(!is.na(.data$validation_flag))
}

validation_summary <- function(
    data,
    candidates = tibble::tibble(),
    unmatched = tibble::tibble()) {

  matched <- sum(
    data$qc_presence_status == "confirmed_by_exact_audited_join",
    na.rm = TRUE
  )
  registered_sum <- if (all(is.na(data$number_registered_qc))) {
    NA_real_
  } else {
    sum(data$number_registered_qc, na.rm = TRUE)
  }

  tibble::tibble(
    metric = c(
      "rows_total",
      "distinct_makes",
      "distinct_models",
      "distinct_model_years",
      "distinct_fuel_types",
      "rows_qc_confirmed",
      "row_level_qc_confirmation_rate_pct",
      "registered_vehicles_attached_to_confirmed_rows",
      "join_candidate_rows",
      "unmatched_saaq_groups"
    ),
    value = c(
      nrow(data),
      dplyr::n_distinct(data$make, na.rm = TRUE),
      {
        complete_identity <- !is.na(data$make) & !is.na(data$model)
        dplyr::n_distinct(
          paste(
            data$make[complete_identity],
            data$model[complete_identity],
            sep = "|"
          )
        )
      },
      dplyr::n_distinct(data$model_year, na.rm = TRUE),
      dplyr::n_distinct(data$fuel_type, na.rm = TRUE),
      matched,
      if (nrow(data) == 0L) NA_real_ else 100 * matched / nrow(data),
      registered_sum,
      nrow(candidates),
      nrow(unmatched)
    )
  )
}

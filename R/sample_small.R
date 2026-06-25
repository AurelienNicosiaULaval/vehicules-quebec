small_sample_coverage_flags <- function(data) {
  tibble::tibble(
    vehicle_id = data$vehicle_id,
    compact_cars = data$vehicle_class_group == "passenger_car" &
      data$vehicle_size_group %in% c("minicompact", "subcompact", "compact"),
    passenger_cars = data$vehicle_class_group == "passenger_car",
    suv = data$vehicle_class_group == "suv",
    pickups = data$vehicle_class_group == "pickup",
    hybrid_or_phev = data$powertrain_group %in% c("HEV_text_derived", "PHEV"),
    battery_electric = data$powertrain_group == "BEV",
    gasoline = data$powertrain_group == "gasoline",
    older_2014_or_before = !is.na(data$model_year) & data$model_year <= 2014,
    recent_2019_or_after = !is.na(data$model_year) & data$model_year >= 2019
  ) |>
    dplyr::mutate(dplyr::across(dplyr::where(is.logical), ~ dplyr::coalesce(.x, FALSE)))
}

select_coverage_ids <- function(eligible, target_n) {
  flags <- small_sample_coverage_flags(eligible)
  criteria <- setdiff(names(flags), "vehicle_id")
  available <- vapply(flags[criteria], any, logical(1), na.rm = TRUE)
  unmet <- criteria[available]
  selected <- character()

  while (length(unmet) > 0L && length(selected) < target_n) {
    remaining <- eligible |>
      dplyr::filter(!.data$vehicle_id %in% selected)
    if (nrow(remaining) == 0L) break

    flag_rows <- flags[match(remaining$vehicle_id, flags$vehicle_id), unmet, drop = FALSE]
    scores <- rowSums(as.data.frame(flag_rows), na.rm = TRUE)
    best <- remaining |>
      dplyr::mutate(coverage_score = scores) |>
      dplyr::arrange(
        dplyr::desc(.data$coverage_score),
        .data$qc_priority,
        .data$vehicle_id
      ) |>
      dplyr::slice_head(n = 1L)

    if (nrow(best) == 0L || best$coverage_score[[1L]] <= 0L) break
    selected <- c(selected, best$vehicle_id[[1L]])

    selected_flags <- flags[match(selected, flags$vehicle_id), unmet, drop = FALSE]
    now_covered <- vapply(selected_flags, any, logical(1), na.rm = TRUE)
    unmet <- unmet[!now_covered]
  }
  selected
}

make_balanced_small_sample <- function(data, target_n = 64L, strict_qc_only = FALSE) {
  target_n <- as.integer(target_n)
  if (is.na(target_n) || target_n < 1L) {
    stop("target_n doit être positif.", call. = FALSE)
  }

  eligible <- data |>
    dplyr::filter(
      !is.na(.data$vehicle_id),
      !is.na(.data$make), !is.na(.data$model), !is.na(.data$model_year),
      !is.na(.data$vehicle_class_group),
      !is.na(.data$powertrain_group)
    ) |>
    dplyr::distinct(.data$vehicle_id, .keep_all = TRUE) |>
    dplyr::mutate(
      model_year_era = model_year_era(.data$model_year),
      pedagogical_powertrain = dplyr::case_when(
        .data$powertrain_group == "BEV" ~ "BEV",
        .data$powertrain_group == "PHEV" ~ "PHEV",
        .data$powertrain_group == "HEV_text_derived" ~ "HEV_text_derived",
        .data$powertrain_group == "gasoline" ~ "gasoline",
        .data$powertrain_group == "diesel" ~ "diesel",
        TRUE ~ "other"
      ),
      pedagogical_stratum = paste(
        .data$vehicle_class_group,
        .data$pedagogical_powertrain,
        .data$model_year_era,
        sep = "|"
      ),
      qc_priority = dplyr::if_else(
        .data$qc_presence_status == "confirmed_by_exact_audited_join",
        0L, 1L
      )
    )

  if (isTRUE(strict_qc_only)) {
    eligible <- eligible |>
      dplyr::filter(.data$qc_priority == 0L)
  }

  if (nrow(eligible) == 0L) {
    warning("Aucune ligne admissible pour vehicules_quebec_small.csv.", call. = FALSE)
    return(
      eligible |>
        dplyr::mutate(small_sample_rule = character()) |>
        dplyr::select(-dplyr::any_of(c("pedagogical_stratum", "qc_priority")))
    )
  }

  final_n <- min(target_n, nrow(eligible))

  # Phase 1 : couvrir les catégories explicitement demandées, si elles existent.
  # Le choix est glouton et déterministe : nombre de critères encore non couverts,
  # puis preuve Québec, puis identifiant stable. Aucune marque n'est choisie à la main.
  coverage_ids <- select_coverage_ids(eligible, final_n)
  coverage_selected <- eligible |>
    dplyr::filter(.data$vehicle_id %in% coverage_ids) |>
    dplyr::mutate(selection_order = match(.data$vehicle_id, coverage_ids)) |>
    dplyr::arrange(.data$selection_order) |>
    dplyr::mutate(
      small_sample_rule = paste0(
        "phase=coverage_greedy;criteria=class_powertrain_era_requirements;",
        "confirmed_qc_tiebreak=TRUE;stable_vehicle_id_tiebreak=TRUE;target_n=",
        target_n,
        ";manual_vehicle_selection=FALSE"
      )
    )

  remaining_n <- final_n - nrow(coverage_selected)
  if (remaining_n > 0L) {
    filler <- eligible |>
      dplyr::filter(!.data$vehicle_id %in% coverage_ids) |>
      dplyr::mutate(
        stratum_order = stable_hash(.data$pedagogical_stratum, n = 16L)
      ) |>
      dplyr::group_by(.data$pedagogical_stratum) |>
      dplyr::arrange(.data$qc_priority, .data$vehicle_id, .by_group = TRUE) |>
      dplyr::mutate(round_robin_rank = dplyr::row_number()) |>
      dplyr::ungroup() |>
      dplyr::arrange(
        .data$round_robin_rank,
        .data$stratum_order,
        .data$qc_priority,
        .data$vehicle_id
      ) |>
      dplyr::slice_head(n = remaining_n) |>
      dplyr::mutate(
        small_sample_rule = paste0(
          "phase=stratified_round_robin_fill;strata=vehicle_class_powertrain_era;",
          "confirmed_qc_within_stratum_first=TRUE;stable_hash_order=TRUE;target_n=",
          target_n,
          ";manual_vehicle_selection=FALSE"
        )
      )
  } else {
    filler <- eligible[0, ] |>
      dplyr::mutate(small_sample_rule = character())
  }

  dplyr::bind_rows(coverage_selected, filler) |>
    dplyr::select(-dplyr::any_of(c(
      "selection_order", "stratum_order", "round_robin_rank",
      "pedagogical_stratum", "qc_priority"
    )))
}

small_sample_coverage <- function(data) {
  if (nrow(data) == 0L) {
    return(tibble::tibble(
      criterion = c(
        "compact_cars", "passenger_cars", "suv", "pickups", "hybrid_or_phev",
        "battery_electric", "gasoline", "older_2014_or_before",
        "recent_2019_or_after"
      ),
      present = FALSE
    ))
  }
  flags <- small_sample_coverage_flags(data)
  tibble::tibble(
    criterion = setdiff(names(flags), "vehicle_id"),
    present = vapply(
      flags[setdiff(names(flags), "vehicle_id")],
      any,
      logical(1),
      na.rm = TRUE
    )
  )
}

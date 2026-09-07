#!/usr/bin/env Rscript

required_packages <- c(
  "fs", "readr", "dplyr", "purrr", "tibble", "yaml", "httr2",
  "jsonlite", "digest", "cli", "stringr"
)

source("R/project_utils.R")
assert_packages(required_packages)
root <- project_root()
create_project_dirs(root)

args <- commandArgs(trailingOnly = TRUE)
include_large <- has_flag("--include-large", args)
page_size <- as.integer(flag_value("--page-size", default = "5000", args = args))
timeout_seconds <- as.numeric(flag_value("--timeout-seconds", default = "180", args = args))
large_timeout_seconds <- as.numeric(flag_value(
  "--large-timeout-seconds", default = "1800", args = args
))
if (is.na(page_size) || page_size < 1L || page_size > 10000L) {
  stop("--page-size doit être compris entre 1 et 10000.", call. = FALSE)
}
if (is.na(timeout_seconds) || timeout_seconds <= 0 ||
    is.na(large_timeout_seconds) || large_timeout_seconds <= 0) {
  stop("Les délais d'attente doivent être positifs.", call. = FALSE)
}

config <- yaml::read_yaml(file.path(root, "config", "sources.yml"))
sources <- config$sources
run_id <- utc_stamp()
log_rows <- list()

base_request <- function(url, timeout = timeout_seconds) {
  httr2::request(url) |>
    httr2::req_user_agent("vehicules-quebec/0.1 (open-data educational project)") |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_timeout(timeout)
}

serializable_headers <- function(response) {
  headers <- unclass(httr2::resp_headers(response))
  headers <- lapply(headers, as.character)
  headers[order(names(headers))]
}

log_row <- function(
    source,
    status,
    version_dir = NA_character_,
    details = NA_character_,
    n_records = NA_integer_,
    n_files = NA_integer_,
    bytes = NA_real_,
    sha256 = NA_character_) {
  tibble::tibble(
    collected_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    run_id = run_id,
    source_id = source$id %||% NA_character_,
    publisher = source$publisher %||% NA_character_,
    dataset_title = source$dataset_title %||% NA_character_,
    method = source$method %||% NA_character_,
    source_url = source$url %||% source$resource_page %||%
      source$dataset_page %||% NA_character_,
    resource_id = source$resource_id %||% NA_character_,
    license = source$license %||% NA_character_,
    status = status,
    version_dir = version_dir,
    n_records = n_records,
    n_files = n_files,
    bytes = bytes,
    sha256 = sha256,
    details = details
  )
}

collect_http_file <- function(source, version_dir) {
  if (!isTRUE(source$download_allowed)) {
    return(log_row(
      source, "manual_reference", version_dir,
      "Téléchargement automatique désactivé par la configuration."
    ))
  }
  if (isTRUE(source$large_file) && !include_large) {
    return(log_row(
      source, "manual_required_large_file", version_dir,
      "Relancer avec --include-large ou suivre references/MANUAL_DOWNLOAD.md."
    ))
  }

  destination <- file.path(version_dir, source$filename)
  if (file.exists(destination)) stop("Refus d'écraser : ", destination, call. = FALSE)
  temporary <- paste0(destination, ".part")
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)

  request_timeout <- if (isTRUE(source$large_file)) {
    large_timeout_seconds
  } else {
    timeout_seconds
  }
  response <- base_request(source$url, timeout = request_timeout) |>
    httr2::req_perform(path = temporary)
  httr2::resp_check_status(response)
  if (!file.rename(temporary, destination)) {
    stop("Impossible de finaliser le téléchargement : ", destination, call. = FALSE)
  }

  metadata <- list(
    source_id = source$id,
    retrieved_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    url = source$url,
    resource_page = source$resource_page %||% NULL,
    http_status = httr2::resp_status(response),
    response_headers = serializable_headers(response),
    filename = basename(destination),
    bytes = as.numeric(file.info(destination)$size),
    sha256 = sha256_file(destination),
    license = source$license %||% NULL,
    license_url = source$license_url %||% NULL
  )
  write_json_guarded(metadata, file.path(version_dir, "collection_metadata.json"))

  log_row(
    source, "downloaded", version_dir,
    n_files = 1L,
    bytes = metadata$bytes,
    sha256 = metadata$sha256
  )
}

collect_ckan_datastore <- function(source, version_dir) {
  if (!isTRUE(source$download_allowed)) {
    return(log_row(
      source, "manual_reference", version_dir,
      "Téléchargement automatique désactivé par la configuration."
    ))
  }

  offset <- 0L
  page_number <- 0L
  total <- NA_integer_
  page_paths <- character()
  field_names <- character()

  repeat {
    page_path <- file.path(version_dir, sprintf("page_%09d.json", offset))
    if (file.exists(page_path)) stop("Refus d'écraser : ", page_path, call. = FALSE)

    response <- base_request(source$api_endpoint) |>
      httr2::req_url_query(
        resource_id = source$resource_id,
        limit = page_size,
        offset = offset,
        sort = "_id asc"
      ) |>
      httr2::req_perform()
    httr2::resp_check_status(response)
    raw_body <- httr2::resp_body_raw(response)
    write_raw_no_overwrite(raw_body, page_path)
    page_paths <- c(page_paths, page_path)

    object <- jsonlite::fromJSON(rawToChar(raw_body), simplifyDataFrame = TRUE)
    if (!isTRUE(object$success)) {
      stop("L'API CKAN a retourné success=false pour : ", source$id, call. = FALSE)
    }
    if (is.na(total)) total <- as.integer(object$result$total)
    if (length(field_names) == 0L && !is.null(object$result$fields$id)) {
      field_names <- as.character(object$result$fields$id)
    }

    records <- object$result$records
    n_page <- if (is.data.frame(records)) nrow(records) else length(records)
    page_number <- page_number + 1L

    if (n_page == 0L || offset + n_page >= total) break
    offset <- offset + n_page
    Sys.sleep(0.15)
  }

  hashes <- vapply(page_paths, sha256_file, character(1))
  bytes <- sum(file.info(page_paths)$size)
  aggregate_hash <- digest::digest(
    paste(hashes, collapse = "|"),
    algo = "sha256",
    serialize = FALSE
  )
  metadata <- list(
    source_id = source$id,
    retrieved_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    api_endpoint = source$api_endpoint,
    dataset_page = source$dataset_page %||% NULL,
    resource_page = source$resource_page %||% NULL,
    resource_id = source$resource_id,
    sort = "_id asc",
    page_size = page_size,
    total_records_reported = total,
    pages = page_number,
    fields = field_names,
    page_files = basename(page_paths),
    page_sha256 = unname(hashes),
    aggregate_sha256 = aggregate_hash,
    bytes = bytes,
    license = source$license %||% NULL,
    license_url = source$license_url %||% NULL
  )
  write_json_guarded(metadata, file.path(version_dir, "collection_metadata.json"))

  log_row(
    source, "downloaded_api_pages", version_dir,
    n_records = total,
    n_files = length(page_paths),
    bytes = bytes,
    sha256 = aggregate_hash
  )
}

for (source_item in sources) {
  if (!isTRUE(source_item$enabled)) next

  version_dir <- file.path(root, "data_raw", source_item$id, run_id)
  if (dir.exists(version_dir)) {
    stop("Le dossier de collecte existe déjà : ", version_dir, call. = FALSE)
  }
  fs::dir_create(version_dir, recurse = TRUE)
  cli::cli_h2("Collecte : {source_item$id}")

  result <- tryCatch(
    {
      switch(
        source_item$method,
        http_file = collect_http_file(source_item, version_dir),
        ckan_datastore = collect_ckan_datastore(source_item, version_dir),
        manual_reference = log_row(
          source_item, "manual_reference", version_dir,
          source_item$notes %||% "Voir la fiche de source."
        ),
        log_row(
          source_item, "unsupported_method", version_dir,
          paste("Méthode inconnue :", source_item$method)
        )
      )
    },
    error = function(e) {
      warning("Échec pour ", source_item$id, " : ", conditionMessage(e), call. = FALSE)
      log_row(
        source_item, "failed", version_dir,
        paste0(conditionMessage(e), " Consultez references/MANUAL_DOWNLOAD.md.")
      )
    }
  )
  log_rows[[length(log_rows) + 1L]] <- result
}

collection_log <- dplyr::bind_rows(log_rows)
log_path <- file.path(root, "data_raw", paste0("collection_log_", run_id, ".csv"))
write_csv_guarded(collection_log, log_path, overwrite = FALSE)

cli::cli_alert_success("Journal écrit : {log_path}")
cli::cli_alert_info("Aucun fichier brut existant n'a été remplacé.")

if (any(collection_log$status == "failed")) {
  stop("Collecte incomplète : consulter le journal avant de nettoyer.", call. = FALSE)
}

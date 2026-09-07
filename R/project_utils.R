`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || all(is.na(x))) y else x
}

assert_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0L) {
    stop(
      "Paquets R manquants : ", paste(missing, collapse = ", "),
      "\nInstallez-les avant de relancer le script.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

project_root <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  required <- c("config/sources.yml", "scripts", "R")
  if (!all(file.exists(file.path(root, required)))) {
    stop(
      "Exécutez ce script depuis la racine du dépôt vehicules-quebec.",
      call. = FALSE
    )
  }
  root
}

utc_stamp <- function(time = Sys.time()) {
  format(time, tz = "UTC", format = "%Y%m%dT%H%M%SZ")
}

has_flag <- function(flag, args = commandArgs(trailingOnly = TRUE)) {
  flag %in% args
}

flag_value <- function(prefix, default = NULL, args = commandArgs(trailingOnly = TRUE)) {
  hits <- args[startsWith(args, paste0(prefix, "="))]
  if (length(hits) == 0L) return(default)
  sub(paste0("^", prefix, "="), "", hits[[length(hits)]])
}

create_project_dirs <- function(root = project_root()) {
  dirs <- c(
    "data_raw", "data_intermediate", "data_clean", "validation",
    "references", "docs", "config", "R", "scripts", "schemas"
  )
  fs::dir_create(file.path(root, dirs), recurse = TRUE)
  invisible(file.path(root, dirs))
}

write_raw_no_overwrite <- function(raw_value, path) {
  if (file.exists(path)) {
    stop("Refus d'écraser un fichier existant : ", path, call. = FALSE)
  }
  fs::dir_create(dirname(path), recurse = TRUE)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw_value, con)
  invisible(path)
}

write_lines_no_overwrite <- function(text, path) {
  if (file.exists(path)) {
    stop("Refus d'écraser un fichier existant : ", path, call. = FALSE)
  }
  fs::dir_create(dirname(path), recurse = TRUE)
  writeLines(text, con = path, useBytes = TRUE)
  invisible(path)
}

write_csv_guarded <- function(data, path, overwrite = FALSE, na = "") {
  fs::dir_create(dirname(path), recurse = TRUE)
  if (file.exists(path) && !isTRUE(overwrite)) {
    stop(
      "Le fichier existe déjà : ", path,
      "\nRelancez avec --overwrite-clean pour autoriser explicitement son remplacement.",
      call. = FALSE
    )
  }
  if (file.exists(path) && isTRUE(overwrite)) {
    warning("Remplacement explicitement autorisé : ", path, call. = FALSE)
  }
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  readr::write_csv(data, tmp, na = na)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) {
    stop("Échec du remplacement atomique de : ", path, call. = FALSE)
  }
  invisible(path)
}

write_json_guarded <- function(object, path, overwrite = FALSE, pretty = TRUE) {
  fs::dir_create(dirname(path), recurse = TRUE)
  if (file.exists(path) && !isTRUE(overwrite)) {
    stop("Le fichier existe déjà : ", path, call. = FALSE)
  }
  if (file.exists(path) && isTRUE(overwrite)) {
    warning("Remplacement explicitement autorisé : ", path, call. = FALSE)
  }
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  jsonlite::write_json(
    object, tmp, auto_unbox = TRUE, pretty = pretty,
    null = "null", na = "null"
  )
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) {
    stop("Échec du remplacement atomique de : ", path, call. = FALSE)
  }
  invisible(path)
}

sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

version_dirs <- function(root, source_id) {
  source_dir <- file.path(root, "data_raw", source_id)
  if (!dir.exists(source_dir)) return(character())
  dirs <- fs::dir_ls(source_dir, type = "directory", recurse = FALSE, fail = FALSE)
  if (length(dirs) == 0L) return(character())
  dirs <- dirs[grepl("^[0-9]{8}T[0-9]{6}Z$", basename(dirs))]
  sort(dirs, decreasing = TRUE)
}

latest_version_dir <- function(root, source_id, required_file = NULL) {
  dirs <- version_dirs(root, source_id)
  if (length(dirs) == 0L) return(NULL)

  if (!is.null(required_file)) {
    complete <- dirs[file.exists(file.path(dirs, required_file))]
    if (length(complete) == 0L) return(NULL)
    return(complete[[1L]])
  }

  nonempty <- dirs[vapply(
    dirs,
    function(path) length(fs::dir_ls(path, type = "file", recurse = FALSE, fail = FALSE)) > 0L,
    logical(1)
  )]
  if (length(nonempty) == 0L) return(NULL)
  nonempty[[1L]]
}

stable_hash <- function(..., n = 20L) {
  values <- list(...)
  key <- do.call(
    paste,
    c(lapply(values, function(x) ifelse(is.na(x), "<NA>", as.character(x))), sep = "|")
  )
  vapply(
    key,
    function(one) substr(digest::digest(one, algo = "sha256", serialize = FALSE), 1L, n),
    character(1)
  )
}

collapse_flags <- function(...) {
  parts <- list(...)
  n <- max(vapply(parts, length, integer(1)))
  parts <- lapply(parts, function(x) rep_len(ifelse(is.na(x), "", x), n))
  out <- vapply(seq_len(n), function(i) {
    vals <- unique(trimws(vapply(parts, `[[`, character(1), i)))
    vals <- vals[nzchar(vals)]
    if (length(vals) == 0L) NA_character_ else paste(vals, collapse = ";")
  }, character(1))
  out
}

safe_parse_double <- function(x) {
  suppressWarnings(readr::parse_double(
    as.character(x),
    na = c(
      "", "NA", "NaN", "N/A", "n/a", "s.o.", "S.O.",
      "not applicable", "Not applicable"
    ),
    locale = readr::locale(decimal_mark = "."),
    trim_ws = TRUE
  ))
}


parse_annotated_first_double <- function(x) {
  text <- as.character(x)
  text <- stringr::str_replace_all(text, ",", ".")
  token <- stringr::str_extract(text, "[-+]?[0-9]+(?:\\.[0-9]+)?")
  safe_parse_double(token)
}

parse_kwh_per_100km_annotation <- function(x) {
  text <- stringr::str_to_upper(as.character(x), locale = "en")
  text <- stringr::str_replace_all(text, ",", ".")
  # Ancien format : 2.5 (22.3 kWh/100 km).
  # Format mixte : 5.1 ([45.4 kWh + 0.0 L]/100 km).
  has_unit <- stringr::str_detect(text, "/\\s*100\\s*KM")
  value <- stringr::str_match(text, "([0-9]+(?:\\.[0-9]+)?)\\s*KWH")[, 2L]
  safe_parse_double(ifelse(has_unit, value, NA_character_))
}

parse_blended_l_per_100km_annotation <- function(x) {
  text <- stringr::str_to_upper(as.character(x), locale = "en")
  text <- stringr::str_replace_all(text, ",", ".")
  value <- stringr::str_match(text,
    "\\+\\s*([0-9]+(?:\\.[0-9]+)?)\\s*L\\]?\\s*/\\s*100\\s*KM")[, 2L]
  safe_parse_double(value)
}

safe_parse_integer <- function(x, tolerance = 1e-8) {
  value <- safe_parse_double(x)
  rounded <- round(value)
  valid <- !is.na(value) & is.finite(value) &
    abs(value - rounded) <= tolerance &
    rounded >= -.Machine$integer.max & rounded <= .Machine$integer.max
  out <- rep(NA_integer_, length(value))
  out[valid] <- as.integer(rounded[valid])
  out
}

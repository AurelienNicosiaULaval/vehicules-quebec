#!/usr/bin/env Rscript
# Construire les deux tables à utiliser en classe depuis les sorties auditées.
library(readr)
library(dplyr)
library(tibble)
library(jsonlite)
library(digest)
source("R/project_utils.R")

specs <- read_csv("data_clean/rncan_vehicle_specs.csv", show_col_types = FALSE)
required_measures <- c("engine_size_l", "cylinders", "city_l_per_100km",
                       "highway_l_per_100km", "combined_l_per_100km",
                       "combined_mpg_source", "co2_g_per_km", "co2_rating", "smog_rating")
eligible <- specs |>
  filter(model_year == 2025, rncan_source_family == "rncan_standard",
         fuel_type %in% c("regular_gasoline", "premium_gasoline"),
         if_all(all_of(required_measures), ~ !is.na(.x))) |>
  mutate(selection_hash = stable_hash("teaching_2025_v1", vehicle_id, n = 32L))

# Un modèle nommé ne contribue qu'une configuration. La première configuration
# selon le hash est retenue sans choisir manuellement une marque ou un résultat.
models <- eligible |>
  arrange(selection_hash, vehicle_id) |>
  distinct(make_key, model_key, .keep_all = TRUE)

# Tourniquet entre les strates classe et type de transmission.
selected <- models |>
  mutate(stratum = paste(vehicle_class_group, transmission_type, sep = "|"),
         stratum_hash = stable_hash("stratum_2025_v1", stratum, n = 32L)) |>
  group_by(stratum) |>
  arrange(selection_hash, vehicle_id, .by_group = TRUE) |>
  mutate(stratum_rank = row_number()) |>
  ungroup() |>
  arrange(stratum_rank, stratum_hash, selection_hash, vehicle_id) |>
  slice_head(n = 64L) |>
  arrange(make, model, vehicle_id)
stopifnot(nrow(selected) == 64L,
          !anyDuplicated(paste(selected$make_key, selected$model_key)))

# Le gallon américain vaut 3,785411784 L et le mille 1,609344 km.
# Conversion du débit publié et arrondi pour l'affichage, pas une nouvelle mesure.
us_mpg_constant <- 100 * 3.785411784 / 1.609344
small <- selected |>
  transmute(vehicle_id, make, model, model_year, vehicle_class, vehicle_class_group,
            engine_size_l, cylinders, transmission, transmission_type, fuel_type,
            city_l_per_100km, highway_l_per_100km, combined_l_per_100km,
            combined_mpg_imperial = combined_mpg_source,
            combined_mpg_us = round(us_mpg_constant / combined_l_per_100km, 4),
            co2_g_per_km, co2_rating, smog_rating)
stopifnot(!anyNA(small))
write_csv(small, "data_clean/vehicules_canada_2025.csv", na = "")

source <- read_json("data_raw/rncan_fcr_2025_en/20260702T183600Z/page_000000000.json",
                    simplifyVector = TRUE)$result$records
raw_selected <- source[match(selected$rncan_source_row_id, as.character(source$`_id`)), ]
stopifnot(nrow(raw_selected) == 64L, !anyNA(raw_selected$`_id`))
provenance <- bind_cols(
  selected |> select(vehicle_id, rncan_source_id, rncan_resource_id,
                     rncan_source_row_id, selection_hash, stratum, stratum_rank),
  as_tibble(raw_selected)
)
write_csv(provenance, "data_clean/vehicules_canada_2025_provenance.csv", na = "")
dir.create("data_source", showWarnings = FALSE)
file.copy("data_raw/rncan_fcr_2025_en/20260702T183600Z/page_000000000.json",
          "data_source/rncan_2025_snapshot.json", overwrite = TRUE)

exclusions <- specs |>
  transmute(vehicle_id, reason = case_when(
    vehicle_id %in% selected$vehicle_id ~ "retained",
    !vehicle_id %in% eligible$vehicle_id ~ "outside_2025_gasoline_complete_scope",
    !vehicle_id %in% models$vehicle_id ~ "another_configuration_of_same_named_model",
    TRUE ~ "not_selected_by_stratified_round_robin"
  ))
write_csv(exclusions, "validation/teaching_selection.csv")
write_csv(exclusions |> count(reason), "validation/teaching_selection_summary.csv")

# Compter les véhicules québécois par région et code de carburant. Les comptes
# sont additionnables; aucune moyenne de masse issue de groupes n'est utilisée.
regional <- read_csv("data_clean/saaq_registration_summary_by_region.csv",
  col_types = cols(.default = col_guess(), region_qc = col_character(),
                   saaq_fuel_code = col_character()), show_col_types = FALSE)
qc <- regional |>
  filter(is_light_vehicle_scope) |>
  group_by(saaq_snapshot_year, region_qc, saaq_fuel_code, saaq_fuel_type) |>
  summarise(number_registered_qc = sum(number_registered_qc), .groups = "drop") |>
  arrange(region_qc, saaq_fuel_code)
write_csv(qc, "data_clean/parc_quebec_2022.csv", na = "")
write_csv(regional |>
  group_by(is_light_vehicle_scope) |>
  summarise(number_registered_qc = sum(number_registered_qc), .groups = "drop"),
  "validation/saaq_scope_counts.csv")

dictionary <- tribble(
  ~variable, ~type, ~unit, ~description,
  "vehicle_id", "character", "", "Identifiant de la ligne RNCan dans la version figée; aucune immatriculation individuelle.",
  "make", "character", "", "Marque publiée par RNCan.",
  "model", "character", "", "Modèle et version tels que publiés; une configuration par couple marque-modèle nommé.",
  "model_year", "integer", "année", "Année modèle, constante à 2025; ce n'est pas l'année d'immatriculation.",
  "vehicle_class", "character", "", "Classe RNCan publiée dans le fichier source.",
  "vehicle_class_group", "character", "", "Regroupement documenté : passenger_car, suv, pickup, van ou wagon.",
  "engine_size_l", "double", "L", "Cylindrée du moteur thermique; ce n'est pas une puissance.",
  "cylinders", "integer", "cylindres", "Nombre de cylindres du moteur thermique.",
  "transmission", "character", "", "Code RNCan complet conservé, par exemple AS8 ou AV.",
  "transmission_type", "character", "", "Décodage du préfixe A, AM, AS, AV ou M; AM n'est pas une boîte manuelle conventionnelle.",
  "fuel_type", "character", "", "Essence ordinaire (regular_gasoline) ou super (premium_gasoline); ne suffit pas à distinguer tous les hybrides.",
  "city_l_per_100km", "double", "L/100 km", "Cote de consommation urbaine publiée; conditions d'essai normalisées.",
  "highway_l_per_100km", "double", "L/100 km", "Cote routière publiée; conditions d'essai normalisées.",
  "combined_l_per_100km", "double", "L/100 km", "Cote combinée publiée, fondée sur 55 % de parcours urbain et 45 % routier avant arrondi.",
  "combined_mpg_imperial", "double", "milles/gallon impérial", "Valeur entière publiée par RNCan; gallon impérial, différent de mtcars.",
  "combined_mpg_us", "double", "milles/gallon américain", "Conversion de combined_l_per_100km avec 235,214583333333; arrondie à quatre décimales, sans information nouvelle.",
  "co2_g_per_km", "double", "g/km", "CO2 à l'échappement publié; pas une analyse de cycle de vie; fortement lié à la consommation et au carburant.",
  "co2_rating", "double", "cote 1 à 10", "Cote ordinale CO2 publiée, 10 étant la meilleure cote.",
  "smog_rating", "double", "cote 1 à 10", "Cote ordinale des polluants contribuant au smog, 10 étant la meilleure cote."
)
stopifnot(identical(names(small), dictionary$variable))
write_csv(dictionary, "data_clean/vehicules_canada_2025_dictionary.csv", na = "")
qc_dictionary <- tribble(
  ~variable, ~type, ~description,
  "saaq_snapshot_year", "integer", "Année du portrait au 31 décembre, constante à 2022.",
  "region_qc", "character", "Libellé et code de région administrative tels que publiés, lus comme texte. Une région manquante reste manquante.",
  "saaq_fuel_code", "character", "Code SAAQ original du carburant; consulter references/saaq_fuel_codes.csv.",
  "saaq_fuel_type", "character", "Libellé du code de carburant issu de la documentation SAAQ; code manquant indiqué Non précisé.",
  "number_registered_qc", "integer", "Nombre de véhicules autorisés à circuler : type AU et classes PAU, CAU ou RAU. Ne couvre pas tous les usages de véhicules légers."
)
write_csv(qc_dictionary, "data_clean/parc_quebec_2022_dictionary.csv")
manifest <- list(
  version = "1.0.0", rncan_collection = "2026-07-02", rncan_model_year = 2025,
  source_rows = nrow(source), eligible_rows = nrow(eligible),
  distinct_named_models = nrow(models), selected_rows = nrow(small),
  selected_columns = ncol(small), qc_rows = nrow(qc),
  qc_vehicle_count = sum(qc$number_registered_qc),
  rule = "2025; standard RNCan; gasoline X/Z; complete core; one configuration per make/model by SHA256; round robin class x transmission; target=64",
  small_sha256 = sha256_file("data_clean/vehicules_canada_2025.csv"),
  qc_sha256 = sha256_file("data_clean/parc_quebec_2022.csv"),
  rncan_source_sha256 = sha256_file("data_source/rncan_2025_snapshot.json")
)
write_json(manifest, "validation/teaching_manifest.json", pretty = TRUE, auto_unbox = TRUE)
cat("Jeu principal :", nrow(small), "configurations et", ncol(small), "variables.\n")
cat("Parc québécois :", nrow(qc), "groupes et", sum(qc$number_registered_qc), "véhicules.\n")

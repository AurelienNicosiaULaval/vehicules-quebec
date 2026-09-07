# Exécuter depuis la racine de vehicules-quebec (ouvrir le fichier .Rproj).
library(readr)
library(dplyr)
library(ggplot2)

vehicules <- read_csv("data_clean/vehicules_canada_2025.csv",
  col_types = cols(.default = col_guess(), vehicle_id = col_character()))
class_labels <- c(passenger_car = "Automobiles", pickup = "Camionnettes",
                  suv = "VUS", van = "Fourgonnettes", wagon = "Familiales")
vehicules <- vehicules |>
  mutate(classe = factor(vehicle_class_group, levels = names(class_labels),
                         labels = unname(class_labels)))
portrait <- vehicules |>
  group_by(classe) |>
  summarise(n = n(), moyenne = mean(combined_l_per_100km),
            mediane = median(combined_l_per_100km),
            ecart_type = sd(combined_l_per_100km),
            minimum = min(combined_l_per_100km),
            maximum = max(combined_l_per_100km), .groups = "drop")
correlations <- vehicules |>
  group_by(classe) |>
  summarise(n = n(), correlation = cor(engine_size_l, combined_l_per_100km),
            .groups = "drop")
correlation_globale <- cor(vehicules$engine_size_l, vehicules$combined_l_per_100km)

palette_classes <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00")
theme_set(theme_minimal(base_size = 12))
distribution_plot <- ggplot(vehicules, aes(classe, combined_l_per_100km, fill = classe)) +
  geom_boxplot(width = 0.5, outlier.shape = NA, alpha = 0.55) +
  geom_point(position = position_jitter(width = 0.12, height = 0, seed = 20260907),
             size = 1.8, alpha = 0.75) +
  scale_fill_manual(values = palette_classes) +
  labs(x = NULL, y = "Consommation combinée (L/100 km)") +
  theme(legend.position = "none") + coord_flip()
scatter_plot <- ggplot(vehicules, aes(engine_size_l, combined_l_per_100km, colour = classe)) +
  geom_point(size = 2.4, alpha = 0.85) +
  scale_colour_manual(values = palette_classes) +
  labs(x = "Cylindrée (L)", y = "Consommation combinée (L/100 km)", colour = "Classe") +
  theme(legend.position = "bottom") + guides(colour = guide_legend(nrow = 2))

# Prolongement : un modèle descriptif simple et des résidus vérifiables.
modele <- lm(combined_l_per_100km ~ engine_size_l, data = vehicules)
coefficients <- tibble(terme = names(coef(modele)), estimation = unname(coef(modele)))
diagnostic <- vehicules |>
  transmute(vehicle_id, ajustement = fitted(modele), residu = residuals(modele))
residual_plot <- ggplot(diagnostic, aes(ajustement, residu)) +
  geom_hline(yintercept = 0, colour = "grey45", linetype = 2) +
  geom_point(colour = "#0072B2", size = 2) +
  labs(x = "Consommation ajustée (L/100 km)", y = "Résidu (L/100 km)")

# Chaque ligne est prédite par un modèle qui n'a pas utilisé cette ligne.
# Cette évaluation interne ne prouve pas une généralisation au parc québécois.
loo <- lapply(seq_len(nrow(vehicules)), function(i) {
  apprentissage <- vehicules[-i, ]
  validation <- vehicules[i, ]
  ajustement <- lm(combined_l_per_100km ~ engine_size_l, data = apprentissage)
  tibble(vehicle_id = validation$vehicle_id,
         observe = validation$combined_l_per_100km,
         prediction_lineaire = unname(predict(ajustement, newdata = validation)),
         prediction_moyenne = mean(apprentissage$combined_l_per_100km))
}) |> bind_rows()
validation_modele <- tibble(
  modele = c("Cylindrée seule", "Moyenne des 63 autres configurations"),
  rmse_loo = c(sqrt(mean((loo$observe - loo$prediction_lineaire)^2)),
               sqrt(mean((loo$observe - loo$prediction_moyenne)^2))))
dir.create("outputs", showWarnings = FALSE)
write_csv(portrait, "outputs/portrait_classes.csv")
write_csv(correlations, "outputs/correlations_classes.csv")
write_csv(coefficients, "outputs/coefficients_regression.csv")
write_csv(loo, "outputs/predictions_loo.csv")
write_csv(validation_modele, "outputs/validation_modele.csv")
ggsave("outputs/distributions.png", distribution_plot, width = 8, height = 5, dpi = 160)
ggsave("outputs/cylindree_consommation.png", scatter_plot, width = 8, height = 5.5, dpi = 160)
ggsave("outputs/residus.png", residual_plot, width = 8, height = 4.5, dpi = 160)
print(portrait)
print(validation_modele)
if (interactive()) print(scatter_plot)

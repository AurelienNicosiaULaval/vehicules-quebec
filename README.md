# Véhicules : données canadiennes et parc québécois

Un jeu pédagogique de 64 configurations de l’année modèle 2025, accompagné
d’une activité exploratoire en R et d’un portrait distinct du parc québécois.
Version 1.0.0, 7 septembre 2026.

## Commencer dans RStudio

1. Télécharger la [trousse pédagogique v1.0.0](https://github.com/AurelienNicosiaULaval/vehicules-quebec/releases/download/v1.0.0/vehicules-quebec-v1.0.0.zip).
2. Décompresser l’archive et ouvrir `vehicules-quebec.Rproj`.
3. Ouvrir `docs/explorer_les_vehicules.html` pour lire l’activité ou `examples/01_explorer_les_vehicules.R` pour exécuter le script.

L’archive contient les CSV, leurs dictionnaires, les sources utiles à leur
vérification, les références, le code et deux documents HTML autonomes.

```r
# Installer une seule fois : install.packages(c("readr", "dplyr", "ggplot2"))
library(readr)
library(dplyr)
library(ggplot2)

vehicules <- read_csv("data_clean/vehicules_canada_2025.csv",
  col_types = cols(.default = col_guess(), vehicle_id = col_character()))
vehicules |>
  group_by(vehicle_class_group) |>
  summarise(n = n(), consommation_mediane = median(combined_l_per_100km),
            .groups = "drop")
ggplot(vehicules, aes(engine_size_l, combined_l_per_100km, colour = vehicle_class_group)) +
  geom_point() +
  labs(x = "Cylindrée (L)", y = "Consommation combinée (L/100 km)", colour = "Classe") +
  theme_minimal()
```

Point d’arrêt : avoir importé les 64 configurations, produit le tableau et
le nuage de points. L’activité poursuit avec des distributions, les unités,
six exercices corrigés et une régression avec validation croisée facultative.
Elle a été exécutée techniquement; aucun essai en classe n’est revendiqué.

## Deux tables, deux unités d’observation

| Fichier | Contenu | Une ligne représente |
|---|---|---|
| [vehicules_canada_2025.csv](data_clean/vehicules_canada_2025.csv) | 64 configurations, 19 variables complètes | Une configuration RNCan, avec une seule configuration par modèle nommé et marque |
| [parc_quebec_2022.csv](data_clean/parc_quebec_2022.csv) | 152 groupes totalisant 5 507 330 véhicules dans le périmètre retenu | Une combinaison de région administrative et carburant déclaré |

Le premier fichier décrit le marché canadien. La présence des configurations
sélectionnées au Québec n’est pas confirmée. Les dénombrements SAAQ ne sont
pas attribués aux configurations RNCan : aucune correspondance de marque-modèle
et de configuration unique n’est vérifiée dans cette version.

Le portrait SAAQ porte sur les automobiles et camions légers de type `AU`
et de classes `PAU`, `CAU` ou `RAU`, autorisés à circuler au 31 décembre 2022.
Ce périmètre exclut d’autres usages et ne doit pas être présenté comme tout
le parc québécois. Une région non renseignée reste non renseignée. Les codes
de carburant inhabituels restent ceux du fichier administratif.

## Sélection du jeu principal

La source 2025 figée comprend 693 configurations. Parmi elles, 677 utilisent
l’essence ordinaire ou super et disposent de toutes les variables requises.
Les hybrides non rechargeables ne sont pas exclus; le nom du modèle ne suffit
pas à les identifier tous. Les véhicules électriques à batterie, les hybrides
rechargeables, le diesel et l’E85 sont hors de ce petit jeu.

Une configuration par marque et modèle nommé est d’abord choisie par un hash
stable, ce qui laisse 591 modèles. Un tourniquet entre les strates classe × type
de transmission retient ensuite 64 configurations. La règle ne choisit aucune
marque manuellement, n’impute aucune mesure et ne vise pas la représentativité
commerciale. Le bilan des exclusions est fourni dans `validation/`.

Le résultat comprend 19 automobiles, 16 VUS, 12 familiales, 9 camionnettes et
8 fourgonnettes. Les cinq types de transmission sont représentés.

## Ce que ce jeu apporte par rapport à mtcars

Il convient aux statistiques descriptives, aux comparaisons de groupes, aux
graphiques, aux corrélations et à une initiation à la régression. Les unités
sont documentées et les mesures sources de chaque configuration sont vérifiables.
L’année modèle unique évite de confondre une comparaison entre véhicules avec
une évolution sur plusieurs décennies.

Il ne reproduit pas toutes les variables de `mtcars` : la puissance thermique,
la masse, le temps sur un quart de mille et plusieurs caractéristiques mécaniques
ne sont pas disponibles dans cette source. Les colonnes de consommation et de
CO2 ne constituent pas autant de mesures indépendantes. Le jeu pédagogique
n’est pas un échantillon probabiliste du parc automobile.

La [documentation de R](https://stat.ethz.ch/R-manual/R-patched/library/datasets/html/mtcars.html)
précise que `mtcars$mpg` utilise le gallon américain. Le mpg publié dans la
source RNCan utilisée est impérial; `combined_mpg_us` est une conversion
explicitement dérivée de la consommation combinée. Une variable convertie
ne doit pas servir de prédicteur de la variable dont elle est calculée.

## Qualité et limites documentées

Les 64 lignes ont été rapprochées directement des cellules du JSON RNCan figé.
Les 152 comptes région-carburant ont été recalculés directement dans les
lignes brutes SAAQ. Le rapport détaille les contrôles, les empreintes et les limites.

Un petit écart de cohérence est conservé pour le Ford Maverick Hybrid : la cote
publiée est 6,2 L/100 km, tandis que 55 % de 5,6 et 45 % de 6,7 donnent 6,095.
L’écart de 0,105 dépasse légèrement la borne de 0,1 correspondant à un simple
arrondi au dixième des trois cotes. Sa cause n’est pas établie. Les trois
valeurs sont conservées telles que publiées et signalées dans
`validation/cote_combinee_review.csv`.

Les cotes sont issues de procédures d’essai normalisées; elles ne sont pas des
mesures de conduite quotidienne au Québec. Les émissions sont à l’échappement,
pas sur le cycle de vie. Une association descriptive ne démontre pas un effet causal.

## Tables détaillées et diversité des motorisations

La [publication v1.0.0](https://github.com/AurelienNicosiaULaval/vehicules-quebec/releases/tag/v1.0.0)
fournit aussi une archive de données complètes et une archive des sources figées.
Les scripts produisent 30 811 configurations RNCan de 1995 à 2026 et les agrégats
SAAQ provinciaux et régionaux. Le fichier historique `vehicules_quebec_small.csv`
conserve une sélection de diversité de 64 configurations, avec véhicules
électriques et hybrides rechargeables. Il possède de nombreuses colonnes de
provenance et des valeurs non applicables; il n’est pas le point d’entrée recommandé.
Son nom historique ne constitue pas une preuve de présence au Québec.

Les Le/100 km, kWh/100 km et L/100 km restent dans des colonnes distinctes.
Pour les PHEV, `blended_l_per_100km` conserve la composante liquide du mode
mixte lorsqu’elle est explicitement publiée, distincte du mode essence seul.
Les cotes 1995–2014 ajustées rétrospectivement ne sont pas de nouveaux essais
sur les véhicules anciens. Les étiquettes de classe françaises et anglaises
sont harmonisées par une table explicite; les valeurs sources sont conservées.

## Reproduction

Le [guide de reproduction](docs/reproduction.md) explique la validation portable,
la reconstruction complète depuis les sources figées et l’environnement R.
Les sources déjà recueillies en juin et juillet 2026 sont conservées : cette
version ne prétend pas inclure les mises à jour ultérieures de RNCan.
Le catalogue SAAQ consulté le 7 septembre 2026 propose toujours 2022 comme
millésime le plus récent de cette ressource CSV.

## Sources et licences

RNCan (2026), [Cotes de consommation de carburant](https://open.canada.ca/data/en/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64),
collecte du 2 juillet 2026, Licence du gouvernement ouvert – Canada.
SAAQ (2023), [Véhicules en circulation](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation),
portrait 2022, CC BY 4.0. Le code et les documents originaux sont sous MIT.
Voir [DATA_LICENSES.md](DATA_LICENSES.md), [CITATION.cff](CITATION.cff) et les
manifestes de `references/` pour les attributions et versions exactes.

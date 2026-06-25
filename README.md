# vehicules-quebec

Infrastructure reproductible pour construire un jeu pédagogique québécois et
canadien inspiré de `mtcars`, à partir de données ouvertes réelles de la SAAQ et
de Ressources naturelles Canada (RNCan).

> **État du dépôt :** échafaudage reproductible, sans valeurs inventées. Le
> dépôt fourni ne contient pas les fichiers administratifs volumineux ni un jeu
> prérempli. Les CSV propres sont produits par les scripts après collecte.

## Diagnostic en une phrase

Les spécifications, cotes de consommation et émissions RNCan sont directement
exploitables, et les comptes SAAQ sont directement calculables. En revanche, un
compte québécois ne peut pas être joint automatiquement à une configuration
RNCan : la SAAQ publie `MARQ_VEH` et `MODEL_VEH` comme codes alphanumériques de
cinq caractères. Plusieurs valeurs sont mnémotechniques, mais elles peuvent être
abrégées, tronquées ou normalisées et aucune table officielle ouverte de
correspondance complète n’a été vérifiée lors de l’audit du 2026-06-25. La SAAQ
ne publie pas non plus la transmission. Le projet laisse donc les comptes
manquants tant qu’une jointure unique n’est pas démontrée.

Le diagnostic détaillé se trouve dans [`docs/feasibility.md`](docs/feasibility.md).

## Produits

Après exécution, le dépôt peut produire :

| Fichier | Rôle |
|---|---|
| `data_clean/vehicules_quebec.csv` | Configurations RNCan et statut de liaison au Québec; compte SAAQ seulement pour une jointure unique auditée |
| `data_clean/vehicules_quebec_small.csv` | Environ 64 configurations sélectionnées de façon déterministe et stratifiée |
| `data_clean/rncan_vehicle_specs.csv` | Table RNCan normalisée, indépendante de la jointure québécoise |
| `data_clean/saaq_registration_summary.csv` | Agrégats provinciaux SAAQ par codes et caractéristiques |
| `data_clean/saaq_registration_summary_by_region.csv` | Même agrégation par région administrative |
| `data_intermediate/join_candidates.csv` | Candidats et contradictions, sans transfert automatique des comptes |
| `data_intermediate/unmatched_saaq.csv` | Groupes SAAQ non appariés ou ambigus |
| `data_clean/vehicules_quebec_dictionary.csv` | Dictionnaire des variables |
| `validation/*` | Résumés, valeurs manquantes et lignes à réviser |

## Grain des données

- **RNCan :** une ligne par configuration publiée dans une ressource de cotes.
- **SAAQ brut :** une ligne par véhicule autorisé à circuler au 31 décembre.
- **SAAQ propre :** une ligne par groupe de codes et caractéristiques, avec un
  compte dérivé par `n()`.
- **Table intégrée :** une ligne par configuration RNCan. Le compte SAAQ reste
  `NA` si plusieurs configurations sont possibles.

Le compte n’est jamais dupliqué entre transmissions, rouages ou versions.

## Installation R

R 4.3 ou plus récent est recommandé. Installer les dépendances :

```r
install.packages(c(
  "tidyverse", "readr", "readxl", "janitor", "stringr", "stringi",
  "dplyr", "lubridate", "arrow", "data.table", "fs", "yaml", "jsonlite",
  "digest", "httr2", "cli", "knitr", "quarto"
))
```

Quarto doit aussi être installé comme application système pour produire le
rapport HTML.

## Exécution

Depuis la racine du dépôt :

```bash
# 1. Collecte des ressources RNCan et de la documentation légère
Rscript scripts/01_collect_vehicle_sources.R

# 2. Collecte facultative du gros CSV SAAQ
Rscript scripts/01_collect_vehicle_sources.R --include-large

# 3. Nettoyage, agrégation et jointure prudente
Rscript scripts/02_clean_vehicle_data.R

# Autoriser explicitement le remplacement de sorties propres existantes
Rscript scripts/02_clean_vehicle_data.R --overwrite-clean

# 4. Rapport de validation
quarto render docs/validation_report.qmd
```

Le script de collecte crée un nouveau dossier horodaté pour chaque source et
n’écrase aucun brut. Le script de nettoyage refuse lui aussi de remplacer une
sortie, sauf avec `--overwrite-clean`.

L'échafaudage livré a fait l'objet de contrôles statiques, mais n'a pas été
exécuté de bout en bout dans son environnement de création, où R et Quarto
n'étaient pas disponibles. Les contrôles réalisés et ceux restant obligatoires
sont consignés dans [`docs/QA_NOTES.md`](docs/QA_NOTES.md).

## Petit jeu pédagogique

La cible par défaut est de 64 lignes. La sélection n’est pas une liste manuelle
de véhicules :

1. définir les catégories de couverture demandées (compactes, automobiles,
   VUS, camionnettes, hybride/PHEV, BEV, essence, ancien et récent);
2. sélectionner de façon gloutonne et déterministe les lignes couvrant le plus
   de catégories encore absentes, avec la preuve Québec puis `vehicle_id` comme
   bris d’égalité;
3. compléter en tourniquet par strate classe × motorisation × période;
4. dans chaque strate, placer les lignes Québec confirmées avant les lignes non
   confirmées, puis utiliser un ordre de hash stable;
5. conserver le statut `unconfirmed` lorsque la preuve de présence québécoise
   n’existe pas; le mode strict n’autorise que les lignes confirmées.

Pour exiger uniquement des lignes québécoises confirmées :

```bash
Rscript scripts/02_clean_vehicle_data.R --strict-small-qc
```

Ce mode peut produire moins de 30 lignes, voire aucune, tant que la table de
correspondance n’est pas disponible. Le script ne complète pas artificiellement
les cellules manquantes.

## Table de correspondance SAAQ

Copier le modèle :

```text
references/saaq_make_model_crosswalk_TEMPLATE.csv
```

vers :

```text
references/saaq_make_model_crosswalk.csv
```

Chaque entrée doit comporter une source, une plage d’années, une méthode de
vérification, une personne ou un processus responsable et le statut exact
`verified`. Toute autre entrée est exclue de la jointure admissible. Les règles
complètes sont dans [`references/join_rules.md`](references/join_rules.md).

## Principales décisions de nettoyage

- conserver les valeurs brutes et les codes dans des colonnes distinctes;
- traiter les codes SAAQ marque-modèle comme des identifiants administratifs,
  même lorsqu’ils ressemblent à des libellés lisibles;
- normaliser les chaînes uniquement pour les clés, sans supprimer les versions;
- ne pas traiter `NB_CYL = 9` de la SAAQ comme exactement neuf cylindres;
- convertir les cm³ SAAQ en litres dans une variable dérivée distincte;
- ne jamais placer des Le/100 km ou kWh/100 km dans une colonne L/100 km;
- conserver le mpg RNCan; si le champ source est absent, une dérivation
  facultative utilise `282,48 / L/100 km` et inscrit son origine;
- utiliser par défaut la ressource RNCan 1995–2014 ajustée rétrospectivement
  pour refléter approximativement la méthode à cinq cycles; signaler qu'il ne
  s'agit pas de nouveaux essais et conserver la ressource originale à deux
  cycles comme référence méthodologique séparée;
- extraire le rouage seulement si AWD, 4WD, 4X4, FWD ou RWD est explicitement
  présent dans le texte du modèle;
- laisser `body_type` manquant dans les sources centrales;
- ne pas imputer la puissance thermique, qui n’est pas publiée dans les sources
  centrales vérifiées;
- conserver tous les non-appariés et toutes les contradictions.

## Alternatives aux variables manquantes de `mtcars`

| Variable classique | Situation | Alternative honnête |
|---|---|---|
| Puissance (`hp`) | Non disponible pour les moteurs thermiques dans les sources centrales | `motor_kw` pour BEV/PHEV; cylindrée; cylindres; CO2 |
| Poids (`wt`) | Masse nette SAAQ disponible, mais non joignable sans correspondance; RNCan ne la publie pas | Statistiques de masse SAAQ pour jointures exactes; CVS facultatif pour masse à vide |
| Rouage | Pas de champ dédié RNCan/SAAQ | Jeton explicite dans le modèle, sinon `NA` |
| Type de carrosserie | Pas de champ détaillé commun | `vehicle_class`, `vehicle_class_group`; enrichissement externe sourcé |

## Structure du dépôt

```text
vehicules-quebec/
├── _quarto.yml             # Exécution du rapport depuis la racine
├── config/                 # Manifeste épinglé et paramètres
├── data_raw/               # Bruts immuables, hors Git
├── data_intermediate/      # Normalisations, candidats et non-appariés
├── data_clean/             # Sorties d’analyse
├── R/                      # Fonctions réutilisables
├── scripts/                # Pipelines exécutables 01 et 02
├── docs/                   # Faisabilité, activités, rapport Quarto
├── references/             # Codes, règles, modèles de correspondance
├── schemas/                # Schéma et dictionnaire
├── validation/             # Contrôles produits
├── data_dictionary.csv     # Dictionnaire source du projet
├── LICENSE                 # MIT pour le code; données non relicenciées
└── CITATION.cff            # Citation à personnaliser
```

### Rôle des dossiers demandés

- `data_raw/` : réponses API et fichiers originaux, horodatés et hachés;
- `data_intermediate/` : objets reproductibles utiles à l’audit;
- `data_clean/` : produits stables destinés aux cours;
- `R/` : fonctions de lecture, normalisation, jointure, échantillonnage et
  validation;
- `scripts/` : points d’entrée exécutables;
- `docs/` : diagnostic, activités et rapport;
- `references/` : documentation, codebooks et décisions de correspondance.

## Licences et attribution

Le code du dépôt est offert sous MIT. Les données ne sont pas relicenciées : la
SAAQ/Données Québec est attribuée selon CC BY 4.0 – Québec et les ressources
fédérales selon la Licence du gouvernement ouvert – Canada. Les URL, dates de
récupération, identifiants de ressource et sommes SHA-256 sont consignés par la
collecte.

## Travaux manuels encore requis

1. confirmer, avant publication, s’il existe un millésime SAAQ postérieur à
   2022 et mettre à jour le manifeste sans remplacer silencieusement la source;
2. télécharger le CSV SAAQ volumineux ou activer `--include-large`;
3. obtenir auprès d’une source réutilisable une table de décodage des codes
   marque-modèle, ou accepter que les comptes restent non attribués;
4. réviser les jointures ambiguës, surtout lorsque plusieurs transmissions ou
   rouages RNCan existent;
5. décider si l’enrichissement Transports Canada CVS est nécessaire et auditer
   ses doublons de versions;
6. examiner le rapport de validation et documenter chaque exclusion éventuelle;
7. décider si les analyses historiques utilisent les cotes 1995–2014 ajustées
   ou originales, et ne jamais les fusionner comme si elles provenaient de la
   même procédure d'essai;
8. compléter l’auteur, le dépôt et éventuellement le DOI dans `CITATION.cff`;
9. publier une version figée avec les sommes de contrôle et l’attribution de
   toutes les sources.

## Activités d’enseignement

Huit activités prêtes à adapter sont décrites dans
[`docs/pedagogical_activities.md`](docs/pedagogical_activities.md).

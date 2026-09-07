# Reproduire la version 1.0.0

## Utiliser la trousse

Télécharger [vehicules-quebec-v1.0.0.zip](https://github.com/AurelienNicosiaULaval/vehicules-quebec/releases/download/v1.0.0/vehicules-quebec-v1.0.0.zip),
décompresser et ouvrir `vehicules-quebec.Rproj`. Les deux fichiers HTML de
`docs/` s’ouvrent sans installer R. Le script de l’activité se lance depuis
la racine du projet.

Pour exécuter l’activité et le contrôle portable, installer les dépendances :

```r
install.packages(c("readr", "dplyr", "ggplot2", "knitr", "jsonlite", "digest"))
source("examples/01_explorer_les_vehicules.R")
source("scripts/04_validate_release.R")
```

Le contrôle portable compare directement les mesures des 64 configurations
au JSON 2025 livré et vérifie les fichiers liés au certificat de l’audit SAAQ.
Il ne prétend pas relire les sept millions de lignes administratives sans
leur archive source. Le script de l’activité écrit ses résultats dans `outputs/`.

L’environnement validé utilise R 4.5.0. `renv.lock` enregistre les versions des
paquets. Pour reconstruire cet environnement dans le projet :

```r
install.packages("renv")
renv::restore(prompt = FALSE)
renv::activate()
```

Les bibliothèques système requises par certains paquets dépendent de la
plateforme. Le fichier `validation/session_info.txt` décrit l’environnement
qui a effectivement exécuté la validation complète.

## Reconstruction complète

Cloner le dépôt par SSH ou utiliser la trousse, puis télécharger
[sources-vehicules-v1.0.0.zip](https://github.com/AurelienNicosiaULaval/vehicules-quebec/releases/download/v1.0.0/sources-vehicules-v1.0.0.zip).
Décompresser cette archive à la racine du projet; elle contient `data_raw/`.
Le manifeste `references/frozen_files.csv` permet de vérifier chaque fichier.
Le script suivant automatise cette récupération avec vérification de l’archive :

```r
source("scripts/00_download_frozen_sources.R")
```

L’archive comprend un CSV SAAQ d’environ 905 Mo une fois décompressé. Prévoir
plusieurs gigaoctets de mémoire et d’espace libre pour la reconstruction complète.
Les dépendances sont listées au début des scripts 01 et 02 et dans `renv.lock`.

Depuis la racine du projet, les commandes suivantes exécutent le pipeline :

```sh
Rscript scripts/02_clean_vehicle_data.R --overwrite-clean
Rscript scripts/03_build_teaching_data.R
Rscript scripts/04_validate_release.R --from-source
Rscript tests/check_core.R
Rscript examples/01_explorer_les_vehicules.R
quarto render
```

`--overwrite-clean` autorise le remplacement des sorties calculées; les bruts
restent inchangés. Le mode complet compare les comptes région-carburant aux
lignes brutes SAAQ et contrôle toutes les empreintes. Les sorties du pipeline
historique comprennent les données RNCan complètes et les agrégats SAAQ détaillés.
Le script 03 construit ensuite les deux tables destinées à l’enseignement.

Quarto doit être installé pour reconstruire les HTML. Les deux `.qmd` incluent
`embed-resources: true`. Le rendu s’exécute depuis la racine du projet.

## Collecter une nouvelle version

Le script `01_collect_vehicle_sources.R` sert à une collecte ultérieure, pas à
reproduire exactement la version 1.0.0. Il crée des dossiers horodatés et
conserve les réponses originales. Les ressources et leur schéma peuvent évoluer;
une nouvelle collecte demande une nouvelle révision et une nouvelle version.
Le nettoyage sélectionne la collecte complète la plus récente disponible.

Les identifiants contenant `_en` sont historiques. La langue réelle des colonnes
et classes des fichiers figés est reconnue et documentée. Le rapprochement
SAAQ–RNCan reste désactivé tant qu’aucune table de correspondance vérifiée ne
permet d’établir une configuration unique. Le mode `--strict-small-qc` concerne
uniquement l’ancien petit jeu de diversité et peut produire zéro ligne.

## Empreintes et publication

`SHA256SUMS.txt` vérifie les archives et documents de la publication.
`checksums_repo.txt` vérifie les fichiers de la trousse. L’archive
`donnees-completes-vehicules-v1.0.0.zip` fournit les sorties détaillées du
pipeline sans obliger à les recalculer. Les cotes source demeurent figées;
aucune modification ne doit être apportée silencieusement à une publication.

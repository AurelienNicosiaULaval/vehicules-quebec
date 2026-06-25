# Notes d'assurance qualité de l'échafaudage

**Date : 2026-06-25**

## Contrôles effectués dans l'environnement de production de l'artefact

- lecture valide de `_quarto.yml`, `config/project.yml` et
  `config/sources.yml` avec un analyseur YAML;
- largeur constante, en-têtes uniques et encodage UTF-8 vérifiés pour tous les
  CSV versionnés;
- identité octet par octet de `data_dictionary.csv` et
  `schemas/vehicules_quebec_schema.csv`;
- présence et unicité des 73 variables documentées;
- cohérence des identifiants et métadonnées principales entre
  `config/sources.yml` et `references/sources.csv`;
- existence des liens internes Markdown et des fichiers obligatoires;
- équilibre des parenthèses, accolades, crochets et chaînes dans les fichiers R
  et Quarto au moyen d'un analyseur lexical statique;
- absence intentionnelle de lignes de véhicules préremplies dans `data_clean/`.

## Contrôle restant obligatoire

R, Rscript et Quarto n'étaient pas installés dans l'environnement ayant produit
cet échafaudage. Les scripts n'ont donc pas été exécutés de bout en bout ici.
Avant une publication, exécuter au minimum :

```bash
Rscript scripts/01_collect_vehicle_sources.R
Rscript scripts/02_clean_vehicle_data.R
quarto render docs/validation_report.qmd
```

Réviser ensuite `validation/`, les journaux de collecte, les sommes SHA-256 et
les cas non appariés. Une exécution réussie ne remplace pas la validation
humaine de la table de correspondance SAAQ.

# Sources, licences et attribution

## Ressources naturelles Canada

Ressources naturelles Canada (2026), Cotes de consommation de carburant,
[Portail du gouvernement ouvert](https://open.canada.ca/data/en/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64).
Six ressources ont été recueillies le 2 juillet 2026. Leurs métadonnées
originales, identifiants et empreintes sont conservés dans les sources figées.

Contient de l’information visée par la
[Licence du gouvernement ouvert – Canada](https://ouvert.canada.ca/fr/licence-du-gouvernement-ouvert-canada).
Les données sont reproduites et adaptées : normalisation des noms de colonnes,
décodage documenté des classes et transmissions, sélection pédagogique et
conversion explicitement indiquée en mpg américain. Les valeurs de consommation
publiées ne sont pas corrigées ou imputées. Le projet n’est pas une publication
officielle de RNCan et ne suggère aucun endossement.

## Société de l’assurance automobile du Québec

SAAQ (2023), [Véhicules en circulation](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation),
portrait au 31 décembre 2022. Documentation du 30 novembre 2023.
Licence [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/),
telle que déclarée dans le catalogue Données Québec.

Adaptations : sélection du type AU et des classes PAU, CAU et RAU, regroupement
par région et carburant, addition des effectifs, décodage des carburants selon
la documentation. Les codes et régions manquantes sont conservés. Aucune ligne
ne reçoit une correspondance RNCan non vérifiée. Le projet n’est pas une
publication officielle de la SAAQ et ne suggère aucun endossement.

## Code et documents du projet

Aurélien Nicosia (2026), Véhicules : données canadiennes et parc québécois,
version 1.0.0, [dépôt source](https://github.com/AurelienNicosiaULaval/vehicules-quebec).
Le code et les documents originaux du projet sont sous licence MIT, décrite
dans `LICENSE`. Les fichiers sources conservent leurs licences respectives.
Aucun DOI n’est attribué à cette version.

## Provenance

- `references/frozen_files.csv` : fichiers bruts exacts, tailles et empreintes SHA-256.
- `data_clean/vehicules_canada_2025_provenance.csv` : correspondance entre les 64 configurations, leurs lignes originales et leur sélection.
- `data_source/rncan_2025_snapshot.json` : réponse originale contenant les 693 configurations de 2025.
- `references/catalogue_checks_20260907/saaq.json` : métadonnées du catalogue SAAQ consultées le 7 septembre 2026.

Les identifiants techniques de certaines ressources se terminent historiquement
par `_en`, bien que le contenu figé soit en français pour 1995–2014 et les
véhicules électriques. Ces identifiants sont conservés pour la traçabilité;
le traitement reconnaît les colonnes et classes effectivement présentes.

> Document de conception du 25 juin 2026. Pour la version publiée et la procédure actuelle, consulter le README et docs/reproduction.md.

# Étapes manuelles de collecte

## 1. Fichier SAAQ volumineux

Le script ne télécharge pas par défaut le CSV SAAQ, car les millésimes peuvent
faire plusieurs centaines de mégaoctets. Deux options :

```bash
Rscript scripts/01_collect_vehicle_sources.R --include-large
```

ou télécharger le fichier officiel indiqué dans `config/sources.yml`, puis le
placer, sans le modifier, dans un dossier horodaté :

```text
data_raw/saaq_vehicles_2022/AAAAMMJJThhmmssZ/Vehicule_En_Circulation_2022.csv
```

Calculer ensuite sa somme SHA-256 et consigner la date, l’URL et la licence dans
un fichier de journal. Ne pas renommer le fichier de façon à perdre le millésime.

## 2. Vérification d’un millésime SAAQ plus récent

La fiche du jeu peut être modifiée sans qu’un nouveau CSV annuel soit publié.
Avant une version officielle du jeu pédagogique, inspecter la liste des
ressources et confirmer explicitement le dernier millésime disponible. Ne pas
remplacer silencieusement le millésime épinglé dans `config/sources.yml`.

## 3. Table de correspondance SAAQ marque-modèle

La documentation vérifiée décrit `MARQ_VEH` et `MODEL_VEH` comme des codes de
cinq caractères. Plusieurs valeurs sont lisibles ou mnémotechniques, mais elles
peuvent être tronquées et ne constituent pas à elles seules une correspondance
avec les libellés détaillés de RNCan. Aucune table officielle ouverte de
correspondance complète n’a été trouvée lors de l’audit du 2026-06-25. Une
correspondance ne doit être ajoutée que si elle possède :

- une source vérifiable et légalement réutilisable;
- une plage de millésimes;
- une méthode de vérification;
- un statut `verified`;
- le nom de la personne ou du processus ayant validé l’entrée.

Copier le modèle `saaq_make_model_crosswalk_TEMPLATE.csv` vers
`saaq_make_model_crosswalk.csv`. Les entrées non vérifiées sont exclues de la
jointure exacte.

## 4. Source facultative Transports Canada

Le jeu Canadian Vehicle Specifications peut apporter des dimensions et une
masse à vide, mais la jointure année-marque-modèle peut être multiple. Télécharger
les ressources pertinentes depuis la fiche officielle, conserver les fichiers
bruts, puis ajouter une étape d’enrichissement distincte. Ne jamais utiliser une
moyenne de versions comme masse d’un véhicule réel sans l’indiquer.

## 5. Deux séries RNCan pour 1995–2014

Le pipeline active la ressource RNCan ajustée rétrospectivement pour refléter
approximativement la procédure à cinq cycles. RNCan précise que les véhicules
n'ont pas été retestés. La ressource officielle de cotes originales à deux
cycles est conservée dans le manifeste comme référence désactivée.

Pour une analyse de sensibilité, collecter cette ressource dans un dossier brut
distinct et ajouter une variable de série méthodologique. Ne pas concaténer les
deux séries comme s'il s'agissait de véhicules différents, et ne pas écraser
une cote ajustée par une cote originale sans enregistrer la décision.


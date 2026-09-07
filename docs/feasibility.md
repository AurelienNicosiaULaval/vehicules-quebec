> Document de conception du 25 juin 2026. Pour la version publiée et la procédure actuelle, consulter le README et docs/reproduction.md.

# Diagnostic de faisabilité

Date de vérification : 2026-06-25
Conclusion : faisable seulement partiellement sans nouvelle table de
correspondance; faisable avec jointures auditées pour un sous-ensemble.

## 1. Résultat principal

Un équivalent exact de `mtcars` où chaque ligne serait une configuration
marque–modèle–année réellement immatriculée au Québec, avec son nombre
d’immatriculations et ses cotes RNCan, n’est pas directement constructible à
partir des seules ressources ouvertes vérifiées.

La raison n’est pas l’absence de données mécaniques : la SAAQ fournit notamment
l’année-modèle, le carburant, la cylindrée, le nombre de cylindres et la masse
nette. Le blocage est l’identification : `MARQ_VEH` et `MODEL_VEH` sont des codes
alphanumériques de cinq caractères. Certaines valeurs ressemblent directement à
une marque ou à un modèle, mais la largeur fixe entraîne des abréviations, des
troncatures et des conventions propres à la SAAQ. Aucune table officielle
ouverte de correspondance complète n’a été repérée lors de l’audit. De plus, la
SAAQ ne publie pas la transmission, alors que RNCan distingue fréquemment
plusieurs configurations d’un même modèle. Même une correspondance
marque–modèle ne suffit donc pas toujours à attribuer un compte québécois à une
version RNCan précise.

Le projet adopte par conséquent trois niveaux :

1. Spécifications RNCan exactes : une ligne par configuration publiée pour
   le marché canadien.
2. Agrégats SAAQ exacts : comptes québécois par codes et caractéristiques
   administratives, sans décodage inventé.
3. Table intégrée prudente : le compte SAAQ est rempli seulement lorsqu’une
   table de correspondance sourcée conduit à un candidat RNCan unique et sans
   contradiction de caractéristiques. Tous les autres comptes restent `NA`.

## 2. Sources vérifiées

| Source | Organisme | Type | Portée vérifiée | Licence | Usage prévu |
|---|---|---|---|---|---|
| [Véhicules en circulation](https://www.donneesquebec.ca/recherche/dataset/vehicules-en-circulation) | SAAQ / Données Québec | CSV annuels + PDF | Portrait au 31 décembre; ressources annuelles vérifiées jusqu’en 2022 | CC BY 4.0 – Québec | Parc québécois, région, carburant, cylindrée, cylindres, masse, comptes |
| [Documentation SAAQ](https://www.donneesquebec.ca/recherche/dataset/4aea7984-10ec-4d4f-80e4-5bb9a0006996/resource/00ea3ac1-da3c-4ece-aa8c-a2e88529447b/download/vehicules-circulation-documentation.pdf) | SAAQ | PDF | Dictionnaire des champs et modalités | Même fiche de jeu | Décodage des variables SAAQ |
| [Fuel consumption ratings](https://open.canada.ca/data/en/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64) | RNCan | CSV + CKAN DataStore API | 1995–2026; ressources distinctes BEV et PHEV | Licence du gouvernement ouvert – Canada | Marque, modèle, classe, moteur, transmission, consommation, CO2 |
| [Original Fuel Consumption Ratings 1995–2014](https://open.canada.ca/data/en/dataset/98f1a129-f628-4ce4-b24d-6f16bf24dd64/resource/29bcf157-9297-4d6a-9695-dfd816bc32ca) | RNCan | CSV + CKAN DataStore API | Cotes historiques originales à deux cycles; non combinées par défaut | Licence du gouvernement ouvert – Canada | Analyse de sensibilité méthodologique |
| [2026 Fuel Consumption Guide](https://natural-resources.canada.ca/energy-efficiency/transportation-energy-efficiency/fuel-consumption-guide) | RNCan | Page web / guide | Méthode et interprétation des cotes courantes | Conditions du gouvernement du Canada | Méthodologie, unités et limites |
| [Canadian Vehicle Specifications](https://open.canada.ca/data/en/dataset/913f8940-036a-45f2-a5f2-19bde76c1252) | Transports Canada | CSV / API | Dimensions et masse à vide par année-marque-modèle | Licence du gouvernement ouvert – Canada | Enrichissement facultatif; jointure potentiellement multiple |

Les identifiants de ressources RNCan et les URL épinglées sont consignés dans
`config/sources.yml`. Ils doivent être revérifiés lors d’une nouvelle version.

## 3. Matrice des champs

Légende : Oui = champ directement publié; Codé = publié mais non
interprétable comme libellé sans table; Dérivé = calcul ou regroupement
explicite; Non = absent de la source centrale.

| Champ | SAAQ | RNCan standard | RNCan BEV/PHEV | Transports Canada CVS |
|---|---:|---:|---:|---:|
| Marque | Codé, 5 caractères (`MARQ_VEH`; souvent abrégé) | Oui | Oui | Oui |
| Modèle | Codé, 5 caractères (`MODEL_VEH`; souvent tronqué) | Oui | Oui | Oui |
| Année-modèle | Oui | Oui | Oui | Oui |
| Type/classe de véhicule | Oui, catégories SAAQ | Oui | Oui | Partiel selon ressource |
| Carburant/propulsion | Oui depuis 2017 | Oui | Oui | Non central |
| Consommation ville | Non | Oui, L/100 km | Oui, unités propres au mode | Non |
| Consommation route | Non | Oui, L/100 km | Oui, unités propres au mode | Non |
| Consommation combinée | Non | Oui | Oui | Non |
| mpg combiné | Non | Oui, gallon impérial | Selon ressource | Non |
| Émissions de CO2 | Non | Oui | Oui | Non |
| Cote CO2 | Non | Oui pour les années visées | Oui | Non |
| Cote smog | Non | Oui pour les années visées | Oui | Non |
| Cylindrée | Oui, cm³ | Oui, L | Oui pour PHEV; non applicable BEV | Non central |
| Nombre de cylindres | Oui, code 1–8; 9 = autre | Oui | Oui pour PHEV; non applicable BEV | Non central |
| Transmission | Non | Oui | Oui | Non central |
| Rouage | Non dédié | Non dédié; parfois dans le texte du modèle | Même limite | Non garanti |
| Masse/poids | Oui, masse nette | Non | Non | Masse à vide, selon ressource |
| Région québécoise | Oui | Non | Non | Non |
| Nombre immatriculé | Dérivé par comptage | Non | Non | Non |
| Puissance thermique | Non | Non | Non | Non vérifiée |
| Puissance électrique | Non | Non | Motor (kW) | Non central |

## 4. Possibilité de jointure

### Jointure directe

Non, pas de façon générale. Quelques codes SAAQ peuvent coïncider avec un
libellé RNCan après normalisation, mais cette coïncidence n’est pas une table de
correspondance et ne règle ni les troncatures ni les variantes. Une jointure par
année, cylindrée et cylindres seulement est souvent plusieurs-à-plusieurs et ne
démontre pas l’identité d’un véhicule.

### Jointure avec table de correspondance vérifiée

Oui, pour un sous-ensemble, sous les conditions suivantes :

- correspondance code SAAQ → marque/modèle avec source, millésimes et statut de
  vérification;
- année-marque-modèle identiques après normalisation conservatrice;
- aucune contradiction de carburant, cylindres ou cylindrée;
- un seul candidat RNCan au niveau de la configuration;
- aucun partage arbitraire d’un compte SAAQ entre transmissions ou rouages.

### Jointure candidate, non probante

Une table de candidats peut utiliser l’année, le carburant, les cylindres, la
cylindrée et la classe. Elle est utile pour le contrôle manuel, mais ses comptes
ne doivent pas être copiés dans le jeu final. Le dépôt sépare donc
`join_candidates.csv` de `vehicules_quebec.csv`.

## 5. Difficultés de nettoyage

- fichiers SAAQ très volumineux; traitement paresseux avec Arrow recommandé;
- variables SAAQ parfois codées et modalités historiques;
- carburant SAAQ indisponible avant le portrait 2017;
- code `NB_CYL = 9` signifiant « autre », et non exactement neuf cylindres;
- cylindrée SAAQ en cm³ contre affichage RNCan en litres arrondis;
- différences de grain : véhicule individuel SAAQ, configuration d’essai RNCan;
- plusieurs transmissions, rouages ou versions RNCan pour un même modèle;
- ressources BEV/PHEV avec kWh/100 km et Le/100 km, qui ne doivent pas être
  placés dans les colonnes L/100 km;
- cotes et méthodologie variables selon l’année : les véhicules antérieurs au
  millésime 2015 ont été testés avec la procédure à deux cycles, tandis que les
  millésimes 2015 et suivants utilisent cinq cycles;
- la ressource 1995–2014 activée dans le pipeline contient les cotes ajustées
  rétrospectivement par RNCan pour refléter approximativement la procédure à
  cinq cycles; les véhicules n'ont pas été retestés. Une ressource officielle
  distincte conserve les cotes originales à deux cycles;
- classes RNCan et catégories SAAQ ne représentent pas exactement le même
  concept;
- les émissions RNCan sont des émissions à l’échappement, pas une empreinte de
  cycle de vie;
- certains véhicules lourds ne sont pas couverts par le programme RNCan des
  véhicules légers.

## 6. Limites pédagogiques

Le jeu est excellent pour enseigner les données manquantes, la provenance, les
unités, la régression et les jointures imparfaites. Il est moins adapté à une
analyse causale ou à une estimation représentative du parc sans pondérations et
sans taux de jointure suffisants. Comparer directement des millésimes avant et
après 2015 doit inclure une discussion sur le changement de procédure d’essai
et sur le statut approximatif des cotes 1995–2014 ajustées. Les cotes ajustées
et originales ne doivent pas être mélangées sans variable de provenance. Les
BEV ne doivent pas recevoir artificiellement une consommation de carburant
liquide; utiliser kWh/100 km ou Le/100 km dans des analyses séparées.

## 7. Recommandation finale

| Produit | Faisabilité | Recommandation |
|---|---|---|
| Table RNCan comparable à `mtcars` pour caractéristiques/consommation | Faisable directement | Produire `rncan_vehicle_specs.csv` |
| Agrégat du parc québécois avec mécanique et région | Faisable directement | Produire `saaq_registration_summary*.csv` |
| Configurations RNCan avec nombre exact immatriculé au Québec | Faisable seulement partiellement | Remplir uniquement les jointures uniques et auditées |
| Petit jeu pédagogique diversifié | Faisable | Échantillonnage déterministe, statut Québec explicite |
| Véritable clone de `mtcars` avec puissance et poids par version | Non faisable avec les sources centrales seules | Utiliser moteur kW, masse SAAQ agrégée ou CVS facultatif; laisser la puissance thermique absente |

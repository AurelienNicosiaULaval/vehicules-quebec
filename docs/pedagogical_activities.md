> Document de conception du 25 juin 2026. Pour la version publiée et la procédure actuelle, consulter le README et docs/reproduction.md.

# Activités pédagogiques proposées

Chaque activité doit commencer par la lecture de `join_quality`,
`qc_presence_status`, `data_quality_flag` et du dictionnaire. Les valeurs
manquantes ne sont pas des zéros.

## 1. Exploration descriptive de la consommation

Niveau : STT-1100 / cours R

- Calculer moyenne, médiane, quartiles et écart-type de
  `combined_l_per_100km` par `vehicle_class_group`.
- Produire histogrammes, boîtes à moustaches et tableaux de fréquences.
- Comparer moyenne et médiane en présence d’asymétrie.
- Question de méthode : pourquoi les BEV sont-ils absents de cette variable et
  pourquoi ne faut-il pas remplacer leurs valeurs par zéro?

## 2. Régression de la consommation

Niveau : STT-2200

- Sous-échantillonner les véhicules thermiques avec cylindrée connue.
- Ajuster `combined_l_per_100km ~ engine_size_l + cylinders + vehicle_class_group`.
- Examiner résidus, interactions et colinéarité cylindrée–cylindres.
- Comparer un modèle simple et un modèle avec effets de classe.
- Limite à discuter : les lignes RNCan sont des configurations, non un
  échantillon aléatoire des véhicules effectivement conduits au Québec.

## 3. Essence, hybride et électrique

Niveau : STT-1100 / STT-2200

- Construire des groupes avec `powertrain_group`.
- Comparer séparément L/100 km, kWh/100 km et Le/100 km.
- Pour une comparaison énergétique commune, utiliser uniquement
  `combined_le_per_100km` lorsque la source le publie; ne pas convertir sans
  règle documentée.
- Discuter émissions à l’échappement et émissions de cycle de vie.
- Vérifier la couverture des HEV, dont l’identification peut provenir du texte
  du modèle et reste explicitement signalée.

## 4. Visualisation consommation–émissions

Niveau : cours R / STT-1100

- Nuage de points `combined_l_per_100km` contre `co2_g_per_km`.
- Ajouter forme ou facette par carburant et classe de véhicule.
- Décrire la relation, les groupes et les valeurs atypiques sans les supprimer.
- Comparer corrélation globale et corrélations par carburant.
- Expliquer pourquoi une forte association ne constitue pas une preuve causale.

## 5. Analyse en composantes principales

Niveau : STT-2200 / science des données

- Choisir un sous-ensemble cohérent de variables numériques : cylindrée,
  cylindres, consommations, CO2 et cotes.
- Standardiser les variables et documenter le traitement des lignes
  incomplètes; aucune imputation ne doit être implicite.
- Interpréter les charges et la carte des configurations.
- Refaire l’ACP avec et sans variables presque redondantes pour discuter de la
  sensibilité.
- Ne pas mélanger automatiquement L/100 km, kWh/100 km et Le/100 km.

## 6. Classification du type de véhicule

Niveau : science des données / projet avancé

- Prédire `vehicle_class_group` à partir des caractéristiques numériques et du
  carburant.
- Séparer entraînement/test par année-modèle ou par marque pour réduire la fuite
  d’information.
- Comparer arbre, régression multinomiale ou k plus proches voisins.
- Évaluer matrice de confusion, rappel par classe et déséquilibre.
- Discuter le fait que `vehicle_class_group` est lui-même un regroupement dérivé
  de la classe RNCan.

## 7. Comparaison avec `mtcars`

Niveau : cours R / STT-1100

- Harmoniser temporairement les unités : mpg impérial RNCan et mpg américain de
  `mtcars` ne doivent pas être confondus.
- Comparer nombre de lignes, période, provenance, poids, cylindres,
  transmission et consommation.
- Identifier les variables absentes : puissance thermique et, au niveau des
  versions RNCan, poids directement comparable.
- Montrer comment la taille et le contexte historique influencent les
  conclusions.
- Pour les millésimes 1995–2014, comparer en activité de sensibilité les cotes
  ajustées et les cotes originales, sans les empiler comme des observations
  indépendantes; documenter la procédure d'essai dans les graphiques.
- Demander aux étudiants de rédiger un paragraphe de « mise en garde » pour
  chaque jeu.

## 8. Limites des jointures de données ouvertes

Niveau : science des données / projet avancé

- Examiner `join_candidates.csv` et `unmatched_saaq.csv`.
- Calculer plusieurs taux : configurations RNCan confirmées, groupes SAAQ
  appariés, véhicules SAAQ couverts.
- Étudier des cas où plusieurs transmissions RNCan partagent la même
  année-marque-modèle.
- Proposer une règle de revue manuelle et mesurer son effet sans modifier le jeu
  principal.
- Débattre de la différence entre « candidat unique dans les données » et
  « identité démontrée ».

# Règles d’appariement

## Principe

Une similarité n’est pas une identité. Le fichier principal reçoit un
`number_registered_qc` uniquement lorsque le groupe SAAQ est relié à une seule
configuration RNCan admissible par une correspondance de codes vérifiée.

## Jointure admissible

1. Correspondance SAAQ `MARQ_VEH` + `MODEL_VEH` présente dans le fichier de
   correspondance et marquée `verified`.
2. Pour le groupe et l’année visés, la table vérifiée doit conduire à une
   seule paire marque–modèle; deux décodages vérifiés qui se chevauchent sont
   traités comme un conflit et non comme une majorité à départager.
3. Année du modèle comprise dans la plage documentée de la correspondance.
4. Égalité des clés normalisées année-marque-modèle.
5. Aucune contradiction entre les champs disponibles : carburant, nombre de
   cylindres et cylindrée.
6. Une seule configuration RNCan admissible pour le groupe SAAQ.

La tolérance par défaut sur la cylindrée est de 0,11 L, afin de comparer une
cylindrée SAAQ en cm³ avec un affichage RNCan arrondi au dixième de litre. Cette
tolérance est une règle dérivée, non une valeur observée.

## Cas non admissibles

- aucune table de décodage vérifiée;
- plusieurs décodages vérifiés incompatibles pour le même code et la même année;
- plusieurs configurations RNCan possibles, notamment à cause de la transmission
  ou du rouage;
- contradiction de carburant, cylindres ou cylindrée;
- correspondance fondée uniquement sur une distance textuelle;
- candidat unique par hasard à partir de caractéristiques mécaniques.

Ces cas sont conservés dans les tables de candidats et de non-appariés. Le
compte SAAQ n’est ni dupliqué ni réparti entre les versions.

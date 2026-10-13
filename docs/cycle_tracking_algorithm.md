# Algorithme de suivi du cycle

## Objectif

Le suivi fournit une tendance personnelle pour le **début des prochaines
règles**. Il ne diagnostique pas un trouble et ne prédit pas l'ovulation à
partir du calendrier seul.

## Construction des épisodes

- Seules les entrées datées d'aujourd'hui ou du passé sont analysées.
- Deux jours de saignement restent dans le même épisode s'ils sont séparés par
  au plus une journée non saisie. Une journée enregistrée sans règles interrompt
  l'épisode : elle n'est pas traitée comme une saisie manquante.
- Un saignement continu n'est jamais découpé artificiellement, même s'il dure
  plus de dix jours.
- La durée calendaire et le nombre réel de journées saisies restent distincts.
  Un épisode comportant un trou n'entre pas dans la durée habituelle.
- L'épisode le plus récent est toujours exclu de la durée habituelle. Le début
  d'un épisode suivant confirme implicitement que le précédent est terminé.
- L'analyse de la durée porte sur les douze derniers épisodes terminés,
  auxquels s'ajoute l'épisode récent pour les contrôles de qualité.
- Une durée « habituelle » n'est affichée qu'après trois épisodes complets et
  ainsi confirmés.

Cette stratégie reprend le principe de prétraitement décrit par Li et al. tout
en empêchant un saignement continu prolongé de devenir un faux nouveau cycle.

## Prévision des prochaines règles

- Un cycle complet est l'intervalle entre deux débuts de règles enregistrés.
- Moins de trois intervalles complets : aucune prévision personnelle n'est
  affichée. Le produit n'utilise jamais 28 jours comme valeur personnelle par
  défaut.
- La fenêtre est limitée aux douze derniers intervalles bruts, **avant**
  l'exclusion des intervalles inutilisables. Les saisies récentes invalides ne
  permettent donc pas de récupérer artificiellement des cycles plus anciens.
- Le centre de la prévision est une médiane pondérée par la récence des
  intervalles exploitables. Le poids d'un intervalle est `2^(-âge / 3)`, où
  l'âge est son rang depuis le plus récent intervalle exploitable (âge 0).
  Le poids diminue de moitié tous les trois intervalles. Une évolution répétée
  influence ainsi le centre plus rapidement qu'avec une médiane uniforme ; une
  seule valeur isolée ne représente jamais la moitié du poids dès que trois
  intervalles sont disponibles. En cas de partage exact des poids, les deux
  valeurs centrales sont moyennées, puis arrondies au jour le plus proche.
- La plage englobe au minimum cinq jours autour de cette médiane et s'élargit
  jusqu'aux durées minimale et maximale observées. À la borne inférieure de
  contrôle (15 jours), elle est prolongée vers la droite pour conserver au
  moins cinq jours possibles.
- Une plage supérieure à quatorze jours reste visible dans le résumé, mais
  n'est pas coloriée jour par jour dans le calendrier afin d'éviter une fausse
  impression de précision.
- Les intervalles très courts ou très longs ne disparaissent pas : ils sont
  exclus du centre lorsqu'ils sont hors des bornes de contrôle 15–90 jours,
  mais déclenchent un avertissement visible.
- Après un intervalle inférieur à 15 jours, l'intervalle suivant est également
  écarté du centre : l'épisode intermédiaire peut être un saignement entre les
  règles et non le début confirmé d'un nouveau cycle. Ce contrôle tient compte
  de l'intervalle qui précède immédiatement la fenêtre des douze derniers.
- Un oubli possible exige au moins trois observations cohérentes et une
  majorité stricte des intervalles exploitables : au moins un cycle proche
  d'une même durée de référence (±2 jours) et au moins un intervalle proche de
  son double ou triple (tolérance de 3 ou 4 jours respectivement). Un simple
  rapport double entre deux cycles variables ne suffit plus. Les intervalles
  suspects ne sont ni divisés ni corrigés silencieusement ; la prévision est
  suspendue tant que le motif persiste dans la fenêtre analysée.
- Un épisode récent situé moins de 15 jours après le précédent ne sert jamais
  d'ancre à une nouvelle prévision.
- Après une interruption de plus de 90 jours, les anciens cycles ne sont plus
  réutilisés : trois nouveaux intervalles consécutifs sont requis.
- Une fois la plage dépassée, l'algorithme conserve la prévision du cycle
  courant. Il n'invente jamais les cycles suivants.

L'indicateur affiché décrit uniquement la stabilité de l'historique. Ce n'est
pas une probabilité calibrée de tomber dans la plage :

- moins de 3 intervalles : historique insuffisant ;
- 3 à 5 : historique court ou variable ;
- 6 à 8 avec variation faible : historique assez stable ;
- au moins 9 avec une variation maximale de 4 jours : historique stable ;
- anomalie de saisie, durée hors de la plage adulte 24–38 jours ou variation
  supérieure à 9 jours : historique variable.

Ces seuils sont une règle prudente du produit, pas une classification médicale
ni une validation statistique de la couverture de la plage.

La pondération par récence et le seuil de concordance des oublis sont également
des choix heuristiques du produit. Ils ne reproduisent pas le modèle appris
de Li et al. et leur précision clinique n'a pas été mesurée.

## Vérification

Les tests couvrent les changements récents répétés dans les deux sens, la
résistance à un cycle isolé, les oublis plausibles et leur correction, la
fenêtre historique, les journées absentes ou explicitement sans règles, les
doublons, les dates futures et les bornes de prévision. Un contrôle sur 150
historiques synthétiques vérifie que les plages contiennent le centre et les
durées analysées. Les tests de l'écran vérifient aussi le calendrier et les
parcours de saisie. Ces vérifications logicielles ne constituent pas une
validation clinique.

## Contexte personnel

Le bouton « Mon contexte » permet de renseigner la situation actuelle, la
contraception, l'allaitement, un SOPK diagnostiqué et la date de début de ce
contexte. Rien n'est déduit automatiquement des symptômes.
Lors du premier chargement sans contexte spécifique, une grossesse déjà déclarée
dans le profil patient est reprise. Un contexte enregistré ensuite dans le
suivi de cycle prévaut sur cette valeur initiale.

- Grossesse, post-partum, ménopause, allaitement ou contraception hormonale :
  journal disponible, mais prévisions et calcul de retard suspendus. C'est une
  limite de prise en charge de notre modèle de cycles naturels, pas l'affirmation
  qu'aucune menstruation ou ovulation n'est possible dans ces contextes.
- Périménopause ou SOPK : six intervalles exploitables sont nécessaires ; la
  qualité reste « historique court ou variable ». Les symptômes ne déplacent
  pas les dates dans ces contextes. Ce seuil est une précaution du produit,
  pas une règle clinique validée.
- Un changement de contexte déjà renseigné initialise la date de début à la
  journée actuelle ; elle reste modifiable dans le formulaire. Le premier
  renseignement d'un contexte menstruel sans facteur particulier conserve
  l'historique. Seuls les épisodes **commençant** à partir de cette date servent
  au calcul : un épisode à cheval sur la date n'est jamais découpé.
- Un contexte absent conserve le modèle calendaire historique, mais n'autorise
  aucun ajustement par symptômes. Un échec de chargement du contexte ne doit
  pas être assimilé à une absence : l'écran propose de réessayer.

Le spotting est enregistré séparément et ne sert jamais de début de règles.
Le journal accepte aussi un niveau de stress (0–3) et une durée de sommeil
(0–24 heures), tous deux facultatifs et effaçables.

## Observations physiologiques

La section repliable « Observations du cycle » du journal permet de saisir :

- une température **basale** en °C, facultative, entre 34 et 42 ;
- un indicateur de mesure perturbée ;
- un test LH négatif ou positif (absence de saisie distincte d'un négatif) ;
- la glaire cervicale : sèche, collante, crémeuse, aqueuse ou filante.

Ces observations sont modifiables et effaçables. Elles sont conservées lors
d'une correction des dates des règles. La glaire est actuellement une
observation du journal ; elle ne déplace pas les prévisions.
Le formulaire attend la confirmation de sauvegarde ; un échec conserve la
saisie et permet de réessayer. Une soumission en cours est verrouillée. Les
écritures et mises à jour locales vérifient l'identité du compte qui a ouvert
le formulaire, y compris après une attente réseau.

### Détection et apprentissage

`cycle_physiology.dart` distingue une observation, une tendance et une
association personnelle avec les règles suivantes. Il ne confirme jamais
l'ovulation et ne calcule aucun jour « sans risque ».

- **LH** : une seule série de jours positifs consécutifs par cycle est retenue.
  Des séries séparées ou des résultats contradictoires le même jour empêchent
  l'utilisation du LH pour ce cycle. Un jour non saisi n'est pas un test négatif.
- **Température** : neuf mesures quotidiennes consécutives non perturbées sont
  nécessaires. Les six premières varient d'au plus 0,3 °C ; les trois suivantes
  se situent chacune de 0,2 à 0,6 °C au-dessus du maximum des six premières.
  Le signal n'est disponible qu'à la troisième mesure élevée. Une mesure
  absente, invalide, perturbée ou contradictoire rompt la séquence. Plusieurs
  hausses distinctes rendent le signal ambigu. Ces seuils sont des heuristiques
  du produit, pas une méthode symptothermique validée.
- Les doublons identiques ne multiplient pas les observations. Les entrées
  futures et les cycles antérieurs au contexte courant ne servent pas à
  l'apprentissage.
- Le délai personnel entre chaque signal et les règles suivantes est appris
  dans les douze derniers cycles exploitables. Aucun délai de quatorze jours
  n'est imposé. Il faut au moins trois observations avec un écart maximal de
  trois jours, puis trois évaluations chronologiques ; le gain moyen doit
  atteindre 0,5 jour, sans aggraver plus d'un tiers des prévisions évaluées.
- Lors de ces évaluations, le cycle cible n'entre dans l'apprentissage qu'après
  la prévision. La hausse thermique n'est utilisable qu'au jour de sa troisième
  mesure élevée. Un second signal découvert ultérieurement ne supprime pas
  rétroactivement un essai défavorable ; les cycles sans signal utilisable
  comptent comme une absence d'ajustement.
- Les ajustements sont limités aux contextes explicitement menstruels sans
  facteur de suspension, SOPK ou périménopause. Ils restent dans la fenêtre
  calendaire et à deux jours au maximum de son centre initial. LH, température
  et symptômes ne peuvent pas cumuler leurs décalages. Toutes les propositions
  individuelles sont comparées avant toute moyenne : une divergence de plus
  de deux jours annule l'ajustement global.
  La fenêtre n'est jamais réduite et sa qualité n'est jamais rehaussée.

L'ASRM souligne les limites du LH et de la température basale, notamment les
faux positifs possibles du LH en présence de SOPK. Cette évolution apprend une
association avec les **règles enregistrées** ; elle ne constitue pas une preuve
d'ovulation ni une validation médicale de la prévision.

## Évaluation chronologique hors ligne

`CyclePredictionEvaluator` dans `lib/cycle_prediction_evaluation.dart` rejoue
le moteur à des jours fixés à l'avance (J10 et J20 par défaut), sans choisir
la date de calcul à partir de la date future des règles. Chaque prévision
reçoit uniquement les entrées datées au plus tard du jour évalué.

```dart
final report = CyclePredictionEvaluator.evaluate(
  consentedEntries,
  now: evaluationDate,
  stableContext: contextForThisSegment,
  evaluationCycleDays: [10, 20],
);
final result = report.toJson();
```

Les résultats comprennent l'erreur absolue moyenne en jours, la proportion
à ±2 jours, la couverture et la largeur des fenêtres, ainsi que la disponibilité
des prévisions. Les résultats sont séparés par jour d'évaluation. Les comptes
de cycles distincts évitent de faire passer plusieurs points d'un même cycle
pour plusieurs personnes ou cycles indépendants.

Les prévisions absentes, issues non encore connues, intervalles ambigus et
changements de contexte ont des raisons explicites. Une issue manquante ne
compte jamais comme une erreur nulle. Le contexte fourni doit avoir été stable
sur la période évaluée ; le contexte courant d'une personne ne doit pas être
appliqué arbitrairement à tout son passé.

Il s'agit d'une **relecture rétrospective par date du journal**, pas d'une étude
prospective : le modèle `CycleEntry` ne conserve pas les versions historiques
ni la date de disponibilité de chaque modification. Une saisie tardive ne peut
donc pas être détectée. L'export JSON conserve des dates de santé sensibles,
même sans identifiant ni note. L'outil ne lit aucune donnée patient à distance,
n'en transmet aucune et ne réalise aucun export automatique. Il prépare une
évaluation sur des données consenties, sans revendiquer une précision réelle
à partir de tests synthétiques.

## Apprentissage des symptômes

Le moteur recherche des associations personnelles dans les mêmes douze
intervalles exploitables que la prévision. Il analyse les symptômes saisis,
certaines humeurs, le stress élevé et les nuits de moins de six heures.
L'absence de saisie n'est pas interprétée comme l'absence d'un symptôme.

1. Un signal doit débuter entre un et sept jours avant les règles dans au
   moins trois cycles distincts. L'écart entre ses délais observés doit être
   d'au plus trois jours ; au moins 75 % des cycles où ce signal est enregistré
   doivent présenter cette proximité. Un symptôme présent dès le début du
   cycle n'est donc pas utilisé comme marqueur prémenstruel.
2. Une vérification chronologique prédit chaque cycle test à partir des seuls
   cycles précédents. Le délai du cycle test n'est ajouté à l'apprentissage
   qu'après l'évaluation. Au moins trois cycles d'apprentissage puis trois
   cycles de vérification sont requis.
3. L'ajustement doit réduire l'erreur absolue moyenne d'au moins 0,5 jour sur
   ces vérifications, sans aggraver plus d'un tiers des prévisions évaluées.
   Les tentatives d'ajustement inapplicables comptent comme le modèle
   calendaire, au lieu d'être retirées de l'évaluation.
4. En usage courant, le contexte doit être explicitement menstruel sans
   contraception hormonale, allaitement ou SOPK. Le signal doit avoir débuté
   dans les trois derniers jours. La date qu'il suggère doit se trouver dans
   la plage calendaire existante et ne doit pas être passée.
5. Le centre est déplacé d'au plus deux jours. Plusieurs signaux divergents
   de plus de deux jours annulent l'ajustement. La plage n'est jamais réduite,
   la qualité n'est jamais rehaussée et une plage dépassée n'est jamais reportée.

Les tendances affichées décrivent des observations, pas un diagnostic de SPM,
une preuve de causalité du stress ou du sommeil, ni une confirmation d'ovulation.
L'évaluation personnelle et ses seuils restent exploratoires ; ils ne remplacent
pas une validation indépendante sur une population réelle.

## Persistance et confidentialité

`ientier.cycle_personal_contexts` conserve un contexte courant par patiente.
La RLS autorise uniquement le compte permanent propriétaire (`auth.uid()`) à
lire et modifier sa ligne ; les rôles publics et les sessions anonymes n'ont
pas d'accès. Les nouvelles colonnes
du journal utilisent la RLS existante de `cycle_entries`. Les contraintes SQL
refusent le cumul règles/spotting, les niveaux de stress et durées de sommeil
invalides, ainsi qu'une date de contexte future.

Les colonnes physiologiques sont ajoutées à `ientier.cycle_entries` sans
modifier ses droits ni sa politique de propriété existante. Des contraintes
SQL refusent les températures invalides et les valeurs de catégorie inconnues.
Les tests vérifient aussi la conservation des entrées antérieures à la migration,
la lecture/écriture par le propriétaire, le refus d'un autre compte et
l'effacement des observations.

La migration est accompagnée d'un test PostgreSQL isolé :
`python3 tools/test_cycle_context_database.py`. Il vérifie les contraintes,
l'accès du propriétaire et le refus des lectures/écritures d'un autre compte.

## Fertilité

`ovulationDate`, `fertileWindowStart` et `fertileWindowEnd` restent
volontairement indisponibles. Les dates menstruelles seules ne permettent pas
de confirmer précisément l'ovulation. Les observations LH, température et glaire
sont désormais disponibles, mais leur ajout ne suffit pas à justifier une
fenêtre fertile ou une date d'ovulation. Une telle estimation demanderait un
modèle et une validation indépendante adaptés.

## Références

- Li K. et al., *A predictive model for next cycle start date that accounts for
  adherence in menstrual self-tracking*:
  https://doi.org/10.1093/jamia/ocab182
- ASRM, *Optimizing natural fertility: a committee opinion*:
  https://www.asrm.org/practice-guidance/practice-committee-documents/optimizing-natural-fertility-a-committee-opinion-2021/
- Johnson S. et al., *Can apps and calendar methods predict ovulation with
  accuracy?*: https://pubmed.ncbi.nlm.nih.gov/29749274/
- FIGO, définitions des paramètres menstruels normaux et anormaux:
  https://doi.org/10.1002/ijgo.12666
- ACOG, suivi prospectif des symptômes prémenstruels :
  https://www.acog.org/womens-health/faqs/Premenstrual-Syndrome
- NHS, irrégularité des cycles et contexte hormonal :
  https://www.nhs.uk/symptoms/irregular-periods/
- ACOG, contextes d'absence de règles :
  https://www.acog.org/womens-health/faqs/amenorrhea-absence-of-periods
- ASRM, limites des tests LH et de la température basale :
  https://www.asrm.org/practice-guidance/practice-committee-documents/fertility-evaluation-of-infertile-women-a-committee-opinion-2021/

## Limites restantes

Le modèle dépend du contexte renseigné et ne détecte pas automatiquement un
changement de situation. Il ne dispose pas d'un modèle physiologique validé
ni d'une intégration aux capteurs ou objets connectés.
Il n'est pas entraîné sur une population et aucune équivalence de précision
avec Flo n'a été démontrée. Les prochains travaux doivent mesurer l'erreur et
la couverture des plages sur des données consenties, avec séparation
chronologique des données d'apprentissage et d'évaluation et analyses par
contexte. Aucun calcul de fertilité n'est activé par cette évolution.

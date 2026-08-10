# Algorithme de suivi du cycle

## Objectif

Le suivi fournit une tendance personnelle pour le **début des prochaines
règles**. Il ne diagnostique pas un trouble et ne prédit pas l'ovulation à
partir du calendrier seul.

## Construction des épisodes

- Seules les entrées datées d'aujourd'hui ou du passé sont analysées.
- Deux jours de saignement restent dans le même épisode s'ils sont séparés par
  au plus une journée non saisie.
- Un saignement continu n'est jamais découpé artificiellement, même s'il dure
  plus de dix jours.
- La durée calendaire et le nombre réel de journées saisies restent distincts.
  Un épisode comportant un trou n'entre pas dans la durée habituelle.
- L'épisode le plus récent est toujours exclu de la durée habituelle. Le début
  d'un épisode suivant confirme implicitement que le précédent est terminé.
- Une durée « habituelle » n'est affichée qu'après trois épisodes complets et
  ainsi confirmés.

Cette stratégie reprend le principe de prétraitement décrit par Li et al. tout
en empêchant un saignement continu prolongé de devenir un faux nouveau cycle.

## Prévision des prochaines règles

- Un cycle complet est l'intervalle entre deux débuts de règles enregistrés.
- Moins de trois intervalles complets : aucune prévision personnelle n'est
  affichée. Le produit n'utilise jamais 28 jours comme valeur personnelle par
  défaut.
- Le centre de la prévision est la médiane des douze derniers intervalles
  exploitables. La médiane limite l'effet d'une valeur isolée.
- La plage englobe au minimum cinq jours autour de cette médiane et s'élargit
  jusqu'aux durées minimale et maximale observées.
- Une plage supérieure à quatorze jours reste visible dans le résumé, mais
  n'est pas coloriée jour par jour dans le calendrier afin d'éviter une fausse
  impression de précision.
- Les intervalles très courts ou très longs ne disparaissent pas : ils sont
  exclus du centre lorsqu'ils sont hors des bornes de contrôle 15–90 jours,
  mais déclenchent un avertissement visible.
- Après un intervalle inférieur à 15 jours, l'intervalle suivant est également
  écarté du centre : l'épisode intermédiaire peut être un saignement entre les
  règles et non le début confirmé d'un nouveau cycle.
- Un intervalle proche de deux ou trois fois la durée habituelle déclenche un
  avertissement d'oubli possible. Il n'est ni divisé ni corrigé silencieusement
  et la prévision est suspendue jusqu'à vérification.
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

## Fertilité

`ovulationDate`, `fertileWindowStart` et `fertileWindowEnd` restent
volontairement indisponibles. Les dates menstruelles seules ne permettent pas
de confirmer précisément l'ovulation. Une future estimation devrait intégrer
des signaux physiologiques validés (par exemple LH, glaire cervicale ou
température) et faire l'objet d'une validation indépendante.

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

## Limites restantes

Le modèle ne connaît pas encore la contraception hormonale, la grossesse, le
post-partum, l'allaitement, la périménopause ni le spotting. Il segmente
l'historique après une interruption longue, mais ne peut pas en identifier la
cause. Ces contextes doivent être collectés avant d'ajouter une fonction de
fertilité. Une évolution plus avancée peut s'appuyer sur un modèle probabiliste
de type Generalized-Poisson, après calibration et validation sur la population
cible.

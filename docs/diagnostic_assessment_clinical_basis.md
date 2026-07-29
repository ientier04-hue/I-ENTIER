# Base clinique de l’évaluation assistée

Dernière revue technique : 29 juillet 2026.
Version documentée : catalogue clinique v3.

## Périmètre

Le moteur est un outil d’orientation et de triage. Il ne calcule pas une
probabilité de maladie, ne confirme aucun diagnostic et ne remplace ni
l’examen clinique, ni les constantes vitales, ni les analyses ou l’imagerie.
Les intitulés de résultats restent donc formulés comme des possibilités à
vérifier.

Les règles privilégient la sensibilité aux signes d’alerte : une réponse
urgente affiche immédiatement une alerte non dismissible. Le patient peut
afficher l’orientation urgente sans attendre ou continuer les questions. Dans
ce second cas, un bandeau d’urgence reste visible et permet d’arrêter à tout
moment. Le niveau d’urgence déjà détecté est conservé dans le résultat final.
Les conseils médicamenteux sont supprimés en cas d’urgence ou de grossesse
possible.

## Audit clinique v3

L’audit v3 a recherché en priorité les faux négatifs d’urgence, les faux
positifs produits par les scores additifs et les formulations ambiguës contenant
« ou ». Il a porté sur les dix parcours : abdomen, céphalée, menstruations,
respiration, peau, grossesse/post-partum, poitrine, urines, vertiges et fièvre.
Cette revue documentaire ne constitue pas, à elle seule, une validation
clinique de mise sur le marché.

Les garde-fous suivants sont normatifs pour la v3 et doivent être couverts par
des tests avant diffusion :

- un drapeau rouge augmente l’urgence mais ne termine pas automatiquement le
  questionnaire ; le patient choisit d’arrêter ou de continuer, et l’alerte
  reste visible ;
- une réponse ultérieure ne peut jamais abaisser une urgence déjà détectée ;
- la raison précise de chaque urgence doit être conservée et affichée avant les
  hypothèses moins graves ;
- les scores sont des indices de concordance internes, jamais des probabilités
  diagnostiques ; une hypothèse grave repose sur des signes discriminants
  obligatoires et des exclusions, pas seulement sur une somme de poids ;
- une option contenant plusieurs symptômes alternatifs ne doit ajouter que les
  signes réellement confirmés. Les questions où plusieurs signes peuvent
  coexister utilisent la sélection multiple, avec « aucun » exclusif ;
- les données facultatives du profil peuvent renforcer la prudence, mais une
  règle vitale ne doit jamais dépendre du consentement à réutiliser ces données.
- un catalogue distant de même version ne remplace pas le catalogue intégré ;
  une version de schéma incompatible ou un niveau d’urgence absent/inconnu est
  rejeté au lieu d’être converti silencieusement en autosoins.

### Seuils et interactions prioritaires

- Fièvre : le parcours fébrile demande la température maximale et l’âge ; les
  parcours respiratoire et urinaire redemandent l’âge localement. Une
  température d’au moins 38 °C avant 3 mois impose une évaluation immédiate ;
  entre 3 et 6 mois, 39 °C ou plus impose au minimum une évaluation urgente le
  jour même.
- Méningite ou infection invasive : raideur de nuque, rash non blanchissant,
  altération de la conscience et céphalée sévère avec fièvre sont recherchés
  séparément et font apparaître une raison urgente explicite.
- Sepsis : altération de la conscience, détresse respiratoire, peau
  pâle/marbrée/moite, température basse du nourrisson, absence prolongée
  d’urines et dégradation générale déclenchent des motifs urgents. Fièvre ou
  malaise sous traitement anticancéreux actif ou récent impose une évaluation
  immédiate pour neutropénie.
- Douleur thoracique : une oppression ou lourdeur nouvelle et persistante peut
  être coronarienne même sans irradiation ni facteur de risque connu. Les
  symptômes priment sur le profil de risque.
- Embolie pulmonaire : un facteur de risque isolé ne suffit pas à créer le
  diagnostic ni une alerte ambulance. Dans un parcours ouvert pour douleur ou
  essoufflement, il peut toutefois imposer un avis le jour même ; l’alerte
  immédiate exige un symptôme aigu associé.
- Respiration : l’essoufflement isolé et les signes d’obstruction des voies
  aériennes restent accessibles sans devoir choisir une toux ou un sifflement.
  L’échec du traitement de secours et l’hémoptysie sont gradués selon la gravité
  et les signes associés.
- Pneumonie : des crachats seuls sont insuffisants. Il faut une toux ou un foyer
  respiratoire avec au moins un élément supplémentaire, par exemple fièvre,
  altération générale, dyspnée, douleur pleurale ou aggravation secondaire.
- Tuberculose : une toux d’au moins 3 semaines doit être associée à un signe
  systémique confirmé séparément ou à une hémoptysie.
- Dengue et paludisme : le lieu de résidence compte autant qu’un voyage ou une
  piqûre remarquée. Les signes d’alerte de dengue peuvent apparaître après la
  baisse de la fièvre ; aspirine et ibuprofène sont évités tant qu’une dengue
  reste possible. Une fièvre compatible avec le paludisme en zone de
  transmission nécessite un test rapide le jour même.
- La branche diphtérie recherche un dépôt gris adhérent, un gonflement du cou
  et une voix ou respiration inhabituelle. L’exposition, la vaccination et le
  contexte épidémiologique daté doivent ensuite être vérifiés par le
  professionnel.
- Grossesse et post-partum : céphalée persistante, troubles visuels,
  pré-éclampsie/éclampsie, saignement, grossesse extra-utérine, thrombose et
  embolie sont séparés ; les signes maternels urgents restent recherchés jusqu’à
  un an après l’accouchement. Une diminution des mouvements fœtaux ou une perte
  de liquide affiche une consigne immédiate de contacter la maternité sans
  attendre le lendemain.
- Urines et vertiges : infection urinaire du nourrisson, grossesse, enfant,
  homme, obstruction infectée et rétention renforcent le triage ; un vertige
  brutal continu avec nouvelle instabilité suit une filière neurologique
  urgente.
- Abdomen, peau et traumatisme : hémorragie digestive, occlusion, pancréatite,
  infection biliaire, torsion testiculaire, brûlure grave, lésion cutanée qui
  change et signes graves après choc crânien disposent désormais de branches
  dédiées.

## Limites connues

- Les symptômes déclarés peuvent être incomplets, mal interprétés ou changer
  rapidement. Un résultat rassurant n’exclut jamais une maladie grave.
- L’outil ne réalise ni examen physique, ni ECG, ni mesure fiable des constantes,
  ni analyse biologique, ni imagerie. Une mesure enregistrée ancienne ne doit
  pas être traitée comme une constante actuelle.
- Les tableaux pédiatriques, la grossesse, le post-partum, l’immunodépression et
  les traitements anticancéreux nécessitent encore une validation spécialisée
  des seuils et formulations.
- La sélection multiple réduit le risque de masquer un signe concomitant, mais
  l’outil dépend toujours de ce que le patient comprend et déclare.
- Les règles géographiques et épidémiques doivent être datées, réévaluées et
  désactivables lorsque la situation change.
- Les conseils d’autosoins et de pharmacie ne doivent jamais retarder une
  évaluation urgente. Toute aggravation, inquiétude importante ou discordance
  avec le résultat justifie un recours professionnel.

## Références d’orientation

- NICE, *Fever in under 5s* : seuils liés à l’âge, signes respiratoires,
  hydratation et risque de maladie grave.
  <https://www.nice.org.uk/guidance/ng143/chapter/Recommendations>
- NICE, *Meningitis and meningococcal disease* : combinaison de fièvre,
  céphalée, raideur de nuque, altération cognitive et rash non blanchissant.
  <https://www.nice.org.uk/guidance/ng240/chapter/Recommendations>
- NICE, *Recent-onset chest pain* et AHA/ACC, *Chest Pain Guideline* :
  syndrome coronarien possible au repos, symptômes associés et équivalents
  angineux sans exiger une irradiation typique.
  <https://www.nice.org.uk/guidance/CG95/chapter/recommendations>
  <https://professional.heart.org/en/science-news/2021-guideline-for-the-evaluation-and-diagnosis-of-chest-pain>
- NICE, *Venous thromboembolic diseases* : association des symptômes, signes
  cliniques et facteurs de risque dans l’évaluation d’une embolie pulmonaire.
  <https://www.nice.org.uk/guidance/ng158/chapter/Recommendations>
- NICE, *Pneumonia*, *Acute cough*, *Suspected sepsis* et *Neutropenic
  sepsis* : gravité respiratoire, durée habituelle d’une toux aiguë, critères de
  sepsis adaptés à l’âge et urgence sous traitement anticancéreux.
  <https://www.nice.org.uk/guidance/NG250/chapter/recommendations>
  <https://www.nice.org.uk/guidance/ng120/chapter/recommendations>
  <https://www.nice.org.uk/guidance/NG253/chapter/evaluating-risk>
  <https://www.nice.org.uk/guidance/ng254/chapter/Evaluating-risk-level>
  <https://www.nice.org.uk/guidance/cg151/chapter/recommendations>
- GINA, *Summary Guide 2026* : critères de gravité d’une exacerbation d’asthme
  et recours urgent lorsque le traitement de secours échoue.
  <https://ginasthma.org/wp-content/uploads/2026/07/GINA-Summary-Guide-2026-WEB-WMS.pdf>
- CDC, *Tuberculosis* et *Malaria* : toux prolongée et symptômes systémiques de
  tuberculose ; nécessité d’un diagnostic rapide du paludisme.
  <https://www.cdc.gov/tb/signs-symptoms/index.html>
  <https://www.cdc.gov/yellow-book/hcp/travel-associated-infections-diseases/malaria.html>
- CDC, *Haiti Traveler View* : présence du paludisme et de la dengue dans le
  contexte haïtien.
  <https://wwwnc.cdc.gov/travel/destinations/traveler/none/Haiti>
- OMS, *Dengue* et *Diphtheria*, et OPS/OMS, situation humanitaire en Haïti :
  signes d’alerte de dengue, éviction des AINS et détection précoce de la
  diphtérie dans un contexte épidémique.
  <https://www.who.int/news-room/fact-sheets/detail/dengue-and-severe-dengue>
  <https://www.who.int/news-room/fact-sheets/detail/diphtheria>
  <https://www.paho.org/en/haiti-humanitarian-crisis-grade-3>
- NHS, *Coughing up blood* : distinction entre quelques traces de sang et une
  hémoptysie abondante ou associée à une détresse.
  <https://www.nhs.uk/symptoms/coughing-up-blood/>
- Organisation mondiale de la Santé, *Basic Emergency Care* : approche ABCDE,
  détresse respiratoire, hémorragie importante, choc, convulsion et altération
  de la conscience.
  <https://qualityhealthservices.who.int/quality-toolkit/qt-catalog-item/basic-emergency-care-approach-to-the-acutely-ill-and-injured-participant-workbook>
- NHS, *Stomach ache* : douleur abdominale brutale ou sévère, abdomen
  douloureux au toucher, hémorragie digestive, rétention, arrêt des selles/gaz
  et collapsus.
  <https://www.nhs.uk/symptoms/stomach-ache/>
- NHS, *Headaches* : céphalée brutale, déficit neurologique, convulsion,
  traumatisme, fièvre avec raideur de nuque et troubles visuels.
  <https://www.nhs.uk/symptoms/headaches/>
- NHS, *Shortness of breath* et *Heart palpitations* : oppression thoracique,
  douleur irradiée, dyspnée sévère, cyanose et palpitations associées à douleur,
  essoufflement ou syncope.
  <https://www.nhs.uk/symptoms/shortness-of-breath/>
  <https://www.nhs.uk/symptoms/heart-palpitations/>
- NHS, *Blood in urine* et *Kidney stones* : hématurie, infection urinaire,
  douleur lombaire fébrile, colique vers l’aine et obstruction urinaire.
  <https://www.nhs.uk/symptoms/blood-in-urine/>
  <https://www.nhs.uk/conditions/kidney-stones/symptoms/>
- NHS, *Fainting* : récupération incomplète, trouble de la parole ou du
  mouvement, douleur thoracique, palpitations, syncope à l’effort ou en position
  couchée.
  <https://www.nhs.uk/symptoms/fainting/>
- CDC, *About Respiratory Illnesses* : difficulté respiratoire, douleur ou
  pression thoracique, confusion, convulsion, faiblesse sévère et aggravation
  après une amélioration.
  <https://www.cdc.gov/respiratory-viruses/about/index.html>
- CDC, *Get Ahead of Sepsis* : confusion, dyspnée, peau moite, tachycardie,
  douleur extrême, fièvre ou frissons comme signes possibles d’infection
  sévère.
  <https://www.cdc.gov/sepsis/media/pdfs/CDC-Sepsis-EMS-card-signs-symptoms-508.pdf>
- NHS, *Angioedema* : gonflement soudain des lèvres, de la bouche, de la langue
  ou de la gorge et difficulté respiratoire.
  <https://www.nhs.uk/conditions/angioedema/>
- ACOG, *Abnormal Uterine Bleeding* : saignement aigu abondant et signes
  d’instabilité ou d’anémie symptomatique.
  <https://www.acog.org/womens-health/faqs/abnormal-uterine-bleeding>
- ACOG, *Urgent Maternal Warning Signs* : céphalée persistante, troubles
  visuels, syncope, douleur abdominale sévère, dyspnée, saignement, vomissements
  sévères et signes d’urgence psychique pendant ou après la grossesse.
  <https://www.acog.org/giving/programs/quality-and-safety/resources>
- ACOG, *Headaches and Pregnancy* : céphalée en coup de tonnerre et signes de
  pré-éclampsie pendant la grossesse ou le post-partum.
  <https://www.acog.org/womens-health/faqs/headaches-and-pregnancy>
- NICE, *Urinary tract infection*, *Pyelonephritis* et *Acute kidney injury* :
  groupes à risque, infection haute et obstruction urinaire infectée.
  <https://www.nice.org.uk/guidance/ng109/chapter/Recommendations>
  <https://www.nice.org.uk/guidance/ng111>
  <https://www.nice.org.uk/guidance/ng148/chapter/Recommendations>
- NICE, *Suspected neurological conditions* : vertige brutal continu avec
  nouvelle instabilité et orientation AVC en l’absence d’un examen spécialisé.
  <https://www.nice.org.uk/guidance/ng127/chapter/Recommendations-for-adults-aged-over-16>
- NHS, *Your baby's movements*, et ACOG, *Bleeding During Pregnancy* :
  contact immédiat de la maternité en cas de mouvements diminués et gradation
  des saignements et signes d’instabilité.
  <https://www.nhs.uk/pregnancy/keeping-well/your-babys-movements/>
  <https://www.acog.org/womens-health/faqs/bleeding-during-pregnancy>
- NHS, *Testicle pain*, *Acute pancreatitis* et *Melanoma skin cancer* :
  torsion testiculaire, douleur pancréatique nécessitant l’hôpital et lésions
  cutanées changeantes ou non cicatrisantes.
  <https://www.nhs.uk/symptoms/testicle-pain/>
  <https://www.nhs.uk/conditions/acute-pancreatitis/>
  <https://www.nhs.uk/conditions/melanoma-skin-cancer/symptoms/>

## Gouvernance

Toute modification d’un seuil d’urgence, d’une formulation clinique ou d’un
conseil médicamenteux doit être relue par un professionnel de santé qualifié
avant publication. Les versions déjà utilisées par un patient restent
reproductibles grâce à l’instantané du parcours enregistré avec l’évaluation.
La validation doit inclure des scénarios de faux négatifs et de faux positifs,
une revue pédiatrique et obstétricale, ainsi qu’une vérification périodique des
références et alertes épidémiologiques.

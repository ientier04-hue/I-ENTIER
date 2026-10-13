part of 'diagnostic_assessment.dart';

List<String> _immediateActionsForTags(Set<String> tags) {
  if (tags.contains('eye_penetrating')) {
    return const [
      'Ne retirez pas l’objet planté dans l’œil et n’appuyez pas dessus. Faites-vous accompagner aux urgences immédiatement.',
    ];
  }
  if (tags.contains('eye_chemical')) {
    return const [
      'Rincez immédiatement l’œil ouvert avec beaucoup d’eau propre, non chaude, à faible débit pendant au moins 20 minutes. Faites appeler le 116 pendant le rinçage; emportez l’emballage du produit si possible.',
    ];
  }
  if (tags.contains('dental_avulsed') &&
      !{
        'dental_airway_warning',
        'dental_swallowing_warning',
        'dental_spreading_infection',
        'dental_trismus',
        'dental_uncontrolled_bleeding',
        'dental_cardiac_warning',
      }.any(tags.contains)) {
    return [
      'Contactez un dentiste immédiatement pour la dent sortie après le choc; n’attendez pas la fin du questionnaire.',
      tags.contains('dental_baby_tooth')
          ? 'Ne remettez pas une dent de lait dans son emplacement.'
          : 'Tenez la dent par la couronne, sans toucher ni frotter la racine, et conservez-la dans un récipient de lait jusqu’au dentiste. Ne la replantez pas si vous ignorez si c’est une dent de lait.',
    ];
  }
  return const [];
}

// Provenance for inferred signs. Only selected options are displayed here;
// authorized profile information remains in contextNotes.
const _derivedEvidenceTags = <String, Set<String>>{
  'cellulitis_pattern': {
    'cellulitis_pattern',
    'painful_skin',
    'warm_skin',
    'skin_swelling',
  },
  'possible_ketoacidosis': {
    'large_urine_volume',
    'excessive_thirst',
    'vomiting',
    'deep_breathing',
    'confusion',
  },
  'posterior_stroke_pattern': {'sudden_dizziness', 'imbalance'},
  'acute_coronary_suspicion': {
    'cardiovascular_risk',
    'chest_pain_at_rest',
    'chest_pressure',
    'nonspecific_chest_pain',
    'acute_coronary_autonomic',
  },
  'pulmonary_embolism_pattern': {
    'pulmonary_embolism_pattern',
    'clot_risk',
    'pleuritic_pain',
    'breathlessness_primary',
    'mild_breathlessness',
    'severe_breathlessness',
  },
  'young_infant_fever': {
    'person_under_3_months',
    'temperature_38',
    'temperature_39',
    'temperature_40',
  },
  'infant_hypothermia': {
    'infant_hypothermia',
    'person_under_3_months',
    'temperature_below_36',
  },
  'young_infant_urinary_infection': {
    'person_under_3_months',
    'urinary_burning',
    'urinary_frequency',
    'small_frequent_voids',
    'cloudy_urine',
  },
  'infected_urinary_obstruction': {
    'fever',
    'chills',
    'colicky_flank_pain',
    'known_urinary_stone',
    'known_urinary_obstruction',
    'urinary_retention',
  },
  'back_fracture_risk': {'back_minor_trauma', 'back_bone_fragility'},
  'back_spinal_infection_risk': {'fever', 'immunocompromised'},
  'joint_hot_swollen': {'joint_hot', 'joint_swollen'},
  'joint_infection_risk': {
    'joint_prosthesis',
    'joint_recent_procedure',
    'immunocompromised',
  },
  'eye_contact_lens_risk': {
    'eye_contact_lenses',
    'eye_red',
    'eye_deep_pain',
    'eye_severe_pain',
    'eye_gritty',
  },
  'eye_orbital_warning': {
    'eye_lid_swelling',
    'eye_spreading_swelling',
    'fever',
    'eye_movement_pain',
  },
};

// Advice is selected from declared signs, never from the highest scoring label.
// Keep emergency disposition ahead of all symptom-specific advice.
class _AssessmentGuidance {
  final List<String> nextSteps;
  final List<String> selfCare;
  final List<String> pharmacyAdvice;

  const _AssessmentGuidance(this.nextSteps, this.selfCare, this.pharmacyAdvice);
}

_AssessmentGuidance _guidanceFor({
  required AssessmentPathway pathway,
  required Set<String> tags,
  required AssessmentUrgency urgency,
  required Map<String, dynamic> context,
}) {
  bool has(String tag) => tags.contains(tag);
  bool any(Set<String> values) => values.any(has);
  bool all(Set<String> values) => values.every(has);
  final pregnant = any({'context_pregnant', 'pregnancy_possible'});
  final maternal = pregnant || pathway.id == 'pregnancy';
  final emergency = urgency == AssessmentUrgency.emergency;
  final next = <String>[];
  final care = <String>[];
  final pharmacy = <String>[];
  final dengue = any({'dengue_pattern', 'dengue_warning'});
  final age = (context['age'] as num?)?.toDouble();
  final ageMonths = (context['ageMonths'] as num?)?.toDouble();
  final child =
      (age != null && age < 16) ||
      (ageMonths != null && ageMonths < 192) ||
      any({
        'person_under_16',
        'person_under_3_months',
        'person_3_to_6_months',
        'young_child',
      });
  const noNewMedication =
      'Ne commencez pas de nouveau médicament sans avis médical ou pharmaceutique dans cette situation.';

  if (emergency) {
    next.add(
      'Appelez le Centre Ambulancier National au 116 ou faites-vous accompagner vers les urgences maintenant.',
    );
    if (pathway.id == 'eyes') {
      next.add(
        'Demandez une évaluation ophtalmologique urgente; ne conduisez pas avec une vision modifiée.',
      );
    }
    if (pathway.id == 'back') {
      next.add(
        'Évitez les manipulations du dos. Signalez immédiatement les changements de force, de sensibilité, des urines ou des selles.',
      );
    }
    if (pathway.id == 'joint' && has('joint_hot_swollen')) {
      next.add(
        'Une infection articulaire doit être exclue à l’hôpital; n’attendez pas qu’un antidouleur ou un ancien traitement de goutte fasse effet.',
      );
    }
    if (pathway.id == 'joint' &&
        any({
          'joint_deformity',
          'joint_open_injury',
          'joint_neurovascular_injury',
          'joint_unable_weight_bear',
        })) {
      next.add(
        'Ne forcez pas l’appui et ne tentez pas de remettre l’articulation en place.',
      );
    }
    if (pathway.id == 'dental') {
      next.add(
        has('dental_cardiac_warning')
            ? 'Signalez la douleur de mâchoire et les signes thoraciques ou respiratoires aux secours; ne retardez pas l’évaluation pour chercher un dentiste.'
            : 'N’attendez pas un rendez-vous dentaire habituel; signalez le gonflement, la difficulté à avaler ou le saignement aux urgences.',
      );
    }
    if (any({
      'neurologic_deficit',
      'posterior_stroke_pattern',
      'thunderclap',
      'acute_vestibular_syndrome',
    })) {
      next.add(
        'Notez l’heure de début des signes, ou la dernière heure où vous alliez bien, et communiquez-la aux secours.',
      );
    }
    if (maternal) {
      next.add(
        'Signalez aux secours votre grossesse et son terme, ou la date de votre accouchement.',
      );
    }
    if (has('reduced_fetal_movement')) {
      next.add(
        'Signalez aussi la diminution des mouvements du bébé à la maternité, sans retarder le départ.',
      );
    }
    if (has('asthma_history') &&
        any({'wheeze', 'reliever_not_working', 'asthma_exacerbation'})) {
      next.add(
        'En attendant les secours, suivez votre plan d’urgence pour l’asthme avec votre inhalateur déjà prescrit.',
      );
    }
    next.add(
      'Ne conduisez pas vous-même. Faites rester quelqu’un auprès de vous et suivez les consignes des secours.',
    );
    pharmacy.add(noNewMedication);
    if (dengue) {
      pharmacy.add(
        'Une dengue est possible : évitez l’aspirine et l’ibuprofène à cause du risque de saignement.',
      );
    }
    return _AssessmentGuidance(next, const [], pharmacy);
  }

  final maternityNow = any({
    'reduced_fetal_movement',
    'fluid_leak',
    'regular_contractions',
  });
  if (maternityNow) {
    next.add(
      'Appelez maintenant votre maternité ou l’unité obstétricale; n’attendez pas demain, même la nuit.',
    );
    if (has('reduced_fetal_movement')) {
      next.add(
        'N’utilisez pas un Doppler domestique pour vous rassurer; faites contrôler les mouvements du bébé.',
      );
    }
    if (has('fluid_leak')) {
      care.add(
        'Mettez une protection hygiénique, pas de tampon; notez l’heure, la couleur et l’odeur du liquide pour la maternité.',
      );
    }
    next.add(
      'Si vous ne pouvez joindre la maternité, appelez le 116 pour être orientée.',
    );
  } else if (pathway.id == 'dental') {
    next.add(
      has('dental_avulsed')
          ? 'Appelez un dentiste immédiatement pour une prise en charge de la dent expulsée.'
          : urgency == AssessmentUrgency.consultationToday
          ? 'Contactez un dentiste aujourd’hui pour des soins urgents.'
          : 'Prenez rendez-vous chez un dentiste dans les prochains jours; une douleur qui dépasse deux jours doit être examinée.',
    );
  } else if (pathway.id == 'eyes') {
    next.add(
      urgency == AssessmentUrgency.consultationToday
          ? 'Faites examiner l’œil aujourd’hui par un ophtalmologue ou un service d’urgence oculaire.'
          : urgency == AssessmentUrgency.consultationSoon
          ? 'Prenez rendez-vous prochainement pour un examen des yeux; consultez plus vite si la vision change.'
          : 'Surveillez l’évolution; faites examiner l’œil si la gêne persiste ou revient.',
    );
  } else {
    next.add(switch (urgency) {
      AssessmentUrgency.consultationToday =>
        maternal
            ? 'Contactez aujourd’hui votre maternité, votre sage-femme ou un médecin pour une évaluation.'
            : child
            ? 'Faites examiner l’enfant aujourd’hui par un médecin ou un service pédiatrique.'
            : 'Faites-vous examiner aujourd’hui par un médecin ou dans une clinique.',
      AssessmentUrgency.consultationSoon =>
        maternal
            ? 'Prenez rendez-vous prochainement avec votre sage-femme ou votre médecin.'
            : 'Prenez rendez-vous dans les prochains jours pour préciser la cause.',
      _ =>
        'Surveillez l’évolution et prenez rendez-vous si les symptômes persistent, reviennent ou vous inquiètent.',
    });
  }

  final digestiveLoss = any({'diarrhea', 'watery_diarrhea', 'vomiting'});
  final canDrink = !any({
    'cannot_hydrate',
    'urinary_retention',
    'acute_kidney_injury_pattern',
  });
  final urinarySigns = any({
    'urinary_burning',
    'urinary_frequency',
    'kidney_infection_pattern',
  });
  final reflux = any({'heartburn', 'acid_reflux', 'reflux_pattern'});
  final skinInfection = any({
    'cellulitis_pattern',
    'abscess_pattern',
    'pus',
    'honey_crust',
  });

  if (digestiveLoss && canDrink) {
    care.add(
      'Buvez par petites gorgées fréquentes; en cas de diarrhée ou de vomissements répétés, utilisez une solution de réhydratation orale préparée selon son sachet. Respectez toute restriction de liquides prescrite.',
    );
    care.add(
      'Surveillez les urines et la capacité à garder les boissons; une baisse des urines ou des vomissements qui empêchent de boire imposent un avis rapide.',
    );
    if (child) {
      care.add(
        'Pour un nourrisson, poursuivez les tétées ou le lait habituel sans le diluer; demandez une solution de réhydratation adaptée à son âge.',
      );
    }
  } else if (canDrink && any({'dehydration_risk', 'fever', 'acute_fever'})) {
    care.add(
      child
          ? 'Proposez souvent à boire à l’enfant; pour un nourrisson, poursuivez les tétées ou le lait habituel et surveillez les couches mouillées.'
          : 'Buvez régulièrement, sauf restriction de liquides prescrite, et surveillez la quantité d’urine.',
    );
  }

  switch (pathway.id) {
    case 'back':
      final backNeedsExamination = any({
        'fever',
        'back_minor_trauma',
        'back_fracture_risk',
        'back_cancer_context',
        'back_weight_loss',
        'back_night_pain',
        'back_rest_pain',
        'back_severe',
        'back_worsening',
      });
      if (!backNeedsExamination) {
        care.add(
          'Gardez une activité douce selon votre tolérance, changez régulièrement de position et évitez le repos prolongé au lit. Arrêtez un mouvement qui aggrave nettement la douleur.',
        );
        if (any({'back_strain', 'back_postural', 'back_muscle_tenderness'})) {
          care.add(
            'Une chaleur douce protégée par un tissu peut soulager les muscles; évitez le port de charges lourdes pendant la poussée.',
          );
        }
      }
      if (has('back_leg_radiation') || has('back_arm_radiation')) {
        next.add(
          'Faites vérifier la force et la sensibilité du membre douloureux; signalez toute faiblesse nouvelle sans attendre.',
        );
      }
      if (has('back_morning_stiffness')) {
        next.add(
          'Notez la durée de la raideur au réveil et l’effet du mouvement pour discuter d’un bilan inflammatoire.',
        );
      }
      if (any({'urinary_burning', 'back_flank', 'back_groin_radiation'})) {
        next.add(
          'Signalez la douleur du flanc et les signes urinaires; le médecin pourra rechercher une infection ou un calcul.',
        );
      }
      if (backNeedsExamination) {
        care.add(
          'Évitez les manipulations forcées du dos avant l’examen médical.',
        );
      }
      pharmacy.add(
        'Demandez quel antalgique convient à votre situation avant un achat; les anti-inflammatoires ne conviennent pas à tout le monde.',
      );
    case 'joint':
      if (has('joint_hot_swollen')) {
        next.add(
          'Faites examiner l’articulation chaude et gonflée aujourd’hui, même sans fièvre; une ponction peut être nécessaire pour distinguer infection et inflammation.',
        );
      } else if (has('joint_long_stiffness')) {
        next.add(
          'Notez les articulations touchées et la durée de la raideur matinale pour le bilan médical.',
        );
      }
      care.add(
        'Réduisez les activités qui déclenchent la douleur. Ne forcez pas une articulation bloquée ou blessée.',
      );
      if (!has('joint_locked') && !has('joint_hot_swollen')) {
        care.add(
          'Gardez des mouvements doux dans les limites du confort, sans immobiliser complètement l’articulation pendant plusieurs jours.',
        );
      }
      if (any({'joint_swollen', 'joint_trauma', 'joint_overuse'})) {
        care.add(
          'Appliquez une poche froide enveloppée dans un tissu jusqu’à 20 minutes; ne posez jamais de glace directement sur la peau.',
        );
      }
      pharmacy.add(
        'Demandez un antalgique compatible avec vos traitements et antécédents; ne reprenez pas seul un ancien traitement de goutte ou de cortisone.',
      );
    case 'eyes':
      care.add(
        'Ne frottez pas l’œil. Évitez les lentilles de contact et le maquillage jusqu’à guérison ou avis du professionnel.',
      );
      if (has('eye_new_floaters')) {
        next.add(
          'Faites contrôler aujourd’hui les nouveaux éclairs ou points flottants; un examen de la rétine peut être nécessaire.',
        );
      }
      if (has('eye_newborn')) {
        next.add(
          'Un œil rouge ou collé chez un nouveau-né nécessite un examen aujourd’hui; n’utilisez pas de collyre sans prescription.',
        );
      }
      if (any({'eye_sticky', 'eye_repeated_discharge'})) {
        care.add(
          'Lavez-vous les mains et ne partagez pas les serviettes. Nettoyez doucement les sécrétions avec une compresse propre et de l’eau préalablement bouillie puis refroidie, une compresse différente pour chaque œil.',
        );
      }
      final mildSurface =
          urgency == AssessmentUrgency.selfCare ||
          urgency == AssessmentUrgency.consultationSoon;
      if (mildSurface && has('eye_vision_preserved')) {
        if (has('eye_dry')) {
          care.add(
            'Faites des pauses d’écran et clignez régulièrement des yeux.',
          );
          pharmacy.add(
            'Demandez si des larmes artificielles sans conservateur conviennent à votre situation.',
          );
        }
        if (has('eye_itch')) {
          care.add(
            'Évitez le déclencheur identifié; une compresse fraîche sur les paupières fermées peut soulager les démangeaisons.',
          );
        }
        if (any({'eye_stye_pattern', 'eye_blepharitis_pattern'})) {
          care.add(
            'Appliquez une compresse tiède sur la paupière fermée; ne percez pas le bouton et ne pressez pas la paupière.',
          );
        }
      }
      pharmacy.add(
        'N’utilisez pas un ancien collyre antibiotique, corticoïde ou anesthésiant sans examen et prescription adaptés.',
      );
    case 'dental':
      if (any({
        'dental_local_swelling',
        'dental_facial_swelling',
        'dental_pus',
      })) {
        next.add(
          'Un abcès possible nécessite des soins dentaires; ne percez pas le gonflement et ne comptez pas sur un antibiotique seul pour traiter la dent.',
        );
      }
      if (any({'dental_dry_socket_pattern', 'dental_postprocedure_warning'})) {
        next.add(
          'Contactez le dentiste qui a réalisé le soin aujourd’hui; indiquez la date du soin et l’évolution de la douleur.',
        );
      }
      if (!has('dental_avulsed')) {
        care.add(
          'Choisissez des aliments mous, mastiquez du côté opposé et évitez les aliments très chauds, très froids ou sucrés qui déclenchent la douleur.',
        );
        care.add(
          'Gardez un brossage doux avec une brosse souple et un dentifrice fluoré.',
        );
      }
      if (has('dental_broken') || has('dental_lost_filling')) {
        next.add(
          'Faites réparer la dent ou la restauration; n’utilisez pas de colle domestique.',
        );
      }
      pharmacy.add(
        'Pour soulager en attendant le dentiste, demandez un antalgique adapté à votre âge et à vos traitements; ne posez pas d’aspirine ni de produit caustique sur la gencive.',
      );
      pharmacy.add(
        'Ne commencez pas d’antibiotique restant d’un ancien traitement; il ne remplace pas les soins dentaires.',
      );
    case 'abdominal':
      if (any({'lower_right', 'migrating_right_lower_pain'})) {
        next.add(
          'Signalez la douleur en bas à droite et son évolution; un examen abdominal est nécessaire pour rechercher une appendicite.',
        );
      }
      if (has('constipation') &&
          !digestiveLoss &&
          !any({'severe_pain', 'abdominal_distension'})) {
        care.add(
          'Augmentez progressivement les fibres, bougez doucement et gardez des horaires réguliers pour aller à la selle.',
        );
        pharmacy.add(
          'Si la constipation persiste, demandez au pharmacien si un laxatif est adapté à votre situation.',
        );
      }
      if (digestiveLoss) {
        care.add(
          'Lavez-vous les mains au savon et évitez de préparer les repas d’autres personnes pendant les symptômes.',
        );
      }
    case 'headache':
      if (any({'photophobia', 'migraine_pattern', 'pulsating'})) {
        care.add(
          'Reposez-vous dans un endroit calme et peu éclairé; gardez des repas réguliers.',
        );
      } else if (any({'neck_tension', 'pressure', 'stress'})) {
        care.add(
          'Faites des pauses d’écran et relâchez doucement les épaules et la nuque. Gardez un rythme de sommeil régulier.',
        );
      }
      if (any({'recurrent', 'frequent_headache', 'frequent_pain_medicine'})) {
        next.add(
          'Notez les jours de céphalée, leur durée et les médicaments pris pour préparer la consultation.',
        );
      }
      if (has('frequent_pain_medicine')) {
        pharmacy.add(
          'Faites revoir la fréquence de vos antidouleurs avec le médecin ou le pharmacien; n’augmentez pas les prises ni n’arrêtez seul un traitement prescrit.',
        );
      }
    case 'menstrual':
      if (has('cramps') &&
          !pregnant &&
          !any({
            'one_sided_pelvic_pain',
            'fever',
            'pelvic_infection_pattern',
          })) {
        care.add(
          'Pour les crampes de règles, appliquez une chaleur douce, protégée par un tissu, et bougez selon votre tolérance.',
        );
      }
      if (any({'heavy_bleeding', 'prolonged_bleeding', 'large_clots'})) {
        next.add(
          'Notez la fréquence des protections et la durée des pertes; un bilan pourra rechercher une anémie.',
        );
      }
      if (any({
        'postmenopausal_bleeding',
        'postcoital_bleeding',
        'intermenstrual_bleeding',
      })) {
        next.add(
          'Faites examiner ce saignement inhabituel, même s’il s’arrête ou reste peu abondant.',
        );
      }
      if (has('missed_period') && has('pregnancy_possible')) {
        next.add(
          'Faites un test de grossesse; une douleur ou un saignement nécessite un avis sans attendre le résultat du test.',
        );
      }
      if (any({'discharge', 'foul_discharge', 'itch', 'genital_sores'})) {
        care.add(
          'Évitez les douches vaginales et les produits parfumés; faites préciser la cause des pertes avant un traitement local.',
        );
      }
    case 'respiratory':
      care.add('Évitez la fumée et aérez la pièce.');
      if (any({'cough', 'upper_respiratory', 'sick_contact'})) {
        care.add(
          'Couvrez la toux, lavez-vous les mains et limitez les contacts rapprochés avec les personnes fragiles.',
        );
      }
      if (all({'asthma_history', 'wheeze'})) {
        care.add(
          'Suivez votre plan d’action pour l’asthme avec les inhalateurs déjà prescrits; un soulagement bref ou absent nécessite une réévaluation rapide.',
        );
      }
      if (has('congestion')) {
        pharmacy.add(
          'Pour le nez bouché, demandez une solution saline adaptée à l’âge; évitez d’associer plusieurs produits contre le rhume.',
        );
      }
      if (any({'chronic', 'weight_loss', 'night_sweats'})) {
        next.add(
          'Précisez la durée de la toux, les sueurs nocturnes ou la perte de poids au médecin; un examen et un dépistage peuvent être nécessaires.',
        );
      }
    case 'skin':
      if (skinInfection) {
        next.add(
          'Faites examiner la zone pour déterminer si un antibiotique ou un drainage est nécessaire.',
        );
        care.add(
          'Gardez la zone propre; ne percez pas les boutons ni l’abcès. Couvrez une plaie qui suinte avec un pansement propre.',
        );
      } else if (any({'dry_patch', 'itch', 'contact_trigger'})) {
        care.add(
          'Évitez le produit déclencheur identifié, les savons parfumés et le grattage; appliquez des compresses fraîches si cela soulage.',
        );
        if (has('dry_patch')) {
          pharmacy.add(
            'Demandez un émollient sans parfum pour les plaques sèches, après vérification de vos allergies.',
          );
        }
      }
      if (has('dermatomal_pattern')) {
        next.add(
          'Faites évaluer rapidement les cloques douloureuses pour discuter d’un traitement; signalez immédiatement une atteinte du visage ou de l’œil.',
        );
      }
      if (any({
        'changing_mole_pattern',
        'non_healing_skin_lesion',
        'recurrent_skin_bleeding',
      })) {
        next.add(
          'Prenez une photo datée de la lésion et faites-la examiner; évitez les produits destinés à la brûler ou à la retirer.',
        );
      }
      if (all({'household_spread', 'night_itch'})) {
        next.add(
          'Signalez les démangeaisons des proches pour organiser, si une gale est confirmée, le traitement des contacts.',
        );
      }
    case 'pregnancy':
      if (has('nausea') && !maternityNow && canDrink) {
        care.add(
          'Prenez de petits repas fréquents et buvez par petites gorgées; signalez une perte de poids ou une baisse des urines.',
        );
      }
      if (has('palms_soles_itch')) {
        next.add(
          'Signalez les démangeaisons des paumes ou des plantes, surtout nocturnes; un bilan hépatique peut être nécessaire.',
        );
      }
      if (has('mild_swelling') && !has('sudden_swelling')) {
        care.add(
          'Surélevez les jambes au repos et évitez de rester longtemps debout.',
        );
      }
    case 'chest':
      care.add(
        'Évitez les efforts qui déclenchent la gêne jusqu’à l’évaluation.',
      );
      if (has('palpitations')) {
        next.add(
          'Notez la durée des palpitations et leurs déclencheurs; un examen et un ECG peuvent être nécessaires.',
        );
        if (has('stimulant_trigger')) {
          care.add(
            'Évitez les boissons énergisantes et réduisez la caféine qui déclenche les épisodes.',
          );
        }
      }
    case 'urinary':
      if (has('urinary_treatment_failure')) {
        next.add(
          'Faites réévaluer aujourd’hui le traitement qui n’a pas amélioré les symptômes après 48 heures; apportez son nom et la date de début.',
        );
      } else if (urinarySigns) {
        next.add(
          'Un professionnel pourra demander une analyse d’urine et décider si un antibiotique est nécessaire.',
        );
      }
      if (has('blood_in_urine')) {
        next.add(
          'Faites vérifier le sang dans les urines, même s’il apparaît une seule fois ou sans douleur.',
        );
      }
      if (all({'large_urine_volume', 'excessive_thirst'})) {
        next.add(
          'Faites contrôler rapidement la glycémie; signalez aussi une perte de poids si elle existe.',
        );
      }
      if (any({'urinary_leakage', 'night_urination', 'urinary_frequency'})) {
        care.add(
          'Notez les boissons, les passages aux toilettes et les fuites pour la consultation; ne réduisez pas fortement les boissons pour éviter les fuites.',
        );
      }
      if (any({'genital_discharge', 'sexual_exposure', 'genital_sores'})) {
        next.add(
          'Demandez un dépistage des infections sexuellement transmissibles et évitez les rapports jusqu’à l’avis du professionnel.',
        );
      }
      if (urinarySigns) {
        pharmacy.add(
          'N’utilisez pas d’antibiotiques restants ou appartenant à quelqu’un d’autre; ne modifiez pas seul un traitement prescrit.',
        );
      }
    case 'dizziness':
      care.add(
        'Asseyez-vous ou allongez-vous jusqu’à la fin du malaise; levez-vous ensuite lentement.',
      );
      care.add(
        'Évitez de conduire, de monter sur une échelle ou d’utiliser une machine tant que les vertiges persistent.',
      );
      if (has('sudden_hearing_loss')) {
        next.add(
          'Faites contrôler la baisse soudaine de l’audition par un service ORL ou hospitalier dans les 24 heures.',
        );
      } else if (all({'brief_positional_vertigo', 'positional_trigger'})) {
        next.add(
          'Un professionnel pourra confirmer un vertige positionnel et proposer une manœuvre adaptée.',
        );
      }
      if (has('low_glucose_pattern') || has('diabetes_context')) {
        next.add(
          'Si vous disposez d’un lecteur, contrôlez la glycémie et suivez votre plan habituel en cas d’hypoglycémie; demandez de l’aide si le malaise persiste.',
        );
      }
      if (has('new_medication')) {
        next.add(
          'Faites vérifier le nouveau médicament et sa dose par le prescripteur; ne l’arrêtez pas de vous-même.',
        );
      }
    case 'fever':
      care.add(
        'Mesurez et notez la température, les horaires et l’évolution de l’état général.',
      );
      if (dengue) {
        next.add(
          'Faites évaluer la possibilité de dengue; un saignement, une forte douleur abdominale ou des vomissements persistants nécessitent une aide immédiate, même après la baisse de la fièvre.',
        );
      }
      if (all({'malaria_pattern', 'travel_to_malaria_area'})) {
        next.add(
          'Demandez aujourd’hui une évaluation et un test du paludisme; précisez les lieux de résidence ou de séjour.',
        );
      }
      if (has('urinary_focus') && urinarySigns) {
        next.add(
          'Signalez les symptômes urinaires associés à la fièvre; une analyse d’urine et un traitement peuvent être nécessaires.',
        );
      }
      if (child) {
        care.add(
          'Surveillez le comportement, la respiration et les boissons de l’enfant, y compris la nuit; ne le couvrez pas excessivement.',
        );
      }
    default:
      care.addAll(pathway.selfCare);
      pharmacy.addAll(pathway.pharmacyAdvice);
  }

  if (reflux &&
      !any({'difficulty_swallowing', 'severe_pain', 'digestive_bleeding'})) {
    care.add(
      'Prenez des repas plus petits, évitez les aliments qui déclenchent les remontées et ne vous allongez pas juste après avoir mangé.',
    );
    pharmacy.add(
      'Pour les brûlures et remontées acides, demandez au pharmacien si un antiacide ou un alginate convient à votre situation.',
    );
  }

  if (!has('frequent_pain_medicine') &&
      any({'pulsating', 'pressure', 'cramps', 'fever', 'acute_fever'})) {
    pharmacy.add(
      'Si la douleur ou la fièvre vous gêne, demandez au pharmacien si le paracétamol vous convient; respectez la notice et évitez les produits qui en contiennent déjà.',
    );
  }

  if (!maternityNow) {
    next.add(switch (pathway.id) {
      'back' =>
        'Appelez le 116 si apparaissent une faiblesse des jambes, une perte de sensation entre les jambes, une difficulté à uriner ou une perte du contrôle des urines ou des selles.',
      'joint' =>
        'Consultez aujourd’hui si l’articulation devient chaude et gonflée ou si une fièvre apparaît; allez aux urgences si vous ne pouvez plus prendre appui ou si le membre devient froid ou insensible.',
      'eyes' =>
        'Allez aux urgences immédiatement en cas de perte de vision, rideau noir, douleur très forte ou projection chimique; faites-vous accompagner.',
      'dental' =>
        'Appelez le 116 si le gonflement atteint le cou ou l’œil, ou si respirer, avaler ou ouvrir la bouche devient difficile.',
      'abdominal' =>
        'Appelez le 116 en cas de douleur très forte, ventre dur, sang vomi, selles noires ou perte de connaissance.',
      'headache' =>
        'Appelez le 116 si la douleur devient brutale et extrême, ou s’accompagne d’un trouble de la parole, d’une faiblesse, d’une confusion ou de fièvre avec raideur de nuque.',
      'menstrual' =>
        'Appelez le 116 si le saignement devient incontrôlable, avec malaise ou essoufflement, ou si une douleur pelvienne brutale apparaît.',
      'respiratory' || 'chest' =>
        'Appelez le 116 en cas de difficulté importante à respirer, douleur thoracique persistante, confusion ou perte de connaissance.',
      'skin' =>
        'Appelez le 116 en cas de difficulté à respirer, gonflement de la langue, décollement étendu de la peau ou douleur cutanée extrême.',
      'pregnancy' =>
        'Appelez le 116 en cas de fort mal de tête, trouble visuel, forte douleur abdominale, saignement important ou difficulté à respirer.',
      'urinary' =>
        'Consultez aujourd’hui si une fièvre ou une douleur du dos apparaît; appelez le 116 en cas d’impossibilité d’uriner, confusion ou malaise important.',
      'dizziness' =>
        'Appelez le 116 si apparaissent une faiblesse d’un côté, un trouble de la parole, une incapacité à marcher, une douleur thoracique ou une perte de connaissance avec récupération incomplète.',
      _ =>
        'Appelez le 116 en cas de confusion, difficulté à respirer, raideur de nuque, taches violacées ou malaise important.',
    });
  }

  final medicationReview =
      maternal ||
      child ||
      any({
        'breastfeeding',
        'anticoagulant',
        'immunocompromised',
        'diabetes_context',
        'complicated_urinary_context',
        'context_allergies',
        'context_medications',
      }) ||
      (context['conditions'] as List?)?.isNotEmpty == true;
  if (medicationReview) {
    pharmacy
      ..clear()
      ..add(noNewMedication);
  }
  if (dengue) {
    pharmacy.add(
      'Une dengue est possible : évitez l’aspirine et l’ibuprofène à cause du risque de saignement.',
    );
  }
  // No unconditional drug or self-care catalogue: absence of a matching rule
  // leaves that section empty instead of suggesting unrelated treatments.
  return _AssessmentGuidance(
    next.toSet().toList(),
    care.toSet().toList(),
    pharmacy.toSet().toList(),
  );
}

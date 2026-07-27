import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AssessmentUrgency {
  selfCare,
  consultationSoon,
  consultationToday,
  emergency,
}

extension AssessmentUrgencyText on AssessmentUrgency {
  String get label => switch (this) {
    AssessmentUrgency.selfCare => 'Surveillance et soins prudents',
    AssessmentUrgency.consultationSoon => 'Consultation recommandée',
    AssessmentUrgency.consultationToday => 'Avis médical aujourd’hui',
    AssessmentUrgency.emergency => 'Urgence médicale',
  };

  String get description => switch (this) {
    AssessmentUrgency.selfCare =>
      'Aucun signe d’alerte majeur n’apparaît dans les réponses. Surveillez l’évolution.',
    AssessmentUrgency.consultationSoon =>
      'Prenez rendez-vous prochainement, surtout si le malaise persiste ou revient.',
    AssessmentUrgency.consultationToday =>
      'Faites-vous évaluer aujourd’hui dans une clinique, une maternité ou un hôpital.',
    AssessmentUrgency.emergency =>
      'N’attendez pas la fin de cette évaluation. Appelez le Centre Ambulancier National au 116 ou allez aux urgences.',
  };

  int get priority => index;
}

class AssessmentOption {
  final String id;
  final String label;
  final IconData icon;
  final Set<String> tags;
  final AssessmentUrgency urgency;
  final String? nextQuestionId;

  const AssessmentOption({
    required this.id,
    required this.label,
    required this.icon,
    this.tags = const {},
    this.urgency = AssessmentUrgency.selfCare,
    this.nextQuestionId,
  });
}

class AssessmentQuestion {
  final String id;
  final String title;
  final String prompt;
  final IconData icon;
  final List<AssessmentOption> options;
  final Set<String> requiredTags;
  final Set<String> excludedTags;

  const AssessmentQuestion({
    required this.id,
    required this.title,
    required this.prompt,
    required this.icon,
    required this.options,
    this.requiredTags = const {},
    this.excludedTags = const {},
  });

  bool appliesTo(Set<String> tags) =>
      requiredTags.every(tags.contains) &&
      excludedTags.every((tag) => !tags.contains(tag));
}

class AssessmentPossibility {
  final String title;
  final String explanation;
  final Map<String, int> tagWeights;
  final int baseScore;

  const AssessmentPossibility({
    required this.title,
    required this.explanation,
    required this.tagWeights,
    this.baseScore = 8,
  });

  AssessmentMatch score(Set<String> tags) {
    final matched = tagWeights.entries
        .where((entry) => tags.contains(entry.key))
        .toList(growable: false);
    final raw =
        baseScore + matched.fold<int>(0, (sum, item) => sum + item.value);
    return AssessmentMatch(
      title: title,
      explanation: explanation,
      compatibility: raw.clamp(8, 92),
      matchedTags: matched.map((entry) => entry.key).toList(growable: false),
    );
  }
}

class AssessmentPathway {
  final String id;
  final int version;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<AssessmentQuestion> questions;
  final List<AssessmentPossibility> possibilities;
  final List<String> selfCare;
  final List<String> pharmacyAdvice;

  const AssessmentPathway({
    required this.id,
    this.version = 1,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.questions,
    required this.possibilities,
    required this.selfCare,
    this.pharmacyAdvice = const [],
  });

  AssessmentQuestion? questionById(String? id) {
    if (id == null) return null;
    for (final question in questions) {
      if (question.id == id) return question;
    }
    return null;
  }
}

class AssessmentMatch {
  final String title;
  final String explanation;
  final int compatibility;
  final List<String> matchedTags;

  const AssessmentMatch({
    required this.title,
    required this.explanation,
    required this.compatibility,
    required this.matchedTags,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'explanation': explanation,
    'compatibility': compatibility,
  };

  factory AssessmentMatch.fromMap(Map<String, dynamic> map) => AssessmentMatch(
    title: map['title']?.toString() ?? '',
    explanation: map['explanation']?.toString() ?? '',
    compatibility: (map['compatibility'] as num?)?.round() ?? 0,
    matchedTags: const [],
  );
}

class AssessmentResult {
  final AssessmentUrgency urgency;
  final List<AssessmentMatch> matches;
  final List<String> nextSteps;
  final List<String> selfCare;
  final List<String> pharmacyAdvice;
  final List<String> contextNotes;

  const AssessmentResult({
    required this.urgency,
    required this.matches,
    required this.nextSteps,
    required this.selfCare,
    required this.pharmacyAdvice,
    required this.contextNotes,
  });

  Map<String, dynamic> toMap() => {
    'urgency': urgency.name,
    'matches': matches.map((item) => item.toMap()).toList(),
    'nextSteps': nextSteps,
    'selfCare': selfCare,
    'pharmacyAdvice': pharmacyAdvice,
    'contextNotes': contextNotes,
    'disclaimer':
        'Les indices indiquent une compatibilité des réponses, pas une probabilité diagnostique.',
  };

  factory AssessmentResult.fromMap(Map<String, dynamic> map) {
    final urgencyName = map['urgency']?.toString();
    final urgency = AssessmentUrgency.values.firstWhere(
      (value) => value.name == urgencyName,
      orElse: () => AssessmentUrgency.consultationSoon,
    );
    List<String> strings(String key) =>
        (map[key] as List?)?.map((item) => item.toString()).toList() ??
        const [];
    final rawMatches = map['matches'] as List? ?? const [];
    return AssessmentResult(
      urgency: urgency,
      matches: rawMatches
          .whereType<Map>()
          .map(
            (item) => AssessmentMatch.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
      nextSteps: strings('nextSteps'),
      selfCare: strings('selfCare'),
      pharmacyAdvice: strings('pharmacyAdvice'),
      contextNotes: strings('contextNotes'),
    );
  }
}

class AssessmentEngine {
  const AssessmentEngine();

  Set<String> answerTags(
    AssessmentPathway pathway,
    Map<String, String> answers,
  ) {
    final tags = <String>{};
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key);
      if (question == null) continue;
      for (final option in question.options) {
        if (option.id == entry.value) tags.addAll(option.tags);
      }
    }
    return tags;
  }

  AssessmentQuestion? nextQuestion(
    AssessmentPathway pathway,
    Map<String, String> answers, {
    String? afterQuestionId,
  }) {
    final tags = answerTags(pathway, answers);
    var start = 0;
    if (afterQuestionId != null) {
      final index = pathway.questions.indexWhere(
        (question) => question.id == afterQuestionId,
      );
      start = math.max(0, index + 1);
      final current = pathway.questionById(afterQuestionId);
      if (current != null) {
        final selectedId = answers[afterQuestionId];
        final selected = current.options
            .where((option) => option.id == selectedId)
            .firstOrNull;
        final explicit = pathway.questionById(selected?.nextQuestionId);
        if (explicit != null && explicit.appliesTo(tags)) return explicit;
      }
    }
    for (var index = start; index < pathway.questions.length; index++) {
      final candidate = pathway.questions[index];
      if (!answers.containsKey(candidate.id) && candidate.appliesTo(tags)) {
        return candidate;
      }
    }
    return null;
  }

  int progress(AssessmentPathway pathway, Map<String, String> answers) {
    if (answers.isEmpty) return 0;
    final visible = pathway.questions
        .where((question) => question.appliesTo(answerTags(pathway, answers)))
        .length;
    if (visible == 0) return 0;
    return ((answers.length / visible) * 100).round().clamp(1, 100);
  }

  AssessmentResult evaluate(
    AssessmentPathway pathway,
    Map<String, String> answers, {
    Map<String, dynamic> context = const {},
  }) {
    final tags = answerTags(pathway, answers);
    final contextNotes = <String>[];
    if (context['pregnancy'] == true) {
      tags.add('context_pregnant');
      contextNotes.add(
        'La grossesse déclarée dans le profil a renforcé le niveau de prudence.',
      );
    }
    final age = (context['age'] as num?)?.round();
    if (age != null && (age < 12 || age >= 65)) {
      tags.add('context_vulnerable_age');
      contextNotes.add(
        'L’âge enregistré justifie une évaluation professionnelle plus prudente.',
      );
    }
    if ((context['allergies'] as List?)?.isNotEmpty == true) {
      tags.add('context_allergies');
      contextNotes.add(
        'Les allergies du dossier doivent être montrées au médecin ou au pharmacien.',
      );
    }
    if ((context['medications'] as List?)?.isNotEmpty == true) {
      tags.add('context_medications');
      contextNotes.add(
        'Les traitements actuels peuvent modifier les choix de médicaments.',
      );
    }
    if (context['recentHighTemperature'] == true) {
      tags.add('fever');
      contextNotes.add(
        'Une température élevée récente a été détectée dans le suivi autorisé.',
      );
    }

    var urgency = AssessmentUrgency.selfCare;
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key);
      if (question == null) continue;
      final option = question.options
          .where((item) => item.id == entry.value)
          .firstOrNull;
      if (option != null && option.urgency.priority > urgency.priority) {
        urgency = option.urgency;
      }
    }

    if (tags.contains('context_pregnant') &&
        (tags.contains('bleeding') ||
            tags.contains('severe_pain') ||
            tags.contains('severe_headache'))) {
      urgency = AssessmentUrgency.emergency;
    } else if (tags.contains('context_vulnerable_age') &&
        urgency == AssessmentUrgency.selfCare) {
      urgency = AssessmentUrgency.consultationSoon;
    }

    final matches =
        pathway.possibilities
            .map((possibility) => possibility.score(tags))
            .where((match) => match.compatibility >= 24)
            .toList()
          ..sort(
            (first, second) =>
                second.compatibility.compareTo(first.compatibility),
          );
    final limitedMatches = matches.take(3).toList(growable: false);

    final nextSteps = switch (urgency) {
      AssessmentUrgency.emergency => [
        'Appelez le Centre Ambulancier National au 116 ou faites-vous accompagner vers les urgences.',
        'Ne conduisez pas vous-même si vous êtes faible, confus(e), essoufflé(e) ou sur le point de perdre connaissance.',
        'Emportez votre liste de médicaments, d’allergies et vos documents de santé.',
      ],
      AssessmentUrgency.consultationToday => [
        'Contactez aujourd’hui une clinique, une maternité ou un médecin.',
        'Si un signe d’alerte apparaît ou s’aggrave, appelez immédiatement le 116.',
      ],
      AssessmentUrgency.consultationSoon => [
        'Prenez rendez-vous dans les prochains jours pour confirmer la cause.',
        'Consultez plus vite si la douleur, la fièvre, le saignement ou l’essoufflement augmente.',
      ],
      AssessmentUrgency.selfCare => [
        'Surveillez les symptômes et refaites une évaluation s’ils changent.',
        'Prenez rendez-vous si le malaise persiste, revient souvent ou vous inquiète.',
      ],
    };

    final medicationUnsafe =
        urgency == AssessmentUrgency.emergency ||
        tags.contains('context_pregnant') ||
        tags.contains('pregnancy_possible');
    return AssessmentResult(
      urgency: urgency,
      matches: limitedMatches.isEmpty
          ? const [
              AssessmentMatch(
                title: 'Cause non spécifique',
                explanation:
                    'Les réponses ne correspondent pas assez clairement à une cause fréquente. Une consultation peut préciser la situation.',
                compatibility: 24,
                matchedTags: [],
              ),
            ]
          : limitedMatches,
      nextSteps: nextSteps,
      selfCare: urgency == AssessmentUrgency.emergency
          ? const []
          : pathway.selfCare,
      pharmacyAdvice: medicationUnsafe
          ? const [
              'Ne commencez pas de nouveau médicament sans avis médical ou pharmaceutique dans cette situation.',
            ]
          : [
              ...pathway.pharmacyAdvice,
              if (tags.contains('context_allergies') ||
                  tags.contains('context_medications'))
                'Montrez vos allergies et traitements actuels au pharmacien avant tout achat.',
            ],
      contextNotes: contextNotes,
    );
  }
}

const assessmentPathways = <AssessmentPathway>[
  AssessmentPathway(
    id: 'abdominal',
    title: 'Mal au ventre',
    subtitle: 'Douleur, crampes, nausée ou trouble digestif',
    icon: Icons.sick_outlined,
    color: Color(0xFFF29D49),
    questions: [
      AssessmentQuestion(
        id: 'abdominal_onset',
        title: 'Début du malaise',
        prompt: 'Depuis quand avez-vous mal au ventre ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'sudden',
            label: 'Très soudainement',
            icon: Icons.bolt_outlined,
            tags: {'sudden'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'hours',
            label: 'Depuis quelques heures',
            icon: Icons.timelapse_outlined,
            tags: {'acute'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis plusieurs jours',
            icon: Icons.calendar_today_outlined,
            tags: {'persistent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'recurrent',
            label: 'Cela revient régulièrement',
            icon: Icons.replay_outlined,
            tags: {'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_location',
        title: 'Zone douloureuse',
        prompt: 'Où ressentez-vous surtout la douleur ?',
        icon: Icons.my_location_outlined,
        options: [
          AssessmentOption(
            id: 'upper',
            label: 'En haut ou après les repas',
            icon: Icons.arrow_upward_outlined,
            tags: {'upper_abdomen', 'after_meal'},
          ),
          AssessmentOption(
            id: 'lower_right',
            label: 'En bas à droite',
            icon: Icons.south_east_outlined,
            tags: {'lower_right'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'lower',
            label: 'Dans le bas-ventre',
            icon: Icons.arrow_downward_outlined,
            tags: {'lower_abdomen'},
          ),
          AssessmentOption(
            id: 'diffuse',
            label: 'Partout ou en crampes',
            icon: Icons.blur_circular_outlined,
            tags: {'diffuse', 'cramps'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_intensity',
        title: 'Intensité',
        prompt: 'Quelle est l’intensité de la douleur maintenant ?',
        icon: Icons.speed_outlined,
        options: [
          AssessmentOption(
            id: 'mild',
            label: 'Légère, je fonctionne normalement',
            icon: Icons.sentiment_satisfied_alt_outlined,
            tags: {'mild_pain'},
          ),
          AssessmentOption(
            id: 'moderate',
            label: 'Modérée, elle me gêne',
            icon: Icons.sentiment_neutral_outlined,
            tags: {'moderate_pain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'severe',
            label: 'Très forte ou insupportable',
            icon: Icons.warning_amber_rounded,
            tags: {'severe_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'rigid',
            label: 'Ventre dur ou très douloureux au toucher',
            icon: Icons.pan_tool_alt_outlined,
            tags: {'rigid_abdomen', 'severe_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_associated',
        title: 'Autres signes',
        prompt: 'Quel autre signe accompagne le mieux la douleur ?',
        icon: Icons.playlist_add_check_circle_outlined,
        options: [
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ceux-ci',
            icon: Icons.remove_circle_outline,
            tags: {'isolated_pain'},
          ),
          AssessmentOption(
            id: 'vomit_diarrhea',
            label: 'Vomissements ou diarrhée',
            icon: Icons.water_drop_outlined,
            tags: {'vomiting', 'diarrhea'},
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Fièvre ou frissons',
            icon: Icons.thermostat_outlined,
            tags: {'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'blood',
            label: 'Sang vomi, selles sanglantes ou noires',
            icon: Icons.emergency_outlined,
            tags: {'bleeding', 'digestive_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_drink',
        title: 'Hydratation',
        prompt: 'Arrivez-vous à boire et à garder les liquides ?',
        icon: Icons.local_drink_outlined,
        options: [
          AssessmentOption(
            id: 'yes',
            label: 'Oui, normalement',
            icon: Icons.check_circle_outline,
            tags: {'hydrated'},
          ),
          AssessmentOption(
            id: 'little',
            label: 'Un peu seulement',
            icon: Icons.opacity_outlined,
            tags: {'dehydration_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'no',
            label: 'Non, je vomis tout ou je suis très faible',
            icon: Icons.warning_amber_rounded,
            tags: {'cannot_hydrate', 'dehydration_risk'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_context',
        title: 'Contexte important',
        prompt: 'L’une de ces situations vous concerne-t-elle ?',
        icon: Icons.info_outline,
        options: [
          AssessmentOption(
            id: 'urinary',
            label: 'Douleur ou brûlure en urinant',
            icon: Icons.water_outlined,
            tags: {'urinary'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pregnancy',
            label: 'Grossesse possible ou confirmée',
            icon: Icons.pregnant_woman_outlined,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'collapse',
            label: 'Malaise, confusion ou perte de connaissance',
            icon: Icons.personal_injury_outlined,
            tags: {'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_outlined,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Gastro-entérite ou irritation digestive',
        explanation:
            'Des crampes avec diarrhée ou vomissements sont compatibles avec une irritation ou une infection digestive.',
        tagWeights: {'diarrhea': 28, 'vomiting': 22, 'diffuse': 12, 'acute': 8},
      ),
      AssessmentPossibility(
        title: 'Appendicite possible',
        explanation:
            'Une douleur en bas à droite, surtout avec fièvre ou nausée, nécessite un examen médical rapide.',
        tagWeights: {
          'lower_right': 42,
          'fever': 25,
          'vomiting': 15,
          'severe_pain': 12,
        },
      ),
      AssessmentPossibility(
        title: 'Reflux, gastrite ou indigestion',
        explanation:
            'Une gêne du haut du ventre liée aux repas peut correspondre à une irritation gastrique.',
        tagWeights: {
          'upper_abdomen': 30,
          'after_meal': 24,
          'recurrent': 12,
          'mild_pain': 6,
        },
      ),
      AssessmentPossibility(
        title: 'Problème urinaire ou calcul',
        explanation:
            'La douleur abdominale associée à une gêne urinaire peut venir des voies urinaires.',
        tagWeights: {
          'urinary': 42,
          'lower_abdomen': 18,
          'fever': 16,
          'severe_pain': 10,
        },
      ),
    ],
    selfCare: [
      'Buvez régulièrement de petites quantités d’eau ou de solution de réhydratation.',
      'Choisissez des aliments simples si vous pouvez manger et évitez l’alcool.',
    ],
    pharmacyAdvice: [
      'Une solution de réhydratation orale peut aider en cas de diarrhée ou de vomissements légers.',
      'Demandez conseil au pharmacien avant un antidouleur; certains anti-inflammatoires peuvent irriter l’estomac.',
    ],
  ),
  AssessmentPathway(
    id: 'headache',
    title: 'Migraine ou mal de tête',
    subtitle: 'Douleur à la tête, lumière gênante ou nausée',
    icon: Icons.psychology_alt_outlined,
    color: Color(0xFF7759D8),
    questions: [
      AssessmentQuestion(
        id: 'headache_onset',
        title: 'Apparition',
        prompt: 'Comment ce mal de tête a-t-il commencé ?',
        icon: Icons.bolt_outlined,
        options: [
          AssessmentOption(
            id: 'thunderclap',
            label: 'Brutalement, le pire de ma vie',
            icon: Icons.emergency_outlined,
            tags: {'thunderclap', 'severe_headache'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'gradual',
            label: 'Progressivement aujourd’hui',
            icon: Icons.trending_up_outlined,
            tags: {'gradual'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis plusieurs jours',
            icon: Icons.calendar_today_outlined,
            tags: {'persistent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'usual',
            label: 'C’est similaire à mes crises habituelles',
            icon: Icons.replay_outlined,
            tags: {'recurrent', 'usual_pattern'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_pattern',
        title: 'Type de douleur',
        prompt: 'Quelle description correspond le mieux ?',
        icon: Icons.graphic_eq_outlined,
        options: [
          AssessmentOption(
            id: 'one_side',
            label: 'D’un côté et pulsatile',
            icon: Icons.flash_on_outlined,
            tags: {'one_sided', 'pulsating'},
          ),
          AssessmentOption(
            id: 'band',
            label: 'Comme un bandeau ou une pression',
            icon: Icons.compress_outlined,
            tags: {'pressure', 'bilateral'},
          ),
          AssessmentOption(
            id: 'face',
            label: 'Front ou visage avec nez bouché',
            icon: Icons.face_outlined,
            tags: {'facial_pressure', 'congestion'},
          ),
          AssessmentOption(
            id: 'general',
            label: 'Diffuse, difficile à décrire',
            icon: Icons.blur_on_outlined,
            tags: {'diffuse'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_associated',
        title: 'Signes associés',
        prompt: 'Qu’est-ce qui accompagne surtout la douleur ?',
        icon: Icons.light_mode_outlined,
        options: [
          AssessmentOption(
            id: 'light_nausea',
            label: 'Lumière ou bruit gênant, avec nausée',
            icon: Icons.brightness_6_outlined,
            tags: {'photophobia', 'nausea'},
          ),
          AssessmentOption(
            id: 'neck_tension',
            label: 'Tension du cou, fatigue ou stress',
            icon: Icons.self_improvement_outlined,
            tags: {'neck_tension', 'stress'},
          ),
          AssessmentOption(
            id: 'fever_stiff',
            label: 'Fièvre, nuque raide ou éruption inhabituelle',
            icon: Icons.emergency_outlined,
            tags: {'fever', 'stiff_neck', 'severe_headache'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ceux-ci',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_neuro',
        title: 'Signes neurologiques',
        prompt: 'Avez-vous remarqué l’un de ces signes ?',
        icon: Icons.psychology_outlined,
        options: [
          AssessmentOption(
            id: 'weakness',
            label: 'Faiblesse d’un côté ou difficulté à parler',
            icon: Icons.emergency_outlined,
            tags: {'neurologic_deficit'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'confusion',
            label: 'Confusion, convulsion ou évanouissement',
            icon: Icons.personal_injury_outlined,
            tags: {'confusion', 'seizure'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'vision',
            label: 'Vision trouble nouvelle ou persistante',
            icon: Icons.visibility_off_outlined,
            tags: {'vision_change'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_context',
        title: 'Contexte',
        prompt: 'Quelle situation s’applique ?',
        icon: Icons.health_and_safety_outlined,
        options: [
          AssessmentOption(
            id: 'injury',
            label: 'Après un choc à la tête',
            icon: Icons.sports_martial_arts_outlined,
            tags: {'head_injury'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pregnant',
            label: 'Enceinte ou récemment accouchée',
            icon: Icons.pregnant_woman_outlined,
            tags: {'pregnancy_possible', 'severe_headache'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'dehydrated',
            label: 'Peu bu, chaleur ou repas sauté',
            icon: Icons.local_drink_outlined,
            tags: {'dehydration_risk'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_outlined,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Migraine',
        explanation:
            'Une douleur pulsatile d’un côté avec gêne à la lumière, au bruit ou nausée est compatible avec une migraine.',
        tagWeights: {
          'one_sided': 25,
          'pulsating': 24,
          'photophobia': 25,
          'nausea': 18,
          'usual_pattern': 10,
        },
      ),
      AssessmentPossibility(
        title: 'Céphalée de tension',
        explanation:
            'Une pression en bandeau avec tension du cou ou stress peut correspondre à une céphalée de tension.',
        tagWeights: {
          'pressure': 30,
          'bilateral': 18,
          'neck_tension': 26,
          'stress': 18,
        },
      ),
      AssessmentPossibility(
        title: 'Céphalée liée à une congestion',
        explanation:
            'Une pression du visage avec nez bouché peut accompagner une infection respiratoire ou une inflammation des sinus.',
        tagWeights: {'facial_pressure': 32, 'congestion': 32, 'fever': 10},
      ),
      AssessmentPossibility(
        title: 'Déshydratation ou fatigue',
        explanation:
            'Le manque d’eau, la chaleur, le manque de sommeil ou un repas sauté peuvent favoriser un mal de tête.',
        tagWeights: {'dehydration_risk': 42, 'gradual': 12, 'diffuse': 12},
      ),
    ],
    selfCare: [
      'Reposez-vous dans un endroit calme et sombre, hydratez-vous et évitez les écrans si cela aggrave la douleur.',
      'Notez le début, la durée et les déclencheurs pour en parler lors d’une consultation.',
    ],
    pharmacyAdvice: [
      'Le paracétamol peut parfois soulager un mal de tête léger; suivez strictement l’étiquette et évitez de cumuler des produits qui en contiennent.',
      'Demandez au pharmacien avant un anti-inflammatoire si vous avez un ulcère, une maladie rénale, prenez un anticoagulant ou pourriez être enceinte.',
    ],
  ),
  AssessmentPathway(
    id: 'menstrual',
    title: 'Santé menstruelle',
    subtitle: 'Règles douloureuses, irrégulières ou saignement',
    icon: Icons.water_drop_outlined,
    color: Color(0xFFE65F91),
    questions: [
      AssessmentQuestion(
        id: 'menstrual_concern',
        title: 'Malaise principal',
        prompt: 'Qu’est-ce qui vous préoccupe le plus ?',
        icon: Icons.favorite_border_outlined,
        options: [
          AssessmentOption(
            id: 'pain',
            label: 'Douleurs ou crampes',
            icon: Icons.waves_outlined,
            tags: {'cramps'},
          ),
          AssessmentOption(
            id: 'heavy',
            label: 'Saignement plus abondant',
            icon: Icons.water_drop_outlined,
            tags: {'heavy_bleeding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'irregular',
            label: 'Règles irrégulières ou absentes',
            icon: Icons.event_busy_outlined,
            tags: {'irregular_cycle'},
          ),
          AssessmentOption(
            id: 'discharge',
            label: 'Pertes inhabituelles ou irritation',
            icon: Icons.info_outline,
            tags: {'discharge'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_severity',
        title: 'Intensité',
        prompt: 'Quelle situation correspond le mieux ?',
        icon: Icons.speed_outlined,
        options: [
          AssessmentOption(
            id: 'manageable',
            label: 'Gênant mais supportable',
            icon: Icons.sentiment_satisfied_outlined,
            tags: {'mild_pain'},
          ),
          AssessmentOption(
            id: 'limits',
            label: 'M’empêche de travailler ou dormir',
            icon: Icons.bedtime_outlined,
            tags: {'moderate_pain', 'activity_limiting'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'severe',
            label: 'Douleur brutale ou insupportable',
            icon: Icons.warning_amber_rounded,
            tags: {'severe_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'very_heavy',
            label: 'Une protection saturée par heure pendant 2 heures',
            icon: Icons.emergency_outlined,
            tags: {'bleeding', 'very_heavy_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_associated',
        title: 'Autres signes',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.playlist_add_check_circle_outlined,
        options: [
          AssessmentOption(
            id: 'dizzy',
            label: 'Vertiges, faiblesse ou évanouissement',
            icon: Icons.personal_injury_outlined,
            tags: {'dizziness', 'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Fièvre, mauvaise odeur ou forte douleur pelvienne',
            icon: Icons.thermostat_outlined,
            tags: {'fever', 'pelvic_pain', 'discharge'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'chronic',
            label: 'Douleur pendant les rapports ou depuis plusieurs cycles',
            icon: Icons.replay_outlined,
            tags: {'chronic_pelvic_pain', 'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_pregnancy',
        title: 'Possibilité de grossesse',
        prompt: 'Une grossesse est-elle possible ?',
        icon: Icons.pregnant_woman_outlined,
        options: [
          AssessmentOption(
            id: 'yes_bleeding',
            label: 'Oui, avec douleur ou saignement',
            icon: Icons.emergency_outlined,
            tags: {'pregnancy_possible', 'bleeding', 'pelvic_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'yes_no_bleeding',
            label: 'Oui, sans douleur forte ni saignement',
            icon: Icons.help_outline,
            tags: {'pregnancy_possible', 'missed_period'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(id: 'no', label: 'Non', icon: Icons.close_outlined),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.question_mark_outlined,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_change',
        title: 'Évolution',
        prompt: 'Depuis combien de temps ce changement existe-t-il ?',
        icon: Icons.calendar_month_outlined,
        options: [
          AssessmentOption(
            id: 'first',
            label: 'C’est la première fois',
            icon: Icons.fiber_new_outlined,
            tags: {'new_pattern'},
          ),
          AssessmentOption(
            id: 'few_cycles',
            label: 'Depuis 2 ou 3 cycles',
            icon: Icons.date_range_outlined,
            tags: {'persistent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'long',
            label: 'Depuis longtemps',
            icon: Icons.history_outlined,
            tags: {'recurrent', 'chronic'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Dysménorrhée (règles douloureuses)',
        explanation:
            'Des crampes liées aux règles, sans signe d’alerte, sont compatibles avec des règles douloureuses.',
        tagWeights: {
          'cramps': 38,
          'mild_pain': 16,
          'moderate_pain': 18,
          'recurrent': 12,
        },
      ),
      AssessmentPossibility(
        title: 'Saignement menstruel abondant',
        explanation:
            'Un flux nettement plus important peut nécessiter un bilan, notamment pour rechercher une anémie ou une cause gynécologique.',
        tagWeights: {
          'heavy_bleeding': 38,
          'very_heavy_bleeding': 40,
          'dizziness': 18,
          'persistent': 10,
        },
      ),
      AssessmentPossibility(
        title: 'Cycle irrégulier ou cause hormonale',
        explanation:
            'Des règles retardées, absentes ou variables peuvent avoir plusieurs causes, dont le stress, une grossesse ou un changement hormonal.',
        tagWeights: {
          'irregular_cycle': 44,
          'missed_period': 28,
          'persistent': 12,
        },
      ),
      AssessmentPossibility(
        title: 'Infection ou inflammation pelvienne possible',
        explanation:
            'Des pertes inhabituelles avec fièvre ou douleur pelvienne doivent être évaluées rapidement.',
        tagWeights: {'discharge': 28, 'fever': 28, 'pelvic_pain': 26},
      ),
      AssessmentPossibility(
        title: 'Endométriose ou autre cause gynécologique possible',
        explanation:
            'Une douleur qui limite les activités, revient sur plusieurs cycles ou survient pendant les rapports mérite un bilan.',
        tagWeights: {
          'chronic_pelvic_pain': 35,
          'activity_limiting': 25,
          'recurrent': 18,
          'chronic': 12,
        },
      ),
    ],
    selfCare: [
      'Une bouillotte tiède et un repos adapté peuvent soulager des crampes légères.',
      'Notez les jours, le flux et les symptômes dans le suivi de cycle.',
    ],
    pharmacyAdvice: [
      'Demandez au pharmacien quel antidouleur est compatible avec vos antécédents et traitements.',
      'Évitez l’aspirine en cas de saignement important et demandez un avis si une grossesse est possible.',
    ],
  ),
  AssessmentPathway(
    id: 'respiratory',
    title: 'Santé respiratoire',
    subtitle: 'Toux, congestion, respiration sifflante ou essoufflement',
    icon: Icons.air_outlined,
    color: Color(0xFF149D9A),
    questions: [
      AssessmentQuestion(
        id: 'respiratory_breathing',
        title: 'Respiration maintenant',
        prompt: 'Comment respirez-vous en ce moment ?',
        icon: Icons.air_outlined,
        options: [
          AssessmentOption(
            id: 'normal',
            label: 'Normalement malgré la toux ou le nez bouché',
            icon: Icons.check_circle_outline,
            tags: {'breathing_ok'},
          ),
          AssessmentOption(
            id: 'mild',
            label: 'Un peu essoufflé(e), je parle normalement',
            icon: Icons.directions_walk_outlined,
            tags: {'mild_breathlessness'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'severe',
            label: 'Trop essoufflé(e) pour parler en phrases',
            icon: Icons.emergency_outlined,
            tags: {'severe_breathlessness'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'blue',
            label: 'Lèvres bleues/grises, confusion ou épuisement',
            icon: Icons.emergency_outlined,
            tags: {'cyanosis', 'confusion'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_main',
        title: 'Signe principal',
        prompt: 'Quel signe correspond le mieux ?',
        icon: Icons.medical_information_outlined,
        options: [
          AssessmentOption(
            id: 'dry_cough',
            label: 'Toux sèche ou gorge irritée',
            icon: Icons.record_voice_over_outlined,
            tags: {'dry_cough'},
          ),
          AssessmentOption(
            id: 'wet_cough',
            label: 'Toux avec crachats',
            icon: Icons.water_drop_outlined,
            tags: {'productive_cough'},
          ),
          AssessmentOption(
            id: 'wheeze',
            label: 'Sifflement ou oppression',
            icon: Icons.graphic_eq_outlined,
            tags: {'wheeze', 'chest_tightness'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'nose',
            label: 'Nez bouché, éternuements ou gorge',
            icon: Icons.face_outlined,
            tags: {'congestion', 'upper_respiratory'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_red_flags',
        title: 'Signes d’alerte',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.warning_amber_rounded,
        options: [
          AssessmentOption(
            id: 'chest_pain',
            label: 'Douleur ou forte pression dans la poitrine',
            icon: Icons.emergency_outlined,
            tags: {'chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'blood',
            label: 'Je crache du sang',
            icon: Icons.emergency_outlined,
            tags: {'coughing_blood'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Forte fièvre, frissons ou grande faiblesse',
            icon: Icons.thermostat_outlined,
            tags: {'fever', 'systemically_unwell'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_duration',
        title: 'Durée',
        prompt: 'Depuis quand avez-vous ces symptômes ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'today',
            label: 'Depuis aujourd’hui',
            icon: Icons.today_outlined,
            tags: {'acute'},
          ),
          AssessmentOption(
            id: 'few_days',
            label: 'Depuis quelques jours',
            icon: Icons.date_range_outlined,
            tags: {'days'},
          ),
          AssessmentOption(
            id: 'over_week',
            label: 'Plus d’une semaine ou aggravation',
            icon: Icons.trending_up_outlined,
            tags: {'persistent', 'worsening'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'weeks',
            label: 'Plus de trois semaines',
            icon: Icons.history_outlined,
            tags: {'chronic'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_context',
        title: 'Contexte respiratoire',
        prompt: 'Quelle situation vous concerne ?',
        icon: Icons.health_and_safety_outlined,
        options: [
          AssessmentOption(
            id: 'asthma',
            label: 'Asthme ou inhalateur habituel',
            icon: Icons.medication_outlined,
            tags: {'asthma_history'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'allergy',
            label: 'Après poussière, parfum, animal ou allergène',
            icon: Icons.grass_outlined,
            tags: {'allergen_trigger'},
          ),
          AssessmentOption(
            id: 'sick_contact',
            label: 'Après contact avec une personne malade',
            icon: Icons.groups_outlined,
            tags: {'sick_contact'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_outlined,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Infection respiratoire virale',
        explanation:
            'Toux, nez bouché, gorge irritée et contact malade sont compatibles avec une infection virale fréquente.',
        tagWeights: {
          'dry_cough': 20,
          'congestion': 24,
          'upper_respiratory': 20,
          'sick_contact': 20,
          'days': 8,
        },
      ),
      AssessmentPossibility(
        title: 'Asthme ou bronchospasme possible',
        explanation:
            'Un sifflement et une oppression, surtout avec un antécédent d’asthme, doivent être évalués.',
        tagWeights: {
          'wheeze': 34,
          'chest_tightness': 28,
          'asthma_history': 30,
          'allergen_trigger': 12,
        },
      ),
      AssessmentPossibility(
        title: 'Pneumonie ou infection basse possible',
        explanation:
            'Une toux avec fièvre, faiblesse ou essoufflement peut nécessiter un examen des poumons.',
        tagWeights: {
          'productive_cough': 22,
          'fever': 28,
          'systemically_unwell': 22,
          'mild_breathlessness': 16,
          'worsening': 10,
        },
      ),
      AssessmentPossibility(
        title: 'Allergie respiratoire',
        explanation:
            'Éternuements, congestion ou sifflement après un déclencheur peuvent correspondre à une réaction allergique.',
        tagWeights: {'allergen_trigger': 38, 'congestion': 22, 'wheeze': 20},
      ),
    ],
    selfCare: [
      'Reposez-vous, buvez régulièrement et évitez fumée, poussière et parfums irritants.',
      'Portez un masque si une infection transmissible est possible et aérez les espaces.',
    ],
    pharmacyAdvice: [
      'Une solution saline nasale peut aider pour une congestion simple.',
      'N’utilisez pas l’antibiotique ou l’inhalateur d’une autre personne; demandez conseil à un professionnel.',
    ],
  ),
  AssessmentPathway(
    id: 'skin',
    title: 'Problème de peau',
    subtitle: 'Boutons, plaques, démangeaisons ou irritation',
    icon: Icons.texture_outlined,
    color: Color(0xFFB56B45),
    questions: [
      AssessmentQuestion(
        id: 'skin_emergency',
        title: 'Réaction générale',
        prompt: 'L’éruption est-elle accompagnée d’un de ces signes ?',
        icon: Icons.health_and_safety_outlined,
        options: [
          AssessmentOption(
            id: 'breathing_swelling',
            label: 'Gonflement lèvres/langue ou difficulté à respirer',
            icon: Icons.emergency_outlined,
            tags: {'anaphylaxis', 'facial_swelling'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'purple_fever',
            label: 'Taches violettes qui ne pâlissent pas avec fièvre',
            icon: Icons.emergency_outlined,
            tags: {'non_blanching_rash', 'fever'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'peeling',
            label: 'Peau qui pèle largement ou plaies dans la bouche',
            icon: Icons.warning_amber_rounded,
            tags: {'widespread_peeling'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_appearance',
        title: 'Aspect',
        prompt: 'À quoi ressemble surtout le problème ?',
        icon: Icons.visibility_outlined,
        options: [
          AssessmentOption(
            id: 'dry',
            label: 'Plaques sèches ou rugueuses qui grattent',
            icon: Icons.texture_outlined,
            tags: {'dry_patch', 'itch'},
          ),
          AssessmentOption(
            id: 'hives',
            label: 'Plaques gonflées qui apparaissent et bougent',
            icon: Icons.bubble_chart_outlined,
            tags: {'hives', 'itch'},
          ),
          AssessmentOption(
            id: 'ring',
            label: 'Plaque ronde avec bord plus marqué',
            icon: Icons.circle_outlined,
            tags: {'ring_shaped', 'scaly'},
          ),
          AssessmentOption(
            id: 'pimples',
            label: 'Boutons, points noirs ou petites pustules',
            icon: Icons.grain_outlined,
            tags: {'pimples', 'pustules'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_sensation',
        title: 'Sensation',
        prompt: 'Que ressentez-vous principalement ?',
        icon: Icons.touch_app_outlined,
        options: [
          AssessmentOption(
            id: 'itch',
            label: 'Démangeaisons',
            icon: Icons.back_hand_outlined,
            tags: {'itch'},
          ),
          AssessmentOption(
            id: 'pain',
            label: 'Douleur ou chaleur locale',
            icon: Icons.local_fire_department_outlined,
            tags: {'painful_skin', 'warm_skin'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'blister',
            label: 'Brûlure ou cloques',
            icon: Icons.water_drop_outlined,
            tags: {'blister'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Peu de sensation',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_spread',
        title: 'Étendue',
        prompt: 'Comment le problème évolue-t-il ?',
        icon: Icons.open_in_full_outlined,
        options: [
          AssessmentOption(
            id: 'small',
            label: 'Petite zone stable',
            icon: Icons.crop_square_outlined,
            tags: {'localized'},
          ),
          AssessmentOption(
            id: 'spreading',
            label: 'S’étend rapidement',
            icon: Icons.zoom_out_map_outlined,
            tags: {'rapid_spread'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'face_eye',
            label: 'Près des yeux ou sur le visage',
            icon: Icons.face_outlined,
            tags: {'face_or_eye'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'widespread',
            label: 'Sur une grande partie du corps',
            icon: Icons.accessibility_new_outlined,
            tags: {'widespread'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_trigger',
        title: 'Déclencheur possible',
        prompt: 'Y a-t-il eu un changement récent ?',
        icon: Icons.search_outlined,
        options: [
          AssessmentOption(
            id: 'product',
            label: 'Nouveau savon, produit, bijou ou vêtement',
            icon: Icons.soap_outlined,
            tags: {'contact_trigger'},
          ),
          AssessmentOption(
            id: 'medicine',
            label: 'Nouveau médicament',
            icon: Icons.medication_outlined,
            tags: {'new_medication'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'heat',
            label: 'Chaleur, transpiration ou frottement',
            icon: Icons.sunny_snowing,
            tags: {'heat_trigger'},
          ),
          AssessmentOption(
            id: 'unknown',
            label: 'Aucun déclencheur connu',
            icon: Icons.help_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Dermatite ou eczéma',
        explanation:
            'Des plaques sèches qui démangent, parfois après un produit, sont compatibles avec une dermatite.',
        tagWeights: {
          'dry_patch': 35,
          'itch': 24,
          'contact_trigger': 28,
          'localized': 8,
        },
      ),
      AssessmentPossibility(
        title: 'Urticaire',
        explanation:
            'Des plaques gonflées et mobiles qui démangent peuvent correspondre à une urticaire.',
        tagWeights: {'hives': 48, 'itch': 22, 'new_medication': 14},
      ),
      AssessmentPossibility(
        title: 'Mycose cutanée possible',
        explanation:
            'Une plaque ronde et squameuse peut être compatible avec une infection fongique.',
        tagWeights: {
          'ring_shaped': 46,
          'scaly': 24,
          'itch': 12,
          'localized': 8,
        },
      ),
      AssessmentPossibility(
        title: 'Acné ou folliculite',
        explanation:
            'Des boutons ou petites pustules, parfois favorisés par chaleur et frottement, peuvent venir des follicules.',
        tagWeights: {'pimples': 40, 'pustules': 32, 'heat_trigger': 16},
      ),
      AssessmentPossibility(
        title: 'Infection de la peau possible',
        explanation:
            'Une zone douloureuse, chaude et qui s’étend doit être examinée rapidement.',
        tagWeights: {
          'painful_skin': 28,
          'warm_skin': 28,
          'rapid_spread': 30,
          'fever': 16,
        },
      ),
    ],
    selfCare: [
      'Évitez de gratter, utilisez un savon doux et gardez la zone propre et sèche.',
      'Arrêtez un nouveau produit cosmétique suspect, sauf s’il s’agit d’un traitement prescrit.',
    ],
    pharmacyAdvice: [
      'Une crème hydratante sans parfum peut aider une peau sèche non infectée.',
      'Faites confirmer une mycose ou une allergie par un pharmacien avant d’utiliser une crème médicamenteuse.',
    ],
  ),
  AssessmentPathway(
    id: 'pregnancy',
    title: 'Malaise pendant la grossesse',
    subtitle: 'Symptômes pendant la grossesse ou après l’accouchement',
    icon: Icons.pregnant_woman_outlined,
    color: Color(0xFF8D65CC),
    questions: [
      AssessmentQuestion(
        id: 'pregnancy_stage',
        title: 'Étape de la grossesse',
        prompt: 'À quelle étape êtes-vous ?',
        icon: Icons.calendar_month_outlined,
        options: [
          AssessmentOption(
            id: 'early',
            label: 'Moins de 20 semaines',
            icon: Icons.looks_one_outlined,
            tags: {'early_pregnancy', 'context_pregnant'},
          ),
          AssessmentOption(
            id: 'late',
            label: '20 semaines ou plus',
            icon: Icons.looks_two_outlined,
            tags: {'late_pregnancy', 'context_pregnant'},
          ),
          AssessmentOption(
            id: 'postpartum',
            label: 'J’ai accouché dans les 6 dernières semaines',
            icon: Icons.child_friendly_outlined,
            tags: {'postpartum', 'context_pregnant'},
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas précisément',
            icon: Icons.help_outline,
            tags: {'context_pregnant'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_bleeding',
        title: 'Douleur ou saignement',
        prompt: 'Avez-vous une douleur abdominale ou un saignement ?',
        icon: Icons.favorite_border_outlined,
        options: [
          AssessmentOption(
            id: 'heavy',
            label: 'Saignement important, forte douleur ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'bleeding', 'severe_pain', 'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'light',
            label: 'Petit saignement ou douleur légère',
            icon: Icons.warning_amber_rounded,
            tags: {'bleeding', 'mild_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pain',
            label: 'Douleur abdominale persistante sans saignement',
            icon: Icons.sick_outlined,
            tags: {'persistent', 'abdominal_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Ni douleur inquiétante ni saignement',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_pressure',
        title: 'Tête, vision et gonflement',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.visibility_outlined,
        options: [
          AssessmentOption(
            id: 'severe',
            label: 'Fort mal de tête, vision trouble ou gonflement soudain',
            icon: Icons.emergency_outlined,
            tags: {'severe_headache', 'vision_change', 'sudden_swelling'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'mild',
            label: 'Mal de tête léger qui s’améliore',
            icon: Icons.psychology_alt_outlined,
            tags: {'mild_headache'},
          ),
          AssessmentOption(
            id: 'swelling',
            label: 'Gonflement progressif des pieds seulement',
            icon: Icons.accessibility_new_outlined,
            tags: {'mild_swelling'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_breathing',
        title: 'Respiration et poitrine',
        prompt: 'Comment vous sentez-vous ?',
        icon: Icons.air_outlined,
        options: [
          AssessmentOption(
            id: 'severe',
            label: 'Essoufflement soudain, douleur poitrine ou convulsion',
            icon: Icons.emergency_outlined,
            tags: {'severe_breathlessness', 'chest_pain', 'seizure'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'lying',
            label: 'Essoufflement au repos ou en position couchée',
            icon: Icons.bed_outlined,
            tags: {'breathless_at_rest'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'effort',
            label: 'Un peu essoufflée seulement à l’effort',
            icon: Icons.directions_walk_outlined,
            tags: {'mild_breathlessness'},
          ),
          AssessmentOption(
            id: 'normal',
            label: 'Je respire normalement',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_baby',
        title: 'Mouvements du bébé',
        prompt: 'Concernant les mouvements du bébé :',
        icon: Icons.child_care_outlined,
        options: [
          AssessmentOption(
            id: 'reduced',
            label: 'Ils sont nettement diminués ou absents',
            icon: Icons.warning_amber_rounded,
            tags: {'reduced_fetal_movement'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'normal',
            label: 'Ils sont habituels',
            icon: Icons.favorite_outline,
            tags: {'normal_fetal_movement'},
          ),
          AssessmentOption(
            id: 'too_early',
            label: 'Trop tôt pour les sentir',
            icon: Icons.schedule_outlined,
            tags: {'early_pregnancy'},
          ),
          AssessmentOption(
            id: 'postpartum',
            label: 'J’ai déjà accouché',
            icon: Icons.child_friendly_outlined,
            tags: {'postpartum'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_sickness',
        title: 'Fièvre et vomissements',
        prompt: 'Quelle situation correspond le mieux ?',
        icon: Icons.thermostat_outlined,
        options: [
          AssessmentOption(
            id: 'cannot_drink',
            label: 'Je vomis tout, urine peu ou suis très faible',
            icon: Icons.emergency_outlined,
            tags: {'cannot_hydrate', 'dehydration_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Fièvre élevée ou frissons',
            icon: Icons.thermostat_outlined,
            tags: {'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'mild_nausea',
            label: 'Nausées légères, je peux boire',
            icon: Icons.local_drink_outlined,
            tags: {'nausea', 'hydrated'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Inconfort courant de la grossesse',
        explanation:
            'Une nausée légère, un essoufflement seulement à l’effort ou un gonflement progressif peuvent survenir pendant la grossesse, mais doivent être surveillés.',
        tagWeights: {
          'nausea': 24,
          'hydrated': 16,
          'mild_breathlessness': 18,
          'mild_swelling': 18,
        },
      ),
      AssessmentPossibility(
        title: 'Pré-éclampsie possible',
        explanation:
            'Un fort mal de tête avec trouble visuel ou gonflement soudain pendant ou après la grossesse est un signe d’alerte.',
        tagWeights: {
          'severe_headache': 34,
          'vision_change': 30,
          'sudden_swelling': 28,
          'late_pregnancy': 10,
          'postpartum': 8,
        },
      ),
      AssessmentPossibility(
        title: 'Complication du début de grossesse possible',
        explanation:
            'Une douleur et un saignement en début de grossesse nécessitent une évaluation urgente.',
        tagWeights: {
          'early_pregnancy': 20,
          'bleeding': 34,
          'severe_pain': 28,
          'collapse': 22,
        },
      ),
      AssessmentPossibility(
        title: 'Déshydratation liée aux vomissements',
        explanation:
            'Des vomissements empêchant de boire peuvent entraîner une déshydratation et nécessiter un traitement.',
        tagWeights: {
          'cannot_hydrate': 42,
          'dehydration_risk': 30,
          'nausea': 12,
        },
      ),
      AssessmentPossibility(
        title: 'Infection possible',
        explanation:
            'Une fièvre pendant la grossesse ou après l’accouchement doit être évaluée rapidement.',
        tagWeights: {'fever': 48, 'systemically_unwell': 20},
      ),
    ],
    selfCare: [
      'Reposez-vous sur le côté, hydratez-vous par petites gorgées et notez l’évolution des symptômes.',
      'Contactez votre maternité ou votre professionnel de suivi dès que quelque chose vous inquiète.',
    ],
    pharmacyAdvice: [
      'Pendant la grossesse ou l’allaitement, vérifiez tout médicament, plante ou supplément avec un professionnel.',
    ],
  ),
];

AssessmentPathway? assessmentPathwayById(String id) {
  for (final pathway in assessmentPathways) {
    if (pathway.id == id) return pathway;
  }
  return null;
}

Map<String, dynamic> assessmentPathwayToMap(AssessmentPathway pathway) => {
  'schemaVersion': 1,
  'id': pathway.id,
  'title': pathway.title,
  'subtitle': pathway.subtitle,
  'iconKey': _assessmentIconKey(pathway.icon),
  'colorHex': _colorHex(pathway.color),
  'questions': [
    for (final question in pathway.questions)
      {
        'id': question.id,
        'title': question.title,
        'prompt': question.prompt,
        'iconKey': _assessmentIconKey(question.icon),
        'requiredTags': question.requiredTags.toList()..sort(),
        'excludedTags': question.excludedTags.toList()..sort(),
        'options': [
          for (final option in question.options)
            {
              'id': option.id,
              'label': option.label,
              'iconKey': _assessmentIconKey(option.icon),
              'tags': option.tags.toList()..sort(),
              'urgency': option.urgency.name,
              'nextQuestionId': option.nextQuestionId,
            },
        ],
      },
  ],
  'possibilities': [
    for (final possibility in pathway.possibilities)
      {
        'title': possibility.title,
        'explanation': possibility.explanation,
        'tagWeights': possibility.tagWeights,
        'baseScore': possibility.baseScore,
      },
  ],
  'selfCare': pathway.selfCare,
  'pharmacyAdvice': pathway.pharmacyAdvice,
};

AssessmentPathway assessmentPathwayFromMap(
  Map<String, dynamic> map, {
  int version = 1,
}) {
  List<Map<String, dynamic>> maps(String key) => (map[key] as List? ?? const [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  List<String> strings(Object? value) => (value as List? ?? const [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  final id = map['id']?.toString().trim() ?? '';
  final title = map['title']?.toString().trim() ?? '';
  if (id.isEmpty || title.isEmpty) {
    throw const FormatException(
      'Parcours diagnostique sans identifiant ou titre.',
    );
  }
  final questions = maps('questions')
      .map((question) {
        final questionId = question['id']?.toString().trim() ?? '';
        final prompt = question['prompt']?.toString().trim() ?? '';
        if (questionId.isEmpty || prompt.isEmpty) {
          throw const FormatException('Question diagnostique incomplète.');
        }
        final options = (question['options'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) {
              final option = Map<String, dynamic>.from(raw);
              final urgencyName = option['urgency']?.toString();
              return AssessmentOption(
                id: option['id']?.toString().trim() ?? '',
                label: option['label']?.toString().trim() ?? '',
                icon: assessmentIconFromKey(option['iconKey']?.toString()),
                tags: strings(option['tags']).toSet(),
                urgency: AssessmentUrgency.values.firstWhere(
                  (value) => value.name == urgencyName,
                  orElse: () => AssessmentUrgency.selfCare,
                ),
                nextQuestionId:
                    option['nextQuestionId']?.toString().trim().isEmpty ?? true
                    ? null
                    : option['nextQuestionId']?.toString().trim(),
              );
            })
            .where((option) => option.id.isNotEmpty && option.label.isNotEmpty)
            .toList(growable: false);
        if (options.length < 2) {
          throw FormatException(
            'La question $questionId a moins de deux choix.',
          );
        }
        return AssessmentQuestion(
          id: questionId,
          title: question['title']?.toString().trim() ?? '',
          prompt: prompt,
          icon: assessmentIconFromKey(question['iconKey']?.toString()),
          options: options,
          requiredTags: strings(question['requiredTags']).toSet(),
          excludedTags: strings(question['excludedTags']).toSet(),
        );
      })
      .toList(growable: false);
  if (questions.isEmpty) {
    throw const FormatException(
      'Un parcours publié doit contenir une question.',
    );
  }

  final possibilities = maps('possibilities')
      .map((possibility) {
        final rawWeights = possibility['tagWeights'];
        final weights = <String, int>{};
        if (rawWeights is Map) {
          for (final entry in rawWeights.entries) {
            final tag = entry.key.toString().trim();
            final weight = entry.value is num
                ? (entry.value as num).round()
                : int.tryParse(entry.value.toString());
            if (tag.isNotEmpty && weight != null) weights[tag] = weight;
          }
        }
        return AssessmentPossibility(
          title: possibility['title']?.toString().trim() ?? '',
          explanation: possibility['explanation']?.toString().trim() ?? '',
          tagWeights: weights,
          baseScore: (possibility['baseScore'] as num?)?.round() ?? 8,
        );
      })
      .where((item) => item.title.isNotEmpty)
      .toList(growable: false);

  return AssessmentPathway(
    id: id,
    version: version,
    title: title,
    subtitle: map['subtitle']?.toString().trim() ?? '',
    icon: assessmentIconFromKey(map['iconKey']?.toString()),
    color: _colorFromHex(map['colorHex']?.toString()),
    questions: questions,
    possibilities: possibilities,
    selfCare: strings(map['selfCare']),
    pharmacyAdvice: strings(map['pharmacyAdvice']),
  );
}

IconData assessmentIconFromKey(String? key) => switch (key) {
  'air' => Icons.air_outlined,
  'alert' => Icons.warning_amber_rounded,
  'blood' => Icons.water_drop_outlined,
  'calendar' => Icons.calendar_month_outlined,
  'check' => Icons.check_circle_outline,
  'clock' => Icons.schedule_outlined,
  'emergency' => Icons.emergency_outlined,
  'face' => Icons.face_outlined,
  'head' => Icons.psychology_alt_outlined,
  'heart' => Icons.favorite_border_outlined,
  'info' => Icons.info_outline,
  'medicine' => Icons.medication_outlined,
  'person' => Icons.accessibility_new_outlined,
  'pregnancy' => Icons.pregnant_woman_outlined,
  'skin' => Icons.texture_outlined,
  'stomach' => Icons.sick_outlined,
  'temperature' => Icons.thermostat_outlined,
  'water' => Icons.local_drink_outlined,
  _ => Icons.radio_button_checked_outlined,
};

String _assessmentIconKey(IconData icon) {
  if (icon == Icons.air_outlined) return 'air';
  if (icon == Icons.warning_amber_rounded) return 'alert';
  if (icon == Icons.water_drop_outlined) return 'blood';
  if (icon == Icons.calendar_month_outlined ||
      icon == Icons.calendar_today_outlined ||
      icon == Icons.date_range_outlined) {
    return 'calendar';
  }
  if (icon == Icons.check_circle_outline || icon == Icons.check_outlined) {
    return 'check';
  }
  if (icon == Icons.schedule_outlined || icon == Icons.timelapse_outlined) {
    return 'clock';
  }
  if (icon == Icons.emergency_outlined) return 'emergency';
  if (icon == Icons.face_outlined) return 'face';
  if (icon == Icons.psychology_alt_outlined ||
      icon == Icons.psychology_outlined) {
    return 'head';
  }
  if (icon == Icons.favorite_border_outlined) return 'heart';
  if (icon == Icons.info_outline ||
      icon == Icons.medical_information_outlined) {
    return 'info';
  }
  if (icon == Icons.medication_outlined) return 'medicine';
  if (icon == Icons.accessibility_new_outlined) return 'person';
  if (icon == Icons.pregnant_woman_outlined) return 'pregnancy';
  if (icon == Icons.texture_outlined) return 'skin';
  if (icon == Icons.sick_outlined) return 'stomach';
  if (icon == Icons.thermostat_outlined) return 'temperature';
  if (icon == Icons.local_drink_outlined) return 'water';
  return 'choice';
}

String _colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Color _colorFromHex(String? value) {
  final normalized = value?.trim().replaceFirst('#', '') ?? '';
  final parsed = int.tryParse(
    normalized.length == 6 ? 'FF$normalized' : normalized,
    radix: 16,
  );
  return parsed == null ? const Color(0xFF176BFF) : Color(parsed);
}

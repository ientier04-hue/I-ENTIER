import 'package:flutter/material.dart';

part 'diagnostic_assessment_guidance.dart';
part 'diagnostic_assessment_additional_pathways.dart';

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
  final bool allowMultiple;

  const AssessmentQuestion({
    required this.id,
    required this.title,
    required this.prompt,
    required this.icon,
    required this.options,
    this.requiredTags = const {},
    this.excludedTags = const {},
    this.allowMultiple = false,
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
  final Set<String> requiredAllTags;
  final Set<String> requiredAnyTags;
  final Set<String> excludedTags;
  final int minimumMatchedEvidence;
  final bool urgentReason;

  const AssessmentPossibility({
    required this.title,
    required this.explanation,
    required this.tagWeights,
    this.baseScore = 8,
    this.requiredAllTags = const {},
    this.requiredAnyTags = const {},
    this.excludedTags = const {},
    this.minimumMatchedEvidence = 1,
    this.urgentReason = false,
  });

  AssessmentMatch? score(Set<String> tags) {
    if (!requiredAllTags.every(tags.contains) ||
        (requiredAnyTags.isNotEmpty && !requiredAnyTags.any(tags.contains)) ||
        excludedTags.any(tags.contains)) {
      return null;
    }
    final matched = tagWeights.entries
        .where((entry) => tags.contains(entry.key))
        .toList(growable: false);
    if (matched.length < minimumMatchedEvidence) return null;
    final raw =
        baseScore + matched.fold<int>(0, (sum, item) => sum + item.value);
    return AssessmentMatch(
      title: title,
      explanation: explanation,
      compatibility: raw.clamp(8, 92),
      matchedTags: matched.map((entry) => entry.key).toList(growable: false),
      urgentReason: urgentReason,
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
  final bool urgentReason;
  final List<String> supportingAnswers;

  const AssessmentMatch({
    required this.title,
    required this.explanation,
    required this.compatibility,
    required this.matchedTags,
    this.urgentReason = false,
    this.supportingAnswers = const [],
  });

  String get compatibilityLabel {
    if (compatibility == 0) return 'À préciser';
    if (compatibility >= 70) return 'Compatibilité forte';
    if (compatibility >= 45) return 'Compatibilité modérée';
    return 'Compatibilité limitée';
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'explanation': explanation,
    'compatibility': compatibility,
    'urgentReason': urgentReason,
    'matchedTags': matchedTags,
    'supportingAnswers': supportingAnswers,
  };

  factory AssessmentMatch.fromMap(Map<String, dynamic> map) => AssessmentMatch(
    title: map['title']?.toString() ?? '',
    explanation: map['explanation']?.toString() ?? '',
    compatibility: (map['compatibility'] as num?)?.round() ?? 0,
    matchedTags:
        (map['matchedTags'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    supportingAnswers:
        (map['supportingAnswers'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    urgentReason: map['urgentReason'] == true,
  );
}

class AssessmentResult {
  final String? summary;
  final AssessmentUrgency urgency;
  final List<AssessmentMatch> matches;
  final List<String> nextSteps;
  final List<String> selfCare;
  final List<String> pharmacyAdvice;
  final List<String> contextNotes;
  final List<String> redFlags;
  final List<String> immediateActions;

  const AssessmentResult({
    required this.urgency,
    required this.matches,
    required this.nextSteps,
    required this.selfCare,
    required this.pharmacyAdvice,
    required this.contextNotes,
    this.redFlags = const [],
    this.immediateActions = const [],
    this.summary,
  });

  Map<String, dynamic> toMap() => {
    'urgency': urgency.name,
    'summary': summary,
    'matches': matches.map((item) => item.toMap()).toList(),
    'nextSteps': nextSteps,
    'selfCare': selfCare,
    'pharmacyAdvice': pharmacyAdvice,
    'contextNotes': contextNotes,
    'redFlags': redFlags,
    'immediateActions': immediateActions,
    'disclaimer':
        'La compatibilité est qualitative, non calibrée, et ne constitue ni une probabilité ni un diagnostic.',
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
      summary: map['summary']?.toString(),
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
      redFlags: strings('redFlags'),
      immediateActions: strings('immediateActions'),
    );
  }
}

class AssessmentEngine {
  const AssessmentEngine();

  List<String> immediateActions(
    AssessmentPathway pathway,
    Map<String, String> answers,
  ) => _immediateActionsForTags(answerTags(pathway, answers));

  Iterable<String> _selectedOptionIds(String? encoded) sync* {
    if (encoded == null) return;
    for (final id in encoded.split('|')) {
      final normalized = id.trim();
      if (normalized.isNotEmpty) yield normalized;
    }
  }

  /// Keeps only valid answers supported by the current branch choices.
  /// Start from unconditional questions so abandoned branches cannot keep
  /// themselves (or each other) active through their own tags.
  Map<String, String> reconcileAnswers(
    AssessmentPathway pathway,
    Map<String, String> answers,
  ) {
    var candidates = <String, String>{};
    for (final question in pathway.questions) {
      final ids = _selectedOptionIds(answers[question.id]).toSet();
      if (ids.isEmpty || (!question.allowMultiple && ids.length > 1)) continue;
      if (ids.any((id) => !question.options.any((option) => option.id == id))) {
        continue;
      }
      final sorted = ids.toList()..sort();
      candidates[question.id] = sorted.join('|');
    }
    while (candidates.isNotEmpty) {
      final supported = <String, String>{};
      final tags = <String>{};
      var added = true;
      while (added) {
        added = false;
        for (final question in pathway.questions) {
          if (supported.containsKey(question.id) ||
              !candidates.containsKey(question.id) ||
              !question.requiredTags.every(tags.contains)) {
            continue;
          }
          supported[question.id] = candidates[question.id]!;
          final ids = _selectedOptionIds(candidates[question.id]).toSet();
          tags.addAll(
            question.options
                .where((option) => ids.contains(option.id))
                .expand((option) => option.tags),
          );
          added = true;
        }
      }
      supported.removeWhere(
        (id, _) => !pathway.questionById(id)!.appliesTo(tags),
      );
      if (supported.length == candidates.length) return supported;
      candidates = supported;
    }
    return candidates;
  }

  Set<String> answerTags(
    AssessmentPathway pathway,
    Map<String, String> answers,
  ) {
    final tags = <String>{};
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key);
      if (question == null) continue;
      final selectedIds = _selectedOptionIds(entry.value).toSet();
      for (final option in question.options) {
        if (selectedIds.contains(option.id)) tags.addAll(option.tags);
      }
    }
    return tags;
  }

  AssessmentQuestion? nextQuestion(
    AssessmentPathway pathway,
    Map<String, String> answers, {
    String? afterQuestionId,
  }) {
    final activeAnswers = reconcileAnswers(pathway, answers);
    final tags = answerTags(pathway, activeAnswers);
    bool isPending(AssessmentQuestion question) =>
        !activeAnswers.containsKey(question.id) && question.appliesTo(tags);

    // Explicit links prioritize follow-ups without skipping other unanswered
    // questions, including sibling branches selected in a multiple choice.
    final current = pathway.questionById(afterQuestionId);
    for (final question in [
      ?current,
      ...pathway.questions.where((question) => question != current),
    ]) {
      final selectedIds = _selectedOptionIds(
        activeAnswers[question.id],
      ).toSet();
      for (final option in question.options) {
        if (!selectedIds.contains(option.id)) continue;
        final target = pathway.questionById(option.nextQuestionId);
        if (target != null && isPending(target)) return target;
      }
    }
    final start =
        pathway.questions.indexWhere(
          (question) => question.id == afterQuestionId,
        ) +
        1;
    for (final question in [
      ...pathway.questions.skip(start),
      ...pathway.questions.take(start),
    ]) {
      if (isPending(question)) return question;
    }
    return null;
  }

  List<AssessmentQuestion> answeredQuestions(
    AssessmentPathway pathway,
    Map<String, String> answers,
  ) {
    final active = reconcileAnswers(pathway, answers);
    final visited = <String, String>{};
    final ordered = <AssessmentQuestion>[];
    while (visited.length < active.length) {
      var next = nextQuestion(
        pathway,
        visited,
        afterQuestionId: ordered.lastOrNull?.id,
      );
      // A restored draft can contain answers beyond an unanswered question.
      if (next == null ||
          !active.containsKey(next.id) ||
          visited.containsKey(next.id)) {
        next = pathway.questions.firstWhere(
          (question) =>
              active.containsKey(question.id) &&
              !visited.containsKey(question.id),
        );
      }
      visited[next.id] = active[next.id]!;
      ordered.add(next);
    }
    return ordered;
  }

  int progress(AssessmentPathway pathway, Map<String, String> answers) {
    final activeAnswers = reconcileAnswers(pathway, answers);
    if (activeAnswers.isEmpty) return 0;
    final tags = answerTags(pathway, activeAnswers);
    final visible = pathway.questions
        .where((question) => question.appliesTo(tags))
        .length;
    if (visible == 0) return 0;
    return ((activeAnswers.length / visible) * 100).round().clamp(1, 100);
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
    final ageMonths = (context['ageMonths'] as num?)?.round();
    if (age != null && (age < 12 || age >= 65)) {
      tags.add('context_vulnerable_age');
      contextNotes.add(
        'L’âge enregistré justifie une évaluation professionnelle plus prudente.',
      );
    }
    if (ageMonths != null && ageMonths >= 0 && ageMonths < 3) {
      tags.add('context_young_infant');
    } else if (ageMonths != null && ageMonths >= 3 && ageMonths < 6) {
      tags.add('context_infant_3_to_6_months');
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
    if ((context['conditions'] as List?)?.isNotEmpty == true) {
      contextNotes.add(
        'Les antécédents déclarés dans le dossier justifient de vérifier tout nouveau médicament avec un professionnel.',
      );
    }
    if (context['recentHighTemperature'] == true) {
      tags.add('fever');
      contextNotes.add(
        'Une température élevée récente a été détectée dans le suivi autorisé.',
      );
    }

    var urgency = AssessmentUrgency.selfCare;
    final redFlags = <String>[];
    final orientationReasons = <({AssessmentUrgency urgency, String label})>[];
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key);
      if (question == null) continue;
      final selectedIds = _selectedOptionIds(entry.value).toSet();
      for (final option in question.options.where(
        (item) => selectedIds.contains(item.id),
      )) {
        if (option.urgency.priority > urgency.priority) {
          urgency = option.urgency;
        }
        if (option.urgency != AssessmentUrgency.selfCare) {
          orientationReasons.add((
            urgency: option.urgency,
            label: option.label,
          ));
        }
        if (option.urgency == AssessmentUrgency.emergency &&
            !redFlags.contains(option.label)) {
          redFlags.add(option.label);
        }
      }
    }

    void raiseUrgency(AssessmentUrgency target, {String? reason}) {
      if (target.priority > urgency.priority) urgency = target;
      if (reason != null) {
        orientationReasons.add((urgency: target, label: reason));
      }
      if (target == AssessmentUrgency.emergency &&
          reason != null &&
          !redFlags.contains(reason)) {
        redFlags.add(reason);
      }
    }

    final pregnancyRelevant =
        tags.contains('context_pregnant') ||
        tags.contains('pregnancy_possible');
    final feverPresent =
        tags.contains('fever') ||
        tags.contains('acute_fever') ||
        context['recentHighTemperature'] == true;
    final dangerousPregnancyBleeding =
        tags.contains('bleeding') &&
        (tags.contains('one_sided_pelvic_pain') ||
            tags.contains('shoulder_pain') ||
            tags.contains('dizziness') ||
            tags.contains('collapse'));
    if (pregnancyRelevant &&
        (tags.contains('severe_pain') ||
            tags.contains('severe_headache') ||
            tags.contains('very_heavy_bleeding') ||
            dangerousPregnancyBleeding)) {
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Association de signes d’alerte pendant une grossesse ou après un accouchement',
      );
    } else if (pregnancyRelevant && tags.contains('bleeding')) {
      raiseUrgency(AssessmentUrgency.consultationToday);
    }

    if (pregnancyRelevant && pathway.id == 'headache') {
      raiseUrgency(AssessmentUrgency.consultationSoon);
    }
    final lowerUrinaryInfectionPattern =
        tags.contains('urinary_burning') ||
        (tags.contains('urinary_frequency') &&
            (tags.contains('small_frequent_voids') ||
                tags.contains('cloudy_urine')));
    if (pathway.id == 'urinary' && lowerUrinaryInfectionPattern) {
      raiseUrgency(AssessmentUrgency.consultationSoon);
      final recordedSex = context['sex']?.toString().trim().toLowerCase() ?? '';
      final maleUrinaryContext =
          tags.contains('male_urinary_context') ||
          recordedSex == 'homme' ||
          recordedSex == 'male' ||
          recordedSex == 'masculin';
      final urinaryChild =
          tags.contains('person_under_16') ||
          (age != null && age >= 0 && age < 16);
      final urinaryYoungInfant =
          tags.contains('person_under_3_months') ||
          (ageMonths != null && ageMonths >= 0 && ageMonths < 3);
      if (urinaryYoungInfant) {
        tags.add('young_infant_urinary_infection');
        raiseUrgency(
          AssessmentUrgency.emergency,
          reason:
              'Suspicion d’infection urinaire chez un nourrisson de moins de 3 mois',
        );
      } else if (pregnancyRelevant ||
          maleUrinaryContext ||
          urinaryChild ||
          tags.contains('older_adult') ||
          (age != null && age >= 65) ||
          tags.contains('complicated_urinary_context')) {
        raiseUrgency(AssessmentUrgency.consultationToday);
        contextNotes.add(
          'Dans ce contexte, une infection urinaire possible doit être évaluée aujourd’hui.',
        );
      }
    }
    if (pregnancyRelevant &&
        pathway.id == 'urinary' &&
        (lowerUrinaryInfectionPattern ||
            tags.contains('kidney_infection_pattern'))) {
      raiseUrgency(AssessmentUrgency.consultationToday);
      contextNotes.add(
        'Pendant une grossesse, une infection urinaire possible doit être évaluée et traitée aujourd’hui.',
      );
    }
    if (pathway.id == 'urinary' &&
        (feverPresent || tags.contains('chills')) &&
        (tags.contains('colicky_flank_pain') ||
            tags.contains('known_urinary_stone') ||
            tags.contains('known_urinary_obstruction') ||
            tags.contains('urinary_retention'))) {
      tags.add('infected_urinary_obstruction');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Fièvre associée à un calcul, une obstruction ou une rétention urinaire',
      );
    }
    if (pathway.id == 'dizziness' &&
        tags.contains('sudden_dizziness') &&
        tags.contains('imbalance')) {
      tags.add('posterior_stroke_pattern');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason: 'Vertige brutal avec nouvelle perte d’équilibre',
      );
    }
    if (pathway.id == 'chest' &&
        tags.contains('cardiovascular_risk') &&
        tags.contains('chest_pain_at_rest')) {
      tags.add('acute_coronary_suspicion');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason: 'Douleur thoracique au repos avec risque cardiovasculaire',
      );
    }
    if (pathway.id == 'chest' &&
        tags.contains('chest_pain_at_rest') &&
        (tags.contains('chest_pressure') ||
            tags.contains('nonspecific_chest_pain') ||
            tags.contains('acute_coronary_autonomic'))) {
      tags.add('acute_coronary_suspicion');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason: 'Douleur thoracique nouvelle ou inexpliquée au repos',
      );
    }
    if (pathway.id == 'chest' &&
        tags.contains('clot_risk') &&
        (tags.contains('pleuritic_pain') ||
            tags.contains('severe_breathlessness'))) {
      tags.add('pulmonary_embolism_pattern');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason: 'Douleur respiratoire associée à un risque de caillot sanguin',
      );
    }
    if (pathway.id == 'respiratory' &&
        tags.contains('clot_risk') &&
        (tags.contains('pleuritic_pain') ||
            tags.contains('breathlessness_primary') ||
            tags.contains('mild_breathlessness') ||
            tags.contains('severe_breathlessness'))) {
      tags.add('pulmonary_embolism_pattern');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Essoufflement ou douleur respiratoire avec facteur de risque de caillot',
      );
    }
    final recentMaxTemperature = (context['recentMaxTemperature'] as num?)
        ?.toDouble();
    final feverAtLeast38 =
        tags.contains('temperature_38') ||
        tags.contains('temperature_39') ||
        tags.contains('temperature_40') ||
        (recentMaxTemperature != null && recentMaxTemperature >= 38);
    final feverAtLeast39 =
        tags.contains('temperature_39') ||
        tags.contains('temperature_40') ||
        (recentMaxTemperature != null && recentMaxTemperature >= 39);
    final youngInfant =
        tags.contains('context_young_infant') ||
        tags.contains('person_under_3_months');
    final infantThreeToSix =
        tags.contains('context_infant_3_to_6_months') ||
        tags.contains('person_3_to_6_months');
    if (youngInfant && feverAtLeast38) {
      tags.add('young_infant_fever');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Température d’au moins 38 °C chez un nourrisson de moins de 3 mois',
      );
      contextNotes.add(
        'Une fièvre avant 3 mois nécessite une évaluation médicale immédiate.',
      );
    } else if (youngInfant &&
        feverPresent &&
        tags.contains('temperature_unconfirmed')) {
      raiseUrgency(AssessmentUrgency.consultationToday);
      contextNotes.add(
        'Chez un nourrisson de moins de 3 mois, mesurez la température et demandez un avis médical aujourd’hui.',
      );
    }
    if (infantThreeToSix && feverAtLeast39) {
      raiseUrgency(AssessmentUrgency.consultationToday);
      contextNotes.add(
        'Une température d’au moins 39 °C entre 3 et 6 mois nécessite une évaluation aujourd’hui.',
      );
    }
    if (youngInfant && tags.contains('temperature_below_36')) {
      tags.add('infant_hypothermia');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Température inférieure à 36 °C chez un nourrisson de moins de 3 mois',
      );
    }
    if (pathway.id == 'skin' &&
        tags.contains('painful_skin') &&
        tags.contains('warm_skin') &&
        tags.contains('skin_swelling')) {
      tags.add('cellulitis_pattern');
      raiseUrgency(
        AssessmentUrgency.consultationToday,
        reason: 'Zone cutanée douloureuse, chaude et gonflée',
      );
    }
    if (pathway.id == 'skin' &&
        (tags.contains('diabetes_context') ||
            tags.contains('immunocompromised')) &&
        (tags.contains('cellulitis_pattern') ||
            tags.contains('wound_trigger'))) {
      raiseUrgency(AssessmentUrgency.consultationToday);
    }
    if (pathway.id == 'urinary' &&
        tags.contains('large_urine_volume') &&
        tags.contains('excessive_thirst') &&
        (tags.contains('vomiting') ||
            tags.contains('deep_breathing') ||
            tags.contains('confusion'))) {
      tags.add('possible_ketoacidosis');
      raiseUrgency(
        AssessmentUrgency.emergency,
        reason:
            'Urines abondantes et soif intense avec vomissements, respiration anormale ou confusion',
      );
    }
    if (pathway.id == 'back') {
      if (tags.contains('back_minor_trauma') &&
          tags.contains('back_bone_fragility')) {
        tags.add('back_fracture_risk');
        raiseUrgency(
          AssessmentUrgency.consultationToday,
          reason: 'Douleur après un choc sur un terrain de fragilité osseuse',
        );
      }
      if (feverPresent && tags.contains('immunocompromised')) {
        tags.add('back_spinal_infection_risk');
        raiseUrgency(
          AssessmentUrgency.emergency,
          reason: 'Mal de dos avec fièvre et immunité diminuée',
        );
      }
    }
    if (pathway.id == 'joint') {
      if (age != null && age < 16) tags.add('person_under_16');
      final hotSwollen =
          tags.contains('joint_hot') && tags.contains('joint_swollen');
      final infectionRisk =
          tags.contains('joint_prosthesis') ||
          tags.contains('joint_recent_procedure') ||
          tags.contains('immunocompromised');
      if (infectionRisk) tags.add('joint_infection_risk');
      if (hotSwollen) {
        tags.add('joint_hot_swollen');
        raiseUrgency(
          feverPresent || infectionRisk
              ? AssessmentUrgency.emergency
              : AssessmentUrgency.consultationToday,
          reason: feverPresent || infectionRisk
              ? 'Articulation chaude et gonflée avec fièvre ou risque d’infection'
              : 'Articulation chaude et gonflée, même sans fièvre',
        );
      }
    }
    if (pathway.id == 'eyes') {
      final eyePain =
          tags.contains('eye_deep_pain') || tags.contains('eye_severe_pain');
      final alteredVision =
          tags.contains('eye_blurred') ||
          tags.contains('eye_double') ||
          tags.contains('eye_vision_loss');
      if (tags.contains('eye_contact_lenses') &&
          (tags.contains('eye_red') ||
              eyePain ||
              tags.contains('eye_gritty'))) {
        tags.add('eye_contact_lens_risk');
        raiseUrgency(
          alteredVision && eyePain
              ? AssessmentUrgency.emergency
              : AssessmentUrgency.consultationToday,
          reason:
              'Œil rouge ou douloureux chez une personne portant des lentilles',
        );
      }
      if ((tags.contains('eye_red') &&
              (alteredVision || tags.contains('eye_photophobia'))) ||
          (tags.contains('eye_minor_trauma') &&
              (alteredVision || tags.contains('eye_photophobia') || eyePain)) ||
          (tags.contains('eye_recent_procedure') &&
              (eyePain || alteredVision)) ||
          (tags.contains('eye_sudden') && eyePain)) {
        raiseUrgency(
          AssessmentUrgency.emergency,
          reason:
              'Douleur, rougeur ou traumatisme de l’œil avec signe visuel d’alerte',
        );
      }
      if ((tags.contains('eye_lid_swelling') ||
              tags.contains('eye_spreading_swelling')) &&
          (feverPresent || tags.contains('eye_movement_pain'))) {
        tags.add('eye_orbital_warning');
        raiseUrgency(
          AssessmentUrgency.emergency,
          reason:
              'Gonflement autour de l’œil avec fièvre ou douleur aux mouvements',
        );
      }
    }
    if (pathway.id == 'dental') {
      // Dental pain needs a dental examination even when an analgesic helps.
      if (answers.isNotEmpty) raiseUrgency(AssessmentUrgency.consultationSoon);
      if (pregnancyRelevant || tags.contains('person_under_16')) {
        contextNotes.add(
          'Le dentiste doit connaître l’âge et une éventuelle grossesse pour adapter les soins.',
        );
      }
    }
    if (tags.contains('context_vulnerable_age') &&
        urgency == AssessmentUrgency.selfCare) {
      raiseUrgency(AssessmentUrgency.consultationSoon);
    }

    if (urgency == AssessmentUrgency.emergency) tags.add('triage_emergency');

    final matches =
        pathway.possibilities
            .map((possibility) => possibility.score(tags))
            .whereType<AssessmentMatch>()
            .where((match) => match.compatibility >= 24)
            .toList()
          ..sort((first, second) {
            if (urgency.priority >=
                    AssessmentUrgency.consultationToday.priority &&
                first.urgentReason != second.urgentReason) {
              return first.urgentReason ? -1 : 1;
            }
            return second.compatibility.compareTo(first.compatibility);
          });
    final limitedMatches = matches
        .take(3)
        .map((match) {
          final evidence = <String>[];
          final evidenceTags = match.matchedTags
              .expand((tag) => _derivedEvidenceTags[tag] ?? {tag})
              .toSet();
          for (final question in pathway.questions) {
            final selected = _selectedOptionIds(answers[question.id]).toSet();
            for (final option in question.options) {
              if (selected.contains(option.id) &&
                  option.tags.any(evidenceTags.contains)) {
                evidence.add('${question.title} : ${option.label}');
              }
            }
          }
          return AssessmentMatch(
            title: match.title,
            explanation: match.explanation,
            compatibility: match.compatibility,
            matchedTags: match.matchedTags,
            supportingAnswers: evidence.toSet().take(3).toList(),
            urgentReason: match.urgentReason,
          );
        })
        .toList(growable: false);
    // An absence of a supported hypothesis must not look like a clean bill of
    // health, particularly when the patient could not describe their symptoms.
    if (limitedMatches.isEmpty && urgency == AssessmentUrgency.selfCare) {
      raiseUrgency(AssessmentUrgency.consultationSoon);
    }
    final guidance = _guidanceFor(
      pathway: pathway,
      tags: tags,
      urgency: urgency,
      context: context,
    );
    final reasons = orientationReasons
        .where((reason) => reason.urgency == urgency)
        .map((reason) => reason.label)
        .toSet()
        .take(2)
        .join('; ');
    final summary = reasons.isNotEmpty
        ? switch (urgency) {
            AssessmentUrgency.emergency =>
              'Une évaluation immédiate est nécessaire : $reasons.',
            AssessmentUrgency.consultationToday =>
              'Ces réponses nécessitent un avis aujourd’hui : $reasons.',
            _ => 'Ces réponses méritent un avis médical : $reasons.',
          }
        : limitedMatches.isEmpty
        ? 'Vos réponses ne permettent pas de préciser la cause. Un avis médical est recommandé si les symptômes persistent ou vous inquiètent.'
        : urgency.description;
    return AssessmentResult(
      urgency: urgency,
      summary: summary,
      matches: limitedMatches.isEmpty
          ? [
              AssessmentMatch(
                title: urgency == AssessmentUrgency.emergency
                    ? 'Signes d’alerte à évaluer en urgence'
                    : 'Orientation à préciser',
                explanation: urgency == AssessmentUrgency.emergency
                    ? 'Les signes déclarés justifient une prise en charge immédiate, même sans cause identifiée par ce questionnaire.'
                    : 'Aucune hypothèse n’est suffisamment étayée par les réponses. Un examen peut aider à préciser la cause.',
                compatibility: 0,
                matchedTags: const [],
                urgentReason: urgency == AssessmentUrgency.emergency,
              ),
            ]
          : limitedMatches,
      nextSteps: guidance.nextSteps,
      selfCare: guidance.selfCare,
      pharmacyAdvice: guidance.pharmacyAdvice,
      contextNotes: contextNotes,
      redFlags: redFlags,
      immediateActions: _immediateActionsForTags(tags),
    );
  }
}

const assessmentPathways = <AssessmentPathway>[
  AssessmentPathway(
    id: 'abdominal',
    version: 4,
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
            label: 'Au milieu, en haut du ventre',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'upper_abdomen', 'branch_upper_abdominal'},
          ),
          AssessmentOption(
            id: 'right_upper',
            label: 'Sous les côtes à droite',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'upper_abdomen',
              'right_upper_abdomen',
              'branch_upper_abdominal',
            },
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
            tags: {'lower_abdomen', 'branch_pelvic'},
          ),
          AssessmentOption(
            id: 'flank',
            label: 'Sur un côté, vers le dos ou l’aine',
            icon: Icons.swap_horiz_outlined,
            tags: {'flank_pain', 'branch_urinary'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'diffuse',
            label: 'Dans tout le ventre',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'diffuse', 'branch_bowel'},
          ),
          AssessmentOption(
            id: 'lower_left',
            label: 'En bas à gauche',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'lower_left', 'branch_bowel'},
          ),
          AssessmentOption(
            id: 'navel',
            label: 'Autour du nombril',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'periumbilical_pain'},
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
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
        id: 'abdominal_warning',
        title: 'Signes à vérifier',
        prompt: 'Avez-vous l’un de ces signes maintenant ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'blood_vomit',
            label: 'Vomissement de sang ou de matière brun-noir',
            icon: Icons.warning_amber_rounded,
            tags: {'digestive_bleeding', 'bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'black_stool',
            label: 'Selles noires, collantes, inhabituelles',
            icon: Icons.warning_amber_rounded,
            tags: {'digestive_bleeding', 'bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'blocked',
            label:
                'Ventre gonflé et impossibilité d’émettre des selles ou des gaz',
            icon: Icons.warning_amber_rounded,
            tags: {'obstruction_pattern', 'abdominal_distension'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'chest',
            label: 'Douleur dans la poitrine en même temps',
            icon: Icons.warning_amber_rounded,
            tags: {'chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'diabetes_vomit',
            label: 'Diabète connu et vomissements',
            icon: Icons.warning_amber_rounded,
            tags: {
              'diabetes_context',
              'vomiting',
              'diabetic_abdominal_warning',
            },
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
        id: 'abdominal_associated',
        title: 'Autres signes',
        prompt: 'Quels autres signes avez-vous avec le mal de ventre ?',
        icon: Icons.playlist_add_check_circle_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ceux-ci',
            icon: Icons.remove_circle_outline,
            tags: {'isolated_pain'},
          ),
          AssessmentOption(
            id: 'vomiting',
            label: 'Vomissements',
            icon: Icons.water_drop_outlined,
            tags: {'vomiting', 'branch_bowel'},
          ),
          AssessmentOption(
            id: 'diarrhea',
            label: 'Diarrhée',
            icon: Icons.water_drop_outlined,
            tags: {'diarrhea', 'branch_bowel'},
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
          AssessmentOption(
            id: 'constipation',
            label: 'Selles plus rares ou difficiles à évacuer',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'constipation', 'branch_bowel'},
          ),
          AssessmentOption(
            id: 'bloating',
            label: 'Ventre gonflé ou ballonné',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'bloating', 'branch_bowel'},
          ),
          AssessmentOption(
            id: 'appetite',
            label: 'Perte d’appétit inhabituelle',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'loss_of_appetite'},
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
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'urinary',
            label: 'Douleur ou brûlure en urinant',
            icon: Icons.water_outlined,
            tags: {'urinary', 'branch_urinary'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pregnancy',
            label: 'Grossesse possible ou confirmée',
            icon: Icons.pregnant_woman_outlined,
            tags: {'pregnancy_possible', 'branch_pelvic'},
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
            id: 'testicular_pain',
            label: 'Douleur ou gonflement soudain d’un testicule',
            icon: Icons.emergency_outlined,
            tags: {'testicular_torsion_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_outlined,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_evolution',
        title: 'Évolution de la douleur',
        prompt: 'Comment la douleur a-t-elle changé depuis son début ?',
        icon: Icons.trending_up_outlined,
        options: [
          AssessmentOption(
            id: 'improving',
            label: 'Elle diminue',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'improving'},
          ),
          AssessmentOption(
            id: 'stable',
            label: 'Elle reste à peu près la même',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'stable_pain'},
          ),
          AssessmentOption(
            id: 'worsening',
            label: 'Elle devient plus forte',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'migration_right',
            label:
                'Elle a commencé près du nombril puis s’est déplacée en bas à droite',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'migrating_right_lower_pain', 'lower_right'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'waves',
            label: 'Elle revient par vagues avec des accalmies',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'colicky_pain'},
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_upper_pattern',
        title: 'Douleur du haut du ventre',
        prompt: 'Quelle description précise le mieux cette douleur ?',
        icon: Icons.sick_outlined,
        requiredTags: {'branch_upper_abdominal'},
        options: [
          AssessmentOption(
            id: 'burning',
            label: 'Brûlure, remontées acides ou goût amer',
            icon: Icons.local_fire_department_outlined,
            tags: {'heartburn', 'acid_reflux'},
          ),
          AssessmentOption(
            id: 'fatty_shoulder',
            label: 'Après un repas gras, vers l’épaule ou le dos',
            icon: Icons.restaurant_outlined,
            tags: {'biliary_pattern', 'radiates_back'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'belt_back',
            label:
                'Douleur forte et continue en ceinture vers le dos avec vomissements',
            icon: Icons.emergency_outlined,
            tags: {'pancreatic_pattern', 'radiates_back', 'vomiting'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'jaundice_fever',
            label: 'Peau ou yeux jaunes avec fièvre ou frissons',
            icon: Icons.emergency_outlined,
            tags: {'biliary_infection_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'chest',
            label: 'Pression poitrine, sueurs ou essoufflement',
            icon: Icons.emergency_outlined,
            tags: {'chest_pain', 'sweating', 'severe_breathlessness'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_urinary_detail',
        title: 'Signes urinaires',
        prompt: 'Quel signe urinaire ou lombaire est présent ?',
        icon: Icons.water_outlined,
        requiredTags: {'branch_urinary'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'burning_frequency',
            label: 'Brûlure et besoin d’uriner souvent',
            icon: Icons.water_drop_outlined,
            tags: {'urinary_burning', 'urinary_frequency'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'waves_groin',
            label: 'Douleur par vagues qui descend vers l’aine',
            icon: Icons.waves_outlined,
            tags: {'colicky_flank_pain', 'radiates_groin'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'fever_flank',
            label: 'Fièvre ou frissons avec douleur dans le dos',
            icon: Icons.warning_amber_rounded,
            tags: {'fever', 'flank_pain', 'kidney_infection_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'retention',
            label: 'Impossible d’uriner malgré une vessie douloureuse',
            icon: Icons.emergency_outlined,
            tags: {'urinary_retention'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun autre signe urinaire',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_pelvic_detail',
        title: 'Bas-ventre et grossesse',
        prompt: 'Quelle situation correspond le mieux ?',
        icon: Icons.favorite_border_outlined,
        requiredTags: {'branch_pelvic'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'pregnancy_one_side',
            label:
                'Grossesse possible, douleur d’un côté, saignement ou malaise',
            icon: Icons.emergency_outlined,
            tags: {
              'pregnancy_possible',
              'one_sided_pelvic_pain',
              'bleeding',
              'collapse',
            },
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever_discharge',
            label: 'Fièvre ou pertes inhabituelles avec douleur pelvienne',
            icon: Icons.thermostat_outlined,
            tags: {'fever', 'discharge', 'pelvic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'cycle_related',
            label: 'Crampes liées aux règles, sans signe d’alerte',
            icon: Icons.calendar_month_outlined,
            tags: {'cycle_related', 'cramps'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'abdominal_bowel_detail',
        title: 'Transit intestinal',
        prompt: 'Comment votre transit a-t-il changé ?',
        icon: Icons.sync_alt_outlined,
        requiredTags: {'branch_bowel'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'watery',
            label: 'Diarrhée liquide, mais je peux boire',
            icon: Icons.water_drop_outlined,
            tags: {'watery_diarrhea', 'hydrated'},
          ),
          AssessmentOption(
            id: 'constipation',
            label: 'Constipation ou ballonnement qui revient',
            icon: Icons.replay_outlined,
            tags: {'constipation', 'bloating', 'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'obstruction',
            label: 'Ventre gonflé, vomissements, ni selles ni gaz',
            icon: Icons.emergency_outlined,
            tags: {'obstruction_pattern', 'vomiting', 'abdominal_distension'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'relieved',
            label: 'Crampes récurrentes soulagées après les selles',
            icon: Icons.check_circle_outline,
            tags: {'bowel_relief', 'recurrent', 'cramps'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces changements',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Douleur abdominale aiguë sévère à évaluer en urgence',
        explanation:
            'Une douleur très forte, un ventre rigide ou une incapacité à garder les liquides peut révéler une urgence abdominale.',
        tagWeights: {
          'severe_pain': 56,
          'rigid_abdomen': 70,
          'cannot_hydrate': 46,
          'collapse': 52,
        },
        requiredAnyTags: {
          'severe_pain',
          'rigid_abdomen',
          'cannot_hydrate',
          'collapse',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Hémorragie digestive possible',
        explanation:
            'Du sang vomi ou des selles noires ou sanglantes nécessite une évaluation urgente.',
        tagWeights: {'digestive_bleeding': 76, 'collapse': 28},
        requiredAllTags: {'digestive_bleeding'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Urgence cardiaque ou thoracique possible',
        explanation:
            'Une pression dans la poitrine avec sueurs ou essoufflement peut parfois être ressentie dans le haut du ventre.',
        tagWeights: {
          'chest_pain': 64,
          'sweating': 24,
          'severe_breathlessness': 34,
        },
        requiredAllTags: {'chest_pain'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Torsion testiculaire possible',
        explanation:
            'Une douleur ou un gonflement testiculaire soudain nécessite une prise en charge immédiate pour préserver le testicule.',
        tagWeights: {'testicular_torsion_pattern': 80},
        requiredAllTags: {'testicular_torsion_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Gastro-entérite ou irritation digestive',
        explanation:
            'Des crampes avec diarrhée ou vomissements sont compatibles avec une irritation ou une infection digestive.',
        tagWeights: {
          'diarrhea': 28,
          'watery_diarrhea': 30,
          'vomiting': 22,
          'diffuse': 12,
          'acute': 8,
        },
        requiredAnyTags: {'diarrhea', 'watery_diarrhea', 'vomiting'},
        excludedTags: {
          'digestive_bleeding',
          'rigid_abdomen',
          'obstruction_pattern',
          'pancreatic_pattern',
          'testicular_torsion_pattern',
          'triage_emergency',
        },
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
        requiredAllTags: {'lower_right'},
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
          'heartburn': 34,
          'acid_reflux': 30,
        },
        requiredAnyTags: {'heartburn', 'acid_reflux'},
        excludedTags: {
          'severe_pain',
          'rigid_abdomen',
          'digestive_bleeding',
          'chest_pain',
          'pancreatic_pattern',
          'biliary_infection_pattern',
          'triage_emergency',
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
        requiredAllTags: {'urinary'},
      ),
      AssessmentPossibility(
        title: 'Colique biliaire ou inflammation de la vésicule possible',
        explanation:
            'Une douleur sous les côtes à droite après un repas gras, parfois vers l’épaule ou le dos, nécessite une évaluation.',
        tagWeights: {
          'right_upper_abdomen': 32,
          'after_fatty_meal': 24,
          'biliary_pattern': 34,
          'radiates_back': 10,
          'fever': 14,
        },
        requiredAllTags: {'biliary_pattern'},
        excludedTags: {'biliary_infection_pattern'},
      ),
      AssessmentPossibility(
        title: 'Infection ou obstruction biliaire possible',
        explanation:
            'Une douleur du haut du ventre avec jaunisse et fièvre ou frissons nécessite une évaluation hospitalière immédiate.',
        tagWeights: {'biliary_infection_pattern': 78},
        requiredAllTags: {'biliary_infection_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Inflammation du pancréas possible',
        explanation:
            'Une douleur continue du haut du ventre irradiant vers le dos avec vomissements doit être examinée rapidement.',
        tagWeights: {
          'pancreatic_pattern': 44,
          'radiates_back': 22,
          'vomiting': 18,
          'upper_abdomen': 12,
        },
        requiredAllTags: {'pancreatic_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Calcul rénal possible',
        explanation:
            'Une douleur intense par vagues sur le côté qui descend vers l’aine peut venir d’un calcul urinaire.',
        tagWeights: {
          'colicky_flank_pain': 42,
          'radiates_groin': 34,
          'flank_pain': 18,
        },
        requiredAllTags: {'colicky_flank_pain', 'radiates_groin'},
      ),
      AssessmentPossibility(
        title: 'Infection urinaire ou rénale possible',
        explanation:
            'Brûlures urinaires, envies fréquentes ou fièvre avec douleur du dos nécessitent un avis médical.',
        tagWeights: {
          'urinary_burning': 28,
          'urinary_frequency': 24,
          'kidney_infection_pattern': 38,
          'fever': 18,
          'flank_pain': 16,
        },
        requiredAnyTags: {'urinary_burning', 'kidney_infection_pattern'},
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Complication gynécologique ou grossesse extra-utérine possible',
        explanation:
            'Une douleur pelvienne d’un côté avec grossesse possible, saignement ou malaise est une urgence à exclure.',
        tagWeights: {
          'pregnancy_possible': 20,
          'one_sided_pelvic_pain': 38,
          'bleeding': 26,
          'collapse': 24,
          'pelvic_pain': 18,
        },
        requiredAllTags: {'pregnancy_possible'},
        requiredAnyTags: {
          'one_sided_pelvic_pain',
          'bleeding',
          'collapse',
          'pelvic_pain',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Occlusion intestinale possible',
        explanation:
            'Un ventre gonflé avec vomissements et arrêt des selles ou des gaz nécessite une prise en charge urgente.',
        tagWeights: {
          'obstruction_pattern': 52,
          'abdominal_distension': 24,
          'vomiting': 16,
        },
        requiredAllTags: {'obstruction_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Constipation ou trouble fonctionnel intestinal',
        explanation:
            'Des crampes et ballonnements récurrents liés au transit peuvent correspondre à une constipation ou à un trouble fonctionnel.',
        tagWeights: {
          'constipation': 34,
          'bloating': 24,
          'bowel_relief': 30,
          'recurrent': 14,
          'cramps': 12,
        },
        requiredAnyTags: {'constipation', 'bowel_relief'},
        excludedTags: {
          'severe_pain',
          'rigid_abdomen',
          'digestive_bleeding',
          'obstruction_pattern',
          'cannot_hydrate',
          'triage_emergency',
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
    version: 4,
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
            label: 'Brutalement, douleur maximale en moins de 5 minutes',
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
            tags: {'recurrent', 'usual_pattern', 'branch_recurrent_headache'},
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
            tags: {'one_sided', 'pulsating', 'branch_one_sided_headache'},
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
            tags: {'facial_pressure', 'congestion', 'branch_sinus_headache'},
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
        prompt: 'Quels signes accompagnent le mal de tête ?',
        icon: Icons.light_mode_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'light_nausea',
            label: 'La lumière me gêne et j’ai des nausées',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'photophobia', 'nausea'},
          ),
          AssessmentOption(
            id: 'neck_tension',
            label: 'Muscles du cou tendus ou douloureux',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'neck_tension'},
          ),
          AssessmentOption(
            id: 'fever_stiff',
            label: 'Fièvre avec nuque raide',
            icon: Icons.warning_amber_rounded,
            tags: {'fever', 'stiff_neck', 'meningeal_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever_only',
            label: 'Fièvre sans raideur de nuque ni confusion',
            icon: Icons.thermostat_outlined,
            tags: {'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'non_blanching_rash',
            label: 'Taches violettes qui ne pâlissent pas sous pression',
            icon: Icons.emergency_outlined,
            tags: {'non_blanching_rash'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ceux-ci',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'light_only',
            label: 'La lumière me gêne, sans nausée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'photophobia'},
          ),
          AssessmentOption(
            id: 'nausea_only',
            label: 'Nausées, sans gêne à la lumière',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'nausea'},
          ),
          AssessmentOption(
            id: 'vomiting',
            label: 'Vomissements',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'vomiting'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_neuro',
        title: 'Signes neurologiques',
        prompt: 'Avez-vous remarqué l’un de ces signes ?',
        icon: Icons.psychology_outlined,
        allowMultiple: true,
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
            label: 'Confusion ou somnolence inhabituelle',
            icon: Icons.warning_amber_rounded,
            tags: {'confusion'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'sudden_vision_loss',
            label: 'Perte brutale de vision ou vision double nouvelle',
            icon: Icons.emergency_outlined,
            tags: {'sudden_vision_loss'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'vision',
            label: 'Vision trouble nouvelle ou persistante sans perte brutale',
            icon: Icons.visibility_off_outlined,
            tags: {'vision_change'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'seizure',
            label: 'Convulsion avec secousses',
            icon: Icons.warning_amber_rounded,
            tags: {'seizure'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'faint',
            label: 'Perte de connaissance',
            icon: Icons.warning_amber_rounded,
            tags: {'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_duration',
        title: 'Durée d’un épisode',
        prompt: 'Combien de temps dure un épisode sans traitement ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'minutes',
            label: 'Moins de 30 minutes',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'headache_short'},
          ),
          AssessmentOption(
            id: 'hours',
            label: 'De 30 minutes à 4 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'headache_hours'},
          ),
          AssessmentOption(
            id: 'day',
            label: 'De 4 à 72 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'headache_4_to_72h'},
          ),
          AssessmentOption(
            id: 'continuous',
            label: 'Plus de 72 heures sans disparaître',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'persistent', 'prolonged_headache'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_context',
        title: 'Contexte',
        prompt: 'Quelles situations vous concernent ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
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
            tags: {'pregnancy_possible', 'branch_headache_pregnancy'},
            urgency: AssessmentUrgency.consultationSoon,
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
          AssessmentOption(
            id: 'jaw_scalp',
            label:
                'Douleur à la mâchoire en mâchant ou cuir chevelu très sensible',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temporal_arteritis_warning'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'immunosuppression',
            label: 'Immunité diminuée ou cancer en cours de traitement',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'immunocompromised'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'stress',
            label: 'Période de stress important',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'stress'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_pregnancy_detail',
        title: 'Grossesse ou post-partum',
        prompt:
            'Quels signes accompagnent ce mal de tête pendant ou après la grossesse ?',
        icon: Icons.pregnant_woman_outlined,
        requiredTags: {'branch_headache_pregnancy'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'persistent_severe',
            label:
                'Fort, nouveau, persiste ou s’aggrave malgré repos et hydratation',
            icon: Icons.emergency_outlined,
            tags: {
              'severe_headache',
              'persistent',
              'obstetric_headache_red_flag',
            },
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'vision_change',
            label: 'Vision trouble, éclairs ou taches devant les yeux',
            icon: Icons.emergency_outlined,
            tags: {'vision_change', 'obstetric_headache_red_flag'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'sudden_swelling',
            label: 'Gonflement soudain du visage ou des mains',
            icon: Icons.emergency_outlined,
            tags: {'sudden_swelling', 'obstetric_headache_red_flag'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'upper_abdominal_pain',
            label: 'Douleur forte sous les côtes ou en haut du ventre',
            icon: Icons.emergency_outlined,
            tags: {'right_upper_abdomen', 'obstetric_headache_red_flag'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'breathlessness',
            label: 'Essoufflement inhabituel au repos',
            icon: Icons.emergency_outlined,
            tags: {'breathless_at_rest', 'obstetric_headache_red_flag'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'mild_improving',
            label: 'Léger ou habituel et il s’améliore',
            icon: Icons.check_circle_outline,
            tags: {'mild_headache'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_injury_detail',
        title: 'Après un choc à la tête',
        prompt: 'Quel signe est apparu depuis le choc ?',
        icon: Icons.sports_martial_arts_outlined,
        requiredTags: {'head_injury'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'loss_memory_vomiting',
            label:
                'Perte de connaissance, trou de mémoire ou vomissements répétés',
            icon: Icons.emergency_outlined,
            tags: {'serious_head_injury_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'anticoagulant',
            label: 'Traitement anticoagulant ou trouble de la coagulation',
            icon: Icons.emergency_outlined,
            tags: {'head_injury_anticoagulant'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'worsening_neuro',
            label: 'Somnolence croissante, faiblesse, confusion ou convulsion',
            icon: Icons.emergency_outlined,
            tags: {'serious_head_injury_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'minor_stable',
            label: 'Petit choc, état normal et douleur qui n’augmente pas',
            icon: Icons.check_circle_outline,
            tags: {'minor_head_injury'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_one_sided_features',
        title: 'Douleur d’un seul côté',
        prompt: 'Quels signes accompagnent la douleur d’un côté de la tête ?',
        icon: Icons.visibility_outlined,
        requiredTags: {'branch_one_sided_headache'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'migraine',
            label: 'Nausée et gêne à la lumière ou au bruit',
            icon: Icons.brightness_6_outlined,
            tags: {'migraine_pattern', 'photophobia', 'nausea'},
          ),
          AssessmentOption(
            id: 'cluster',
            label: 'Œil qui pleure, nez bouché et agitation du même côté',
            icon: Icons.remove_red_eye_outlined,
            tags: {'cluster_pattern', 'tearing_eye', 'restlessness'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'aura',
            label: 'Lignes lumineuses ou fourmillements brefs avant la douleur',
            icon: Icons.auto_awesome_outlined,
            tags: {'aura', 'migraine_pattern'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'red_eye',
            label: 'Œil rouge très douloureux avec baisse de vision',
            icon: Icons.warning_amber_rounded,
            tags: {'red_painful_eye', 'vision_change'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_sinus_features',
        title: 'Visage et nez',
        prompt:
            'Quelle situation décrit le mieux les signes du visage ou du nez ?',
        icon: Icons.face_outlined,
        requiredTags: {'branch_sinus_headache'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'viral',
            label: 'Rhume récent, gorge irritée ou toux',
            icon: Icons.sick_outlined,
            tags: {'upper_respiratory', 'viral_pattern'},
          ),
          AssessmentOption(
            id: 'persistent_fever',
            label:
                'Douleur faciale forte, fièvre ou aggravation après amélioration',
            icon: Icons.thermostat_outlined,
            tags: {'sinus_infection_pattern', 'fever', 'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'allergy',
            label: 'Éternuements et yeux qui grattent après un allergène',
            icon: Icons.grass_outlined,
            tags: {'allergen_trigger', 'itchy_eyes'},
          ),
          AssessmentOption(
            id: 'dental',
            label: 'Douleur d’une dent ou gonflement de la joue',
            icon: Icons.warning_amber_rounded,
            tags: {'dental_pain', 'facial_swelling'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_frequency',
        title: 'Fréquence et évolution',
        prompt: 'Comment ces maux de tête évoluent-ils ?',
        icon: Icons.calendar_month_outlined,
        requiredTags: {'branch_recurrent_headache'},
        options: [
          AssessmentOption(
            id: 'occasional',
            label: 'Quelques crises semblables, avec retour à la normale',
            icon: Icons.check_circle_outline,
            tags: {'episodic'},
          ),
          AssessmentOption(
            id: 'frequent_medicine',
            label: 'Mal de tête au moins 15 jours par mois',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'frequent_headache'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'progressive',
            label: 'De plus en plus forts, nouveaux ou réveillent la nuit',
            icon: Icons.trending_up_outlined,
            tags: {'progressive_headache', 'night_waking'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'exertion',
            label: 'Déclenchés par effort, toux, rapport sexuel ou position',
            icon: Icons.directions_run_outlined,
            tags: {'exertional_headache', 'positional_headache'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces évolutions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'headache_medicine_days',
        title: 'Antidouleurs',
        prompt:
            'Depuis au moins 3 mois, combien de jours par mois prenez-vous des antidouleurs pour ces maux de tête ?',
        icon: Icons.medication_outlined,
        requiredTags: {'branch_recurrent_headache'},
        options: [
          AssessmentOption(
            id: 'none',
            label: 'Aucun',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'under_10',
            label: 'De 1 à 9 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'occasional_pain_medicine'},
          ),
          AssessmentOption(
            id: '10_to_14',
            label: 'De 10 à 14 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'frequent_pain_medicine', 'pain_medicine_over_3_months'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: '15_plus',
            label: '15 jours ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'frequent_pain_medicine', 'pain_medicine_over_3_months'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'recent',
            label: 'Ces prises ont commencé il y a moins de 3 mois',
            icon: Icons.radio_button_unchecked_rounded,
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
        excludedTags: {
          'thunderclap',
          'neurologic_deficit',
          'stiff_neck',
          'seizure',
          'obstetric_headache_red_flag',
          'aura',
          'triage_emergency',
        },
        requiredAnyTags: {'one_sided', 'pulsating', 'migraine_pattern'},
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
        excludedTags: {
          'thunderclap',
          'neurologic_deficit',
          'stiff_neck',
          'seizure',
          'obstetric_headache_red_flag',
          'triage_emergency',
        },
        requiredAnyTags: {'pressure', 'neck_tension'},
      ),
      AssessmentPossibility(
        title: 'Céphalée liée à une congestion',
        explanation:
            'Une pression du visage avec nez bouché peut accompagner une infection respiratoire ou une inflammation des sinus.',
        tagWeights: {'facial_pressure': 32, 'congestion': 32, 'fever': 10},
        requiredAllTags: {'facial_pressure', 'congestion'},
        excludedTags: {'sinus_infection_pattern', 'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Déshydratation ou fatigue',
        explanation:
            'Le manque d’eau, la chaleur, le manque de sommeil ou un repas sauté peuvent favoriser un mal de tête.',
        tagWeights: {'dehydration_risk': 42, 'gradual': 12, 'diffuse': 12},
        requiredAllTags: {'dehydration_risk'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Algie vasculaire de la face possible',
        explanation:
            'Des crises très fortes d’un côté avec larmoiement, nez bouché et agitation peuvent correspondre à une algie vasculaire de la face.',
        tagWeights: {
          'cluster_pattern': 46,
          'tearing_eye': 28,
          'restlessness': 22,
          'one_sided': 14,
        },
        requiredAllTags: {'cluster_pattern'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Migraine avec aura possible',
        explanation:
            'Des signes visuels ou sensitifs brefs avant une douleur migraineuse sont compatibles avec une aura, mais un symptôme nouveau doit être évalué.',
        tagWeights: {
          'aura': 42,
          'migraine_pattern': 28,
          'pulsating': 16,
          'photophobia': 14,
        },
        requiredAllTags: {'aura'},
        excludedTags: {'neurologic_deficit', 'thunderclap', 'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Céphalée par surutilisation médicamenteuse possible',
        explanation:
            'Des maux de tête très fréquents avec prise répétée d’antidouleurs peuvent entretenir la douleur et nécessitent une révision du traitement.',
        tagWeights: {
          'frequent_headache': 38,
          'frequent_pain_medicine': 44,
          'persistent': 14,
        },
        requiredAllTags: {
          'frequent_headache',
          'frequent_pain_medicine',
          'pain_medicine_over_3_months',
        },
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Rhinosinusite ou infection ORL possible',
        explanation:
            'Une douleur du visage avec congestion, fièvre ou aggravation après une amélioration mérite une évaluation.',
        tagWeights: {
          'facial_pressure': 26,
          'sinus_infection_pattern': 40,
          'fever': 18,
          'worsening': 18,
          'upper_respiratory': 10,
        },
        requiredAllTags: {'facial_pressure', 'sinus_infection_pattern'},
      ),
      AssessmentPossibility(
        title: 'Allergie nasale',
        explanation:
            'Congestion, éternuements et yeux qui grattent après un déclencheur sont compatibles avec une allergie.',
        tagWeights: {
          'allergen_trigger': 38,
          'itchy_eyes': 34,
          'congestion': 18,
        },
        requiredAnyTags: {'allergen_trigger', 'itchy_eyes'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Problème oculaire urgent possible',
        explanation:
            'Un œil rouge très douloureux avec baisse de vision nécessite un examen le jour même.',
        tagWeights: {
          'red_painful_eye': 52,
          'vision_change': 30,
          'one_sided': 10,
        },
        requiredAllTags: {'red_painful_eye'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Céphalée secondaire à faire évaluer',
        explanation:
            'Une douleur nouvelle qui progresse, réveille la nuit ou survient à l’effort, à la toux ou selon la position doit être examinée.',
        tagWeights: {
          'progressive_headache': 38,
          'night_waking': 24,
          'exertional_headache': 34,
          'positional_headache': 24,
          'temporal_arteritis_warning': 60,
        },
      ),
      AssessmentPossibility(
        title: 'Complication de grossesse ou du post-partum à exclure',
        explanation:
            'Un mal de tête fort ou persistant avec trouble visuel, gonflement soudain, douleur haute du ventre ou essoufflement nécessite une évaluation urgente.',
        tagWeights: {
          'obstetric_headache_red_flag': 52,
          'vision_change': 16,
          'sudden_swelling': 16,
          'right_upper_abdomen': 16,
        },
        requiredAllTags: {'obstetric_headache_red_flag'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Cause neurologique ou infectieuse urgente à exclure',
        explanation:
            'Une douleur brutale, un déficit neurologique, une convulsion ou des signes méningés nécessitent une prise en charge urgente.',
        tagWeights: {
          'thunderclap': 52,
          'neurologic_deficit': 52,
          'seizure': 48,
          'stiff_neck': 36,
          'non_blanching_rash': 42,
          'meningeal_pattern': 46,
          'sudden_vision_loss': 52,
          'serious_head_injury_pattern': 56,
          'head_injury_anticoagulant': 52,
        },
        requiredAnyTags: {
          'thunderclap',
          'neurologic_deficit',
          'seizure',
          'stiff_neck',
          'non_blanching_rash',
          'meningeal_pattern',
          'sudden_vision_loss',
          'serious_head_injury_pattern',
          'head_injury_anticoagulant',
        },
        urgentReason: true,
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
    version: 4,
    title: 'Santé menstruelle',
    subtitle: 'Règles douloureuses, irrégulières ou saignement',
    icon: Icons.water_drop_outlined,
    color: Color(0xFFE65F91),
    questions: [
      AssessmentQuestion(
        id: 'menstrual_concern',
        title: 'Malaise principal',
        prompt: 'Quels changements avez-vous remarqués ?',
        icon: Icons.favorite_border_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'pain',
            label: 'Douleurs ou crampes',
            icon: Icons.waves_outlined,
            tags: {
              'cramps',
              'branch_menstrual_pain',
              'branch_menstrual_severity',
            },
          ),
          AssessmentOption(
            id: 'heavy',
            label: 'Saignement plus abondant',
            icon: Icons.water_drop_outlined,
            tags: {
              'heavy_bleeding',
              'branch_menstrual_bleeding',
              'branch_menstrual_severity',
            },
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'irregular',
            label: 'Règles irrégulières ou absentes',
            icon: Icons.event_busy_outlined,
            tags: {'irregular_cycle', 'branch_menstrual_cycle'},
          ),
          AssessmentOption(
            id: 'discharge',
            label: 'Pertes inhabituelles ou irritation',
            icon: Icons.info_outline,
            tags: {'discharge', 'branch_menstrual_discharge'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_severity',
        title: 'Intensité',
        prompt: 'Quelle situation correspond le mieux ?',
        icon: Icons.speed_outlined,
        requiredTags: {'branch_menstrual_severity'},
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
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Ni douleur importante ni saignement très abondant',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_bleeding_quantity',
        title: 'Quantité de sang',
        prompt:
            'À quelle fréquence une protection est-elle complètement imbibée ?',
        icon: Icons.water_drop_outlined,
        requiredTags: {'branch_menstrual_bleeding'},
        options: [
          AssessmentOption(
            id: 'usual',
            label: 'Pas plus souvent que d’habitude',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'usual_flow'},
          ),
          AssessmentOption(
            id: 'every_1_2h',
            label: 'Toutes les 1 à 2 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'heavy_bleeding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'hourly',
            label: 'Au moins une par heure, pendant 2 heures de suite',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'bleeding', 'very_heavy_bleeding'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'uncontrolled',
            label: 'Le sang coule sans arrêt malgré les protections',
            icon: Icons.warning_amber_rounded,
            tags: {'bleeding', 'very_heavy_bleeding', 'uncontrolled_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'no_current_bleeding',
            label: 'Je ne saigne pas actuellement',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_associated',
        title: 'Autres signes',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.playlist_add_check_circle_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'dizzy',
            label: 'Vertiges marqués ou faiblesse inhabituelle',
            icon: Icons.warning_amber_rounded,
            tags: {'dizziness', 'weakness'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'faint',
            label: 'Évanouissement ou perte de connaissance',
            icon: Icons.emergency_outlined,
            tags: {'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'chest_breathing',
            label: 'Douleur thoracique ou difficulté importante à respirer',
            icon: Icons.emergency_outlined,
            tags: {'cardiopulmonary_instability_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'palpitations',
            label: 'Palpitations persistantes avec faiblesse ou vertiges',
            icon: Icons.warning_amber_rounded,
            tags: {'symptomatic_palpitations'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Fièvre, mauvaise odeur ou forte douleur pelvienne',
            icon: Icons.thermostat_outlined,
            tags: {'pelvic_infection_pattern'},
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
            label: 'Oui, avec saignement',
            icon: Icons.emergency_outlined,
            tags: {'pregnancy_possible', 'bleeding'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'yes_pain',
            label: 'Oui, avec douleur du bas-ventre mais sans saignement',
            icon: Icons.warning_amber_rounded,
            tags: {
              'pregnancy_possible',
              'pelvic_pain',
              'branch_menstrual_pain',
            },
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'yes_no_bleeding',
            label: 'Oui, sans douleur forte ni saignement',
            icon: Icons.help_outline,
            tags: {
              'pregnancy_possible',
              'missed_period',
              'branch_menstrual_cycle',
            },
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(id: 'no', label: 'Non', icon: Icons.close_outlined),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.question_mark_outlined,
            tags: {'pregnancy_possible', 'branch_menstrual_cycle'},
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
      AssessmentQuestion(
        id: 'menstrual_contraception',
        title: 'Contexte du cycle',
        prompt: 'Quelles situations vous concernent actuellement ?',
        icon: Icons.calendar_month_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'hormonal_change',
            label:
                'Contraception hormonale commencée, arrêtée ou modifiée récemment',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'hormonal_change'},
          ),
          AssessmentOption(
            id: 'missed_pill',
            label: 'Oubli de pilule ou incident de préservatif',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'iud',
            label: 'Stérilet en place',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'iud'},
          ),
          AssessmentOption(
            id: 'breastfeeding',
            label: 'Allaitement en cours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'breastfeeding'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_bleeding_pattern',
        title: 'Caractéristiques du saignement',
        prompt: 'Quels changements de saignement avez-vous remarqués ?',
        icon: Icons.water_drop_outlined,
        requiredTags: {'branch_menstrual_bleeding'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'clots_long',
            label: 'Les règles durent plus de 7 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'prolonged_bleeding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'between_after_sex',
            label: 'Saignement entre les règles',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'intermenstrual_bleeding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'postmenopausal',
            label: 'Saignement après au moins 12 mois sans règles',
            icon: Icons.emergency_outlined,
            tags: {'postmenopausal_bleeding'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'anticoagulant',
            label: 'Je prends un anticoagulant ou saigne facilement ailleurs',
            icon: Icons.medication_outlined,
            tags: {'bleeding_tendency', 'anticoagulant'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces changements',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'after_sex',
            label: 'Saignement après un rapport',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'postcoital_bleeding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'large_clots',
            label: 'Caillots plus gros qu’une pièce de monnaie',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'large_clots'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_pain_pattern',
        title: 'Caractéristiques de la douleur',
        prompt: 'Quand et comment la douleur se manifeste-t-elle ?',
        icon: Icons.waves_outlined,
        requiredTags: {'branch_menstrual_pain'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'with_period',
            label: 'Surtout juste avant ou pendant les règles',
            icon: Icons.calendar_today_outlined,
            tags: {'cycle_related', 'cramps'},
          ),
          AssessmentOption(
            id: 'sex_bowel',
            label: 'Pendant les rapports, les selles ou plusieurs jours',
            icon: Icons.replay_outlined,
            tags: {'deep_pelvic_pain', 'bowel_related_pain', 'chronic'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'sudden_one_side',
            label: 'Brutale d’un seul côté avec nausée ou malaise',
            icon: Icons.warning_amber_rounded,
            tags: {'one_sided_pelvic_pain', 'sudden', 'nausea'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'outside_fever',
            label: 'En dehors des règles avec fièvre ou pertes',
            icon: Icons.thermostat_outlined,
            tags: {'pelvic_pain', 'fever', 'discharge'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_cycle_context',
        title: 'Contexte du cycle',
        prompt:
            'Quel changement accompagne les règles irrégulières ou absentes ?',
        icon: Icons.sync_outlined,
        requiredTags: {'branch_menstrual_cycle'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'stress_weight',
            label: 'Stress important récemment',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'stress'},
          ),
          AssessmentOption(
            id: 'acne_hair',
            label: 'Acné marquée ou augmentation des poils',
            icon: Icons.face_outlined,
            tags: {'androgen_pattern', 'acne'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'hot_flashes',
            label: 'Bouffées de chaleur ou âge proche de la ménopause',
            icon: Icons.local_fire_department_outlined,
            tags: {'hot_flashes', 'perimenopause_pattern'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'milk_headache',
            label: 'Écoulement de lait en dehors de l’allaitement',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'galactorrhea'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun changement évident',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'weight_change',
            label: 'Perte ou prise de poids importante',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'weight_change'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'exercise',
            label: 'Entraînement physique devenu très intense',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'intense_exercise'},
          ),
          AssessmentOption(
            id: 'headache',
            label: 'Maux de tête nouveaux',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'headache'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'menstrual_discharge_detail',
        title: 'Pertes et irritation',
        prompt: 'Comment sont les pertes et quels signes les accompagnent ?',
        icon: Icons.info_outline,
        requiredTags: {'branch_menstrual_discharge'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'fever_odor',
            label: 'Mauvaise odeur avec fièvre ou douleur pelvienne',
            icon: Icons.thermostat_outlined,
            tags: {'foul_discharge', 'fever', 'pelvic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'thick_itch',
            label: 'Épaisses avec fortes démangeaisons',
            icon: Icons.back_hand_outlined,
            tags: {'thick_discharge', 'itch'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'thin_odor',
            label: 'Fluides avec odeur inhabituelle, sans fièvre',
            icon: Icons.water_drop_outlined,
            tags: {'thin_discharge', 'odor'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'sores',
            label: 'Plaies, cloques ou douleur importante',
            icon: Icons.warning_amber_rounded,
            tags: {'genital_sores', 'painful_skin'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
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
        requiredAllTags: {'cramps'},
        excludedTags: {
          'pregnancy_possible',
          'one_sided_pelvic_pain',
          'severe_pain',
          'collapse',
          'triage_emergency',
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
        requiredAnyTags: {'heavy_bleeding', 'very_heavy_bleeding'},
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
        requiredAnyTags: {'irregular_cycle', 'missed_period'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Infection ou inflammation pelvienne possible',
        explanation:
            'Des pertes inhabituelles avec fièvre ou douleur pelvienne doivent être évaluées rapidement.',
        tagWeights: {
          'discharge': 28,
          'foul_discharge': 30,
          'fever': 28,
          'pelvic_pain': 26,
          'pelvic_infection_pattern': 48,
        },
        requiredAnyTags: {
          'fever',
          'pelvic_pain',
          'foul_discharge',
          'pelvic_infection_pattern',
        },
      ),
      AssessmentPossibility(
        title: 'Endométriose ou autre cause gynécologique possible',
        explanation:
            'Une douleur qui limite les activités, revient sur plusieurs cycles ou survient pendant les rapports mérite un bilan.',
        tagWeights: {
          'chronic_pelvic_pain': 35,
          'activity_limiting': 25,
          'deep_pelvic_pain': 34,
          'bowel_related_pain': 30,
          'recurrent': 18,
          'chronic': 12,
        },
        requiredAnyTags: {
          'chronic_pelvic_pain',
          'deep_pelvic_pain',
          'bowel_related_pain',
        },
      ),
      AssessmentPossibility(
        title: 'Fibrome, polype ou adénomyose possible',
        explanation:
            'Des règles longues ou abondantes avec caillots, pression ou douleur peuvent avoir une cause structurelle à vérifier.',
        tagWeights: {
          'heavy_bleeding': 24,
          'prolonged_bleeding': 30,
          'large_clots': 26,
          'activity_limiting': 14,
          'chronic': 10,
        },
        requiredAnyTags: {
          'heavy_bleeding',
          'prolonged_bleeding',
          'large_clots',
        },
      ),
      AssessmentPossibility(
        title: 'Syndrome des ovaires polykystiques possible',
        explanation:
            'Des cycles irréguliers associés à de l’acné ou une augmentation des poils peuvent évoquer un trouble hormonal.',
        tagWeights: {
          'irregular_cycle': 32,
          'androgen_pattern': 38,
          'acne': 18,
          'persistent': 12,
        },
        requiredAllTags: {'irregular_cycle', 'androgen_pattern'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Transition vers la ménopause possible',
        explanation:
            'Des cycles variables avec bouffées de chaleur peuvent correspondre à la périménopause; tout saignement après la ménopause doit être examiné.',
        tagWeights: {
          'perimenopause_pattern': 42,
          'hot_flashes': 30,
          'irregular_cycle': 20,
          'postmenopausal_bleeding': 20,
        },
        requiredAnyTags: {'perimenopause_pattern', 'hot_flashes'},
        excludedTags: {'postmenopausal_bleeding', 'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Cause cervicale ou utérine à vérifier',
        explanation:
            'Un saignement entre les règles, après un rapport ou après la ménopause nécessite un examen pour en identifier la cause.',
        tagWeights: {
          'intermenstrual_bleeding': 34,
          'postcoital_bleeding': 34,
          'postmenopausal_bleeding': 46,
        },
      ),
      AssessmentPossibility(
        title: 'Vaginite ou infection locale possible',
        explanation:
            'Des pertes épaisses ou odorantes avec démangeaisons peuvent correspondre à une irritation ou une infection locale.',
        tagWeights: {
          'thick_discharge': 32,
          'thin_discharge': 28,
          'itch': 24,
          'odor': 22,
          'foul_discharge': 30,
        },
        requiredAnyTags: {
          'thick_discharge',
          'thin_discharge',
          'foul_discharge',
        },
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Kyste ovarien ou autre cause pelvienne aiguë possible',
        explanation:
            'Une douleur nouvelle d’un seul côté, surtout brutale avec nausée, nécessite un examen rapide.',
        tagWeights: {
          'one_sided_pelvic_pain': 42,
          'sudden': 24,
          'nausea': 18,
          'severe_pain': 18,
        },
        requiredAllTags: {'one_sided_pelvic_pain'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Anémie liée aux pertes possible',
        explanation:
            'Des saignements abondants avec faiblesse, essoufflement ou vertiges peuvent entraîner une anémie.',
        tagWeights: {
          'very_heavy_bleeding': 34,
          'heavy_bleeding': 24,
          'dizziness': 28,
          'prolonged_bleeding': 18,
        },
        requiredAnyTags: {'heavy_bleeding', 'very_heavy_bleeding'},
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Complication de grossesse à exclure',
        explanation:
            'Une grossesse possible associée à une douleur ou un saignement doit être évaluée rapidement; douleur unilatérale, épaule, malaise ou saignement important sont des urgences.',
        tagWeights: {
          'pregnancy_possible': 18,
          'bleeding': 28,
          'pelvic_pain': 22,
          'one_sided_pelvic_pain': 38,
          'collapse': 34,
          'severe_pain': 30,
          'cardiopulmonary_instability_pattern': 38,
        },
        requiredAllTags: {'pregnancy_possible'},
        requiredAnyTags: {
          'bleeding',
          'pelvic_pain',
          'one_sided_pelvic_pain',
          'collapse',
          'severe_pain',
          'cardiopulmonary_instability_pattern',
        },
        minimumMatchedEvidence: 2,
        urgentReason: true,
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
    version: 4,
    title: 'Santé respiratoire',
    subtitle: 'Toux, congestion, respiration sifflante ou essoufflement',
    icon: Icons.air_outlined,
    color: Color(0xFF149D9A),
    questions: [
      AssessmentQuestion(
        id: 'respiratory_age',
        title: 'Âge',
        prompt: 'Quel âge a la personne concernée ?',
        icon: Icons.cake_outlined,
        options: [
          AssessmentOption(
            id: 'under_3_months',
            label: 'Moins de 3 mois',
            icon: Icons.child_care_outlined,
            tags: {'person_under_3_months'},
          ),
          AssessmentOption(
            id: '3_to_6_months',
            label: 'De 3 à moins de 6 mois',
            icon: Icons.child_care_outlined,
            tags: {'person_3_to_6_months'},
          ),
          AssessmentOption(
            id: 'child',
            label: 'De 6 mois à moins de 16 ans',
            icon: Icons.escalator_warning_outlined,
            tags: {'person_under_16'},
          ),
          AssessmentOption(
            id: 'adult',
            label: '16 ans ou plus',
            icon: Icons.person_outline,
          ),
        ],
      ),
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
            tags: {'respiratory_failure_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_main',
        title: 'Signe principal',
        prompt: 'Quels symptômes respiratoires avez-vous ?',
        icon: Icons.medical_information_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'dry_cough',
            label: 'Toux sèche ou gorge irritée',
            icon: Icons.record_voice_over_outlined,
            tags: {'cough', 'dry_cough', 'branch_respiratory_cough'},
          ),
          AssessmentOption(
            id: 'wet_cough',
            label: 'Toux avec crachats',
            icon: Icons.water_drop_outlined,
            tags: {'cough', 'productive_cough', 'branch_respiratory_cough'},
          ),
          AssessmentOption(
            id: 'wheeze',
            label: 'Sifflement en respirant',
            icon: Icons.graphic_eq_outlined,
            tags: {'wheeze', 'branch_respiratory_wheeze'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'tightness',
            label: 'Oppression ou poitrine serrée sans douleur forte',
            icon: Icons.compress_outlined,
            tags: {'chest_tightness', 'branch_respiratory_wheeze'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'nose',
            label: 'Nez bouché, éternuements ou gorge',
            icon: Icons.face_outlined,
            tags: {
              'congestion',
              'upper_respiratory',
              'branch_respiratory_nose',
            },
          ),
          AssessmentOption(
            id: 'breathlessness',
            label: 'Essoufflement sans toux ni nez bouché au premier plan',
            icon: Icons.air_outlined,
            tags: {
              'breathlessness_primary',
              'branch_respiratory_breathlessness',
            },
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_red_flags',
        title: 'Signes d’alerte',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.warning_amber_rounded,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'chest_pain',
            label: 'Douleur ou forte pression dans la poitrine',
            icon: Icons.emergency_outlined,
            tags: {'chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'blood_streaks',
            label: 'Quelques traces ou stries de sang dans les crachats',
            icon: Icons.warning_amber_rounded,
            tags: {'coughing_blood'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'blood_more',
            label:
                'Plus que quelques traces de sang, ou sang avec essoufflement/douleur',
            icon: Icons.emergency_outlined,
            tags: {'significant_hemoptysis'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Température mesurée à 39 °C ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'fever', 'temperature_39'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'very_unwell',
            label: 'État très altéré, peau moite ou très peu d’urines',
            icon: Icons.emergency_outlined,
            tags: {'systemically_unwell', 'sepsis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'airway_swelling',
            label:
                'Langue/gorge gonflée, voix modifiée ou bruit aigu en respirant',
            icon: Icons.emergency_outlined,
            tags: {'upper_airway_obstruction', 'anaphylaxis'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'child_distress',
            label:
                'Enfant : tirage des côtes, pauses respiratoires ou mauvaise alimentation',
            icon: Icons.emergency_outlined,
            tags: {'pediatric_respiratory_distress'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'chills',
            label: 'Frissons, sans température mesurée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'chills', 'temperature_unconfirmed'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_temperature',
        title: 'Température',
        prompt:
            'Quelle a été la température la plus élevée mesurée depuis le début ?',
        icon: Icons.thermostat_outlined,
        options: [
          AssessmentOption(
            id: 'below_38',
            label: 'De 36 à 37,9 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_below_38'},
          ),
          AssessmentOption(
            id: '38',
            label: 'De 38 à 38,9 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_38', 'fever'},
          ),
          AssessmentOption(
            id: '39',
            label: 'De 39 à 39,9 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_39', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: '40',
            label: '40 °C ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_40', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'below_36',
            label: 'Moins de 36 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_below_36'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unmeasured',
            label: 'Je ne l’ai pas mesurée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_unconfirmed'},
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
            label: 'Entre 1 et 3 semaines, stable ou en amélioration',
            icon: Icons.trending_up_outlined,
            tags: {'subacute'},
          ),
          AssessmentOption(
            id: 'worsening',
            label: 'Aggravation rapide ou amélioration puis rechute',
            icon: Icons.warning_amber_rounded,
            tags: {'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'weeks',
            label: 'Plus de trois semaines',
            icon: Icons.history_outlined,
            tags: {'chronic', 'branch_respiratory_chronic'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_context',
        title: 'Contexte respiratoire',
        prompt: 'Quelles situations vous concernent ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'asthma',
            label: 'Asthme ou inhalateur habituel',
            icon: Icons.medication_outlined,
            tags: {'asthma_history', 'branch_respiratory_wheeze'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'allergy',
            label: 'Après poussière, parfum, animal ou allergène',
            icon: Icons.grass_outlined,
            tags: {'allergen_trigger', 'branch_respiratory_nose'},
          ),
          AssessmentOption(
            id: 'sick_contact',
            label: 'Après contact avec une personne malade',
            icon: Icons.groups_outlined,
            tags: {'sick_contact'},
          ),
          AssessmentOption(
            id: 'smoke',
            label: 'Tabac, charbon, fumée ou poussière au travail',
            icon: Icons.smoke_free_outlined,
            tags: {'smoke_exposure', 'branch_respiratory_chronic'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'clot_risk',
            label:
                'Immobilisation, chirurgie, cancer, caillot antérieur ou post-partum récent',
            icon: Icons.warning_amber_rounded,
            tags: {'clot_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'active_cancer_treatment',
            label:
                'Chimiothérapie ou traitement anticancéreux actif/récent avec fièvre ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'possible_neutropenic_sepsis'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_outlined,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_breathlessness_detail',
        title: 'Essoufflement sans toux',
        prompt: 'Quelle situation accompagne l’essoufflement ?',
        icon: Icons.air_outlined,
        requiredTags: {'branch_respiratory_breathlessness'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'sudden_pleuritic',
            label:
                'Début soudain avec douleur respiratoire, sang ou une jambe gonflée',
            icon: Icons.emergency_outlined,
            tags: {'pulmonary_embolism_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'throat',
            label: 'Gorge/langue gonflée, voix modifiée ou difficulté à avaler',
            icon: Icons.emergency_outlined,
            tags: {'upper_airway_obstruction', 'anaphylaxis'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'lying',
            label: 'Pire en position couchée ou avec chevilles gonflées',
            icon: Icons.warning_amber_rounded,
            tags: {'orthopnea'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'gradual',
            label: 'Progressif, seulement à l’effort, sans autre signe',
            icon: Icons.directions_walk_outlined,
            tags: {'exertional_breathlessness'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_cough_detail',
        title: 'Caractéristiques de la toux',
        prompt: 'Quels signes accompagnent votre toux ?',
        icon: Icons.record_voice_over_outlined,
        requiredTags: {'branch_respiratory_cough'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'fits_vomit',
            label: 'Quintes répétées avec vomissement ou reprise bruyante',
            icon: Icons.sync_problem_outlined,
            tags: {'coughing_fits', 'post_tussive_vomiting'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'breath_pain',
            label: 'Douleur sur le côté quand je respire ou tousse',
            icon: Icons.warning_amber_rounded,
            tags: {'pleuritic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'night_reflux',
            label: 'La toux est surtout nocturne',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'night_cough'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'improved_worse',
            label: 'Elle s’améliorait puis revient plus forte avec fièvre',
            icon: Icons.trending_up_outlined,
            tags: {'worsening_after_improvement', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'simple',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'after_meals',
            label: 'Toux après les repas avec remontées acides',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'reflux_pattern', 'acid_reflux'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_wheeze_detail',
        title: 'Sifflement et oppression',
        prompt: 'Comment évoluent le sifflement ou l’oppression ?',
        icon: Icons.air_outlined,
        requiredTags: {'branch_respiratory_wheeze'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'reliever_fails',
            label: 'Le traitement de secours n’aide pas et je m’aggrave',
            icon: Icons.emergency_outlined,
            tags: {'reliever_not_working', 'asthma_exacerbation'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'reliever_short',
            label:
                'Le traitement aide trop peu de temps ou doit être repris très souvent',
            icon: Icons.warning_amber_rounded,
            tags: {'reliever_short_effect', 'asthma_exacerbation'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'night_activity',
            label: 'Réveils la nuit ou gêne pour les activités habituelles',
            icon: Icons.bedtime_outlined,
            tags: {'night_wheeze', 'activity_limiting'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'triggered',
            label: 'Après effort, froid, poussière, fumée ou allergène',
            icon: Icons.grass_outlined,
            tags: {'triggered_wheeze'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'swelling',
            label: 'Avec gonflement des lèvres/langue ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'anaphylaxis', 'facial_swelling'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_nose_detail',
        title: 'Nez, gorge et visage',
        prompt: 'Quel ensemble de signes est présent ?',
        icon: Icons.face_outlined,
        requiredTags: {'branch_respiratory_nose'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'itchy_watery',
            label: 'Éternuements, nez clair et yeux qui grattent',
            icon: Icons.grass_outlined,
            tags: {'itchy_eyes', 'watery_nose', 'allergy_pattern'},
          ),
          AssessmentOption(
            id: 'sore_throat',
            label:
                'Gorge très douloureuse, difficulté à avaler ou forte fièvre',
            icon: Icons.warning_amber_rounded,
            tags: {'severe_sore_throat', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'facial_pain',
            label: 'Douleur du visage avec écoulement épais ou aggravation',
            icon: Icons.sick_outlined,
            tags: {'facial_pressure', 'sinus_infection_pattern', 'worsening'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'simple_cold',
            label: 'Rhume léger depuis quelques jours',
            icon: Icons.check_circle_outline,
            tags: {'simple_cold'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces ensembles de signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_swallowing',
        title: 'Gorge et déglutition',
        prompt: 'Comment arrivez-vous à avaler ?',
        icon: Icons.record_voice_over_outlined,
        requiredTags: {'branch_respiratory_nose'},
        options: [
          AssessmentOption(
            id: 'normal',
            label: 'Je mange et bois normalement',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'swallowing_ok'},
          ),
          AssessmentOption(
            id: 'painful',
            label: 'Avaler fait mal, mais je peux boire',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'sore_throat'},
          ),
          AssessmentOption(
            id: 'cannot_swallow_saliva',
            label: 'Je n’arrive pas à avaler ma salive',
            icon: Icons.warning_amber_rounded,
            tags: {'upper_airway_obstruction'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'muffled_voice',
            label: 'Ma voix est étouffée et j’ai du mal à ouvrir la bouche',
            icon: Icons.warning_amber_rounded,
            tags: {'deep_throat_infection_warning'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'respiratory_chronic_detail',
        title: 'Toux persistante',
        prompt: 'Quels signes accompagnent cette toux persistante ?',
        icon: Icons.history_outlined,
        requiredTags: {'branch_respiratory_chronic'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'smoking_phlegm',
            label: 'Exposition à la fumée avec toux et crachats réguliers',
            icon: Icons.smoke_free_outlined,
            tags: {'chronic_phlegm', 'smoke_exposure'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'weight_loss',
            label: 'Perte de poids involontaire',
            icon: Icons.warning_amber_rounded,
            tags: {'weight_loss'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'night_sweats',
            label: 'Sueurs nocturnes répétées',
            icon: Icons.warning_amber_rounded,
            tags: {'night_sweats'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'prolonged_fever',
            label: 'Fièvre prolongée ou répétée',
            icon: Icons.warning_amber_rounded,
            tags: {'prolonged_fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'lying',
            label: 'Essoufflement en position couchée',
            icon: Icons.bed_outlined,
            tags: {'orthopnea'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'ankles',
            label: 'Chevilles gonflées avec essoufflement',
            icon: Icons.accessibility_new_outlined,
            tags: {'ankle_swelling'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Fièvre du jeune nourrisson à évaluer immédiatement',
        explanation:
            'Une température élevée avant 3 mois nécessite une évaluation pédiatrique immédiate, même si le symptôme principal paraît respiratoire.',
        tagWeights: {'young_infant_fever': 80},
        requiredAllTags: {'young_infant_fever'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title:
            'Neutropénie fébrile ou infection grave sous traitement possible',
        explanation:
            'Une fièvre ou un malaise sous traitement anticancéreux actif ou récent nécessite une évaluation hospitalière immédiate.',
        tagWeights: {'possible_neutropenic_sepsis': 80},
        requiredAllTags: {'possible_neutropenic_sepsis'},
        urgentReason: true,
      ),
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
        excludedTags: {
          'severe_breathlessness',
          'cyanosis',
          'confusion',
          'upper_airway_obstruction',
          'pulmonary_embolism_pattern',
          'significant_hemoptysis',
          'respiratory_failure_pattern',
          'young_infant_fever',
          'possible_neutropenic_sepsis',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Détresse respiratoire à prendre en charge immédiatement',
        explanation:
            'Des lèvres bleues ou grises, une confusion ou un épuisement respiratoire nécessitent une aide médicale immédiate.',
        tagWeights: {
          'respiratory_failure_pattern': 80,
          'severe_breathlessness': 66,
        },
        requiredAnyTags: {
          'respiratory_failure_pattern',
          'severe_breathlessness',
        },
        urgentReason: true,
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
          'reliever_not_working': 42,
          'reliever_short_effect': 28,
        },
        requiredAnyTags: {'wheeze', 'chest_tightness'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Pneumonie ou infection basse possible',
        explanation:
            'Une toux avec fièvre, faiblesse ou essoufflement peut nécessiter un examen des poumons.',
        tagWeights: {
          'cough': 8,
          'productive_cough': 22,
          'fever': 28,
          'systemically_unwell': 22,
          'mild_breathlessness': 16,
          'pleuritic_pain': 16,
          'worsening': 10,
          'worsening_after_improvement': 22,
        },
        requiredAllTags: {'cough'},
        requiredAnyTags: {
          'fever',
          'systemically_unwell',
          'mild_breathlessness',
          'pleuritic_pain',
          'worsening',
          'worsening_after_improvement',
        },
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Allergie respiratoire',
        explanation:
            'Éternuements, congestion ou sifflement après un déclencheur peuvent correspondre à une réaction allergique.',
        tagWeights: {'allergen_trigger': 38, 'congestion': 22, 'wheeze': 20},
        requiredAnyTags: {'allergen_trigger', 'allergy_pattern'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Bronchite aiguë possible',
        explanation:
            'Une toux récente, sèche ou avec crachats, peut accompagner une inflammation virale des bronches.',
        tagWeights: {
          'dry_cough': 22,
          'productive_cough': 24,
          'days': 16,
          'simple_cold': 14,
        },
        requiredAnyTags: {'dry_cough', 'productive_cough'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Coqueluche ou autre toux en quintes possible',
        explanation:
            'Des quintes répétées avec vomissement ou reprise bruyante nécessitent un avis et des mesures pour limiter la transmission.',
        tagWeights: {
          'coughing_fits': 46,
          'post_tussive_vomiting': 32,
          'persistent': 14,
        },
        requiredAllTags: {'coughing_fits'},
      ),
      AssessmentPossibility(
        title: 'Rhinosinusite possible',
        explanation:
            'Une congestion avec douleur du visage, écoulement épais ou aggravation peut correspondre à une inflammation des sinus.',
        tagWeights: {
          'facial_pressure': 34,
          'sinus_infection_pattern': 38,
          'worsening': 16,
          'congestion': 16,
        },
        requiredAllTags: {'facial_pressure'},
      ),
      AssessmentPossibility(
        title: 'Toux liée au reflux ou à l’écoulement nasal possible',
        explanation:
            'Une toux surtout nocturne, couchée ou après les repas peut être favorisée par un reflux ou un écoulement nasal.',
        tagWeights: {'night_cough': 34, 'reflux_pattern': 36, 'congestion': 14},
        requiredAllTags: {'night_cough'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Maladie respiratoire chronique possible',
        explanation:
            'Une toux durable avec crachats et exposition répétée à la fumée mérite un bilan respiratoire.',
        tagWeights: {
          'chronic': 22,
          'chronic_phlegm': 38,
          'smoke_exposure': 34,
          'mild_breathlessness': 14,
        },
        requiredAllTags: {'chronic'},
      ),
      AssessmentPossibility(
        title: 'Tuberculose ou autre infection prolongée à exclure',
        explanation:
            'Une toux prolongée avec perte de poids, sueurs nocturnes ou fièvre doit être évaluée rapidement.',
        tagWeights: {
          'chronic': 12,
          'weight_loss': 30,
          'night_sweats': 32,
          'prolonged_fever': 30,
          'coughing_blood': 28,
        },
        requiredAllTags: {'chronic'},
        requiredAnyTags: {
          'weight_loss',
          'night_sweats',
          'prolonged_fever',
          'coughing_blood',
        },
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Cause cardiaque de l’essoufflement à vérifier',
        explanation:
            'Un essoufflement en position couchée avec gonflement des chevilles nécessite un examen médical.',
        tagWeights: {
          'orthopnea': 46,
          'ankle_swelling': 38,
          'mild_breathlessness': 16,
        },
        requiredAnyTags: {'orthopnea', 'ankle_swelling'},
      ),
      AssessmentPossibility(
        title: 'Embolie pulmonaire à exclure en urgence',
        explanation:
            'Un essoufflement soudain avec douleur respiratoire, sang ou jambe gonflée nécessite une prise en charge urgente.',
        tagWeights: {
          'pulmonary_embolism_pattern': 60,
          'severe_breathlessness': 26,
          'pleuritic_pain': 22,
          'significant_hemoptysis': 28,
        },
        requiredAllTags: {'pulmonary_embolism_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Obstruction des voies aériennes ou anaphylaxie possible',
        explanation:
            'Un gonflement de la langue ou de la gorge, une voix modifiée ou un bruit aigu en respirant est une urgence.',
        tagWeights: {
          'upper_airway_obstruction': 60,
          'anaphylaxis': 48,
          'facial_swelling': 24,
        },
        requiredAnyTags: {'upper_airway_obstruction', 'anaphylaxis'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Hémoptysie importante à prendre en charge',
        explanation:
            'Cracher plus que quelques traces de sang, surtout avec douleur ou essoufflement, nécessite une prise en charge urgente.',
        tagWeights: {'significant_hemoptysis': 60},
        requiredAllTags: {'significant_hemoptysis'},
        urgentReason: true,
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
    version: 4,
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
        allowMultiple: true,
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
            label:
                'Taches violettes qui ne pâlissent pas, dépassent 2 mm ou s’étendent vite',
            icon: Icons.emergency_outlined,
            tags: {'non_blanching_rash'},
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
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'dry',
            label: 'Plaques sèches ou rugueuses qui grattent',
            icon: Icons.texture_outlined,
            tags: {'dry_patch', 'itch', 'branch_skin_itch'},
          ),
          AssessmentOption(
            id: 'hives',
            label: 'Plaques gonflées qui apparaissent et bougent',
            icon: Icons.bubble_chart_outlined,
            tags: {'hives', 'itch', 'branch_skin_itch'},
          ),
          AssessmentOption(
            id: 'ring',
            label: 'Plaque ronde avec bord plus marqué',
            icon: Icons.circle_outlined,
            tags: {'ring_shaped', 'scaly', 'branch_skin_itch'},
          ),
          AssessmentOption(
            id: 'pimples',
            label: 'Boutons, points noirs ou petites pustules',
            icon: Icons.grain_outlined,
            tags: {'pimples', 'pustules', 'branch_skin_pustules'},
          ),
          AssessmentOption(
            id: 'changing_lesion',
            label:
                'Grain de beauté qui change, plaie qui ne guérit pas ou lésion qui saigne',
            icon: Icons.search_outlined,
            tags: {'branch_skin_changing_lesion'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'other',
            label: 'Autre aspect ou je ne sais pas',
            icon: Icons.help_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_sensation',
        title: 'Sensation',
        prompt: 'Que ressentez-vous principalement ?',
        icon: Icons.touch_app_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'itch',
            label: 'Démangeaisons',
            icon: Icons.back_hand_outlined,
            tags: {'itch'},
          ),
          AssessmentOption(
            id: 'pain',
            label: 'Douleur de la peau',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'painful_skin', 'branch_skin_infection'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'blister',
            label: 'Cloques remplies de liquide',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'blister', 'branch_skin_blister'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Peu de sensation',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'warm',
            label: 'Zone plus chaude au toucher',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'warm_skin', 'branch_skin_infection'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'swollen',
            label: 'Zone gonflée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_swelling', 'branch_skin_infection'},
            urgency: AssessmentUrgency.consultationSoon,
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
        id: 'skin_duration',
        title: 'Ancienneté',
        prompt: 'Depuis quand le problème de peau est-il présent ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'today',
            label: 'Depuis moins de 24 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'acute_skin'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis 1 à 7 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_days'},
          ),
          AssessmentOption(
            id: 'weeks',
            label: 'Depuis plus d’une semaine',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'persistent_skin'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'recurrent',
            label: 'Il disparaît puis revient',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_location',
        title: 'Localisation',
        prompt: 'Quelles zones sont touchées ?',
        icon: Icons.accessibility_new_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'face',
            label: 'Visage ou autour d’un œil',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'face_or_eye'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'trunk',
            label: 'Poitrine, ventre ou dos',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_trunk'},
          ),
          AssessmentOption(
            id: 'limbs',
            label: 'Bras ou jambes',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_limbs'},
          ),
          AssessmentOption(
            id: 'folds',
            label: 'Aisselles, aine ou sous les seins',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_folds'},
          ),
          AssessmentOption(
            id: 'hands_feet',
            label: 'Mains ou pieds',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_hands_feet'},
          ),
          AssessmentOption(
            id: 'genitals',
            label: 'Organes génitaux',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'skin_genitals'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'other',
            label: 'Autre zone',
            icon: Icons.radio_button_unchecked_rounded,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_trigger',
        title: 'Déclencheur possible',
        prompt: 'Y a-t-il eu un changement récent ?',
        icon: Icons.search_outlined,
        allowMultiple: true,
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
      AssessmentQuestion(
        id: 'skin_risk_context',
        title: 'Contexte de la peau',
        prompt: 'Une de ces situations vous concerne-t-elle ?',
        icon: Icons.medical_information_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'diabetes',
            label: 'Diabète connu',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'diabetes_context'},
          ),
          AssessmentOption(
            id: 'immunity',
            label: 'Immunité diminuée ou traitement immunosuppresseur',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'immunocompromised'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'surgery',
            label: 'Intervention ou plaie récente dans cette zone',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'wound_trigger'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_infection_detail',
        title: 'Douleur, chaleur ou gonflement',
        prompt: 'Quels signes accompagnent la zone de peau douloureuse ?',
        icon: Icons.local_fire_department_outlined,
        requiredTags: {'branch_skin_infection'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'red_spreading_fever',
            label: 'Rougeur qui s’étend avec fièvre ou frissons',
            icon: Icons.warning_amber_rounded,
            tags: {'cellulitis_pattern', 'rapid_spread', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'abscess',
            label: 'Boule très sensible avec pus ou centre mou',
            icon: Icons.circle_outlined,
            tags: {'abscess_pattern', 'pus'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'severe_fast',
            label:
                'Douleur extrême, cloques sombres ou progression en quelques heures',
            icon: Icons.emergency_outlined,
            tags: {'severe_skin_pain', 'skin_necrosis_pattern', 'rapid_spread'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'wound_bite',
            label: 'Après une plaie, morsure, piqûre ou intervention',
            icon: Icons.healing_outlined,
            tags: {'wound_trigger'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Zone stable sans ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_blister_detail',
        title: 'Cloques ou brûlures',
        prompt: 'Comment les cloques sont-elles réparties ?',
        icon: Icons.water_drop_outlined,
        requiredTags: {'branch_skin_blister'},
        options: [
          AssessmentOption(
            id: 'one_side_band',
            label: 'En bande douloureuse d’un seul côté',
            icon: Icons.view_stream_outlined,
            tags: {'dermatomal_pattern', 'nerve_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'eyes_mouth_genitals',
            label: 'Avec plaies des yeux, de la bouche ou des organes génitaux',
            icon: Icons.emergency_outlined,
            tags: {'mucosal_involvement', 'widespread_peeling'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'burn',
            label: 'Petite brûlure superficielle par chaleur ou soleil',
            icon: Icons.wb_sunny_outlined,
            tags: {'burn_trigger'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'major_burn',
            label:
                'Brûlure chimique/électrique, profonde, étendue ou du visage, mains ou organes génitaux',
            icon: Icons.emergency_outlined,
            tags: {'major_burn_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'grouped_recurrent',
            label: 'Petites cloques groupées qui reviennent au même endroit',
            icon: Icons.bubble_chart_outlined,
            tags: {'grouped_blisters', 'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'friction_or_other',
            label: 'Petite cloque de frottement stable ou autre aspect',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_itch_detail',
        title: 'Démangeaisons',
        prompt: 'Quand et où les démangeaisons sont-elles les plus fortes ?',
        icon: Icons.back_hand_outlined,
        requiredTags: {'branch_skin_itch'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'night_household',
            label: 'Surtout la nuit; d’autres proches se grattent aussi',
            icon: Icons.bedtime_outlined,
            tags: {'night_itch', 'household_spread'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'contact_area',
            label: 'Seulement sur la zone touchée par un produit ou objet',
            icon: Icons.soap_outlined,
            tags: {'contact_distribution', 'contact_trigger'},
          ),
          AssessmentOption(
            id: 'scalp_elbows',
            label: 'Plaques épaisses sur cuir chevelu, coudes ou genoux',
            icon: Icons.texture_outlined,
            tags: {'thick_scale', 'extensor_distribution'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'generalized',
            label: 'Sur tout le corps sans éruption claire',
            icon: Icons.accessibility_new_outlined,
            tags: {'generalized_itch'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_pustule_detail',
        title: 'Boutons et pustules',
        prompt: 'Quel aspect décrit le mieux les boutons ?',
        icon: Icons.grain_outlined,
        requiredTags: {'branch_skin_pustules'},
        options: [
          AssessmentOption(
            id: 'comedones',
            label: 'Points noirs/blancs et boutons du visage ou du dos',
            icon: Icons.face_outlined,
            tags: {'comedones', 'acne_pattern'},
          ),
          AssessmentOption(
            id: 'hair_shaving',
            label: 'Autour des poils après rasage, sueur ou frottement',
            icon: Icons.content_cut_outlined,
            tags: {'follicular_pattern', 'friction_trigger'},
          ),
          AssessmentOption(
            id: 'deep_recurrent',
            label: 'Nodules profonds récidivants aux aisselles ou à l’aine',
            icon: Icons.replay_outlined,
            tags: {'deep_recurrent_nodules', 'skin_folds'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'honey_crust',
            label: 'Plaies avec croûte jaune couleur miel',
            icon: Icons.warning_amber_rounded,
            tags: {'honey_crust'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces aspects',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'skin_changing_lesion_detail',
        title: 'Lésion qui change',
        prompt: 'Quels changements avez-vous remarqués sur cette lésion ?',
        icon: Icons.search_outlined,
        requiredTags: {'branch_skin_changing_lesion'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'mole_change',
            label:
                'Forme asymétrique, bords irréguliers, plusieurs couleurs ou croissance',
            icon: Icons.warning_amber_rounded,
            tags: {'changing_mole_pattern'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'non_healing',
            label:
                'Plaie ou croûte qui ne guérit pas depuis plusieurs semaines',
            icon: Icons.warning_amber_rounded,
            tags: {'non_healing_skin_lesion'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'recurrent_bleeding',
            label: 'Lésion qui saigne ou s’ulcère à répétition',
            icon: Icons.warning_amber_rounded,
            tags: {'recurrent_skin_bleeding'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces changements précis',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Lésion cutanée à faire examiner',
        explanation:
            'Un grain de beauté qui change, une plaie qui ne guérit pas ou une lésion qui saigne doit être examiné sans conclure soi-même à sa cause.',
        tagWeights: {
          'changing_mole_pattern': 54,
          'non_healing_skin_lesion': 52,
          'recurrent_skin_bleeding': 50,
        },
        requiredAnyTags: {
          'changing_mole_pattern',
          'non_healing_skin_lesion',
          'recurrent_skin_bleeding',
        },
      ),
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
        requiredAnyTags: {'dry_patch', 'contact_trigger'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Urticaire',
        explanation:
            'Des plaques gonflées et mobiles qui démangent peuvent correspondre à une urticaire.',
        tagWeights: {'hives': 48, 'itch': 22, 'new_medication': 14},
        requiredAllTags: {'hives'},
        excludedTags: {'triage_emergency'},
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
        requiredAllTags: {'ring_shaped'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Acné ou folliculite',
        explanation:
            'Des boutons ou petites pustules, parfois favorisés par chaleur et frottement, peuvent venir des follicules.',
        tagWeights: {'pimples': 40, 'pustules': 32, 'heat_trigger': 16},
        requiredAnyTags: {'pimples', 'pustules'},
        excludedTags: {'triage_emergency'},
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
        requiredAllTags: {'painful_skin', 'warm_skin'},
        excludedTags: {'cellulitis_pattern', 'abscess_pattern'},
      ),
      AssessmentPossibility(
        title: 'Cellulite infectieuse possible',
        explanation:
            'Une zone rouge, chaude, douloureuse et qui s’étend, surtout avec fièvre, doit être examinée le jour même.',
        tagWeights: {
          'cellulitis_pattern': 44,
          'rapid_spread': 28,
          'warm_skin': 18,
          'fever': 20,
        },
        requiredAllTags: {'cellulitis_pattern'},
      ),
      AssessmentPossibility(
        title: 'Abcès cutané possible',
        explanation:
            'Une boule très sensible contenant du pus peut nécessiter un drainage ou un autre traitement professionnel.',
        tagWeights: {'abscess_pattern': 48, 'pus': 32, 'painful_skin': 18},
        requiredAnyTags: {'abscess_pattern', 'pus'},
      ),
      AssessmentPossibility(
        title: 'Zona possible',
        explanation:
            'Des cloques douloureuses en bande sur un seul côté peuvent correspondre à un zona; un traitement précoce peut être important.',
        tagWeights: {'dermatomal_pattern': 48, 'nerve_pain': 28, 'blister': 18},
        requiredAllTags: {'dermatomal_pattern'},
      ),
      AssessmentPossibility(
        title: 'Gale possible',
        explanation:
            'Des démangeaisons surtout nocturnes touchant aussi des proches peuvent correspondre à une infestation contagieuse.',
        tagWeights: {'night_itch': 42, 'household_spread': 40, 'itch': 20},
        requiredAllTags: {'night_itch', 'household_spread'},
      ),
      AssessmentPossibility(
        title: 'Psoriasis possible',
        explanation:
            'Des plaques épaisses et squameuses du cuir chevelu, des coudes ou des genoux peuvent évoquer un psoriasis.',
        tagWeights: {
          'thick_scale': 44,
          'extensor_distribution': 38,
          'scaly': 18,
        },
        requiredAllTags: {'thick_scale'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Herpès cutané possible',
        explanation:
            'De petites cloques groupées qui reviennent au même endroit peuvent avoir une cause virale à confirmer.',
        tagWeights: {'grouped_blisters': 46, 'recurrent': 24, 'blister': 18},
        requiredAllTags: {'grouped_blisters'},
      ),
      AssessmentPossibility(
        title: 'Hidradénite suppurée possible',
        explanation:
            'Des nodules profonds qui récidivent dans les plis, comme les aisselles ou l’aine, méritent un suivi médical.',
        tagWeights: {
          'deep_recurrent_nodules': 50,
          'skin_folds': 34,
          'recurrent': 16,
        },
        requiredAllTags: {'deep_recurrent_nodules'},
      ),
      AssessmentPossibility(
        title: 'Impétigo possible',
        explanation:
            'Des plaies superficielles avec croûtes couleur miel peuvent correspondre à une infection contagieuse.',
        tagWeights: {'honey_crust': 54, 'pustules': 16},
        requiredAllTags: {'honey_crust'},
      ),
      AssessmentPossibility(
        title: 'Brûlure grave à prendre en charge immédiatement',
        explanation:
            'Une brûlure chimique ou électrique, profonde, étendue ou touchant une zone sensible nécessite une prise en charge immédiate.',
        tagWeights: {'major_burn_pattern': 80},
        requiredAllTags: {'major_burn_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Réaction allergique grave ou obstruction respiratoire possible',
        explanation:
            'Un gonflement des lèvres, de la langue ou une difficulté à respirer est une urgence immédiate.',
        tagWeights: {'anaphylaxis': 60, 'facial_swelling': 38},
        requiredAllTags: {'anaphylaxis'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Maladie méningococcique à exclure',
        explanation:
            'Un purpura ou une éruption non blanchissante qui s’étend peut signaler une infection grave, même sans fièvre.',
        tagWeights: {'non_blanching_rash': 60},
        requiredAllTags: {'non_blanching_rash'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Réaction cutanée grave à exclure',
        explanation:
            'Une peau qui pèle largement ou des plaies des muqueuses nécessitent une prise en charge urgente.',
        tagWeights: {'widespread_peeling': 54, 'mucosal_involvement': 48},
        requiredAnyTags: {'widespread_peeling', 'mucosal_involvement'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Infection profonde de la peau à exclure',
        explanation:
            'Une douleur extrême, des zones sombres ou une progression en quelques heures peuvent correspondre à une infection profonde urgente.',
        tagWeights: {
          'skin_necrosis_pattern': 58,
          'severe_skin_pain': 44,
          'rapid_spread': 22,
        },
        requiredAnyTags: {'skin_necrosis_pattern', 'severe_skin_pain'},
        urgentReason: true,
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
    version: 4,
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
            tags: {
              'early_pregnancy',
              'context_pregnant',
              'branch_pregnancy_early',
            },
          ),
          AssessmentOption(
            id: 'late',
            label: 'De 20 à 27 semaines de grossesse',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'late_pregnancy',
              'context_pregnant',
              'branch_pregnancy_late',
            },
          ),
          AssessmentOption(
            id: 'postpartum',
            label: 'J’ai accouché dans les 6 dernières semaines',
            icon: Icons.child_friendly_outlined,
            tags: {
              'postpartum',
              'context_pregnant',
              'branch_pregnancy_postpartum',
            },
          ),
          AssessmentOption(
            id: 'postpartum_late',
            label: 'Accouchement il y a plus de 6 semaines et moins d’un an',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'postpartum',
              'postpartum_within_year',
              'context_pregnant',
              'branch_pregnancy_postpartum',
            },
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas précisément',
            icon: Icons.help_outline,
            tags: {'context_pregnant'},
          ),
          AssessmentOption(
            id: '28_to_36',
            label: 'De 28 à 36 semaines de grossesse',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'late_pregnancy',
              'context_pregnant',
              'branch_pregnancy_late',
            },
          ),
          AssessmentOption(
            id: '37_plus',
            label: '37 semaines ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'late_pregnancy',
              'term_pregnancy',
              'context_pregnant',
              'branch_pregnancy_late',
            },
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_bleeding',
        title: 'Douleur ou saignement',
        prompt: 'Avez-vous une douleur abdominale ou un saignement ?',
        icon: Icons.favorite_border_outlined,
        excludedTags: {'postpartum'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'heavy_bleeding',
            label:
                'Saignement important ou qui imbibe rapidement une protection',
            icon: Icons.emergency_outlined,
            tags: {'bleeding', 'very_heavy_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'severe_pain',
            label: 'Douleur abdominale forte ou brutale',
            icon: Icons.emergency_outlined,
            tags: {'severe_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'collapse',
            label: 'Malaise avec évanouissement ou perte de connaissance',
            icon: Icons.emergency_outlined,
            tags: {'collapse'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'light_bleeding',
            label: 'Petit saignement sans douleur forte',
            icon: Icons.warning_amber_rounded,
            tags: {'bleeding'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'mild_pain',
            label: 'Douleur légère sans saignement',
            icon: Icons.warning_amber_rounded,
            tags: {'mild_pain'},
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
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'severe',
            label: 'Fort mal de tête qui persiste ou s’aggrave',
            icon: Icons.emergency_outlined,
            tags: {'severe_headache'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'vision',
            label: 'Vision trouble, éclairs ou taches devant les yeux',
            icon: Icons.emergency_outlined,
            tags: {'vision_change'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'sudden_swelling',
            label: 'Gonflement soudain du visage ou des mains',
            icon: Icons.emergency_outlined,
            tags: {'sudden_swelling'},
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
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'sudden_breathing_chest',
            label: 'Essoufflement soudain ou douleur thoracique',
            icon: Icons.emergency_outlined,
            tags: {'pregnancy_pulmonary_embolism_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'seizure',
            label: 'Convulsion ou perte de connaissance avec secousses',
            icon: Icons.emergency_outlined,
            tags: {'eclampsia_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'lying',
            label: 'Essoufflement au repos ou en position couchée',
            icon: Icons.warning_amber_rounded,
            tags: {'breathless_at_rest'},
            urgency: AssessmentUrgency.emergency,
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
        id: 'pregnancy_leg_symptoms',
        title: 'Jambes et circulation',
        prompt: 'Avez-vous remarqué un de ces changements ?',
        icon: Icons.accessibility_new_outlined,
        options: [
          AssessmentOption(
            id: 'one_leg',
            label:
                'Une seule jambe nouvellement gonflée, chaude ou douloureuse',
            icon: Icons.warning_amber_rounded,
            tags: {'pregnancy_dvt_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'both_ankles',
            label: 'Les deux chevilles gonflent progressivement, sans douleur',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'mild_swelling'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_baby',
        title: 'Mouvements du bébé',
        prompt: 'Concernant les mouvements du bébé :',
        icon: Icons.child_care_outlined,
        requiredTags: {'branch_pregnancy_late'},
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
            label: 'Je ne les sens pas encore de façon habituelle',
            icon: Icons.schedule_outlined,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_sickness',
        title: 'Fièvre et vomissements',
        prompt: 'Quelle situation correspond le mieux ?',
        icon: Icons.thermostat_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'cannot_drink',
            label: 'Je vomis chaque fois que je bois',
            icon: Icons.warning_amber_rounded,
            tags: {'cannot_hydrate', 'dehydration_risk'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever',
            label: 'Température mesurée à 38 °C ou plus',
            icon: Icons.warning_amber_rounded,
            tags: {'temperature_38', 'fever'},
            urgency: AssessmentUrgency.emergency,
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
          AssessmentOption(
            id: 'chills',
            label: 'Frissons, sans température mesurée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'chills'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'low_urine',
            label: 'J’urine beaucoup moins que d’habitude',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'low_urine'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_urinary',
        title: 'Urines',
        prompt: 'Avez-vous un de ces symptômes urinaires ?',
        icon: Icons.water_drop_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'burning',
            label: 'Brûlure ou douleur en urinant',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'urinary_burning'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'blood',
            label: 'Sang visible dans les urines',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'blood_in_urine'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'fever_back',
            label: 'Fièvre avec douleur d’un côté du dos',
            icon: Icons.warning_amber_rounded,
            tags: {'fever', 'flank_pain', 'kidney_infection_pattern'},
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
        id: 'pregnancy_early_detail',
        title: 'Début de grossesse',
        prompt: 'Quel signe concerne le début de grossesse ?',
        icon: Icons.pregnant_woman_outlined,
        requiredTags: {'branch_pregnancy_early'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'one_side',
            label: 'Douleur du bas-ventre surtout d’un seul côté',
            icon: Icons.warning_amber_rounded,
            tags: {'one_sided_pelvic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'shoulder',
            label: 'Douleur au bout de l’épaule avec douleur abdominale',
            icon: Icons.emergency_outlined,
            tags: {'shoulder_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'faint',
            label: 'Étourdissement marqué, faiblesse ou évanouissement',
            icon: Icons.emergency_outlined,
            tags: {'hemodynamic_instability_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'severe_vomiting',
            label: 'Vomissements persistants, je ne garde pas les liquides',
            icon: Icons.warning_amber_rounded,
            tags: {'cannot_hydrate', 'dehydration_risk', 'severe_vomiting'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'mild_cramps',
            label: 'Nausée ou crampes légères sans saignement',
            icon: Icons.check_circle_outline,
            tags: {'nausea', 'mild_pain'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'pregnancy_late_detail',
        title: 'Deuxième moitié de grossesse',
        prompt: 'Avez-vous remarqué l’un de ces signes ?',
        icon: Icons.child_care_outlined,
        requiredTags: {'branch_pregnancy_late'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'fluid_leak',
            label: 'Perte de liquide pouvant venir de la poche des eaux',
            icon: Icons.warning_amber_rounded,
            tags: {'fluid_leak'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'regular_contractions',
            label: 'Contractions régulières avant le terme',
            icon: Icons.warning_amber_rounded,
            tags: {'regular_contractions'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'upper_right',
            label: 'Douleur forte sous les côtes à droite ou à l’épaule',
            icon: Icons.emergency_outlined,
            tags: {'preeclampsia_upper_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'itch_palms',
            label:
                'Démangeaisons intenses des paumes ou plantes, surtout la nuit',
            icon: Icons.back_hand_outlined,
            tags: {'palms_soles_itch', 'night_itch'},
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
        id: 'pregnancy_postpartum_detail',
        title: 'Après l’accouchement',
        prompt: 'Quel signe est apparu depuis l’accouchement ?',
        icon: Icons.child_friendly_outlined,
        requiredTags: {'branch_pregnancy_postpartum'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'heavy_bleeding',
            label:
                'Saignement très abondant, gros caillots, faiblesse ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'postpartum_heavy_bleeding', 'very_heavy_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'fever_discharge',
            label: 'Fièvre, frissons, douleur du ventre ou pertes malodorantes',
            icon: Icons.warning_amber_rounded,
            tags: {'postpartum_infection_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'leg',
            label: 'Une jambe gonflée, rouge ou douloureuse d’un seul côté',
            icon: Icons.emergency_outlined,
            tags: {'pregnancy_dvt_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'chest_breathing',
            label:
                'Essoufflement soudain, douleur thoracique ou évanouissement',
            icon: Icons.emergency_outlined,
            tags: {'pregnancy_pulmonary_embolism_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'mental_health',
            label:
                'Confusion ou pensées de me faire du mal ou de faire mal au bébé',
            icon: Icons.emergency_outlined,
            tags: {'mental_health_emergency'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes urgents',
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
        excludedTags: {
          'postpartum',
          'severe_headache',
          'vision_change',
          'sudden_swelling',
          'severe_breathlessness',
          'very_heavy_bleeding',
          'collapse',
          'triage_emergency',
        },
        requiredAnyTags: {'nausea', 'mild_breathlessness', 'mild_swelling'},
      ),
      AssessmentPossibility(
        title: 'Pré-éclampsie possible',
        explanation:
            'Un fort mal de tête avec trouble visuel ou gonflement soudain pendant ou après la grossesse est un signe d’alerte.',
        tagWeights: {
          'severe_headache': 34,
          'vision_change': 30,
          'sudden_swelling': 28,
          'preeclampsia_upper_pain': 34,
          'eclampsia_pattern': 60,
          'late_pregnancy': 10,
          'postpartum': 8,
        },
        requiredAnyTags: {'late_pregnancy', 'postpartum'},
        minimumMatchedEvidence: 2,
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Complication du début de grossesse possible',
        explanation:
            'Une douleur et un saignement en début de grossesse nécessitent une évaluation urgente.',
        tagWeights: {
          'early_pregnancy': 8,
          'bleeding': 34,
          'severe_pain': 28,
          'collapse': 22,
          'hemodynamic_instability_pattern': 34,
        },
        requiredAllTags: {'early_pregnancy'},
        requiredAnyTags: {
          'bleeding',
          'severe_pain',
          'collapse',
          'hemodynamic_instability_pattern',
        },
        minimumMatchedEvidence: 2,
        urgentReason: true,
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
        requiredAnyTags: {'cannot_hydrate', 'dehydration_risk'},
      ),
      AssessmentPossibility(
        title: 'Infection possible',
        explanation:
            'Une fièvre pendant la grossesse ou après l’accouchement doit être évaluée rapidement.',
        tagWeights: {'fever': 48, 'systemically_unwell': 20},
      ),
      AssessmentPossibility(
        title: 'Grossesse extra-utérine possible',
        explanation:
            'Au début de la grossesse, une douleur d’un côté avec saignement, douleur d’épaule ou étourdissement est une urgence à exclure.',
        tagWeights: {
          'early_pregnancy': 8,
          'one_sided_pelvic_pain': 36,
          'shoulder_pain': 24,
          'bleeding': 24,
          'dizziness': 20,
          'hemodynamic_instability_pattern': 38,
        },
        requiredAllTags: {'early_pregnancy'},
        requiredAnyTags: {
          'one_sided_pelvic_pain',
          'shoulder_pain',
          'bleeding',
          'dizziness',
          'collapse',
          'hemodynamic_instability_pattern',
        },
        minimumMatchedEvidence: 2,
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Hyperémèse ou déshydratation sévère possible',
        explanation:
            'Des vomissements persistants empêchant de boire nécessitent une évaluation et parfois une réhydratation.',
        tagWeights: {
          'severe_vomiting': 42,
          'cannot_hydrate': 34,
          'dehydration_risk': 24,
          'early_pregnancy': 10,
        },
        requiredAllTags: {'severe_vomiting'},
      ),
      AssessmentPossibility(
        title: 'Travail prématuré ou rupture de la poche des eaux possible',
        explanation:
            'Une perte de liquide ou des contractions régulières avant le terme doivent être évaluées immédiatement par la maternité.',
        tagWeights: {
          'fluid_leak': 44,
          'regular_contractions': 40,
          'late_pregnancy': 6,
        },
        requiredAllTags: {'late_pregnancy'},
        requiredAnyTags: {'fluid_leak', 'regular_contractions'},
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Bien-être du bébé à contrôler immédiatement',
        explanation:
            'Une diminution nette ou une absence des mouvements habituels doit être contrôlée sans attendre par la maternité.',
        tagWeights: {'reduced_fetal_movement': 60, 'late_pregnancy': 12},
        requiredAllTags: {'late_pregnancy', 'reduced_fetal_movement'},
      ),
      AssessmentPossibility(
        title: 'Cholestase gravidique possible',
        explanation:
            'Des démangeaisons intenses des paumes ou plantes pendant la grossesse nécessitent un bilan rapide.',
        tagWeights: {
          'palms_soles_itch': 52,
          'night_itch': 24,
          'late_pregnancy': 14,
        },
        requiredAllTags: {'late_pregnancy', 'palms_soles_itch'},
      ),
      AssessmentPossibility(
        title: 'Hémorragie après l’accouchement possible',
        explanation:
            'Un saignement très abondant avec caillots, faiblesse ou étourdissement après l’accouchement est une urgence.',
        tagWeights: {
          'postpartum_heavy_bleeding': 52,
          'very_heavy_bleeding': 32,
          'dizziness': 20,
          'postpartum': 14,
        },
        requiredAllTags: {'postpartum', 'postpartum_heavy_bleeding'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Infection du post-partum possible',
        explanation:
            'Fièvre, frissons, douleur abdominale ou pertes malodorantes après l’accouchement doivent être évalués le jour même.',
        tagWeights: {
          'postpartum_infection_pattern': 46,
          'foul_discharge': 28,
          'fever': 24,
          'postpartum': 14,
        },
        requiredAllTags: {'postpartum', 'postpartum_infection_pattern'},
      ),
      AssessmentPossibility(
        title: 'Caillot sanguin ou embolie possible',
        explanation:
            'Une jambe gonflée d’un seul côté ou un essoufflement soudain pendant ou après la grossesse est une urgence.',
        tagWeights: {
          'context_pregnant': 8,
          'one_sided_leg_swelling': 40,
          'leg_pain': 22,
          'severe_breathlessness': 34,
          'postpartum': 14,
          'pregnancy_dvt_pattern': 54,
          'pregnancy_pulmonary_embolism_pattern': 64,
        },
        requiredAllTags: {'context_pregnant'},
        requiredAnyTags: {
          'one_sided_leg_swelling',
          'severe_breathlessness',
          'chest_pain',
          'pregnancy_dvt_pattern',
          'pregnancy_pulmonary_embolism_pattern',
        },
        minimumMatchedEvidence: 2,
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Urgence de santé mentale périnatale',
        explanation:
            'Confusion ou pensées de se faire du mal ou de faire du mal au bébé nécessitent une aide urgente et une présence de confiance immédiate.',
        tagWeights: {
          'mental_health_emergency': 60,
          'confusion': 24,
          'postpartum': 12,
        },
        requiredAllTags: {'mental_health_emergency'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Signe maternel urgent dans l’année après l’accouchement',
        explanation:
            'Un symptôme grave peut rester lié à la période post-partum jusqu’à un an et nécessite une évaluation urgente.',
        tagWeights: {
          'postpartum_within_year': 12,
          'severe_headache': 38,
          'vision_change': 34,
          'pregnancy_pulmonary_embolism_pattern': 52,
          'pregnancy_dvt_pattern': 44,
          'mental_health_emergency': 52,
          'postpartum_heavy_bleeding': 44,
          'postpartum_infection_pattern': 36,
        },
        requiredAllTags: {'postpartum_within_year'},
        requiredAnyTags: {
          'severe_headache',
          'vision_change',
          'pregnancy_pulmonary_embolism_pattern',
          'pregnancy_dvt_pattern',
          'mental_health_emergency',
          'postpartum_heavy_bleeding',
          'postpartum_infection_pattern',
        },
        minimumMatchedEvidence: 2,
        urgentReason: true,
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
  AssessmentPathway(
    id: 'chest',
    version: 4,
    title: 'Poitrine et palpitations',
    subtitle: 'Douleur, oppression, battements rapides ou irréguliers',
    icon: Icons.favorite_border_outlined,
    color: Color(0xFFD84A5F),
    questions: [
      AssessmentQuestion(
        id: 'chest_now',
        title: 'État actuel',
        prompt: 'Que ressentez-vous maintenant ?',
        icon: Icons.favorite_border_outlined,
        options: [
          AssessmentOption(
            id: 'pressure_radiating',
            label:
                'Poitrine serrée/lourde, douleur vers bras, dos, cou ou mâchoire',
            icon: Icons.emergency_outlined,
            tags: {'chest_pressure', 'radiating_chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'pressure_persistent',
            label:
                'Oppression ou poids nouveau dans la poitrine qui ne disparaît pas',
            icon: Icons.warning_amber_rounded,
            tags: {'chest_pressure', 'persistent_chest_pressure'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'severe_breathing',
            label: 'Douleur avec grande difficulté à respirer',
            icon: Icons.warning_amber_rounded,
            tags: {'chest_pain', 'severe_breathlessness'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'faint_palpitations',
            label: 'Palpitations persistantes avec impression de m’évanouir',
            icon: Icons.warning_amber_rounded,
            tags: {'palpitations', 'presyncope', 'branch_chest_palpitations'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'stable',
            label: 'Gêne légère ou intermittente, je respire normalement',
            icon: Icons.check_circle_outline,
            tags: {'stable_chest_symptom'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_radiation',
        title: 'Extension de la douleur',
        prompt: 'La douleur de la poitrine s’étend-elle ailleurs ?',
        icon: Icons.open_in_full_outlined,
        options: [
          AssessmentOption(
            id: 'arm',
            label: 'Vers un bras ou les deux bras',
            icon: Icons.warning_amber_rounded,
            tags: {'radiating_chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'jaw',
            label: 'Vers la mâchoire ou le cou',
            icon: Icons.warning_amber_rounded,
            tags: {'radiating_chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'back',
            label: 'Vers le dos',
            icon: Icons.warning_amber_rounded,
            tags: {'radiating_chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'abdomen',
            label: 'Vers le haut du ventre',
            icon: Icons.warning_amber_rounded,
            tags: {'radiating_chest_pain'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Non, elle reste dans la poitrine',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'no_pain',
            label:
                'Je n’ai pas de douleur, seulement des battements inhabituels',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_character',
        title: 'Type de gêne',
        prompt: 'Quelle description correspond le mieux ?',
        icon: Icons.monitor_heart_outlined,
        options: [
          AssessmentOption(
            id: 'burning',
            label: 'Brûlure après les repas ou en position couchée',
            icon: Icons.local_fire_department_outlined,
            tags: {'heartburn', 'after_meal', 'branch_chest_digestive'},
          ),
          AssessmentOption(
            id: 'movement',
            label: 'Douleur reproduite en bougeant ou en appuyant',
            icon: Icons.accessibility_new_outlined,
            tags: {'chest_wall_pain', 'movement_related'},
          ),
          AssessmentOption(
            id: 'breathing',
            label:
                'Douleur vive aggravée par une grande inspiration ou la toux',
            icon: Icons.air_outlined,
            tags: {'pleuritic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'palpitations',
            label: 'Cœur très rapide, irrégulier ou battements sautés',
            icon: Icons.monitor_heart_outlined,
            tags: {'palpitations', 'branch_chest_palpitations'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Difficile à décrire',
            icon: Icons.help_outline,
            tags: {'nonspecific_chest_pain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_timing',
        title: 'Début et durée',
        prompt: 'Quand la gêne apparaît-elle ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'effort',
            label: 'Pendant un effort et elle s’améliore au repos',
            icon: Icons.directions_run_outlined,
            tags: {'exertional_chest_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'rest_minutes',
            label:
                'Au repos, pendant plusieurs minutes ou elle revient aujourd’hui',
            icon: Icons.warning_amber_rounded,
            tags: {'chest_pain_at_rest', 'recurrent_today'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'seconds',
            label: 'Quelques secondes, de façon occasionnelle',
            icon: Icons.timer_outlined,
            tags: {'brief_episodes'},
          ),
          AssessmentOption(
            id: 'persistent',
            label: 'Continue depuis plusieurs heures ou s’aggrave',
            icon: Icons.trending_up_outlined,
            tags: {'persistent', 'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_duration',
        title: 'Durée de la gêne',
        prompt: 'Combien de temps dure chaque épisode ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'seconds',
            label: 'Quelques secondes',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'brief_episodes'},
          ),
          AssessmentOption(
            id: 'minutes',
            label: 'Plusieurs minutes, puis la gêne disparaît',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'chest_minutes'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'ongoing',
            label:
                'Une douleur nouvelle dans la poitrine est toujours présente',
            icon: Icons.warning_amber_rounded,
            tags: {'persistent_chest_pressure'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'repeated',
            label: 'Les épisodes se rapprochent ou deviennent plus forts',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'worsening_chest_episodes'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'no_pain',
            label: 'Je n’ai pas de douleur dans la poitrine',
            icon: Icons.radio_button_unchecked_rounded,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_associated',
        title: 'Signes associés',
        prompt: 'Quels signes accompagnent la gêne thoracique ?',
        icon: Icons.warning_amber_rounded,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'sweat_nausea',
            label: 'Sueurs froides inhabituelles',
            icon: Icons.warning_amber_rounded,
            tags: {'sweating', 'acute_coronary_autonomic'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'nausea',
            label: 'Nausée inhabituelle avec la gêne thoracique',
            icon: Icons.warning_amber_rounded,
            tags: {'nausea'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'fever_cough',
            label: 'Fièvre, toux ou crachats',
            icon: Icons.thermostat_outlined,
            tags: {'respiratory_infection_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'aortic',
            label:
                'Douleur maximale d’emblée vers le dos avec malaise ou signe neurologique',
            icon: Icons.emergency_outlined,
            tags: {'acute_aortic_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'anxiety',
            label: 'Stress intense, respiration rapide ou fourmillements',
            icon: Icons.psychology_outlined,
            tags: {'anxiety_pattern', 'hyperventilation'},
          ),
          AssessmentOption(
            id: 'rash',
            label: 'Picotements puis boutons ou cloques d’un seul côté',
            icon: Icons.texture_outlined,
            tags: {'dermatomal_pattern', 'blister'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'sudden_weakness',
            label: 'Faiblesse soudaine avec la gêne thoracique',
            icon: Icons.warning_amber_rounded,
            tags: {'sudden_weakness', 'acute_coronary_autonomic'},
            urgency: AssessmentUrgency.emergency,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_context',
        title: 'Contexte important',
        prompt: 'Quelle situation vous concerne ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'heart_history',
            label:
                'Maladie du cœur, hypertension, diabète ou antécédent similaire',
            icon: Icons.medical_information_outlined,
            tags: {'cardiovascular_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'clot_risk',
            label: 'Immobilisation, chirurgie, cancer ou post-partum récent',
            icon: Icons.warning_amber_rounded,
            tags: {'clot_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'leg_swelling',
            label: 'Une jambe est gonflée ou douloureuse d’un seul côté',
            icon: Icons.warning_amber_rounded,
            tags: {'clot_risk', 'one_sided_leg_swelling'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'injury',
            label:
                'Après un choc, un effort musculaire ou avoir beaucoup toussé',
            icon: Icons.healing_outlined,
            tags: {'chest_injury', 'muscle_strain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_palpitations_detail',
        title: 'Palpitations',
        prompt: 'Comment évoluent les battements inhabituels ?',
        icon: Icons.monitor_heart_outlined,
        requiredTags: {'branch_chest_palpitations'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'persistent_symptoms',
            label: 'Ne s’arrêtent pas avec douleur, essoufflement ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'persistent_palpitations', 'chest_pain', 'dizziness'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'exercise',
            label: 'Surviennent pendant l’effort ou réveillent la nuit',
            icon: Icons.warning_amber_rounded,
            tags: {'exertional_palpitations', 'night_waking'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'stimulants',
            label: 'Après café, boisson énergisante, tabac ou décongestionnant',
            icon: Icons.local_cafe_outlined,
            tags: {'stimulant_trigger'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'stress',
            label: 'Brèves et liées au stress, sans autre signe',
            icon: Icons.self_improvement_outlined,
            tags: {'stress', 'brief_episodes'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'chest_digestive_detail',
        title: 'Brûlure thoracique',
        prompt: 'Qu’est-ce qui accompagne la brûlure ?',
        icon: Icons.sick_outlined,
        requiredTags: {'branch_chest_digestive'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'acid',
            label: 'Remontées acides ou goût amer après le repas',
            icon: Icons.restaurant_outlined,
            tags: {'acid_reflux', 'after_meal'},
          ),
          AssessmentOption(
            id: 'swallowing',
            label: 'Difficulté ou douleur pour avaler',
            icon: Icons.warning_amber_rounded,
            tags: {'difficulty_swallowing'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'not_food',
            label: 'Pas de lien clair avec les repas',
            icon: Icons.help_outline,
            tags: {'non_food_related'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Problème cardiaque aigu possible',
        explanation:
            'Une pression thoracique irradiant vers le bras, le dos, le cou ou la mâchoire, surtout avec sueurs ou nausée, est une urgence.',
        tagWeights: {
          'chest_pressure': 36,
          'radiating_chest_pain': 34,
          'persistent_chest_pressure': 40,
          'acute_coronary_autonomic': 36,
          'sweating': 22,
          'nausea': 14,
          'cardiovascular_risk': 14,
          'exertional_chest_pain': 18,
          'chest_pain_at_rest': 20,
          'acute_coronary_suspicion': 52,
        },
        requiredAnyTags: {
          'chest_pressure',
          'radiating_chest_pain',
          'persistent_chest_pressure',
          'acute_coronary_autonomic',
          'acute_coronary_suspicion',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Trouble du rythme cardiaque possible',
        explanation:
            'Des battements rapides ou irréguliers persistants, surtout avec malaise ou essoufflement, nécessitent un contrôle du rythme.',
        tagWeights: {
          'palpitations': 30,
          'persistent_palpitations': 36,
          'collapse': 24,
          'exertional_palpitations': 20,
        },
        requiredAllTags: {'palpitations'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Embolie pulmonaire possible',
        explanation:
            'Une douleur respiratoire avec essoufflement, immobilisation récente ou jambe gonflée est une urgence à exclure.',
        tagWeights: {
          'pleuritic_pain': 22,
          'severe_breathlessness': 32,
          'clot_risk': 34,
          'one_sided_leg_swelling': 30,
          'pulmonary_embolism_pattern': 60,
        },
        requiredAllTags: {'pulmonary_embolism_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Reflux gastro-œsophagien possible',
        explanation:
            'Une brûlure après les repas ou en position couchée avec remontées acides peut venir d’un reflux.',
        tagWeights: {'heartburn': 34, 'acid_reflux': 34, 'after_meal': 18},
        requiredAllTags: {'heartburn', 'acid_reflux'},
        excludedTags: {
          'chest_pressure',
          'persistent_chest_pressure',
          'acute_coronary_autonomic',
          'pulmonary_embolism_pattern',
          'acute_aortic_pattern',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Douleur de la paroi thoracique',
        explanation:
            'Une douleur reproduite par le mouvement ou la pression peut venir des muscles, des côtes ou des articulations.',
        tagWeights: {
          'chest_wall_pain': 42,
          'movement_related': 30,
          'muscle_strain': 20,
          'chest_injury': 16,
        },
        requiredAllTags: {'chest_wall_pain', 'movement_related'},
        excludedTags: {
          'chest_pressure',
          'pulmonary_embolism_pattern',
          'acute_aortic_pattern',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Pleurésie ou infection thoracique possible',
        explanation:
            'Une douleur augmentée par la respiration avec toux ou fièvre nécessite un examen des poumons.',
        tagWeights: {
          'pleuritic_pain': 32,
          'respiratory_infection_pattern': 30,
          'fever': 20,
          'cough': 18,
        },
      ),
      AssessmentPossibility(
        title: 'Réaction au stress ou hyperventilation possible',
        explanation:
            'Stress, respiration rapide et fourmillements peuvent provoquer une gêne réelle, après exclusion des signes médicaux urgents.',
        tagWeights: {
          'anxiety_pattern': 38,
          'hyperventilation': 34,
          'stress': 18,
          'brief_episodes': 12,
        },
        requiredAllTags: {'anxiety_pattern', 'hyperventilation'},
        excludedTags: {
          'chest_pressure',
          'persistent_chest_pressure',
          'pulmonary_embolism_pattern',
          'acute_aortic_pattern',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Zona thoracique possible',
        explanation:
            'Des picotements suivis de cloques douloureuses en bande d’un seul côté peuvent correspondre à un zona.',
        tagWeights: {'dermatomal_pattern': 46, 'blister': 30},
        requiredAllTags: {'dermatomal_pattern', 'blister'},
      ),
      AssessmentPossibility(
        title: 'Syndrome aortique aigu à exclure',
        explanation:
            'Une douleur thoracique brutale maximale d’emblée vers le dos avec malaise ou signe neurologique est une urgence.',
        tagWeights: {'acute_aortic_pattern': 60},
        requiredAllTags: {'acute_aortic_pattern'},
        urgentReason: true,
      ),
    ],
    selfCare: [
      'Évitez l’effort jusqu’à clarification si la douleur est nouvelle ou revient.',
      'Notez la durée, les déclencheurs et le rythme des palpitations.',
    ],
    pharmacyAdvice: [
      'Ne prenez pas un médicament cardiaque appartenant à une autre personne.',
      'Demandez conseil avant un antiacide si vous prenez déjà plusieurs traitements.',
    ],
  ),
  AssessmentPathway(
    id: 'urinary',
    version: 4,
    title: 'Troubles urinaires',
    subtitle: 'Brûlure, envies fréquentes, sang, fuite ou difficulté à uriner',
    icon: Icons.local_drink_outlined,
    color: Color(0xFF2878C7),
    questions: [
      AssessmentQuestion(
        id: 'urinary_age',
        title: 'Âge',
        prompt: 'Quel âge a la personne concernée ?',
        icon: Icons.cake_outlined,
        options: [
          AssessmentOption(
            id: 'under_3_months',
            label: 'Moins de 3 mois',
            icon: Icons.child_care_outlined,
            tags: {'person_under_3_months'},
          ),
          AssessmentOption(
            id: 'under_16',
            label: 'De 3 mois à moins de 16 ans',
            icon: Icons.escalator_warning_outlined,
            tags: {'person_under_16'},
          ),
          AssessmentOption(
            id: 'adult',
            label: 'De 16 à 64 ans',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          AssessmentOption(
            id: '65_plus',
            label: '65 ans ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'older_adult'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_main',
        title: 'Malaise principal',
        prompt: 'Quel trouble urinaire vous gêne le plus ?',
        icon: Icons.local_drink_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'burning',
            label: 'Brûlure ou douleur en urinant',
            icon: Icons.local_fire_department_outlined,
            tags: {'urinary_burning', 'branch_urinary_irritation'},
          ),
          AssessmentOption(
            id: 'frequency',
            label: 'Besoin urgent ou très fréquent d’uriner',
            icon: Icons.schedule_outlined,
            tags: {'urinary_frequency', 'branch_urinary_pattern'},
          ),
          AssessmentOption(
            id: 'blood',
            label: 'Urine rose, rouge ou brune',
            icon: Icons.warning_amber_rounded,
            tags: {'blood_in_urine'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'difficulty',
            label: 'Jet faible, difficulté à commencer ou vessie non vidée',
            icon: Icons.warning_amber_rounded,
            tags: {'voiding_difficulty', 'branch_urinary_voiding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'leak',
            label: 'Fuites involontaires',
            icon: Icons.water_drop_outlined,
            tags: {'urinary_leakage', 'branch_urinary_pattern'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_red_flags',
        title: 'Signes d’alerte',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.warning_amber_rounded,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'fever_flank',
            label: 'Fièvre ou frissons avec douleur du côté ou du dos',
            icon: Icons.thermostat_outlined,
            tags: {'fever', 'flank_pain', 'kidney_infection_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'confused_weak',
            label:
                'Confusion, grande faiblesse, respiration rapide ou peau moite',
            icon: Icons.emergency_outlined,
            tags: {'confusion', 'severe_weakness', 'sepsis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'cannot_urinate',
            label: 'Impossible d’uriner avec douleur ou bas-ventre gonflé',
            icon: Icons.emergency_outlined,
            tags: {'urinary_retention', 'lower_abdomen'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'anuria',
            label:
                'Presque aucune urine depuis de nombreuses heures, avec gonflement, essoufflement ou malaise',
            icon: Icons.emergency_outlined,
            tags: {'acute_kidney_injury_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'saddle_weakness',
            label:
                'Nouvel engourdissement entre les jambes, faiblesse des jambes ou perte de contrôle urinaire/fécal',
            icon: Icons.emergency_outlined,
            tags: {'cauda_equina_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'fever_only',
            label: 'Fièvre mesurée, sans douleur du dos',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'chills',
            label: 'Frissons marqués, sans température mesurée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'chills'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_pattern',
        title: 'Aspect et quantité',
        prompt: 'Comment vos urines ou vos habitudes ont-elles changé ?',
        icon: Icons.water_drop_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'small_frequent',
            label: 'Petites quantités à chaque fois',
            icon: Icons.info_outline,
            tags: {'small_frequent_voids'},
          ),
          AssessmentOption(
            id: 'cloudy',
            label: 'Urine trouble',
            icon: Icons.info_outline,
            tags: {'cloudy_urine'},
          ),
          AssessmentOption(
            id: 'odor',
            label: 'Odeur nettement plus forte ou inhabituelle',
            icon: Icons.info_outline,
            tags: {'urine_odor'},
          ),
          AssessmentOption(
            id: 'large_thirst',
            label: 'Grandes quantités avec soif inhabituelle',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {
              'large_urine_volume',
              'excessive_thirst',
              'branch_urinary_thirst',
            },
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'colicky',
            label: 'Douleur par vagues du côté vers l’aine avec nausée',
            icon: Icons.waves_outlined,
            tags: {'colicky_flank_pain', 'radiates_groin', 'nausea'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'cough_leak',
            label: 'Fuite en toussant, riant, portant ou faisant un effort',
            icon: Icons.directions_run_outlined,
            tags: {'stress_incontinence_pattern'},
          ),
          AssessmentOption(
            id: 'night_urge',
            label: 'Envies soudaines, parfois la nuit, sans brûlure',
            icon: Icons.bedtime_outlined,
            tags: {'urge_incontinence_pattern', 'night_urination'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces changements',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_duration',
        title: 'Durée',
        prompt: 'Depuis quand le problème existe-t-il ?',
        icon: Icons.calendar_month_outlined,
        options: [
          AssessmentOption(
            id: 'today',
            label: 'Depuis aujourd’hui',
            icon: Icons.today_outlined,
            tags: {'acute'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis quelques jours',
            icon: Icons.date_range_outlined,
            tags: {'days'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'recurrent',
            label: 'Cela revient régulièrement',
            icon: Icons.replay_outlined,
            tags: {'recurrent'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'weeks',
            label: 'Depuis plusieurs semaines ou aggravation',
            icon: Icons.trending_up_outlined,
            tags: {'persistent', 'worsening'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_treatment_response',
        title: 'Traitement et évolution',
        prompt: 'Avez-vous déjà commencé un traitement pour cet épisode ?',
        icon: Icons.medication_outlined,
        options: [
          AssessmentOption(
            id: 'none',
            label: 'Non',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'under_48h',
            label: 'Oui, depuis moins de 48 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'treatment_started'},
          ),
          AssessmentOption(
            id: 'improving',
            label: 'Oui, les symptômes diminuent',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'treatment_improving'},
          ),
          AssessmentOption(
            id: 'not_improving',
            label: 'Oui, depuis au moins 48 heures, sans amélioration',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'urinary_treatment_failure'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'worse',
            label: 'Oui, mais les symptômes s’aggravent',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'urinary_treatment_failure', 'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_context',
        title: 'Contexte',
        prompt: 'Quelle situation vous concerne ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'pregnancy',
            label: 'Grossesse possible ou confirmée',
            icon: Icons.pregnant_woman_outlined,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'male',
            label: 'Homme ou garçon',
            icon: Icons.person_outline,
            tags: {'male_urinary_context'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'prostate',
            label: 'Prostate connue, jet faible ou levers nocturnes répétés',
            icon: Icons.accessibility_new_outlined,
            tags: {'prostate_pattern', 'branch_urinary_voiding'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'catheter',
            label: 'Sonde urinaire, intervention récente ou maladie rénale',
            icon: Icons.medical_information_outlined,
            tags: {'complicated_urinary_context'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'stone_obstruction',
            label: 'Calcul urinaire déjà diagnostiqué',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'known_urinary_stone'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'obstruction',
            label: 'Obstacle urinaire déjà diagnostiqué',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'known_urinary_obstruction'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'diabetes',
            label: 'Diabète connu',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'diabetes_context', 'complicated_urinary_context'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'immunity',
            label: 'Immunité diminuée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'immunocompromised', 'complicated_urinary_context'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_irritation_detail',
        title: 'Irritation associée',
        prompt: 'Quels signes ou situations accompagnent la brûlure urinaire ?',
        icon: Icons.info_outline,
        requiredTags: {'branch_urinary_irritation'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'frequency',
            label: 'Envies fréquentes avec petites quantités',
            icon: Icons.schedule_outlined,
            tags: {'urinary_frequency', 'small_frequent_voids'},
          ),
          AssessmentOption(
            id: 'discharge',
            label: 'Écoulement inhabituel par les organes génitaux',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'genital_discharge'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'external_itch',
            label: 'Irritation ou démangeaison surtout externe',
            icon: Icons.back_hand_outlined,
            tags: {'external_irritation', 'itch'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun autre signe',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'sexual_exposure',
            label: 'Rapport sans préservatif ou nouveau partenaire récent',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'sexual_exposure'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'sores',
            label: 'Plaies ou cloques génitales',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'genital_sores'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_voiding_detail',
        title: 'Difficulté à uriner',
        prompt: 'Quelle description correspond le mieux ?',
        icon: Icons.warning_amber_rounded,
        requiredTags: {'branch_urinary_voiding'},
        options: [
          AssessmentOption(
            id: 'complete_block',
            label: 'Plus aucune urine malgré une envie douloureuse',
            icon: Icons.emergency_outlined,
            tags: {'urinary_retention'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'weak_night',
            label: 'Jet faible, gouttes et plusieurs levers la nuit',
            icon: Icons.bedtime_outlined,
            tags: {'weak_stream', 'night_urination', 'prostate_pattern'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'medicine',
            label: 'Début après un nouveau médicament',
            icon: Icons.medication_outlined,
            tags: {'new_medication'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces descriptions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_volume',
        title: 'Quantité d’urine',
        prompt:
            'Quand vous urinez souvent, quelle quantité sort à chaque fois ?',
        icon: Icons.water_drop_outlined,
        requiredTags: {'urinary_frequency'},
        options: [
          AssessmentOption(
            id: 'small',
            label: 'Quelques gouttes ou de petites quantités',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'small_frequent_voids'},
          ),
          AssessmentOption(
            id: 'normal',
            label: 'Une quantité habituelle',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          AssessmentOption(
            id: 'large',
            label: 'De grandes quantités à répétition',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'large_urine_volume', 'branch_urinary_thirst'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'urinary_thirst',
        title: 'Soif et état général',
        prompt: 'Quels signes accompagnent ces urines abondantes ?',
        icon: Icons.local_drink_outlined,
        requiredTags: {'branch_urinary_thirst'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'thirst',
            label: 'Soif nettement plus forte que d’habitude',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'excessive_thirst'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'weight_loss',
            label: 'Perte de poids involontaire',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'weight_loss'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'vomiting',
            label: 'Vomissements',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'vomiting'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'deep_breathing',
            label: 'Respiration inhabituellement profonde et rapide',
            icon: Icons.warning_amber_rounded,
            tags: {'deep_breathing'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'confusion',
            label: 'Somnolence inhabituelle ou confusion',
            icon: Icons.warning_amber_rounded,
            tags: {'confusion'},
            urgency: AssessmentUrgency.emergency,
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
        title: 'Infection urinaire basse possible',
        explanation:
            'Brûlure, envies fréquentes et petites quantités d’urine trouble ou odorante sont compatibles avec une infection urinaire.',
        tagWeights: {
          'urinary_burning': 34,
          'urinary_frequency': 28,
          'small_frequent_voids': 22,
          'cloudy_urine': 18,
          'urine_odor': 14,
        },
        requiredAnyTags: {
          'urinary_burning',
          'small_frequent_voids',
          'cloudy_urine',
        },
      ),
      AssessmentPossibility(
        title: 'Infection rénale possible',
        explanation:
            'Fièvre ou frissons avec douleur du côté ou du dos peuvent indiquer une infection remontée vers le rein.',
        tagWeights: {
          'kidney_infection_pattern': 44,
          'fever': 24,
          'flank_pain': 28,
          'complicated_urinary_context': 14,
        },
        requiredAllTags: {'kidney_infection_pattern'},
      ),
      AssessmentPossibility(
        title: 'Calcul urinaire possible',
        explanation:
            'Une douleur par vagues du côté vers l’aine, avec nausée ou sang dans les urines, peut venir d’un calcul.',
        tagWeights: {
          'colicky_flank_pain': 42,
          'radiates_groin': 34,
          'blood_in_urine': 22,
          'nausea': 14,
        },
        requiredAllTags: {'colicky_flank_pain'},
      ),
      AssessmentPossibility(
        title: 'Rétention ou obstacle urinaire possible',
        explanation:
            'Une vessie douloureuse qui ne se vide plus est une urgence; un jet faible persistant mérite aussi un bilan.',
        tagWeights: {
          'urinary_retention': 52,
          'voiding_difficulty': 26,
          'weak_stream': 24,
          'prostate_pattern': 22,
        },
        requiredAnyTags: {'urinary_retention', 'voiding_difficulty'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Vessie hyperactive possible',
        explanation:
            'Des envies soudaines et fréquentes, parfois avec fuite et sans brûlure, peuvent correspondre à une vessie hyperactive.',
        tagWeights: {
          'urge_incontinence_pattern': 44,
          'urinary_frequency': 22,
          'night_urination': 18,
          'urinary_leakage': 16,
        },
        requiredAllTags: {'urge_incontinence_pattern'},
        excludedTags: {'urinary_burning', 'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Incontinence d’effort possible',
        explanation:
            'Une fuite lors de la toux, du rire ou d’un effort peut correspondre à une faiblesse du soutien pelvien.',
        tagWeights: {'stress_incontinence_pattern': 52, 'urinary_leakage': 20},
        requiredAllTags: {'stress_incontinence_pattern'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Glycémie élevée à vérifier',
        explanation:
            'Uriner en grande quantité avec une soif inhabituelle peut nécessiter un contrôle de la glycémie.',
        tagWeights: {'large_urine_volume': 42, 'excessive_thirst': 42},
        requiredAllTags: {'large_urine_volume', 'excessive_thirst'},
      ),
      AssessmentPossibility(
        title: 'Déséquilibre du diabète à exclure en urgence',
        explanation:
            'Une soif intense et des urines abondantes associées à des vomissements, une respiration anormale ou une confusion peuvent révéler une acidocétose, même sans diabète déjà connu.',
        tagWeights: {'possible_ketoacidosis': 85},
        requiredAllTags: {'possible_ketoacidosis'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Urétrite ou infection génitale possible',
        explanation:
            'Une brûlure avec écoulement génital ou exposition sexuelle nécessite un dépistage et un traitement adaptés.',
        tagWeights: {
          'genital_discharge': 42,
          'sexual_exposure': 34,
          'urinary_burning': 18,
        },
        requiredAllTags: {'genital_discharge'},
      ),
      AssessmentPossibility(
        title: 'Infection urinaire du jeune nourrisson à évaluer immédiatement',
        explanation:
            'Une infection urinaire possible avant 3 mois nécessite une évaluation pédiatrique spécialisée immédiate.',
        tagWeights: {'young_infant_urinary_infection': 80},
        requiredAllTags: {'young_infant_urinary_infection'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Atteinte rénale aiguë possible',
        explanation:
            'Une chute marquée des urines avec gonflement, essoufflement ou malaise nécessite une évaluation hospitalière immédiate.',
        tagWeights: {'acute_kidney_injury_pattern': 80},
        requiredAllTags: {'acute_kidney_injury_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Compression des nerfs lombaires à exclure',
        explanation:
            'Un engourdissement périnéal, une faiblesse des jambes ou une perte récente du contrôle urinaire ou fécal est une urgence neurologique.',
        tagWeights: {'cauda_equina_pattern': 80},
        requiredAllTags: {'cauda_equina_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Obstruction urinaire infectée à exclure en urgence',
        explanation:
            'Une fièvre associée à un calcul, une obstruction ou une rétention urinaire nécessite une prise en charge hospitalière urgente.',
        tagWeights: {'infected_urinary_obstruction': 60},
        requiredAllTags: {'infected_urinary_obstruction'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Sang visible dans les urines à faire vérifier',
        explanation:
            'Du sang visible dans les urines doit être évalué même s’il est isolé ou sans douleur.',
        tagWeights: {'blood_in_urine': 54},
        requiredAllTags: {'blood_in_urine'},
      ),
    ],
    selfCare: [
      'Buvez régulièrement si aucun professionnel ne vous a demandé de limiter les liquides.',
      'N’attendez pas si apparaissent fièvre, douleur du dos, confusion ou impossibilité d’uriner.',
    ],
    pharmacyAdvice: [
      'N’utilisez pas des antibiotiques restants ou appartenant à une autre personne.',
      'Montrez vos traitements et allergies avant tout produit pour les symptômes urinaires.',
    ],
  ),
  AssessmentPathway(
    id: 'dizziness',
    version: 4,
    title: 'Vertiges et malaise',
    subtitle: 'Tête qui tourne, faiblesse, perte d’équilibre ou évanouissement',
    icon: Icons.accessibility_new_outlined,
    color: Color(0xFF6C63C7),
    questions: [
      AssessmentQuestion(
        id: 'dizziness_now',
        title: 'État actuel',
        prompt: 'Quelle situation décrit votre état maintenant ?',
        icon: Icons.accessibility_new_outlined,
        options: [
          AssessmentOption(
            id: 'neuro',
            label:
                'Faiblesse d’un côté, visage asymétrique ou difficulté à parler',
            icon: Icons.emergency_outlined,
            tags: {'neurologic_deficit', 'sudden_dizziness'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'faint_chest',
            label: 'Évanouissement avec douleur poitrine ou palpitations',
            icon: Icons.emergency_outlined,
            tags: {'collapse', 'chest_pain', 'palpitations'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'cannot_walk',
            label: 'Impossible de tenir debout ou de marcher',
            icon: Icons.emergency_outlined,
            tags: {'severe_imbalance'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'confusion',
            label: 'Confusion nouvelle ou difficulté à rester éveillé(e)',
            icon: Icons.emergency_outlined,
            tags: {'confusion'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'persistent_vomiting',
            label: 'Vomissements continus, impossible de garder les liquides',
            icon: Icons.emergency_outlined,
            tags: {'persistent_vomiting', 'cannot_hydrate'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'stable',
            label: 'Malaise léger ou intermittent, je peux marcher',
            icon: Icons.check_circle_outline,
            tags: {'stable_dizziness'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_type',
        title: 'Sensation principale',
        prompt: 'Que ressentez-vous surtout ?',
        icon: Icons.sync_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'spinning',
            label: 'La pièce tourne ou bouge autour de moi',
            icon: Icons.sync_outlined,
            tags: {'vertigo', 'branch_dizziness_vertigo'},
          ),
          AssessmentOption(
            id: 'faint',
            label: 'Voile noir, sueurs ou impression de m’évanouir',
            icon: Icons.personal_injury_outlined,
            tags: {'presyncope', 'branch_dizziness_faint'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'imbalance',
            label: 'Je dévie ou perds l’équilibre en marchant',
            icon: Icons.directions_walk_outlined,
            tags: {'imbalance'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'weak',
            label: 'Faiblesse générale ou fatigue sans rotation',
            icon: Icons.battery_2_bar_outlined,
            tags: {'general_weakness'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_onset',
        title: 'Déclenchement',
        prompt: 'Quand le malaise apparaît-il ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'sudden',
            label: 'Brutalement, pour la première fois',
            icon: Icons.warning_amber_rounded,
            tags: {'sudden_dizziness', 'new_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'head_position',
            label: 'En tournant la tête ou en me retournant dans le lit',
            icon: Icons.bedtime_outlined,
            tags: {'positional_trigger'},
          ),
          AssessmentOption(
            id: 'standing',
            label: 'En me levant ou après être resté(e) debout',
            icon: Icons.trending_up_outlined,
            tags: {'standing_trigger', 'branch_dizziness_faint'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis plusieurs jours ou de plus en plus souvent',
            icon: Icons.calendar_month_outlined,
            tags: {'persistent', 'worsening'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'other',
            label: 'Sans déclencheur clair ou autre situation',
            icon: Icons.help_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_duration',
        title: 'Durée des épisodes',
        prompt: 'Combien de temps dure le vertige ou le malaise ?',
        icon: Icons.schedule_outlined,
        options: [
          AssessmentOption(
            id: 'seconds',
            label: 'Quelques secondes à moins d’une minute',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'brief_dizziness'},
          ),
          AssessmentOption(
            id: 'minutes',
            label: 'De 1 minute à moins d’une heure',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'episodic_dizziness'},
          ),
          AssessmentOption(
            id: 'hours',
            label:
                'Plusieurs heures, avec des périodes normales entre les crises',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'episodic_vertigo'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'continuous',
            label: 'En continu, même immobile',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'continuous_vertigo'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_associated',
        title: 'Signes associés',
        prompt: 'Quels signes accompagnent le vertige ou le malaise ?',
        icon: Icons.warning_amber_rounded,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'headache_neuro',
            label:
                'Vision double, faiblesse, engourdissement ou parole inhabituelle',
            icon: Icons.emergency_outlined,
            tags: {'vision_change', 'neurologic_deficit'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'severe_headache',
            label: 'Mal de tête brutal, nouveau ou très intense',
            icon: Icons.emergency_outlined,
            tags: {'severe_headache'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'hearing',
            label: 'J’entends moins bien',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'hearing_change', 'branch_dizziness_vertigo'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'dehydration',
            label: 'Chaleur, diarrhée, vomissements ou peu bu',
            icon: Icons.local_drink_outlined,
            tags: {'dehydration_risk'},
          ),
          AssessmentOption(
            id: 'bleeding',
            label:
                'Saignement important, selles noires ou règles très abondantes',
            icon: Icons.emergency_outlined,
            tags: {'bleeding', 'digestive_bleeding', 'very_heavy_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
          AssessmentOption(
            id: 'tinnitus',
            label: 'Sifflement ou bourdonnement dans une oreille',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'tinnitus', 'branch_dizziness_vertigo'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'ear_fullness',
            label: 'Sensation d’oreille bouchée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'ear_fullness', 'branch_dizziness_vertigo'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_context',
        title: 'Contexte',
        prompt: 'Quelle situation vous concerne ?',
        icon: Icons.health_and_safety_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'diabetes',
            label: 'Diabète connu',
            icon: Icons.medical_information_outlined,
            tags: {'diabetes_context'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'low_glucose',
            label: 'Repas sauté avec tremblements, sueurs ou faim inhabituelle',
            icon: Icons.warning_amber_rounded,
            tags: {'low_glucose_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pregnancy',
            label: 'Grossesse possible ou récente',
            icon: Icons.pregnant_woman_outlined,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'medicine',
            label: 'Nouveau médicament ou changement de dose',
            icon: Icons.medication_outlined,
            tags: {'new_medication'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'stress',
            label: 'Crise de stress avec respiration rapide',
            icon: Icons.psychology_outlined,
            tags: {'anxiety_pattern', 'hyperventilation'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_balance_detail',
        title: 'Marche et équilibre',
        prompt: 'Depuis le début du vertige, comment marchez-vous ?',
        icon: Icons.directions_walk_outlined,
        requiredTags: {'branch_dizziness_vertigo'},
        options: [
          AssessmentOption(
            id: 'new_unsteadiness',
            label:
                'Nouvelle difficulté à marcher droit avec vertige continu et nausée',
            icon: Icons.emergency_outlined,
            tags: {
              'sudden_dizziness',
              'imbalance',
              'continuous_vertigo',
              'nausea',
              'acute_vestibular_syndrome',
            },
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'walk_normal',
            label: 'Je marche normalement entre les épisodes',
            icon: Icons.check_circle_outline,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas ou aucune de ces descriptions',
            icon: Icons.help_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_vertigo_detail',
        title: 'Vertige rotatoire',
        prompt: 'Comment évolue la sensation de rotation ?',
        icon: Icons.sync_outlined,
        requiredTags: {'branch_dizziness_vertigo'},
        options: [
          AssessmentOption(
            id: 'seconds_position',
            label: 'Quelques secondes lors d’un mouvement de tête',
            icon: Icons.timer_outlined,
            tags: {'brief_positional_vertigo'},
          ),
          AssessmentOption(
            id: 'hours_ear',
            label: 'Crises avec baisse d’audition ou bourdonnement',
            icon: Icons.hearing_outlined,
            tags: {'episodic_vertigo', 'hearing_change', 'tinnitus'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'continuous_after_virus',
            label:
                'Continu depuis un rhume, avec nausée mais sans faiblesse d’un côté',
            icon: Icons.sick_outlined,
            tags: {'continuous_vertigo', 'recent_viral_illness', 'nausea'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'new_hearing_loss',
            label: 'Baisse soudaine de l’audition d’une oreille',
            icon: Icons.warning_amber_rounded,
            tags: {'sudden_hearing_loss'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces évolutions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_faint_detail',
        title: 'Malaise ou évanouissement',
        prompt: 'Dans quelle situation le malaise survient-il ?',
        icon: Icons.personal_injury_outlined,
        requiredTags: {'branch_dizziness_faint'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'exercise_lying',
            label:
                'J’ai réellement perdu connaissance pendant l’effort ou couché(e)',
            icon: Icons.emergency_outlined,
            tags: {'true_syncope', 'exertional_syncope', 'supine_syncope'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'not_recovered',
            label: 'Perte de connaissance prolongée ou récupération incomplète',
            icon: Icons.emergency_outlined,
            tags: {'prolonged_unconsciousness', 'confusion'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'cardiac_risk',
            label:
                'Vraie perte de connaissance avec maladie cardiaque, nouvel essoufflement ou mort subite familiale avant 40 ans',
            icon: Icons.warning_amber_rounded,
            tags: {'true_syncope', 'cardiac_syncope_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'standing_heat',
            label: 'Après station debout, chaleur, douleur ou émotion forte',
            icon: Icons.wb_sunny_outlined,
            tags: {'vasovagal_pattern', 'standing_trigger'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'standing_fast',
            label: 'Juste après m’être levé(e) rapidement',
            icon: Icons.trending_up_outlined,
            tags: {'orthostatic_pattern'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'dizziness_consciousness',
        title: 'Perte de connaissance',
        prompt: 'Avez-vous réellement perdu connaissance pendant ce malaise ?',
        icon: Icons.psychology_alt_outlined,
        requiredTags: {'branch_dizziness_faint'},
        options: [
          AssessmentOption(
            id: 'no',
            label: 'Non, je suis resté(e) conscient(e)',
            icon: Icons.radio_button_unchecked_rounded,
          ),
          AssessmentOption(
            id: 'recovered',
            label: 'Oui, brièvement, puis je suis revenu(e) à mon état normal',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'true_syncope'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'incomplete',
            label: 'Oui, et je ne suis pas revenu(e) à mon état normal',
            icon: Icons.warning_amber_rounded,
            tags: {'true_syncope', 'confusion'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'injury',
            label: 'Oui, et je me suis gravement blessé(e) en tombant',
            icon: Icons.warning_amber_rounded,
            tags: {'true_syncope', 'serious_fall_injury'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Vertige positionnel possible',
        explanation:
            'Une rotation brève déclenchée par un mouvement de la tête est compatible avec un vertige positionnel.',
        tagWeights: {
          'brief_positional_vertigo': 50,
          'positional_trigger': 30,
          'vertigo': 16,
        },
        requiredAllTags: {
          'brief_positional_vertigo',
          'positional_trigger',
          'vertigo',
        },
        excludedTags: {
          'neurologic_deficit',
          'continuous_vertigo',
          'sudden_hearing_loss',
          'posterior_stroke_pattern',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Inflammation de l’oreille interne possible',
        explanation:
            'Un vertige continu après une infection virale ou associé à des signes auditifs nécessite un examen.',
        tagWeights: {
          'continuous_vertigo': 34,
          'recent_viral_illness': 24,
          'hearing_change': 26,
          'tinnitus': 18,
          'nausea': 12,
        },
        requiredAllTags: {'vertigo'},
        requiredAnyTags: {
          'continuous_vertigo',
          'hearing_change',
          'recent_viral_illness',
        },
        excludedTags: {
          'neurologic_deficit',
          'posterior_stroke_pattern',
          'sudden_hearing_loss',
        },
      ),
      AssessmentPossibility(
        title: 'Baisse de tension ou déshydratation possible',
        explanation:
            'Un voile noir au lever, après chaleur ou manque de liquide peut correspondre à une baisse de tension.',
        tagWeights: {
          'presyncope': 26,
          'standing_trigger': 28,
          'orthostatic_pattern': 38,
          'dehydration_risk': 28,
        },
        requiredAllTags: {'presyncope'},
        requiredAnyTags: {
          'standing_trigger',
          'orthostatic_pattern',
          'dehydration_risk',
        },
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Malaise vagal possible',
        explanation:
            'Un malaise après station debout, chaleur, douleur ou émotion forte peut correspondre à un réflexe vagal.',
        tagWeights: {
          'vasovagal_pattern': 48,
          'standing_trigger': 22,
          'presyncope': 16,
        },
        requiredAllTags: {'vasovagal_pattern'},
        excludedTags: {'triage_emergency'},
      ),
      AssessmentPossibility(
        title: 'Glycémie basse possible',
        explanation:
            'Malaise, tremblements ou sueurs après un repas sauté, surtout avec diabète, nécessitent un contrôle rapide.',
        tagWeights: {
          'low_glucose_pattern': 48,
          'diabetes_context': 32,
          'sweating': 16,
        },
        requiredAllTags: {'low_glucose_pattern'},
      ),
      AssessmentPossibility(
        title: 'Anémie ou perte de sang possible',
        explanation:
            'Faiblesse et étourdissement avec saignement important peuvent correspondre à une perte de sang ou une anémie.',
        tagWeights: {
          'general_weakness': 20,
          'bleeding': 34,
          'digestive_bleeding': 30,
          'very_heavy_bleeding': 30,
        },
        requiredAnyTags: {
          'bleeding',
          'digestive_bleeding',
          'very_heavy_bleeding',
        },
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Cause cardiaque du malaise possible',
        explanation:
            'Un évanouissement à l’effort ou couché, avec douleur thoracique ou palpitations, nécessite une évaluation urgente.',
        tagWeights: {
          'exertional_syncope': 40,
          'supine_syncope': 36,
          'chest_pain': 24,
          'palpitations': 24,
          'collapse': 18,
          'cardiac_syncope_risk': 44,
        },
        requiredAllTags: {'true_syncope'},
        requiredAnyTags: {
          'exertional_syncope',
          'supine_syncope',
          'chest_pain',
          'palpitations',
          'cardiac_syncope_risk',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Cause neurologique urgente possible',
        explanation:
            'Un vertige brutal avec faiblesse d’un côté, trouble de la parole, vision double ou incapacité à marcher est une urgence.',
        tagWeights: {
          'neurologic_deficit': 46,
          'sudden_dizziness': 24,
          'severe_imbalance': 32,
          'vision_change': 20,
          'acute_vestibular_syndrome': 48,
          'posterior_stroke_pattern': 52,
        },
        requiredAnyTags: {
          'neurologic_deficit',
          'severe_imbalance',
          'acute_vestibular_syndrome',
          'posterior_stroke_pattern',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Baisse auditive soudaine à évaluer sous 24 heures',
        explanation:
            'Une baisse soudaine de l’audition d’une oreille nécessite une évaluation ORL ou hospitalière rapide.',
        tagWeights: {'sudden_hearing_loss': 60},
        requiredAllTags: {'sudden_hearing_loss'},
      ),
    ],
    selfCare: [
      'Asseyez-vous ou allongez-vous immédiatement pour éviter une chute.',
      'Levez-vous lentement et hydratez-vous si vous pouvez boire sans restriction.',
    ],
    pharmacyAdvice: [
      'Évitez de conduire et demandez conseil avant un médicament contre les vertiges.',
      'Si vous êtes diabétique, suivez votre plan habituel de contrôle de la glycémie.',
    ],
  ),
  AssessmentPathway(
    id: 'fever',
    version: 4,
    title: 'Fièvre et frissons',
    subtitle: 'Température élevée, frissons, sueurs ou sensation d’infection',
    icon: Icons.thermostat_outlined,
    color: Color(0xFFE05E3A),
    questions: [
      AssessmentQuestion(
        id: 'fever_age',
        title: 'Âge',
        prompt: 'Quel âge a la personne qui a de la fièvre ?',
        icon: Icons.cake_outlined,
        options: [
          AssessmentOption(
            id: 'under_3_months',
            label: 'Moins de 3 mois',
            icon: Icons.child_care_outlined,
            tags: {'person_under_3_months', 'branch_fever_infant'},
          ),
          AssessmentOption(
            id: '3_to_6_months',
            label: 'De 3 à moins de 6 mois',
            icon: Icons.child_care_outlined,
            tags: {'person_3_to_6_months', 'branch_fever_infant'},
          ),
          AssessmentOption(
            id: '6_months_to_4_years',
            label: 'De 6 mois à 4 ans',
            icon: Icons.escalator_warning_outlined,
            tags: {'young_child'},
          ),
          AssessmentOption(
            id: '5_to_64_years',
            label: 'De 5 à 64 ans',
            icon: Icons.person_outline,
          ),
          AssessmentOption(
            id: '65_or_more',
            label: '65 ans ou plus',
            icon: Icons.elderly_outlined,
            tags: {'older_adult'},
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_temperature',
        title: 'Température mesurée',
        prompt: 'Quelle est la température la plus élevée mesurée ?',
        icon: Icons.device_thermostat_outlined,
        options: [
          AssessmentOption(
            id: 'unconfirmed',
            label: 'Je n’ai pas mesuré la température',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_unconfirmed'},
          ),
          AssessmentOption(
            id: '38',
            label: 'De 38,0 à 38,9 °C',
            icon: Icons.thermostat_outlined,
            tags: {'temperature_38', 'fever'},
          ),
          AssessmentOption(
            id: '39',
            label: 'De 39,0 à 39,9 °C',
            icon: Icons.thermostat_outlined,
            tags: {'temperature_39', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: '40',
            label: '40 °C ou plus',
            icon: Icons.warning_amber_rounded,
            tags: {'temperature_40', 'fever'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'below_38',
            label: 'De 36 à 37,9 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_below_38'},
          ),
          AssessmentOption(
            id: 'below_36',
            label: 'Moins de 36 °C',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'temperature_below_36'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_course',
        title: 'Évolution',
        prompt: 'Comment la fièvre ou les frissons évoluent-ils ?',
        icon: Icons.thermostat_outlined,
        options: [
          AssessmentOption(
            id: 'today',
            label: 'Depuis aujourd’hui, état général encore correct',
            icon: Icons.today_outlined,
            tags: {'acute_fever'},
          ),
          AssessmentOption(
            id: 'days',
            label: 'Depuis 2 ou 3 jours',
            icon: Icons.date_range_outlined,
            tags: {'fever', 'days'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'persistent',
            label: 'Plus de 3 jours ou aggravation progressive',
            icon: Icons.trending_up_outlined,
            tags: {'fever', 'persistent', 'worsening'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'returned',
            label: 'Elle avait diminué puis revient plus forte',
            icon: Icons.replay_outlined,
            tags: {'fever', 'worsening_after_improvement'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_duration',
        title: 'Nombre de jours',
        prompt:
            'Depuis combien de jours avez-vous de la fièvre ou des frissons ?',
        icon: Icons.calendar_month_outlined,
        options: [
          AssessmentOption(
            id: 'under_24h',
            label: 'Moins de 24 heures',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'fever_under_24h'},
          ),
          AssessmentOption(
            id: '1_to_3',
            label: 'De 1 à 3 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'fever_1_to_3_days'},
          ),
          AssessmentOption(
            id: '4_days',
            label: '4 jours',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'persistent'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: '5_plus',
            label: '5 jours ou plus',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'fever_5_days', 'persistent'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_emergency',
        title: 'Signes d’urgence',
        prompt: 'Avez-vous l’un de ces signes ?',
        icon: Icons.emergency_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'altered_consciousness',
            label: 'Confusion inhabituelle ou très difficile à réveiller',
            icon: Icons.emergency_outlined,
            tags: {'altered_consciousness', 'sepsis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'seizure_or_collapse',
            label: 'Convulsion ou perte de connaissance',
            icon: Icons.emergency_outlined,
            tags: {'acute_neurologic_emergency'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'breathing_or_cyanosis',
            label: 'Grande difficulté à respirer ou lèvres pâles/bleues',
            icon: Icons.emergency_outlined,
            tags: {'respiratory_emergency_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'chest_pain',
            label: 'Douleur thoracique nouvelle ou inexpliquée',
            icon: Icons.emergency_outlined,
            tags: {'chest_pain_with_fever'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'meningeal',
            label: 'Fort mal de tête avec nuque raide',
            icon: Icons.emergency_outlined,
            tags: {'meningeal_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'non_blanching_rash',
            label:
                'Taches rouges ou violettes qui ne pâlissent pas sous un verre',
            icon: Icons.emergency_outlined,
            tags: {'non_blanching_rash'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'shock_pattern',
            label: 'Peau moite ou marbrée avec faiblesse extrême',
            icon: Icons.emergency_outlined,
            tags: {'shock_pattern', 'sepsis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'almost_no_urine',
            label: 'Presque plus d’urine malgré une hydratation habituelle',
            icon: Icons.emergency_outlined,
            tags: {'low_urine', 'sepsis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'child_serious_illness',
            label:
                'Enfant : respiration très rapide ou côtes creusées, peau pâle/marbrée ou réaction inhabituelle',
            icon: Icons.emergency_outlined,
            tags: {'pediatric_serious_illness_pattern'},
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
        id: 'fever_infant_warning',
        title: 'Petit nourrisson',
        prompt: 'Un de ces signes est-il présent chez le nourrisson ?',
        icon: Icons.child_care_outlined,
        requiredTags: {'branch_fever_infant'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'poor_feeding_or_drowsy',
            label:
                'Boit nettement moins, geint, paraît mou ou anormalement somnolent',
            icon: Icons.emergency_outlined,
            tags: {'infant_serious_illness_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'apnea_or_work_of_breathing',
            label:
                'Pause respiratoire, geignement respiratoire ou côtes qui se creusent',
            icon: Icons.emergency_outlined,
            tags: {'infant_respiratory_distress'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'temperature_below_36',
            label: 'Température mesurée inférieure à 36 °C',
            icon: Icons.emergency_outlined,
            tags: {'infant_hypothermia', 'sepsis_pattern'},
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
        id: 'fever_focus',
        title: 'Zone principale',
        prompt: 'Quelles zones ou quels symptômes accompagnent la fièvre ?',
        icon: Icons.search_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'respiratory',
            label: 'Toux, gorge, essoufflement ou douleur en respirant',
            icon: Icons.air_outlined,
            tags: {'respiratory_focus', 'branch_fever_respiratory'},
          ),
          AssessmentOption(
            id: 'urinary',
            label: 'Brûlure urinaire ou douleur du côté/dos',
            icon: Icons.local_drink_outlined,
            tags: {'urinary_focus', 'branch_fever_urinary'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'digestive',
            label: 'Vomissements, diarrhée ou douleur abdominale',
            icon: Icons.sick_outlined,
            tags: {'digestive_focus', 'branch_fever_digestive'},
          ),
          AssessmentOption(
            id: 'skin',
            label: 'Plaie, rougeur chaude, gonflement ou éruption',
            icon: Icons.texture_outlined,
            tags: {'skin_focus', 'branch_fever_skin'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune zone claire',
            icon: Icons.help_outline,
            tags: {'fever_without_focus'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_hydration',
        title: 'Hydratation',
        prompt: 'Comment arrivez-vous à boire et à uriner ?',
        icon: Icons.local_drink_outlined,
        options: [
          AssessmentOption(
            id: 'hydrated',
            label: 'Je bois et j’urine normalement',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'hydrated'},
          ),
          AssessmentOption(
            id: 'less',
            label: 'Je bois moins et j’urine moins que d’habitude',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'dehydration_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'cannot_drink',
            label: 'Je vomis chaque fois que je bois',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'cannot_hydrate', 'dehydration_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'dry',
            label: 'Bouche très sèche ou absence de larmes chez l’enfant',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'dehydration_risk'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'unsure',
            label: 'Je ne sais pas',
            icon: Icons.help_outline,
            tags: {'answer_uncertain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_medical_context',
        title: 'Contexte médical',
        prompt: 'Quelles situations vous concernent ?',
        icon: Icons.medical_information_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'pregnant',
            label: 'Grossesse ou accouchement dans l’année écoulée',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'pregnancy_possible'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'active_cancer_treatment',
            label: 'Chimiothérapie ou traitement anticancéreux actif ou récent',
            icon: Icons.warning_amber_rounded,
            tags: {'possible_neutropenic_sepsis'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'immunocompromised',
            label: 'Immunité diminuée ou traitement immunosuppresseur',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'immunocompromised'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'recent_procedure',
            label: 'Opération, hospitalisation ou sonde récente',
            icon: Icons.radio_button_unchecked_rounded,
            tags: {'recent_procedure'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces situations',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_exposure',
        title: 'Exposition récente',
        prompt: 'Y a-t-il eu une exposition particulière ?',
        icon: Icons.public_outlined,
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'mosquito_travel',
            label: 'Nombreuses piqûres de moustiques',
            icon: Icons.public_outlined,
            tags: {'mosquito_exposure', 'branch_fever_vector'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'vector_travel',
            label: 'Voyage ou séjour récent dans une zone de dengue/paludisme',
            icon: Icons.flight_outlined,
            tags: {'travel', 'branch_fever_vector'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'resident_vector_area',
            label:
                'Je vis dans une zone où dengue ou paludisme circule, notamment en Haïti',
            icon: Icons.home_outlined,
            tags: {'resident_vector_area', 'branch_fever_vector'},
            urgency: AssessmentUrgency.consultationSoon,
          ),
          AssessmentOption(
            id: 'sick_contact',
            label: 'Contact proche avec une personne malade',
            icon: Icons.groups_outlined,
            tags: {'sick_contact'},
          ),
          AssessmentOption(
            id: 'food_water',
            label: 'Aliment ou eau possiblement contaminé',
            icon: Icons.restaurant_outlined,
            tags: {'food_water_exposure'},
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune exposition connue',
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_vector_detail',
        title: 'Moustiques ou voyage',
        prompt: 'Quel autre signe accompagne cette exposition ?',
        icon: Icons.public_outlined,
        requiredTags: {'branch_fever_vector'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'dengue_pattern',
            label: 'Fortes courbatures, douleur derrière les yeux ou éruption',
            icon: Icons.warning_amber_rounded,
            tags: {'dengue_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'dengue_warning',
            label:
                'Douleur abdominale forte, vomissements persistants, saignement ou grande somnolence',
            icon: Icons.emergency_outlined,
            tags: {'dengue_warning'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'malaria_pattern',
            label:
                'Accès de frissons/sueurs et vie ou séjour dans une zone de paludisme',
            icon: Icons.thermostat_outlined,
            tags: {'malaria_pattern', 'travel_to_malaria_area'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_respiratory_detail',
        title: 'Signes respiratoires',
        prompt: 'Quel signe respiratoire est présent ?',
        icon: Icons.air_outlined,
        requiredTags: {'branch_fever_respiratory'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'mild_upper',
            label: 'Nez bouché, gorge ou toux légère',
            icon: Icons.face_outlined,
            tags: {'upper_respiratory', 'viral_pattern'},
          ),
          AssessmentOption(
            id: 'productive_cough',
            label: 'Toux avec crachats',
            icon: Icons.warning_amber_rounded,
            tags: {'productive_cough'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'breathlessness',
            label: 'Essoufflement inhabituel',
            icon: Icons.warning_amber_rounded,
            tags: {'mild_breathlessness'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pleuritic_pain',
            label: 'Douleur qui augmente en respirant',
            icon: Icons.warning_amber_rounded,
            tags: {'pleuritic_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'worsening',
            label: 'Amélioration puis retour de la fièvre et de la toux',
            icon: Icons.trending_up_outlined,
            tags: {'worsening_after_improvement', 'cough'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'diphtheria_pattern',
            label:
                'Dépôt gris adhérent dans la gorge, cou gonflé ou voix/bruit respiratoire inhabituel',
            icon: Icons.emergency_outlined,
            tags: {'diphtheria_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes respiratoires',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_urinary_detail',
        title: 'Signes urinaires',
        prompt: 'Quel signe urinaire est présent ?',
        icon: Icons.local_drink_outlined,
        requiredTags: {'branch_fever_urinary'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'burning',
            label: 'Brûlure et envies fréquentes',
            icon: Icons.local_fire_department_outlined,
            tags: {'urinary_burning', 'urinary_frequency'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'flank',
            label: 'Douleur du côté ou du dos avec frissons',
            icon: Icons.warning_amber_rounded,
            tags: {'flank_pain', 'kidney_infection_pattern'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'retention',
            label: 'Impossible d’uriner',
            icon: Icons.emergency_outlined,
            tags: {'urinary_retention'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes urinaires',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_skin_detail',
        title: 'Peau ou plaie',
        prompt: 'Comment la zone de peau évolue-t-elle ?',
        icon: Icons.texture_outlined,
        requiredTags: {'branch_fever_skin'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'red_spreading',
            label: 'Rouge, chaude, douloureuse et elle s’étend',
            icon: Icons.warning_amber_rounded,
            tags: {'cellulitis_pattern', 'rapid_spread'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'pus',
            label: 'Boule douloureuse ou plaie avec pus',
            icon: Icons.warning_amber_rounded,
            tags: {'abscess_pattern', 'pus'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'severe',
            label:
                'Douleur extrême, cloques sombres ou progression très rapide',
            icon: Icons.emergency_outlined,
            tags: {'severe_skin_pain', 'skin_necrosis_pattern'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucune de ces évolutions',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
      AssessmentQuestion(
        id: 'fever_digestive_detail',
        title: 'Signes digestifs',
        prompt: 'Quel signe digestif est présent ?',
        icon: Icons.sick_outlined,
        requiredTags: {'branch_fever_digestive'},
        allowMultiple: true,
        options: [
          AssessmentOption(
            id: 'diarrhea',
            label: 'Diarrhée, mais je peux boire',
            icon: Icons.water_drop_outlined,
            tags: {'diarrhea', 'hydrated'},
          ),
          AssessmentOption(
            id: 'vomiting',
            label: 'Vomissements, mais je peux garder des liquides',
            icon: Icons.water_drop_outlined,
            tags: {'vomiting', 'hydrated'},
          ),
          AssessmentOption(
            id: 'blood',
            label: 'Sang dans les selles ou les vomissements',
            icon: Icons.emergency_outlined,
            tags: {'digestive_bleeding'},
            urgency: AssessmentUrgency.emergency,
          ),
          AssessmentOption(
            id: 'localized_pain',
            label: 'Douleur abdominale forte et localisée',
            icon: Icons.warning_amber_rounded,
            tags: {'localized_abdominal_pain', 'severe_pain'},
            urgency: AssessmentUrgency.consultationToday,
          ),
          AssessmentOption(
            id: 'none',
            label: 'Aucun de ces signes digestifs',
            icon: Icons.remove_circle_outline,
          ),
        ],
      ),
    ],
    possibilities: [
      AssessmentPossibility(
        title: 'Fièvre du jeune nourrisson à évaluer immédiatement',
        explanation:
            'Une température d’au moins 38 °C avant 3 mois, une température basse ou un nourrisson inhabituellement somnolent nécessite une évaluation pédiatrique immédiate.',
        tagWeights: {
          'young_infant_fever': 70,
          'infant_hypothermia': 60,
          'infant_serious_illness_pattern': 58,
          'infant_respiratory_distress': 64,
        },
        requiredAnyTags: {
          'young_infant_fever',
          'infant_hypothermia',
          'infant_serious_illness_pattern',
          'infant_respiratory_distress',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Méningite ou maladie méningococcique possible',
        explanation:
            'Une raideur de nuque avec fort mal de tête, un rash non blanchissant ou une altération de la conscience impose une évaluation hospitalière immédiate.',
        tagWeights: {
          'meningeal_pattern': 70,
          'non_blanching_rash': 70,
          'altered_consciousness': 52,
          'acute_neurologic_emergency': 48,
        },
        requiredAnyTags: {
          'meningeal_pattern',
          'non_blanching_rash',
          'altered_consciousness',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Détresse respiratoire associée à la fièvre',
        explanation:
            'Une grande difficulté respiratoire ou une coloration pâle ou bleue nécessite une prise en charge immédiate.',
        tagWeights: {'respiratory_emergency_pattern': 76},
        requiredAllTags: {'respiratory_emergency_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Maladie fébrile grave possible chez l’enfant',
        explanation:
            'Une respiration très rapide ou difficile, une peau pâle ou marbrée ou un comportement inhabituel chez un enfant nécessite une prise en charge immédiate.',
        tagWeights: {'pediatric_serious_illness_pattern': 80, 'young_child': 8},
        requiredAllTags: {'pediatric_serious_illness_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title:
            'Neutropénie fébrile ou infection grave sous traitement possible',
        explanation:
            'Une fièvre ou un malaise sous traitement anticancéreux actif ou récent nécessite une évaluation hospitalière immédiate.',
        tagWeights: {'possible_neutropenic_sepsis': 80},
        requiredAllTags: {'possible_neutropenic_sepsis'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Diphtérie ou obstruction infectieuse de la gorge possible',
        explanation:
            'Un dépôt gris adhérent, un cou gonflé ou une voix ou respiration inhabituelle nécessite une évaluation immédiate et des précautions contre la transmission.',
        tagWeights: {'diphtheria_pattern': 80},
        requiredAllTags: {'diphtheria_pattern'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Infection virale possible',
        explanation:
            'Une fièvre récente avec rhume, gorge, toux légère ou contact malade peut correspondre à une infection virale.',
        tagWeights: {
          'acute_fever': 22,
          'upper_respiratory': 24,
          'viral_pattern': 30,
          'sick_contact': 18,
        },
        requiredAnyTags: {'upper_respiratory', 'viral_pattern', 'sick_contact'},
        excludedTags: {
          'young_infant_fever',
          'infant_serious_illness_pattern',
          'infant_respiratory_distress',
          'meningeal_pattern',
          'non_blanching_rash',
          'altered_consciousness',
          'respiratory_emergency_pattern',
          'sepsis_pattern',
          'shock_pattern',
          'dengue_warning',
          'possible_neutropenic_sepsis',
          'diphtheria_pattern',
          'triage_emergency',
        },
      ),
      AssessmentPossibility(
        title: 'Pneumonie ou infection respiratoire basse possible',
        explanation:
            'Fièvre avec toux productive, essoufflement ou douleur respiratoire nécessite un examen des poumons.',
        tagWeights: {
          'productive_cough': 28,
          'mild_breathlessness': 24,
          'pleuritic_pain': 24,
          'worsening_after_improvement': 22,
          'respiratory_focus': 14,
        },
        requiredAllTags: {'respiratory_focus'},
        requiredAnyTags: {
          'productive_cough',
          'mild_breathlessness',
          'pleuritic_pain',
          'worsening_after_improvement',
        },
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Infection urinaire ou rénale possible',
        explanation:
            'Fièvre avec brûlure urinaire ou douleur du dos peut indiquer une infection des voies urinaires ou du rein.',
        tagWeights: {
          'urinary_burning': 26,
          'urinary_frequency': 20,
          'kidney_infection_pattern': 38,
          'flank_pain': 24,
          'urinary_focus': 14,
        },
        requiredAllTags: {'urinary_focus'},
        requiredAnyTags: {
          'urinary_burning',
          'urinary_frequency',
          'kidney_infection_pattern',
          'flank_pain',
        },
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Gastro-entérite ou infection digestive possible',
        explanation:
            'Fièvre avec diarrhée ou vomissements après une exposition alimentaire peut avoir une origine digestive.',
        tagWeights: {
          'diarrhea': 26,
          'vomiting': 22,
          'food_water_exposure': 26,
          'digestive_focus': 16,
        },
        requiredAllTags: {'digestive_focus'},
        requiredAnyTags: {'diarrhea', 'vomiting'},
        minimumMatchedEvidence: 2,
        excludedTags: {
          'digestive_bleeding',
          'localized_abdominal_pain',
          'cannot_hydrate',
        },
      ),
      AssessmentPossibility(
        title: 'Infection de la peau possible',
        explanation:
            'Fièvre avec rougeur chaude qui s’étend, plaie ou pus nécessite un examen rapide.',
        tagWeights: {
          'cellulitis_pattern': 34,
          'rapid_spread': 24,
          'abscess_pattern': 30,
          'pus': 20,
          'skin_focus': 14,
        },
        requiredAllTags: {'skin_focus'},
        requiredAnyTags: {'cellulitis_pattern', 'abscess_pattern', 'pus'},
        minimumMatchedEvidence: 2,
        excludedTags: {'skin_necrosis_pattern'},
      ),
      AssessmentPossibility(
        title: 'Dengue ou autre arbovirose possible',
        explanation:
            'Fièvre avec courbatures, douleur derrière les yeux ou éruption après exposition aux moustiques nécessite une évaluation; les signes de saignement ou de déshydratation sont urgents.',
        tagWeights: {
          'dengue_pattern': 46,
          'body_aches': 20,
          'retro_orbital_pain': 24,
          'rash': 14,
          'dengue_warning': 40,
          'mosquito_exposure': 8,
        },
        requiredAnyTags: {'dengue_pattern', 'dengue_warning'},
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Paludisme ou autre infection de voyage à exclure',
        explanation:
            'Une fièvre avec accès de frissons chez une personne qui vit ou a séjourné dans une zone de transmission doit être testée rapidement.',
        tagWeights: {
          'malaria_pattern': 48,
          'travel_to_malaria_area': 34,
          'travel': 8,
        },
        requiredAllTags: {'malaria_pattern', 'travel_to_malaria_area'},
        minimumMatchedEvidence: 2,
      ),
      AssessmentPossibility(
        title: 'Infection sévère ou sepsis possible',
        explanation:
            'Confusion, difficulté respiratoire, peau moite, douleur extrême ou très peu d’urine avec infection sont des signes d’urgence.',
        tagWeights: {
          'sepsis_pattern': 46,
          'confusion': 28,
          'severe_breathlessness': 24,
          'clammy_skin': 22,
          'extreme_pain': 20,
          'low_urine': 18,
          'altered_consciousness': 38,
          'respiratory_emergency_pattern': 34,
          'shock_pattern': 46,
          'infant_hypothermia': 28,
        },
        requiredAnyTags: {
          'sepsis_pattern',
          'altered_consciousness',
          'shock_pattern',
          'low_urine',
          'infant_hypothermia',
        },
        urgentReason: true,
      ),
      AssessmentPossibility(
        title: 'Cause de fièvre non localisée',
        explanation:
            'Une fièvre sans foyer clair qui persiste ou s’aggrave doit être examinée pour en identifier la cause.',
        tagWeights: {
          'fever_without_focus': 34,
          'persistent': 24,
          'worsening': 22,
          'immunocompromised': 18,
        },
        requiredAllTags: {'fever_without_focus'},
        excludedTags: {
          'young_infant_fever',
          'meningeal_pattern',
          'non_blanching_rash',
          'sepsis_pattern',
          'shock_pattern',
        },
      ),
    ],
    selfCare: [
      'Buvez régulièrement, reposez-vous et surveillez l’évolution de l’état général.',
      'Évitez de partager verres et couverts si une infection transmissible est possible.',
    ],
    pharmacyAdvice: [
      'Suivez strictement l’étiquette de tout médicament contre la fièvre et évitez les doublons de paracétamol.',
      'Si une dengue est possible, évitez l’aspirine et l’ibuprofène jusqu’à l’avis d’un professionnel à cause du risque de saignement.',
      'Ne commencez pas d’antibiotique sans évaluation ou prescription adaptée.',
    ],
  ),
  ..._additionalAssessmentPathways,
];

AssessmentPathway? assessmentPathwayById(String id) {
  for (final pathway in assessmentPathways) {
    if (pathway.id == id) return pathway;
  }
  return null;
}

List<AssessmentPathway> mergeNewestAssessmentPathways(
  Iterable<AssessmentPathway> bundled,
  Iterable<AssessmentPathway> published,
) {
  final bundledList = bundled.toList(growable: false);
  final newestById = <String, AssessmentPathway>{
    for (final pathway in bundledList) pathway.id: pathway,
  };
  for (final pathway in published) {
    final current = newestById[pathway.id];
    if (current == null || pathway.version > current.version) {
      newestById[pathway.id] = pathway;
    }
  }
  return List<AssessmentPathway>.unmodifiable([
    for (final pathway in bundledList) newestById.remove(pathway.id)!,
    ...newestById.values,
  ]);
}

Map<String, dynamic> assessmentPathwayToMap(AssessmentPathway pathway) => {
  'schemaVersion': 3,
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
        'allowMultiple': question.allowMultiple,
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
        'requiredAllTags': possibility.requiredAllTags.toList()..sort(),
        'requiredAnyTags': possibility.requiredAnyTags.toList()..sort(),
        'excludedTags': possibility.excludedTags.toList()..sort(),
        'minimumMatchedEvidence': possibility.minimumMatchedEvidence,
        'urgentReason': possibility.urgentReason,
      },
  ],
  'selfCare': pathway.selfCare,
  'pharmacyAdvice': pathway.pharmacyAdvice,
};

AssessmentPathway assessmentPathwayFromMap(
  Map<String, dynamic> map, {
  int version = 1,
}) {
  final schemaVersion = (map['schemaVersion'] as num?)?.round();
  if (schemaVersion == null || schemaVersion < 1 || schemaVersion > 3) {
    throw FormatException(
      'Version de schéma clinique absente ou incompatible : '
      '${map['schemaVersion']}.',
    );
  }

  List<Map<String, dynamic>> maps(String key) => (map[key] as List? ?? const [])
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .toList(growable: false);

  List<String> strings(Object? value) => (value as List? ?? const [])
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  AssessmentUrgency parseUrgency(Object? raw) {
    final name = raw?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw const FormatException(
        'Niveau d’urgence absent dans un parcours clinique.',
      );
    }
    for (final value in AssessmentUrgency.values) {
      if (value.name == name) return value;
    }
    throw FormatException('Niveau d’urgence inconnu : $name.');
  }

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
              return AssessmentOption(
                id: option['id']?.toString().trim() ?? '',
                label: option['label']?.toString().trim() ?? '',
                icon: assessmentIconFromKey(option['iconKey']?.toString()),
                tags: strings(option['tags']).toSet(),
                urgency: parseUrgency(option['urgency']),
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
          allowMultiple: question['allowMultiple'] == true,
        );
      })
      .toList(growable: false);
  if (questions.isEmpty) {
    throw const FormatException(
      'Un parcours publié doit contenir une question.',
    );
  }
  final questionIds = <String>{};
  for (final question in questions) {
    if (!questionIds.add(question.id)) {
      throw FormatException(
        'Identifiant de question dupliqué : ${question.id}.',
      );
    }
    final optionIds = <String>{};
    for (final option in question.options) {
      if (option.id.contains('|') || !optionIds.add(option.id)) {
        throw FormatException('Identifiant de choix invalide : ${option.id}.');
      }
    }
    if (question.requiredTags.intersection(question.excludedTags).isNotEmpty) {
      throw FormatException('Conditions contradictoires : ${question.id}.');
    }
  }
  for (final question in questions) {
    for (final option in question.options) {
      final target = option.nextQuestionId;
      if (target != null &&
          (target == question.id || !questionIds.contains(target))) {
        throw FormatException('Destination de branche invalide : $target.');
      }
    }
  }
  if (!questions.any((question) => question.appliesTo(const {}))) {
    throw const FormatException('Aucune question initiale accessible.');
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
          requiredAllTags: strings(possibility['requiredAllTags']).toSet(),
          requiredAnyTags: strings(possibility['requiredAnyTags']).toSet(),
          excludedTags: strings(possibility['excludedTags']).toSet(),
          minimumMatchedEvidence:
              (possibility['minimumMatchedEvidence'] as num?)?.round() ?? 1,
          urgentReason: possibility['urgentReason'] == true,
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
  'eyes' => Icons.visibility_outlined,
  'joint' => Icons.directions_walk_outlined,
  'dental' => Icons.health_and_safety_outlined,
  _ => Icons.radio_button_checked_outlined,
};

String _assessmentIconKey(IconData icon) {
  if (icon == Icons.visibility_outlined) return 'eyes';
  if (icon == Icons.directions_walk_outlined) return 'joint';
  if (icon == Icons.health_and_safety_outlined) return 'dental';
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

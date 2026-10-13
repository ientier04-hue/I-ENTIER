import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/diagnostic_assessment.dart';

void main() {
  const engine = AssessmentEngine();
  AssessmentResult evaluate(
    String id,
    Map<String, String> answers, {
    Map<String, dynamic> context = const {},
  }) {
    final pathway = assessmentPathwayById(id)!;
    // A misspelled option must fail a scenario rather than silently testing no answer.
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key)!;
      for (final option in entry.value.split('|')) {
        expect(
          question.options.any((item) => item.id == option),
          isTrue,
          reason: '${entry.key}: $option',
        );
      }
    }
    return engine.evaluate(pathway, answers, context: context);
  }

  test('diarrhée et reflux reçoivent des conseils différents', () {
    final diarrhea = evaluate('abdominal', {
      'abdominal_associated': 'diarrhea',
      'abdominal_bowel_detail': 'watery',
    });
    final reflux = evaluate('abdominal', {
      'abdominal_location': 'upper',
      'abdominal_upper_pattern': 'burning',
    });
    expect(diarrhea.selfCare.join(' '), contains('réhydratation orale'));
    expect(diarrhea.pharmacyAdvice.join(' '), isNot(contains('antiacide')));
    expect(reflux.selfCare.join(' '), contains('repas plus petits'));
    expect(reflux.selfCare.join(' '), isNot(contains('réhydratation orale')));
    expect(reflux.pharmacyAdvice.join(' '), contains('antiacide'));
  });

  test('ne propose pas de laxatif avec diarrhée ou urgence abdominale', () {
    for (final detail in ['watery', 'obstruction']) {
      final result = evaluate('abdominal', {
        'abdominal_associated': 'constipation',
        'abdominal_bowel_detail': detail,
      });
      expect(result.pharmacyAdvice.join(' '), isNot(contains('laxatif')));
      if (detail == 'obstruction') {
        expect(result.selfCare, isEmpty);
        expect(result.nextSteps.first, contains('116'));
      }
    }
  });

  test('migraine étayée conserve uniquement les réponses sélectionnées', () {
    final result = evaluate('headache', {
      'headache_onset': 'usual',
      'headache_pattern': 'one_side',
      'headache_associated': 'light_only',
    });
    expect(result.matches.first.title, 'Migraine');
    expect(result.selfCare.join(' '), contains('peu éclairé'));
    expect(result.matches.first.matchedTags, isNot(contains('nausea')));
    expect(
      result.matches.first.supportingAnswers.join(' '),
      contains('La lumière me gêne, sans nausée'),
    );
    expect(result.matches.first.supportingAnswers.length, lessThanOrEqualTo(3));
  });

  test('les signes combinés gardent la trace de leurs réponses sources', () {
    final result = evaluate('skin', {'skin_sensation': 'pain|warm|swollen'});
    expect(result.matches.first.title, 'Cellulite infectieuse possible');
    expect(result.matches.first.supportingAnswers, hasLength(3));
    expect(result.summary, contains('chaude et gonflée'));
    expect(result.nextSteps.join(' '), contains('antibiotique ou un drainage'));
    expect(result.pharmacyAdvice.join(' '), isNot(contains('émollient')));
  });

  final weakEvidence =
      <({String path, Map<String, String> answers, String excluded})>[
        (
          path: 'dizziness',
          answers: {'dizziness_context': 'diabetes'},
          excluded: 'Glycémie basse',
        ),
        (
          path: 'menstrual',
          answers: {'menstrual_concern': 'irregular'},
          excluded: 'ovaires polykystiques',
        ),
        (
          path: 'respiratory',
          answers: {'respiratory_main': 'nose'},
          excluded: 'Allergie respiratoire',
        ),
        (
          path: 'skin',
          answers: {'skin_sensation': 'itch'},
          excluded: 'Dermatite',
        ),
        (path: 'skin', answers: {'skin_sensation': 'pain'}, excluded: 'Abcès'),
        (
          path: 'headache',
          answers: {'headache_associated': 'nausea_only'},
          excluded: 'Migraine',
        ),
        (
          path: 'headache',
          answers: {'headache_context': 'stress'},
          excluded: 'Céphalée de tension',
        ),
      ];
  for (final scenario in weakEvidence) {
    test('un indice isolé ne suffit pas pour ${scenario.excluded}', () {
      final result = evaluate(scenario.path, scenario.answers);
      expect(
        result.matches.map((m) => m.title).join(' '),
        isNot(contains(scenario.excluded)),
      );
    });
  }

  test('un reflux associé à une hémorragie ne masque pas l’urgence', () {
    final result = evaluate('abdominal', {
      'abdominal_upper_pattern': 'burning',
      'abdominal_associated': 'blood',
    });
    expect(result.matches.first.title, 'Hémorragie digestive possible');
    expect(
      result.matches.map((m) => m.title).join(' '),
      isNot(contains('Reflux')),
    );
    expect(result.selfCare, isEmpty);
    expect(result.pharmacyAdvice.join(' '), isNot(contains('antiacide')));
  });

  test('une urgence prime sur la consigne de joindre la maternité', () {
    final result = evaluate('pregnancy', {
      'pregnancy_stage': 'late',
      'pregnancy_late_detail': 'fluid_leak',
      'pregnancy_sickness': 'fever',
    });
    expect(result.urgency, AssessmentUrgency.emergency);
    expect(result.nextSteps.first, contains('116'));
    expect(result.nextSteps.join(' '), contains('terme'));
    expect(result.selfCare, isEmpty);
  });

  test('perte des eaux seule oriente immédiatement vers la maternité', () {
    final result = evaluate('pregnancy', {
      'pregnancy_stage': 'late',
      'pregnancy_late_detail': 'fluid_leak',
    });
    expect(result.nextSteps.first, contains('maintenant votre maternité'));
    expect(result.nextSteps.join(' '), isNot(contains('Doppler')));
    expect(result.selfCare.join(' '), contains('pas de tampon'));
  });

  test('dengue conserve les précautions médicamenteuses même en urgence', () {
    for (final option in ['dengue_pattern', 'dengue_warning']) {
      final result = evaluate(
        'fever',
        {'fever_vector_detail': option},
        context: {
          'medications': ['traitement déclaré'],
        },
      );
      expect(
        result.pharmacyAdvice.join(' '),
        contains('évitez l’aspirine et l’ibuprofène'),
      );
      if (option == 'dengue_pattern') {
        expect(
          result.nextSteps.join(' '),
          contains('après la baisse de la fièvre'),
        );
      }
    }
    final otherFever = evaluate('fever', {'fever_course': 'days'});
    expect(otherFever.pharmacyAdvice.join(' '), isNot(contains('dengue')));
  });

  for (final context in <Map<String, dynamic>>[
    {'pregnancy': true},
    {'age': 7},
    {'ageMonths': 18},
    {
      'allergies': ['allergie déclarée'],
    },
    {
      'medications': ['traitement déclaré'],
    },
    {
      'conditions': ['maladie rénale déclarée'],
    },
  ]) {
    test('pharmacie prudente avec ${context.keys.single}', () {
      final result = evaluate('abdominal', {
        'abdominal_upper_pattern': 'burning',
      }, context: context);
      expect(result.pharmacyAdvice.single, contains('sans avis médical'));
      expect(result.pharmacyAdvice.join(' '), isNot(contains('antiacide')));
    });
  }

  test(
    'traitement urinaire inefficace produit une réévaluation spécifique',
    () {
      final result = evaluate('urinary', {
        'urinary_main': 'burning',
        'urinary_treatment_response': 'not_improving',
      });
      expect(result.urgency, AssessmentUrgency.consultationToday);
      expect(result.nextSteps.join(' '), contains('après 48 heures'));
      expect(result.nextSteps.join(' '), contains('date de début'));
      expect(result.summary, contains('sans amélioration'));
    },
  );

  test('aucune réponse ne produit pas une fausse réassurance', () {
    for (final pathway in assessmentPathways) {
      final result = engine.evaluate(pathway, {});
      expect(result.urgency, AssessmentUrgency.consultationSoon);
      expect(result.matches.single.compatibility, 0);
      expect(result.matches.single.compatibilityLabel, 'À préciser');
      expect(result.summary, isNot(contains('Aucun signe d’alerte')));
    }
  });

  test('alerte sans hypothèse précise garde une orientation urgente', () {
    final result = evaluate('abdominal', {
      'abdominal_warning': 'diabetes_vomit',
    });
    expect(result.urgency, AssessmentUrgency.emergency);
    expect(result.nextSteps.first, contains('116'));
    expect(result.selfCare, isEmpty);
    expect(result.summary, contains('immédiate'));
  });

  test('résultat personnalisé survit à une sauvegarde et un rechargement', () {
    final result = evaluate('skin', {'skin_sensation': 'pain|warm|swollen'});
    final restored = AssessmentResult.fromMap(result.toMap());
    expect(restored.toMap(), result.toMap());
    expect(restored.matches.first.supportingAnswers, hasLength(3));
  });

  test('anciens résultats sans nouvelles propriétés restent lisibles', () {
    final restored = AssessmentResult.fromMap({
      'urgency': 'consultationSoon',
      'matches': [
        {
          'title': 'Ancienne orientation',
          'explanation': 'Texte enregistré',
          'compatibility': 50,
        },
      ],
      'nextSteps': ['Consulter'],
      'selfCare': [],
      'pharmacyAdvice': [],
      'contextNotes': [],
    });
    expect(restored.summary, isNull);
    expect(restored.matches.single.supportingAnswers, isEmpty);
    expect(restored.matches.single.matchedTags, isEmpty);
    expect(restored.nextSteps, ['Consulter']);
  });
}

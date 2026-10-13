import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/diagnostic_assessment.dart';

void main() {
  const engine = AssessmentEngine();
  const ids = ['back', 'joint', 'eyes', 'dental'];

  AssessmentResult evaluate(
    String id,
    Map<String, String> answers, {
    Map<String, dynamic> context = const {},
  }) {
    final pathway = assessmentPathwayById(id)!;
    for (final entry in answers.entries) {
      final question = pathway.questionById(entry.key)!;
      for (final choice in entry.value.split('|')) {
        expect(
          question.options.map((o) => o.id),
          contains(choice),
          reason: '${entry.key}/$choice',
        );
      }
    }
    return engine.evaluate(pathway, answers, context: context);
  }

  test('quatre parcours complets, sérialisables avec leurs icônes', () {
    final pathways = ids.map((id) => assessmentPathwayById(id)!).toList();
    expect(pathways.expand((p) => p.questions), hasLength(45));
    expect(
      pathways.expand((p) => p.questions).expand((q) => q.options),
      hasLength(273),
    );
    for (final pathway in pathways) {
      final restored = assessmentPathwayFromMap(
        assessmentPathwayToMap(pathway),
        version: pathway.version,
      );
      expect(restored.icon, pathway.icon);
      expect(assessmentPathwayToMap(restored), assessmentPathwayToMap(pathway));
      expect(
        engine.nextQuestion(restored, {})!.id,
        '${pathway.id == 'eyes' ? 'eyes' : pathway.id}_warning',
      );
    }
  });

  for (final id in ids) {
    final pathway = assessmentPathwayById(id)!;
    for (final question in pathway.questions) {
      for (final option in question.options.where(
        (o) => o.urgency == AssessmentUrgency.emergency,
      )) {
        test('alerte immédiate ${question.id}/${option.id}', () {
          final result = evaluate(id, {question.id: option.id});
          expect(result.urgency, AssessmentUrgency.emergency);
          expect(result.redFlags, contains(option.label));
          expect(result.nextSteps.first, contains('116'));
          expect(result.selfCare, isEmpty);
        });
      }
    }
  }

  test('dos mécanique : activité douce sans imagerie automatique', () {
    final result = evaluate('back', {
      'back_trigger': 'lifting',
      'back_radiation': 'none',
      'back_intensity': 'mild',
      'back_evolution': 'improving',
    });
    expect(result.urgency, AssessmentUrgency.selfCare);
    expect(result.matches.first.title, contains('mécanique'));
    expect(
      result.selfCare.join(' '),
      contains('évitez le repos prolongé au lit'),
    );
    expect(result.nextSteps.join(' '), isNot(contains('radiographie')));
  });

  test('une douleur du dos isolée ne devient pas une sciatique', () {
    final result = evaluate('back', {
      'back_location': 'lower',
      'back_radiation': 'none',
    });
    expect(
      result.matches.map((m) => m.title).join(' '),
      isNot(contains('Sciatique')),
    );
  });

  test('sciatique puis faiblesse nouvelle : l’urgence prend la priorité', () {
    final mild = evaluate('back', {
      'back_radiation': 'one_leg',
      'back_leg_detail': 'below_knee|tingling',
    });
    expect(mild.matches.first.title, contains('Sciatique'));
    final urgent = evaluate('back', {
      'back_radiation': 'one_leg',
      'back_leg_detail': 'below_knee|weakness',
      'back_trigger': 'lifting',
    });
    expect(urgent.urgency, AssessmentUrgency.emergency);
    expect(urgent.matches.first.title, contains('Compression nerveuse'));
    expect(
      urgent.matches.map((m) => m.title).join(' '),
      isNot(contains('mécanique')),
    );
  });

  test('petit choc avec fragilité osseuse requiert un examen aujourd’hui', () {
    final result = evaluate('back', {
      'back_trigger': 'minor_fall',
      'back_context': 'osteoporosis',
    });
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(result.matches.first.title, contains('Lésion traumatique'));
    expect(result.matches.first.supportingAnswers, hasLength(2));
    expect(
      result.selfCare.join(' '),
      isNot(contains('Gardez une activité douce')),
    );
  });

  test('fièvre avec immunodépression et mal de dos reste urgente', () {
    final result = evaluate('back', {
      'back_associated': 'fever',
      'back_context': 'immunity',
    });
    expect(result.urgency, AssessmentUrgency.emergency);
    expect(result.matches.first.title, contains('Cause secondaire'));
  });

  test('raideur inflammatoire et douleur rénale ont des suites distinctes', () {
    final inflammatory = evaluate('back', {
      'back_duration': 'months',
      'back_associated': 'morning',
      'back_stiffness_detail': 'movement',
    });
    expect(inflammatory.matches.first.title, contains('inflammatoire'));
    expect(inflammatory.nextSteps.join(' '), contains('bilan inflammatoire'));
    final renal = evaluate('back', {
      'back_location': 'flank',
      'back_associated': 'urinary|fever',
    });
    expect(renal.urgency, AssessmentUrgency.consultationToday);
    expect(renal.matches.map((m) => m.title).join(' '), contains('rénale'));
    expect(renal.nextSteps.join(' '), contains('infection ou un calcul'));
  });

  test('une articulation chaude et gonflée est évaluée même sans fièvre', () {
    final result = evaluate('joint', {
      'joint_signs': 'hot|swollen',
      'joint_context': 'gout',
    });
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(result.matches.first.title, contains('Infection articulaire'));
    expect(
      result.matches.first.supportingAnswers.join(' '),
      contains('gonflée'),
    );
    expect(result.nextSteps.join(' '), contains('même sans fièvre'));
  });

  for (final extra in [
    {'joint_signs': 'hot|swollen|fever'},
    {'joint_signs': 'hot|swollen', 'joint_context': 'prosthesis'},
    {'joint_signs': 'hot|swollen', 'joint_context': 'procedure'},
  ]) {
    test('articulation chaude gonflée et risque associé : $extra', () {
      final result = evaluate('joint', extra);
      expect(result.urgency, AssessmentUrgency.emergency);
      expect(result.matches.first.title, contains('Infection articulaire'));
      expect(result.nextSteps.join(' '), contains('à l’hôpital'));
    });
  }

  test('arthrose non déduite de la localisation ou proposée à un enfant', () {
    final isolated = evaluate('joint', {'joint_location': 'knee'});
    expect(
      isolated.matches.map((m) => m.title).join(' '),
      isNot(contains('Arthrose')),
    );
    final child = evaluate(
      'joint',
      {
        'joint_trigger': 'walking',
        'joint_duration': 'months',
        'joint_stiffness': 'brief',
      },
      context: {'age': 8},
    );
    expect(
      child.matches.map((m) => m.title).join(' '),
      isNot(contains('Arthrose')),
    );
    expect(child.pharmacyAdvice.single, contains('sans avis médical'));
  });

  test('raideur articulaire prolongée avec symétrie oriente un bilan', () {
    final result = evaluate('joint', {
      'joint_distribution': 'symmetric',
      'joint_stiffness': 'long',
    });
    expect(result.matches.first.title, contains('Rhumatisme inflammatoire'));
    expect(result.nextSteps.join(' '), contains('raideur matinale'));
  });

  test(
    'sécheresse oculaire avec vision conservée reçoit des conseils ciblés',
    () {
      final result = evaluate('eyes', {
        'eyes_main': 'dry',
        'eyes_vision': 'normal',
        'eyes_context': 'screen',
        'eyes_surface_detail': 'blink',
        'eyes_pain': 'none',
      });
      expect(result.urgency, AssessmentUrgency.selfCare);
      expect(result.matches.first.title, contains('Sécheresse'));
      expect(result.pharmacyAdvice.join(' '), contains('larmes artificielles'));
      expect(result.selfCare.join(' '), contains('pauses d’écran'));
    },
  );

  test('rougeur seule ne suffit pas à diagnostiquer une conjonctivite', () {
    final result = evaluate('eyes', {
      'eyes_main': 'red',
      'eyes_vision': 'normal',
    });
    expect(
      result.matches.map((m) => m.title).join(' '),
      isNot(contains('Conjonctivite')),
    );
  });

  test('rougeur avec lentilles élimine la conjonctivite rassurante', () {
    final result = evaluate('eyes', {
      'eyes_main': 'red|sticky',
      'eyes_vision': 'normal',
      'eyes_context': 'lenses',
    });
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(result.matches.first.title, contains('cornée'));
    expect(
      result.matches.map((m) => m.title).join(' '),
      isNot(contains('Conjonctivite')),
    );
    expect(result.selfCare.join(' '), contains('Évitez les lentilles'));
  });

  for (final answers in [
    {'eyes_main': 'red', 'eyes_associated': 'light'},
    {'eyes_main': 'red', 'eyes_vision': 'blurred'},
    {'eyes_context': 'lenses', 'eyes_vision': 'blurred', 'eyes_pain': 'deep'},
    {'eyes_context': 'surgery', 'eyes_pain': 'deep'},
    {'eyes_main': 'swollen', 'eyes_associated': 'movement'},
    {'eyes_main': 'swollen', 'eyes_associated': 'fever'},
  ]) {
    test('association oculaire urgente : $answers', () {
      final result = evaluate('eyes', answers);
      expect(result.urgency, AssessmentUrgency.emergency);
      expect(result.selfCare, isEmpty);
      expect(
        result.pharmacyAdvice.join(' '),
        isNot(contains('larmes artificielles')),
      );
    });
  }

  test('nouveaux corps flottants nécessitent un contrôle aujourd’hui', () {
    final result = evaluate('eyes', {'eyes_vision': 'flashes'});
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(result.nextSteps.first, contains('aujourd’hui'));
    expect(result.nextSteps.join(' '), contains('rétine'));
  });

  test('œil collé du nouveau-né ne produit pas de résultat rassurant', () {
    final result = evaluate('eyes', {
      'eyes_age': 'newborn',
      'eyes_main': 'red|sticky',
      'eyes_vision': 'normal',
    });
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(
      result.matches.map((m) => m.title).join(' '),
      isNot(contains('Conjonctivite')),
    );
    expect(result.nextSteps.join(' '), contains('nouveau-né'));
  });

  test(
    'projection chimique : premier secours immédiat, persisté dans le résultat',
    () {
      final result = evaluate('eyes', {'eyes_warning': 'chemical'});
      expect(result.immediateActions.single, contains('au moins 20 minutes'));
      final restored = AssessmentResult.fromMap(result.toMap());
      expect(restored.immediateActions, result.immediateActions);
      expect(restored.toMap(), result.toMap());
      final penetrating = evaluate('eyes', {
        'eyes_warning': 'penetrating|chemical',
      });
      expect(penetrating.immediateActions.single, contains('Ne retirez pas'));
      expect(penetrating.immediateActions.join(' '), isNot(contains('Rincez')));
    },
  );

  test(
    'sensibilité brève et douleur persistante de la dent sont distinguées',
    () {
      final sensitivity = evaluate('dental', {
        'dental_pain': 'brief_cold',
        'dental_intensity': 'mild',
      });
      expect(sensitivity.urgency, AssessmentUrgency.consultationSoon);
      expect(sensitivity.matches.first.title, contains('Sensibilité'));
      expect(sensitivity.nextSteps.first, contains('dentiste'));
      final lingering = evaluate('dental', {
        'dental_pain': 'brief_cold|lingering',
      });
      expect(lingering.urgency, AssessmentUrgency.consultationToday);
      expect(lingering.matches.first.title, contains('pulpe'));
      expect(
        lingering.matches.map((m) => m.title).join(' '),
        isNot(contains('Sensibilité')),
      );
    },
  );

  test('abcès local et extension menaçante n’ont pas la même orientation', () {
    final local = evaluate('dental', {'dental_associated': 'swollen_gum|pus'});
    expect(local.urgency, AssessmentUrgency.consultationToday);
    expect(local.nextSteps.first, contains('dentiste aujourd’hui'));
    expect(local.nextSteps.join(' '), contains('antibiotique seul'));
    final spreading = evaluate('dental', {
      'dental_associated': 'pus',
      'dental_warning': 'eye_neck',
    });
    expect(spreading.urgency, AssessmentUrgency.emergency);
    expect(spreading.nextSteps.first, contains('116'));
    expect(spreading.selfCare, isEmpty);
  });

  test(
    'dent expulsée : dentiste immédiatement, avec distinction dent de lait',
    () {
      final result = evaluate('dental', {
        'dental_warning': 'knocked_out',
        'dental_trauma_detail': 'permanent',
      });
      expect(result.urgency, AssessmentUrgency.consultationToday);
      expect(result.nextSteps.first, contains('dentiste immédiatement'));
      expect(result.immediateActions.join(' '), contains('récipient de lait'));
      final baby = evaluate('dental', {
        'dental_warning': 'knocked_out',
        'dental_trauma_detail': 'baby',
      });
      expect(
        baby.immediateActions.join(' '),
        contains('Ne remettez pas une dent de lait'),
      );
      expect(
        baby.immediateActions.join(' '),
        isNot(contains('récipient de lait')),
      );
    },
  );

  test('l’urgence respiratoire prime sur la conservation d’une dent', () {
    final result = evaluate('dental', {
      'dental_warning': 'knocked_out|breathing',
    });
    expect(result.urgency, AssessmentUrgency.emergency);
    expect(result.nextSteps.first, contains('116'));
    expect(result.immediateActions, isEmpty);
  });

  test('douleur après extraction oriente vers le dentiste qui a soigné', () {
    final result = evaluate('dental', {
      'dental_duration': 'procedure',
      'dental_procedure_detail': 'worse',
    });
    expect(result.urgency, AssessmentUrgency.consultationToday);
    expect(result.matches.first.title, contains('après extraction'));
    expect(
      result.nextSteps.join(' '),
      contains('dentiste qui a réalisé le soin'),
    );
  });

  test(
    'allaitement ne déclare pas une grossesse et limite les médicaments',
    () {
      final pathway = assessmentPathwayById('dental')!;
      const answers = {'dental_context': 'breastfeeding'};
      expect(
        engine.answerTags(pathway, answers),
        isNot(contains('pregnancy_possible')),
      );
      expect(
        evaluate('dental', answers).pharmacyAdvice.single,
        contains('sans avis médical'),
      );
    },
  );

  test('correction de la douleur irradiée retire uniquement sa branche', () {
    final pathway = assessmentPathwayById('back')!;
    final answers = engine.reconcileAnswers(pathway, {
      'back_radiation': 'none',
      'back_leg_detail': 'below_knee',
      'back_associated': 'morning',
      'back_stiffness_detail': 'movement',
    });
    expect(answers, isNot(contains('back_leg_detail')));
    expect(answers['back_stiffness_detail'], 'movement');
  });
}

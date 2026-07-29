import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/diagnostic_assessment.dart';
import 'package:i_entier/diagnostic_assessment_page.dart';

class _FakeAssessmentRepository implements SymptomAssessmentRepository {
  final List<SymptomAssessmentRecord> saved = [];
  Map<String, dynamic> context = const {};
  bool failSaves = false;

  @override
  Future<Map<String, dynamic>> loadAuthorizedContext({
    required String patientId,
    required Map<String, dynamic> patientProfile,
    required Map<String, bool> consents,
  }) async => context;

  @override
  Future<void> save(SymptomAssessmentRecord assessment) async {
    if (failSaves) throw StateError('offline');
    saved.add(assessment);
  }

  @override
  Stream<List<SymptomAssessmentRecord>> watch(String patientId) =>
      Stream.value(saved);
}

void main() {
  const engine = AssessmentEngine();

  test('présente les scores comme compatibilité et détecte une urgence', () {
    final pathway = assessmentPathwayById('abdominal')!;
    final result = engine.evaluate(pathway, const {
      'abdominal_onset': 'sudden',
      'abdominal_location': 'lower_right',
      'abdominal_intensity': 'severe',
    });

    expect(result.urgency, AssessmentUrgency.emergency);
    expect(
      result.matches.first.title,
      'Douleur abdominale aiguë sévère à évaluer en urgence',
    );
    expect(
      result.matches.map((item) => item.title),
      contains('Appendicite possible'),
    );
    expect(result.matches.first.compatibility, lessThanOrEqualTo(92));
    expect(result.matches.first.compatibilityLabel, 'Compatibilité modérée');
    expect(
      result.toMap()['disclaimer'],
      contains('ni une probabilité ni un diagnostic'),
    );
  });

  test('reconnaît un ensemble de réponses compatible avec une migraine', () {
    final pathway = assessmentPathwayById('headache')!;
    final result = engine.evaluate(pathway, const {
      'headache_onset': 'usual',
      'headache_pattern': 'one_side',
      'headache_associated': 'light_nausea',
      'headache_neuro': 'none',
      'headache_context': 'none',
    });

    expect(result.urgency, AssessmentUrgency.selfCare);
    expect(result.matches.first.title, 'Migraine');
    expect(result.matches.first.compatibility, greaterThan(70));
  });

  test('recharge sans perte un parcours publié par l’administration', () {
    final original = assessmentPathwayById('respiratory')!;
    final restored = assessmentPathwayFromMap(
      assessmentPathwayToMap(original),
      version: 4,
    );

    expect(restored.id, original.id);
    expect(restored.version, 4);
    expect(restored.title, original.title);
    expect(restored.color, original.color);
    expect(restored.questions, hasLength(original.questions.length));
    expect(
      restored.questions.first.options.map((option) => option.id),
      original.questions.first.options.map((option) => option.id),
    );
    expect(
      restored.possibilities.map((item) => item.title),
      original.possibilities.map((item) => item.title),
    );
    expect(restored.pharmacyAdvice, original.pharmacyAdvice);
  });

  test('retire les suggestions médicamenteuses pendant la grossesse', () {
    final pathway = assessmentPathwayById('headache')!;
    final result = engine.evaluate(
      pathway,
      const {
        'headache_onset': 'gradual',
        'headache_pattern': 'band',
        'headache_associated': 'neck_tension',
        'headache_neuro': 'none',
        'headache_context': 'none',
      },
      context: const {'pregnancy': true},
    );

    expect(result.pharmacyAdvice, hasLength(1));
    expect(result.pharmacyAdvice.single, contains('sans avis médical'));
    expect(result.contextNotes, isNotEmpty);
  });

  test('ouvre uniquement la branche abdominale rendue pertinente', () {
    final pathway = assessmentPathwayById('abdominal')!;
    const answers = {
      'abdominal_onset': 'hours',
      'abdominal_location': 'upper',
      'abdominal_intensity': 'mild',
      'abdominal_associated': 'none',
      'abdominal_drink': 'yes',
      'abdominal_context': 'none',
    };

    expect(
      engine
          .nextQuestion(pathway, answers, afterQuestionId: 'abdominal_context')
          ?.id,
      'abdominal_upper_pattern',
    );
    expect(
      pathway
          .questionById('abdominal_urinary_detail')!
          .appliesTo(engine.answerTags(pathway, answers)),
      isFalse,
    );
  });

  test('reconnaît les ramifications cliniques enrichies', () {
    final cases =
        <
          ({
            String pathwayId,
            Map<String, String> answers,
            String expected,
            AssessmentUrgency urgency,
          })
        >[
          (
            pathwayId: 'abdominal',
            answers: const {
              'abdominal_location': 'diffuse',
              'abdominal_bowel_detail': 'obstruction',
            },
            expected: 'Occlusion intestinale possible',
            urgency: AssessmentUrgency.emergency,
          ),
          (
            pathwayId: 'headache',
            answers: const {
              'headache_pattern': 'one_side',
              'headache_one_sided_features': 'cluster',
            },
            expected: 'Algie vasculaire de la face possible',
            urgency: AssessmentUrgency.consultationSoon,
          ),
          (
            pathwayId: 'menstrual',
            answers: const {
              'menstrual_concern': 'irregular',
              'menstrual_cycle_context': 'acne_hair',
            },
            expected: 'Syndrome des ovaires polykystiques possible',
            urgency: AssessmentUrgency.consultationSoon,
          ),
          (
            pathwayId: 'respiratory',
            answers: const {
              'respiratory_duration': 'weeks',
              'respiratory_chronic_detail': 'weight_loss',
            },
            expected: 'Tuberculose ou autre infection prolongée à exclure',
            urgency: AssessmentUrgency.consultationToday,
          ),
          (
            pathwayId: 'skin',
            answers: const {
              'skin_sensation': 'blister',
              'skin_blister_detail': 'one_side_band',
            },
            expected: 'Zona possible',
            urgency: AssessmentUrgency.consultationToday,
          ),
          (
            pathwayId: 'pregnancy',
            answers: const {
              'pregnancy_stage': 'postpartum',
              'pregnancy_postpartum_detail': 'heavy_bleeding',
            },
            expected: 'Hémorragie après l’accouchement possible',
            urgency: AssessmentUrgency.emergency,
          ),
        ];

    for (final testCase in cases) {
      final result = engine.evaluate(
        assessmentPathwayById(testCase.pathwayId)!,
        testCase.answers,
      );
      expect(
        result.matches.first.title,
        testCase.expected,
        reason: testCase.pathwayId,
      );
      expect(result.urgency, testCase.urgency, reason: testCase.pathwayId);
    }
  });

  test('oriente les nouveaux parcours de malaise', () {
    final cases =
        <
          ({
            String pathwayId,
            Map<String, String> answers,
            String expected,
            AssessmentUrgency urgency,
          })
        >[
          (
            pathwayId: 'chest',
            answers: const {
              'chest_now': 'stable',
              'chest_character': 'movement',
              'chest_context': 'injury',
            },
            expected: 'Douleur de la paroi thoracique',
            urgency: AssessmentUrgency.consultationSoon,
          ),
          (
            pathwayId: 'urinary',
            answers: const {
              'urinary_main': 'burning',
              'urinary_red_flags': 'fever_flank',
            },
            expected: 'Infection rénale possible',
            urgency: AssessmentUrgency.consultationToday,
          ),
          (
            pathwayId: 'dizziness',
            answers: const {
              'dizziness_now': 'stable',
              'dizziness_type': 'spinning',
              'dizziness_onset': 'head_position',
              'dizziness_vertigo_detail': 'seconds_position',
            },
            expected: 'Vertige positionnel possible',
            urgency: AssessmentUrgency.selfCare,
          ),
          (
            pathwayId: 'fever',
            answers: const {
              'fever_course': 'days',
              'fever_emergency': 'altered_consciousness',
            },
            expected: 'Infection sévère ou sepsis possible',
            urgency: AssessmentUrgency.emergency,
          ),
        ];

    for (final testCase in cases) {
      final result = engine.evaluate(
        assessmentPathwayById(testCase.pathwayId)!,
        testCase.answers,
      );
      expect(
        result.matches.first.title,
        testCase.expected,
        reason: testCase.pathwayId,
      );
      expect(result.urgency, testCase.urgency, reason: testCase.pathwayId);
    }
  });

  test('ouvre une branche spécialisée dans un nouveau parcours', () {
    final pathway = assessmentPathwayById('chest')!;
    const answers = {
      'chest_now': 'stable',
      'chest_character': 'palpitations',
      'chest_timing': 'seconds',
      'chest_associated': 'none',
      'chest_context': 'none',
    };

    expect(
      engine
          .nextQuestion(pathway, answers, afterQuestionId: 'chest_context')
          ?.id,
      'chest_palpitations_detail',
    );
  });

  test('évite les possibilités alarmantes sans leurs signes discriminants', () {
    final pregnancyResult = engine
        .evaluate(assessmentPathwayById('pregnancy')!, const {
          'pregnancy_stage': 'early',
          'pregnancy_bleeding': 'none',
          'pregnancy_pressure': 'none',
          'pregnancy_breathing': 'normal',
          'pregnancy_baby': 'too_early',
          'pregnancy_sickness': 'none',
          'pregnancy_early_detail': 'none',
        });
    final respiratoryResult = engine.evaluate(
      assessmentPathwayById('respiratory')!,
      const {'respiratory_duration': 'weeks'},
    );

    expect(
      pregnancyResult.matches.map((item) => item.title),
      isNot(contains('Grossesse extra-utérine possible')),
    );
    expect(
      respiratoryResult.matches.map((item) => item.title),
      isNot(contains('Tuberculose ou autre infection prolongée à exclure')),
    );
  });

  test('priorise les drapeaux rouges de fièvre et du jeune nourrisson', () {
    final pathway = assessmentPathwayById('fever')!;
    final infant = engine.evaluate(pathway, const {
      'fever_age': 'under_3_months',
      'fever_temperature': '38',
      'fever_course': 'today',
    });
    final meningeal = engine.evaluate(pathway, const {
      'fever_age': '5_to_64_years',
      'fever_temperature': '38',
      'fever_emergency': 'meningeal',
    });

    expect(infant.urgency, AssessmentUrgency.emergency);
    expect(
      infant.matches.first.title,
      'Fièvre du jeune nourrisson à évaluer immédiatement',
    );
    expect(infant.redFlags, isNotEmpty);
    expect(meningeal.urgency, AssessmentUrgency.emergency);
    expect(
      meningeal.matches.first.title,
      'Méningite ou maladie méningococcique possible',
    );
    expect(
      meningeal.matches.map((item) => item.title),
      isNot(contains('Infection virale possible')),
    );
  });

  test('combine plusieurs réponses sans masquer le signe le plus urgent', () {
    final pathway = assessmentPathwayById('fever')!;
    final result = engine.evaluate(pathway, const {
      'fever_age': '5_to_64_years',
      'fever_temperature': '39',
      'fever_emergency': 'meningeal|shock_pattern',
      'fever_focus': 'respiratory|skin',
    });

    expect(
      engine.answerTags(pathway, const {
        'fever_emergency': 'meningeal|shock_pattern',
      }),
      containsAll({'meningeal_pattern', 'shock_pattern', 'sepsis_pattern'}),
    );
    expect(result.urgency, AssessmentUrgency.emergency);
    expect(result.redFlags, hasLength(2));
    expect(result.matches.first.urgentReason, isTrue);
  });

  test('applique les garde-fous grossesse, urinaire et vertige aigu', () {
    final mildPregnancyHeadache = engine
        .evaluate(assessmentPathwayById('headache')!, const {
          'headache_onset': 'usual',
          'headache_pattern': 'band',
          'headache_context': 'pregnant',
          'headache_pregnancy_detail': 'mild_improving',
        });
    final reducedMovement = engine.evaluate(
      assessmentPathwayById('pregnancy')!,
      const {'pregnancy_stage': 'late', 'pregnancy_baby': 'reduced'},
    );
    final pregnancyUti = engine
        .evaluate(assessmentPathwayById('urinary')!, const {
          'urinary_main': 'burning',
          'urinary_pattern': 'cloudy|small_frequent',
          'urinary_context': 'pregnancy',
        });
    final infectedObstruction = engine.evaluate(
      assessmentPathwayById('urinary')!,
      const {
        'urinary_red_flags': 'fever_flank',
        'urinary_context': 'stone_obstruction',
      },
    );
    final acuteVestibular = engine
        .evaluate(assessmentPathwayById('dizziness')!, const {
          'dizziness_type': 'spinning',
          'dizziness_onset': 'sudden',
          'dizziness_balance_detail': 'new_unsteadiness',
        });

    expect(mildPregnancyHeadache.urgency, AssessmentUrgency.consultationSoon);
    expect(reducedMovement.urgency, AssessmentUrgency.consultationToday);
    expect(reducedMovement.nextSteps.first, contains('maternité'));
    expect(pregnancyUti.urgency, AssessmentUrgency.consultationToday);
    expect(infectedObstruction.urgency, AssessmentUrgency.emergency);
    expect(
      infectedObstruction.matches.first.title,
      'Obstruction urinaire infectée à exclure en urgence',
    );
    expect(acuteVestibular.urgency, AssessmentUrgency.emergency);
    expect(
      acuteVestibular.matches.first.title,
      'Cause neurologique urgente possible',
    );
  });

  test('ne laisse pas une cause bénigne masquer une urgence abdominale', () {
    final pathway = assessmentPathwayById('abdominal')!;
    final thoracic = engine.evaluate(pathway, const {
      'abdominal_location': 'upper',
      'abdominal_upper_pattern': 'chest',
    });
    final torsion = engine.evaluate(pathway, const {
      'abdominal_context': 'testicular_pain',
    });

    expect(thoracic.urgency, AssessmentUrgency.emergency);
    expect(
      thoracic.matches.first.title,
      'Urgence cardiaque ou thoracique possible',
    );
    expect(
      thoracic.matches.map((item) => item.title),
      isNot(contains('Reflux, gastrite ou indigestion')),
    );
    expect(torsion.urgency, AssessmentUrgency.emergency);
    expect(torsion.matches.first.title, 'Torsion testiculaire possible');
  });

  test('couvre les nouveaux garde-fous respiratoires et cutanés', () {
    final respiratory = assessmentPathwayById('respiratory')!;
    final infantFever = engine.evaluate(respiratory, const {
      'respiratory_age': 'under_3_months',
      'respiratory_red_flags': 'fever',
    });
    final clotRisk = engine.evaluate(respiratory, const {
      'respiratory_age': 'adult',
      'respiratory_main': 'dry_cough|breathlessness',
      'respiratory_cough_detail': 'breath_pain',
      'respiratory_context': 'clot_risk',
    });
    final cancerTreatment = engine.evaluate(respiratory, const {
      'respiratory_age': 'adult',
      'respiratory_context': 'active_cancer_treatment',
    });
    final skinLesion = engine.evaluate(assessmentPathwayById('skin')!, const {
      'skin_appearance': 'changing_lesion',
      'skin_changing_lesion_detail': 'mole_change',
    });
    final majorBurn = engine.evaluate(assessmentPathwayById('skin')!, const {
      'skin_sensation': 'blister',
      'skin_blister_detail': 'major_burn',
    });

    expect(infantFever.urgency, AssessmentUrgency.emergency);
    expect(
      infantFever.matches.first.title,
      'Fièvre du jeune nourrisson à évaluer immédiatement',
    );
    expect(clotRisk.urgency, AssessmentUrgency.emergency);
    expect(
      clotRisk.matches.first.title,
      'Embolie pulmonaire à exclure en urgence',
    );
    expect(cancerTreatment.urgency, AssessmentUrgency.emergency);
    expect(
      cancerTreatment.matches.first.title,
      'Neutropénie fébrile ou infection grave sous traitement possible',
    );
    expect(skinLesion.urgency, AssessmentUrgency.consultationSoon);
    expect(skinLesion.matches.first.title, 'Lésion cutanée à faire examiner');
    expect(majorBurn.urgency, AssessmentUrgency.emergency);
    expect(
      majorBurn.matches.first.title,
      'Brûlure grave à prendre en charge immédiatement',
    );
  });

  test('couvre les alertes maternelles tardives, rénales et de syncope', () {
    final latePostpartum = engine
        .evaluate(assessmentPathwayById('pregnancy')!, const {
          'pregnancy_stage': 'postpartum_late',
          'pregnancy_postpartum_detail': 'mental_health',
        });
    final caudaEquina = engine.evaluate(
      assessmentPathwayById('urinary')!,
      const {'urinary_red_flags': 'saddle_weakness'},
    );
    final cardiacSyncope = engine.evaluate(
      assessmentPathwayById('dizziness')!,
      const {
        'dizziness_type': 'faint',
        'dizziness_faint_detail': 'cardiac_risk',
      },
    );
    final feverPathway = assessmentPathwayById('fever')!;
    const vectorResidence = {'fever_exposure': 'resident_vector_area'};

    expect(latePostpartum.urgency, AssessmentUrgency.emergency);
    expect(
      latePostpartum.matches.map((item) => item.title),
      contains('Signe maternel urgent dans l’année après l’accouchement'),
    );
    expect(caudaEquina.urgency, AssessmentUrgency.emergency);
    expect(
      caudaEquina.matches.first.title,
      'Compression des nerfs lombaires à exclure',
    );
    expect(cardiacSyncope.urgency, AssessmentUrgency.consultationToday);
    expect(
      cardiacSyncope.matches.first.title,
      'Cause cardiaque du malaise possible',
    );
    expect(
      engine
          .nextQuestion(
            feverPathway,
            vectorResidence,
            afterQuestionId: 'fever_exposure',
          )
          ?.id,
      'fever_vector_detail',
    );
  });

  test('n’invente plus les signes urinaires non sélectionnés', () {
    final pathway = assessmentPathwayById('urinary')!;
    final tags = engine.answerTags(pathway, const {
      'urinary_pattern': 'cloudy',
    });

    expect(tags, contains('cloudy_urine'));
    expect(tags, isNot(contains('urine_odor')));
    expect(tags, isNot(contains('small_frequent_voids')));
  });

  test('rejette un niveau d’urgence publié inconnu', () {
    final raw = assessmentPathwayToMap(assessmentPathwayById('skin')!);
    final firstQuestion = (raw['questions'] as List).first as Map;
    final firstOption = (firstQuestion['options'] as List).first as Map;
    firstOption['urgency'] = 'critical';
    final missingUrgency = assessmentPathwayToMap(
      assessmentPathwayById('skin')!,
    );
    final missingQuestion = (missingUrgency['questions'] as List).first as Map;
    final missingOption = (missingQuestion['options'] as List).first as Map
      ..remove('urgency');
    expect(missingOption.containsKey('urgency'), isFalse);
    final futureSchema = assessmentPathwayToMap(assessmentPathwayById('skin')!)
      ..['schemaVersion'] = 99;

    expect(
      () => assessmentPathwayFromMap(raw),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => assessmentPathwayFromMap(missingUrgency),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => assessmentPathwayFromMap(futureSchema),
      throwsA(isA<FormatException>()),
    );
  });

  test('sérialise les branches enrichies et la version locale', () {
    final original = assessmentPathwayById('skin')!;
    final restored = assessmentPathwayFromMap(
      assessmentPathwayToMap(original),
      version: original.version,
    );

    expect(original.version, 3);
    expect(
      restored.questionById('skin_blister_detail')!.requiredTags,
      contains('branch_skin_blister'),
    );
    expect(restored.questionById('skin_emergency')!.allowMultiple, isTrue);
    expect(
      restored.possibilities.map((item) => item.title),
      contains('Zona possible'),
    );
  });

  test(
    'conserve le catalogue enrichi face à une publication plus ancienne',
    () {
      final bundled = assessmentPathwayById('abdominal')!;
      final older = assessmentPathwayFromMap(
        assessmentPathwayToMap(bundled),
        version: 1,
      );
      final equalVersion = assessmentPathwayFromMap({
        ...assessmentPathwayToMap(bundled),
        'title': 'Parcours abdominal révisé',
      }, version: 3);
      final newer = assessmentPathwayFromMap({
        ...assessmentPathwayToMap(bundled),
        'title': 'Parcours abdominal révisé v4',
      }, version: 4);

      expect(
        mergeNewestAssessmentPathways([bundled], [older]).single.version,
        3,
      );
      expect(
        mergeNewestAssessmentPathways([bundled], [equalVersion]).single.title,
        bundled.title,
      );
      expect(
        mergeNewestAssessmentPathways([bundled], [newer]).single.title,
        'Parcours abdominal révisé v4',
      );
    },
  );

  test(
    'le catalogue enrichi reste cohérent et chaque branche est atteignable',
    () {
      final questionCount = assessmentPathways.fold<int>(
        0,
        (total, pathway) => total + pathway.questions.length,
      );
      final possibilityCount = assessmentPathways.fold<int>(
        0,
        (total, pathway) => total + pathway.possibilities.length,
      );

      expect(assessmentPathways, hasLength(10));
      expect(questionCount, greaterThanOrEqualTo(84));
      expect(possibilityCount, greaterThanOrEqualTo(103));

      final forcedBranchQuestions = assessmentPathways
          .expand(
            (pathway) => pathway.questions.map(
              (question) => (pathway: pathway, question: question),
            ),
          )
          .where(
            (item) =>
                item.question.requiredTags.isNotEmpty &&
                item.question.options.every((option) => option.tags.isNotEmpty),
          )
          .map((item) => '${item.pathway.id}/${item.question.id}')
          .toList();
      expect(
        forcedBranchQuestions,
        isEmpty,
        reason:
            'Une question conditionnelle doit toujours permettre de répondre '
            '« aucun/autre » sans fabriquer un signe clinique.',
      );

      for (final pathway in assessmentPathways) {
        final questionIds = pathway.questions.map((item) => item.id).toList();
        expect(questionIds.toSet(), hasLength(questionIds.length));
        final availableTags = pathway.questions
            .expand((question) => question.options)
            .expand((option) => option.tags)
            .toSet();
        for (final question in pathway.questions) {
          final optionIds = question.options.map((item) => item.id).toList();
          expect(optionIds.toSet(), hasLength(optionIds.length));
          expect(
            availableTags,
            containsAll(question.requiredTags),
            reason: '${pathway.id}/${question.id}',
          );
        }
      }
    },
  );

  testWidgets(
    'alerte en urgence et laisse le patient terminer le questionnaire',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 980));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeAssessmentRepository();
      String? spoken;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DiagnosticAssessmentPage(
            patientId: 'patient-test',
            patientProfile: const {},
            repository: repository,
            assessmentStream: Stream.value(const []),
            onSpeak: (text) async => spoken = text,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Mes évaluations'), findsOneWidget);
      await tester.tap(find.byKey(const Key('assessment-start')));
      await tester.pumpAndSettle();
      expect(find.text('Vos données, votre choix'), findsOneWidget);
      expect(
        find.textContaining('ne remplace pas un professionnel'),
        findsOneWidget,
      );

      await tester.drag(find.byType(Scrollable).last, const Offset(0, -320));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent-understood')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('consent-continue')));
      await tester.tap(find.byKey(const Key('consent-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Que ressentez-vous ?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pathway-abdominal')));
      await tester.pumpAndSettle();
      expect(
        find.text('Depuis quand avez-vous mal au ventre ?'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('answer-abdominal_onset-sudden')));
      await tester.tap(find.byKey(const Key('assessment-read-question')));
      await tester.pump();
      expect(spoken, contains('Très soudainement'));
      expect(spoken, contains('Choix sélectionné'));
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('answer-abdominal_location-lower_right')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();
      expect(repository.saved.last.currentQuestionId, 'abdominal_intensity');

      await tester.tap(
        find.byKey(const Key('answer-abdominal_intensity-severe')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();

      expect(find.text('Signe d’urgence détecté'), findsOneWidget);
      expect(
        find.byKey(const Key('assessment-emergency-stop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assessment-emergency-continue')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('assessment-emergency-continue')));
      await tester.pumpAndSettle();

      expect(
        find.text('Quel autre signe accompagne le mieux la douleur ?'),
        findsOneWidget,
      );
      expect(find.text('Plusieurs réponses possibles'), findsOneWidget);
      expect(
        find.byKey(const Key('assessment-emergency-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assessment-emergency-finish-now')),
        findsOneWidget,
      );
      expect(repository.saved.last.status, 'draft');
      expect(repository.saved.last.currentQuestionId, 'abdominal_associated');

      final associatedNone = find.byKey(
        const Key('answer-abdominal_associated-none'),
      );
      await tester.tap(
        find.byKey(const Key('answer-abdominal_associated-vomiting')),
      );
      await tester.pump();
      final associatedFever = find.byKey(
        const Key('answer-abdominal_associated-fever'),
      );
      await tester.scrollUntilVisible(
        associatedFever,
        140,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(associatedFever);
      await tester.pump();
      await tester.ensureVisible(associatedNone);
      await tester.tap(associatedNone);
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();
      expect(repository.saved.last.answers['abdominal_associated'], 'none');
      final drinkYes = find.byKey(const Key('answer-abdominal_drink-yes'));
      await tester.ensureVisible(drinkYes);
      await tester.tap(drinkYes);
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();
      final contextNone = find.byKey(
        const Key('answer-abdominal_context-none'),
      );
      await tester.scrollUntilVisible(
        contextNone,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(contextNone);
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();

      expect(find.text('Urgence médicale'), findsOneWidget);
      expect(find.byKey(const Key('assessment-call-116')), findsOneWidget);
      expect(
        find.text('Douleur abdominale aiguë sévère à évaluer en urgence'),
        findsOneWidget,
      );
      expect(repository.saved.last.status, 'completed');
      expect(repository.saved.last.answers, hasLength(6));
      expect(repository.saved.last.pathwayVersion, 3);
      expect(repository.saved.last.pathwaySnapshot['id'], 'abdominal');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'affiche l’urgence de la dernière question même si la sauvegarde échoue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 980));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pathway = assessmentPathwayById('abdominal')!;
      final now = DateTime(2026, 7, 29);
      final draft = SymptomAssessmentRecord(
        id: 'offline-last-question',
        patientId: 'patient-test',
        pathwayId: pathway.id,
        pathwayTitle: pathway.title,
        pathwayVersion: pathway.version,
        pathwaySnapshot: assessmentPathwayToMap(pathway),
        status: 'draft',
        currentQuestionId: 'abdominal_bowel_detail',
        answers: const {
          'abdominal_onset': 'hours',
          'abdominal_location': 'diffuse',
          'abdominal_intensity': 'mild',
          'abdominal_associated': 'diarrhea',
          'abdominal_drink': 'yes',
          'abdominal_context': 'none',
        },
        consents: const {'understood': true},
        contextSnapshot: const {},
        result: null,
        startedAt: now,
        updatedAt: now,
        completedAt: null,
      );
      final repository = _FakeAssessmentRepository()..failSaves = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DiagnosticAssessmentPage(
            patientId: 'patient-test',
            patientProfile: const {},
            repository: repository,
            assessmentStream: Stream.value([draft]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(pathway.title));
      await tester.pumpAndSettle();

      expect(
        find.text('Comment votre transit a-t-il changé ?'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('answer-abdominal_bowel_detail-obstruction')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('assessment-confirm-answer')));
      await tester.pumpAndSettle();

      expect(find.text('Signe d’urgence détecté'), findsOneWidget);
      expect(
        find.byKey(const Key('assessment-emergency-call')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assessment-emergency-continue')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('assessment-emergency-stop')));
      await tester.pumpAndSettle();

      expect(find.text('Urgence médicale'), findsOneWidget);
      expect(find.byKey(const Key('assessment-call-116')), findsOneWidget);
      expect(find.text('Occlusion intestinale possible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

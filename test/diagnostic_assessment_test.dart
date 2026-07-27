import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/diagnostic_assessment.dart';
import 'package:i_entier/diagnostic_assessment_page.dart';

class _FakeAssessmentRepository implements SymptomAssessmentRepository {
  final List<SymptomAssessmentRecord> saved = [];
  Map<String, dynamic> context = const {};

  @override
  Future<Map<String, dynamic>> loadAuthorizedContext({
    required String patientId,
    required Map<String, dynamic> patientProfile,
    required Map<String, bool> consents,
  }) async => context;

  @override
  Future<void> save(SymptomAssessmentRecord assessment) async {
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
    expect(result.matches.first.title, 'Appendicite possible');
    expect(result.matches.first.compatibility, lessThanOrEqualTo(92));
    expect(
      result.toMap()['disclaimer'],
      contains('pas une probabilité diagnostique'),
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

  testWidgets(
    'demande le consentement, lit les choix et interrompt sur une urgence',
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

      expect(find.text('Urgence médicale'), findsOneWidget);
      expect(find.byKey(const Key('assessment-call-116')), findsOneWidget);
      expect(find.text('Appendicite possible'), findsOneWidget);
      expect(repository.saved.last.status, 'completed');
      expect(repository.saved.last.answers, hasLength(3));
      expect(repository.saved.last.pathwayVersion, 1);
      expect(repository.saved.last.pathwaySnapshot['id'], 'abdominal');
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/preventive_medicine_page.dart';

void main() {
  test('personnalise le plan selon le profil médical', () {
    final plan = buildPreventivePlan({
      'sex': 'Femme',
      'birthDate': DateTime(1980, 4, 12),
      'pregnancyStatus': 'Oui',
      'medicalConditions': ['Hypertension'],
    }, now: DateTime(2026, 7, 18));

    expect(plan.map((item) => item.id), contains('prenatal-care'));
    expect(plan.map((item) => item.id), contains('breast-awareness'));
    expect(plan.map((item) => item.id), contains('breast-screening'));
    expect(plan.map((item) => item.id), contains('cervical-screening'));
    expect(plan.map((item) => item.id), contains('colorectal-screening'));
    expect(plan.map((item) => item.id), contains('known-condition-follow-up'));
  });

  test('propose une décision partagée sur la prostate au bon âge', () {
    final plan = buildPreventivePlan({
      'sex': 'Homme',
      'birthDate': DateTime(1966, 3, 2),
    }, now: DateTime(2026, 7, 18));

    expect(plan.map((item) => item.id), contains('prostate-screening'));
    expect(plan.map((item) => item.id), contains('colorectal-screening'));
    expect(plan.map((item) => item.id), isNot(contains('breast-awareness')));
  });

  testWidgets('affiche le plan, les échéances et le carnet privé', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final records = [
      PreventiveCareRecord(
        id: 'record-1',
        category: PreventiveCareCategory.vaccine,
        title: 'Vérification du carnet vaccinal',
        planItemId: 'vaccine-record',
        completedAt: DateTime(2026, 6, 1),
        nextDueAt: DateTime(2026, 12, 1),
        provider: 'Centre de santé',
      ),
    ];
    final reminders = [
      PreventiveCareReminder(
        id: 'reminder-1',
        category: PreventiveCareCategory.checkup,
        title: 'Faire mon prochain check-up',
        planItemId: 'preventive-review',
        dueAt: DateTime(2026, 8, 18),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: {'sex': 'Femme', 'birthDate': DateTime(1990, 2, 10)},
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(records),
          reminderStream: Stream.value(reminders),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Médecine préventive'), findsOneWidget);
    expect(find.text('Mon plan de prévention'), findsOneWidget);
    expect(
      find.text('Prévention et détection précoce des cancers'),
      findsOneWidget,
    );
    expect(
      find.text('Connaître l’aspect habituel de mes seins'),
      findsOneWidget,
    );
    expect(find.text('Parler du dépistage du col de l’utérus'), findsOneWidget);
    expect(find.text('Mes rappels'), findsOneWidget);
    expect(find.text('Faire mon prochain check-up'), findsOneWidget);
    expect(find.text('Alimentation & hydratation'), findsOneWidget);
    expect(find.text('Composer des repas nourrissants'), findsOneWidget);
    expect(find.text('Boire de l’eau régulièrement'), findsWidgets);
    expect(find.text('Mes prochaines échéances'), findsOneWidget);
    expect(find.text('Vérification du carnet vaccinal'), findsWidgets);
    expect(find.text('1 action enregistrée.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enregistre une action de prévention complète', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: const {},
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(const <PreventiveCareRecord>[]),
          reminderStream: Stream.value(const <PreventiveCareReminder>[]),
          onSaveRecord: (data) async => saved = data,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('preventive-add-record')));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter à mon carnet'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('preventive-title-field')),
      'Bilan de santé annuel',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('preventive-provider-field')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const Key('preventive-provider-field')),
      'Clinique Espoir',
    );
    await tester.enterText(
      find.byKey(const Key('preventive-note-field')),
      'Tension vérifiée pendant la consultation.',
    );
    await tester.ensureVisible(find.byKey(const Key('preventive-save-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preventive-save-record')));
    await tester.pumpAndSettle();

    expect(saved?['category'], 'checkup');
    expect(saved?['title'], 'Bilan de santé annuel');
    expect(saved?['completedAt'], DateTime(2026, 7, 18));
    expect(saved?['provider'], 'Clinique Espoir');
    expect(saved?['note'], 'Tension vérifiée pendant la consultation.');
    expect(find.text('Action de prévention enregistrée.'), findsOneWidget);
  });

  testWidgets('préremplit le carnet depuis une action du plan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: const {},
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(const <PreventiveCareRecord>[]),
          reminderStream: Stream.value(const <PreventiveCareReminder>[]),
          onSaveRecord: (data) async => saved = data,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('preventive-plan-preventive-review')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Faire le point sur ma santé'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('preventive-save-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preventive-save-record')));
    await tester.pumpAndSettle();

    expect(saved?['planItemId'], 'preventive-review');
    expect(saved?['title'], 'Faire le point sur ma santé');
  });

  testWidgets('crée un rappel depuis une recommandation personnalisée', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? savedReminder;

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: {'sex': 'Femme', 'birthDate': DateTime(1980, 4, 12)},
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(const <PreventiveCareRecord>[]),
          reminderStream: Stream.value(const <PreventiveCareReminder>[]),
          onSaveReminder: (data) async => savedReminder = data,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final breastReminder = find.byKey(
      const Key('preventive-reminder-breast-screening'),
    );
    await tester.scrollUntilVisible(
      breastReminder,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(breastReminder);
    await tester.pumpAndSettle();
    expect(find.text('Créer un rappel'), findsWidgets);
    expect(find.text('Discuter du dépistage du cancer du sein'), findsWidgets);

    await tester.tap(find.byKey(const Key('preventive-reminder-preset-1')));
    await tester.ensureVisible(
      find.byKey(const Key('preventive-save-reminder')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preventive-save-reminder')));
    await tester.pumpAndSettle();

    expect(savedReminder?['category'], 'screening');
    expect(savedReminder?['planItemId'], 'breast-screening');
    expect(savedReminder?['title'], 'Discuter du dépistage du cancer du sein');
    expect(savedReminder?['dueAt'], DateTime(2026, 8, 18));
    expect(find.text('Rappel ajouté à votre plan.'), findsOneWidget);
  });

  testWidgets('explique une observation mammaire sans faux diagnostic', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: {'sex': 'Femme', 'birthDate': DateTime(1992, 4, 12)},
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(const <PreventiveCareRecord>[]),
          reminderStream: Stream.value(const <PreventiveCareReminder>[]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('preventive-breast-awareness-guide')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const Key('preventive-breast-awareness-guide')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('doigts à plat'), findsOneWidget);
    expect(
      find.textContaining('ne remplace ni l’examen clinique'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('propose des conseils d’eau adaptés et crée un rappel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? savedReminder;

    await tester.pumpWidget(
      MaterialApp(
        home: PreventiveMedicinePage(
          patientId: 'patient-test',
          patientProfile: const {
            'medicalConditions': ['Maladie rénale chronique'],
          },
          now: DateTime(2026, 7, 18),
          recordStream: Stream.value(const <PreventiveCareRecord>[]),
          reminderStream: Stream.value(const <PreventiveCareReminder>[]),
          onSaveReminder: (data) async => savedReminder = data,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Alimentation & hydratation'), findsOneWidget);
    expect(find.textContaining('limité vos boissons'), findsOneWidget);
    expect(find.text('Urines foncées ou rares'), findsOneWidget);

    final hydrationReminder = find.byKey(
      const Key('preventive-hydration-reminder'),
    );
    await tester.scrollUntilVisible(
      hydrationReminder,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(hydrationReminder);
    await tester.pumpAndSettle();

    expect(find.text('Créer un rappel'), findsWidgets);
    expect(find.text('Boire de l’eau régulièrement'), findsWidgets);
    await tester.ensureVisible(
      find.byKey(const Key('preventive-save-reminder')),
    );
    await tester.tap(find.byKey(const Key('preventive-save-reminder')));
    await tester.pumpAndSettle();

    expect(savedReminder?['category'], 'habit');
    expect(savedReminder?['planItemId'], 'hydration-habit');
    expect(savedReminder?['title'], 'Boire de l’eau régulièrement');
    expect(tester.takeException(), isNull);
  });
}

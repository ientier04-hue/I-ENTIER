import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/maternal_child_health_page.dart';

void main() {
  final now = DateTime(2026, 8, 5);
  final pregnancy = PregnancyProfile(
    id: 'pregnancy-1',
    patientId: 'patient-1',
    lastMenstrualPeriod: DateTime(2026, 3, 1),
    estimatedDueDate: DateTime(2026, 12, 6),
    riskFactors: const {'hypertension'},
    nutritionHabits: const {'hydration'},
  );

  test('calcule le terme, la semaine et les repères prénataux', () {
    final profile = PregnancyProfile(
      id: 'pregnancy-calendar',
      patientId: 'patient-1',
      lastMenstrualPeriod: DateTime(2026, 1, 1),
      estimatedDueDate: DateTime(2026, 10, 8),
    );
    final calendar = buildPregnancyCalendar(profile);

    expect(profile.weekAt(DateTime(2026, 3, 12)), 10);
    expect(calendar.length, 14);
    expect(
      calendar
          .where(
            (item) => item.category == PregnancyReminderCategory.consultation,
          )
          .length,
      8,
    );
    expect(
      calendar.any(
        (item) =>
            item.category == PregnancyReminderCategory.ultrasound &&
            item.dueAt == DateTime(2026, 5, 21),
      ),
      isTrue,
    );
    expect(pregnancyWeekGuidance(12), contains('Semaine 12'));
    expect(pregnancyWeekGuidance(32), contains('plan de naissance'));
    expect(pregnancyWeekGuidance(12), isNot(pregnancyWeekGuidance(13)));
  });

  test('identifie une grossesse nécessitant un accompagnement renforcé', () {
    final score = calculateMaternalHealthScore(
      pregnancy,
      buildPregnancyCalendar(pregnancy),
      now: now,
    );

    expect(score.total, lessThan(60));
    expect(score.needsReinforcedSupport, isTrue);
    expect(score.riskProtection, lessThan(20));
  });

  test('détecte retard vaccinal et absence de mesure récente', () {
    final child = ChildProfile(
      id: 'child-1',
      guardianPatientId: 'patient-1',
      firstName: 'Ana',
      birthDate: DateTime(2025, 8, 5),
      sex: 'feminin',
      birthWeightKg: 2.3,
    );
    final vaccines = buildChildVaccinationCalendar(child);
    final risks = detectChildHealthRisks(child, const [], vaccines, now: now);

    expect(risks.any((item) => item.contains('2,5 kg')), isTrue);
    expect(risks.any((item) => item.contains('croissance récente')), isTrue);
    expect(risks.any((item) => item.contains('vaccin(s)')), isTrue);
  });

  testWidgets('affiche le suivi grossesse, le score et les accès urgents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var transportOpened = false;
    final reminders = buildPregnancyCalendar(pregnancy);

    await tester.pumpWidget(
      MaterialApp(
        home: MaternalChildHealthPage(
          patientId: 'patient-1',
          patientProfile: const {'pregnancyStatus': 'Oui'},
          now: now,
          initialSnapshot: MaternalChildSnapshot(
            pregnancy: pregnancy,
            reminders: reminders,
          ),
          onOpenEmergencyTransport: () => transportOpened = true,
        ),
      ),
    );

    expect(find.text('Maternité & Petite Enfance'), findsOneWidget);
    expect(find.text('Semaine 22 de grossesse'), findsOneWidget);
    expect(find.text('Score Santé Maternité & Petite Enfance'), findsOneWidget);
    expect(find.byKey(const Key('maternal-pregnancy-alert')), findsOneWidget);
    expect(
      find.byKey(const Key('maternal-emergency-transport')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('maternal-emergency-transport')));
    expect(transportOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ouvre directement le parcours grossesse du Diagnostic Assisté', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MaternalChildHealthPage(
          patientId: 'patient-1',
          patientProfile: const {'pregnancyStatus': 'Oui'},
          now: now,
          initialSnapshot: MaternalChildSnapshot(
            pregnancy: pregnancy,
            reminders: buildPregnancyCalendar(pregnancy),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('maternal-pregnancy-alert')));
    await tester.pumpAndSettle();
    expect(find.text('Vos données, votre choix'), findsOneWidget);

    await tester.tap(find.byKey(const Key('consent-understood')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Étape de la grossesse'), findsOneWidget);
    expect(find.text('Que ressentez-vous ?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche le carnet enfant, sa croissance et les vaccins', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final child = ChildProfile(
      id: 'child-1',
      guardianPatientId: 'patient-1',
      firstName: 'Noa',
      birthDate: DateTime(2026, 2, 5),
      sex: 'masculin',
      birthWeightKg: 3.2,
    );
    final growth = ChildGrowthRecord(
      id: 'growth-1',
      childId: child.id,
      guardianPatientId: 'patient-1',
      measuredAt: DateTime(2026, 8, 1),
      weightKg: 7.4,
      heightCm: 66,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MaternalChildHealthPage(
          patientId: 'patient-1',
          patientProfile: const {},
          now: now,
          initialSnapshot: MaternalChildSnapshot(
            children: [child],
            growthRecords: [growth],
            vaccinationRecords: buildChildVaccinationCalendar(child),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Enfant 0–5 ans'));
    await tester.pumpAndSettle();

    expect(find.text('Noa'), findsWidgets);
    expect(find.text('7.4 kg  •  66 cm'), findsOneWidget);
    expect(find.text('Conseils nutritionnels'), findsOneWidget);
    expect(find.text('Carnet de vaccination'), findsOneWidget);
    expect(find.textContaining('BCG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

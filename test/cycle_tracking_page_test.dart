import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';

CycleEntry _periodDay(DateTime date, {String flow = 'medium'}) =>
    CycleEntry(id: cycleDateKey(date), date: date, isPeriod: true, flow: flow);

List<CycleEntry> _period(DateTime start, int length) => List.generate(
  length,
  (index) => _periodDay(start.add(Duration(days: index))),
);

void main() {
  test('calcule les tendances à partir des périodes enregistrées', () {
    final entries = [
      ..._period(DateTime(2026, 1, 1), 5),
      ..._period(DateTime(2026, 1, 29), 4),
      ..._period(DateTime(2026, 2, 26), 5),
    ];

    final insights = CycleInsights.fromEntries(
      entries,
      now: DateTime(2026, 3, 5),
    );

    expect(insights.averageCycleLength, 28);
    expect(insights.averagePeriodLength, 5);
    expect(insights.currentCycleDay, 8);
    expect(insights.nextPeriodStart, DateTime(2026, 3, 26));
    expect(insights.daysUntilNextPeriod, 21);
    expect(insights.ovulationDate, DateTime(2026, 3, 12));
    expect(insights.fertileWindowStart, DateTime(2026, 3, 7));
    expect(insights.fertileWindowEnd, DateTime(2026, 3, 13));
    expect(insights.isPredictedPeriod(DateTime(2026, 3, 28)), isTrue);
    expect(insights.isFertile(DateTime(2026, 3, 10)), isTrue);
  });

  testWidgets('affiche le tableau de bord, le calendrier et les estimations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = [
      ..._period(DateTime(2026, 1, 1), 5),
      ..._period(DateTime(2026, 1, 29), 4),
      ..._period(DateTime(2026, 2, 26), 5),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: entries,
        ),
      ),
    );

    expect(find.text('Suivi de cycle'), findsOneWidget);
    expect(find.text('Prochaines règles dans 21 jours'), findsOneWidget);
    expect(find.text('Cycle moyen'), findsOneWidget);
    expect(find.text('28 jours'), findsOneWidget);
    expect(find.byKey(const Key('cycle-calendar')), findsOneWidget);
    expect(find.text('Mars 2026'), findsOneWidget);
    expect(find.textContaining('Fenêtre fertile estimée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enregistre les règles, symptômes, humeur et note', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CycleEntry? savedEntry;

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: const [],
          onSaveEntry: (entry) async => savedEntry = entry,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('cycle-log-today')));
    await tester.pumpAndSettle();
    expect(find.text('Comment vous sentez-vous ?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cycle-period-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cycle-flow-heavy')));
    await tester.tap(find.byKey(const Key('cycle-symptom-cramps')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-mood-sensitive')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cycle-mood-sensitive')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-note-field')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const Key('cycle-note-field')),
      'Douleurs modérées le matin.',
    );
    await tester.ensureVisible(find.byKey(const Key('cycle-save-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cycle-save-entry')));
    await tester.pumpAndSettle();

    expect(savedEntry, isNotNull);
    expect(savedEntry!.date, DateTime(2026, 3, 5));
    expect(savedEntry!.isPeriod, isTrue);
    expect(savedEntry!.flow, 'heavy');
    expect(savedEntry!.symptoms, contains('cramps'));
    expect(savedEntry!.mood, 'sensitive');
    expect(savedEntry!.note, 'Douleurs modérées le matin.');
    expect(find.text('Votre journée a été enregistrée.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajoute une période en cours depuis une seule action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final savedEntries = <CycleEntry>[];

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: const [],
          onSaveEntry: (entry) async => savedEntries.add(entry),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('cycle-add-period')));
    await tester.pumpAndSettle();

    expect(find.text('Ajouter mes règles'), findsWidgets);
    expect(find.text('Premier jour des règles'), findsOneWidget);
    expect(find.text('Mes règles sont toujours en cours'), findsOneWidget);
    expect(find.textContaining('modifier la date de fin'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('cycle-save-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cycle-save-period')));
    await tester.pumpAndSettle();

    expect(savedEntries, hasLength(1));
    expect(savedEntries.single.date, DateTime(2026, 3, 5));
    expect(savedEntries.single.isPeriod, isTrue);
    expect(find.text('Historique des règles'), findsOneWidget);
    expect(find.text('1 jour enregistré'), findsOneWidget);
  });

  testWidgets('permet de corriger la date de fin d’une période', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final savedEntries = <CycleEntry>[];
    final entries = _period(DateTime(2026, 1, 1), 3);

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: entries,
          onSaveEntry: (entry) async => savedEntries.add(entry),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-edit-period-2026-01-01')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('cycle-edit-period-2026-01-01')));
    await tester.pumpAndSettle();

    expect(find.text('Modifier mes règles'), findsOneWidget);
    expect(find.text('1 janv. – 3 janvier 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cycle-range-end')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4').last);
    await tester.tap(find.text('Choisir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cycle-save-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cycle-save-period')));
    await tester.pumpAndSettle();

    expect(savedEntries, hasLength(1));
    expect(savedEntries.single.date, DateTime(2026, 1, 4));
    expect(savedEntries.single.isPeriod, isTrue);
    expect(find.text('4 jours enregistrés'), findsOneWidget);
  });

  testWidgets('reste utilisable sur un petit écran mobile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: const [],
        ),
      ),
    );

    expect(
      find.text('Comprendre votre cycle,\nun jour à la fois.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-calendar')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('cycle-calendar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

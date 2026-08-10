import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';

CycleEntry _periodDay(DateTime date, {String flow = 'medium'}) =>
    CycleEntry(id: cycleDateKey(date), date: date, isPeriod: true, flow: flow);

List<CycleEntry> _period(DateTime start, int length) => List.generate(
  length,
  (index) => _periodDay(start.add(Duration(days: index))),
);

List<CycleEntry> _periodHistory(List<DateTime> starts, {int length = 5}) => [
  for (final start in starts) ..._period(start, length),
];

List<CycleEntry> _regularHistory() => _periodHistory([
  DateTime(2025, 12, 3),
  DateTime(2025, 12, 31),
  DateTime(2026, 1, 28),
  DateTime(2026, 2, 25),
]);

void main() {
  test('calcule une médiane et une plage à partir de cycles complets', () {
    final entries = _regularHistory();

    final insights = CycleInsights.fromEntries(
      entries,
      now: DateTime(2026, 3, 5),
    );

    expect(insights.averageCycleLength, 28);
    expect(insights.averagePeriodLength, 5);
    expect(insights.cycleSampleCount, 3);
    expect(insights.historyQuality, CycleHistoryQuality.limited);
    expect(insights.currentCycleDay, 9);
    expect(insights.nextPeriodStart, DateTime(2026, 3, 25));
    expect(insights.nextPeriodEarliest, DateTime(2026, 3, 23));
    expect(insights.nextPeriodLatest, DateTime(2026, 3, 27));
    expect(insights.daysUntilNextPeriod, 20);
    expect(insights.isPredictedPeriod(DateTime(2026, 3, 25)), isTrue);
    expect(insights.ovulationDate, isNull);
    expect(insights.fertileWindowStart, isNull);
    expect(insights.isFertile(DateTime(2026, 3, 10)), isFalse);
  });

  test('ne fabrique pas un cycle de 28 jours avec trop peu de données', () {
    final insights = CycleInsights.fromEntries(
      _periodHistory([
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ]),
      now: DateTime(2026, 3, 5),
    );

    expect(insights.cycleSampleCount, 2);
    expect(insights.typicalCycleLength, isNull);
    expect(insights.nextPeriodStart, isNull);
    expect(insights.historyQuality, CycleHistoryQuality.insufficient);
    expect(insights.isPredictedPeriod(DateTime(2026, 3, 26)), isFalse);
  });

  test('ne découpe pas un saignement continu en cycles artificiels', () {
    final insights = CycleInsights.fromEntries(
      _period(DateTime(2026, 1, 1), 20),
      now: DateTime(2026, 2, 1),
    );

    expect(insights.periodStarts, [DateTime(2026, 1, 1)]);
    expect(insights.cycleSampleCount, 0);
    expect(insights.typicalPeriodLength, isNull);
    expect(insights.hasProlongedBleeding, isTrue);
  });

  test(
    'isole deux blocs de saignement proches sans fausser le cycle suivant',
    () {
      final entries = _periodHistory([
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 14),
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
      ]);
      final insights = CycleInsights.fromEntries(
        entries,
        now: DateTime(2026, 3, 10),
      );

      expect(insights.periodStarts, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 14),
        DateTime(2026, 2, 1),
        DateTime(2026, 3, 1),
      ]);
      expect(insights.hasOutOfRangeInterval, isTrue);
      expect(insights.cycleSampleCount, 1);
      expect(insights.typicalCycleLength, isNull);
    },
  );

  test('mesure la durée calendaire malgré une journée non saisie', () {
    final insights = CycleInsights.fromEntries([
      _periodDay(DateTime(2026, 1, 1)),
      _periodDay(DateTime(2026, 1, 3)),
      _periodDay(DateTime(2026, 2, 1)),
      _periodDay(DateTime(2026, 2, 3)),
      _periodDay(DateTime(2026, 3, 1)),
      _periodDay(DateTime(2026, 3, 3)),
      _periodDay(DateTime(2026, 4, 1)),
      _periodDay(DateTime(2026, 4, 3)),
    ], now: DateTime(2026, 4, 10));

    expect(insights.periodStarts, [
      DateTime(2026, 1, 1),
      DateTime(2026, 2, 1),
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
    ]);
    expect(insights.periodSampleCount, 0);
    expect(insights.typicalPeriodLength, isNull);
    expect(insights.hasIncompletePeriodRecord, isTrue);
  });

  test('exclut la période potentiellement en cours de sa durée habituelle', () {
    final insights = CycleInsights.fromEntries([
      ..._period(DateTime(2026, 1, 1), 4),
      ..._period(DateTime(2026, 1, 29), 4),
      ..._period(DateTime(2026, 2, 26), 4),
      ..._period(DateTime(2026, 3, 26), 7),
    ], now: DateTime(2026, 4, 1));

    expect(insights.periodSampleCount, 3);
    expect(insights.typicalPeriodLength, 4);
  });

  test('signale une plage dépassée sans inventer le cycle suivant', () {
    final insights = CycleInsights.fromEntries(
      _regularHistory(),
      now: DateTime(2026, 4, 1),
    );

    expect(insights.nextPeriodStart, DateTime(2026, 3, 25));
    expect(insights.nextPeriodLatest, DateTime(2026, 3, 27));
    expect(insights.isOverdue, isTrue);
    expect(insights.daysPastPredictionWindow, 5);
    expect(insights.isPredictedPeriod(DateTime(2026, 4, 22)), isFalse);
  });

  test('suspend la prévision devant un oubli de saisie possible', () {
    final entries = _periodHistory([
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 29),
      DateTime(2026, 2, 26),
      DateTime(2026, 4, 23),
    ]);
    final insights = CycleInsights.fromEntries(
      entries,
      now: DateTime(2026, 5, 1),
    );

    expect(insights.typicalCycleLength, isNull);
    expect(insights.cycleVariationDays, 28);
    expect(insights.hasPossibleTrackingGap, isTrue);
    expect(insights.isPredictionSuspended, isTrue);
    expect(insights.hasHighVariability, isTrue);
    expect(insights.historyQuality, CycleHistoryQuality.limited);
    expect(insights.predictionWindowDays, isNull);
    expect(insights.canHighlightPrediction, isFalse);
    expect(insights.isPredictedPeriod(DateTime(2026, 5, 21)), isFalse);
  });

  test('détecte aussi plusieurs intervalles doubles consécutifs', () {
    final insights = CycleInsights.fromEntries(
      _periodHistory([
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 3, 26),
        DateTime(2026, 5, 21),
      ]),
      now: DateTime(2026, 5, 30),
    );

    expect(insights.hasPossibleTrackingGap, isTrue);
    expect(insights.isPredictionSuspended, isTrue);
    expect(insights.nextPeriodStart, isNull);
  });

  test('ne prend pas un saignement rapproché comme nouveau départ', () {
    final entries = [..._regularHistory(), ..._period(DateTime(2026, 3, 7), 2)];
    final insights = CycleInsights.fromEntries(
      entries,
      now: DateTime(2026, 3, 12),
    );

    expect(insights.hasRecentAmbiguousBleeding, isTrue);
    expect(insights.lastPeriodStart, DateTime(2026, 3, 7));
    expect(insights.isPredictionSuspended, isTrue);
    expect(insights.nextPeriodStart, isNull);
  });

  test('reconstruit uniquement l’historique après une longue interruption', () {
    final insights = CycleInsights.fromEntries(
      _periodHistory([
        DateTime(2025, 1, 1),
        DateTime(2025, 1, 29),
        DateTime(2025, 2, 26),
        DateTime(2025, 3, 26),
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 29),
        DateTime(2026, 2, 26),
      ]),
      now: DateTime(2026, 3, 1),
    );

    expect(insights.hasHistoryBreak, isTrue);
    expect(insights.cycleSampleCount, 2);
    expect(insights.periodSampleCount, 2);
    expect(insights.typicalCycleLength, isNull);
    expect(insights.typicalPeriodLength, isNull);
    expect(insights.hasPrediction, isFalse);
  });

  test('qualifie de stable seulement un long historique régulier', () {
    final starts = <DateTime>[];
    var start = DateTime(2025, 1, 1);
    for (var index = 0; index < 10; index++) {
      starts.add(start);
      start = start.add(const Duration(days: 28));
    }
    final insights = CycleInsights.fromEntries(
      _periodHistory(starts),
      now: starts.last.add(const Duration(days: 7)),
    );

    expect(insights.cycleSampleCount, 9);
    expect(insights.cycleVariationDays, 0);
    expect(insights.historyQuality, CycleHistoryQuality.veryStable);
  });

  test('ne qualifie pas de stable une fréquence adulte atypique', () {
    final starts = <DateTime>[];
    for (var index = 0; index < 10; index++) {
      starts.add(DateTime(2025, 1, 1 + index * 15));
    }
    final insights = CycleInsights.fromEntries(
      _periodHistory(starts, length: 3),
      now: starts.last.add(const Duration(days: 5)),
    );

    expect(insights.hasAtypicalCycleFrequency, isTrue);
    expect(insights.typicalCycleLength, 15);
    expect(insights.historyQuality, CycleHistoryQuality.limited);
  });

  test(
    'normalise les heures, trie les entrées et ignore les dates futures',
    () {
      final entries = <CycleEntry>[
        _periodDay(DateTime(2026, 3, 6)),
        _periodDay(DateTime(2026, 3, 5, 18, 30)),
        _periodDay(DateTime(2026, 3, 5, 8)),
      ];

      final insights = CycleInsights.fromEntries(
        entries.reversed,
        now: DateTime(2026, 3, 5, 7),
      );

      expect(insights.periodStarts, [DateTime(2026, 3, 5)]);
      expect(insights.lastPeriodStart, DateTime(2026, 3, 5));
      expect(insights.cycleSampleCount, 0);
    },
  );

  test('calcule les jours calendaires à travers une année bissextile', () {
    final insights = CycleInsights.fromEntries(
      _periodHistory([
        DateTime(2023, 12, 7),
        DateTime(2024, 1, 4),
        DateTime(2024, 2, 1),
        DateTime(2024, 2, 29),
      ]),
      now: DateTime(2024, 3, 5),
    );

    expect(insights.typicalCycleLength, 28);
    expect(insights.nextPeriodStart, DateTime(2024, 3, 28));
    expect(insights.nextPeriodEarliest, DateTime(2024, 3, 26));
    expect(insights.nextPeriodLatest, DateTime(2024, 3, 30));
  });

  testWidgets('affiche le tableau de bord, le calendrier et les estimations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = _regularHistory();

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
    expect(find.text('Prochaines règles estimées'), findsOneWidget);
    expect(find.text('23–27 mars 2026'), findsOneWidget);
    expect(find.text('Cycle habituel'), findsOneWidget);
    expect(find.text('28 jours'), findsOneWidget);
    expect(find.byKey(const Key('cycle-calendar')), findsOneWidget);
    expect(find.text('Mars 2026'), findsOneWidget);
    expect(find.byKey(const Key('cycle-estimation-prudent')), findsOneWidget);
    expect(
      find.byKey(const Key('cycle-fertility-unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cycle-contraception-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('Fenêtre fertile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'masque toute prévision personnalisée si l’historique est court',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CycleTrackingPage(
            patientId: 'patient-test',
            now: DateTime(2026, 3, 5),
            initialEntries: _periodHistory([
              DateTime(2026, 1, 1),
              DateTime(2026, 1, 29),
              DateTime(2026, 2, 26),
            ]),
          ),
        ),
      );

      expect(
        find.byKey(const Key('cycle-history-insufficient')),
        findsOneWidget,
      );
      expect(find.text('Historique insuffisant pour prévoir'), findsOneWidget);
      expect(find.text('Cycle habituel'), findsNothing);
      expect(find.text('28 jours'), findsNothing);
      expect(find.byKey(const Key('cycle-next-period-range')), findsNothing);
      expect(
        find.byKey(const Key('cycle-fertility-unavailable')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('garde la date sélectionnée visible au changement de mois', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 31),
          initialEntries: const [],
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-calendar')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('cycle-previous-month')));
    await tester.pumpAndSettle();

    expect(find.text('Février 2026'), findsOneWidget);
    expect(find.text('28 février 2026'), findsOneWidget);
    final selectedDay = find.byKey(const Key('cycle-day-2026-02-28'));
    final selectedDaySemantics = tester.getSemantics(selectedDay);
    expect(selectedDaySemantics.label, contains('sélectionné'));
    expect(selectedDaySemantics.flagsCollection.isSelected, ui.Tristate.isTrue);

    await tester.ensureVisible(
      find.byKey(const Key('cycle-selected-day-card')),
    );
    await tester.tap(find.byKey(const Key('cycle-selected-day-card')));
    await tester.pumpAndSettle();

    expect(find.text('Comment vous sentez-vous ?'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('annonce les états utiles des journées du calendrier', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final entries = _regularHistory();

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 3, 5),
          initialEntries: entries,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-calendar')),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    final today = tester.getSemantics(
      find.byKey(const Key('cycle-day-2026-03-05')),
    );
    expect(today.label, contains('aujourd’hui'));
    expect(today.label, contains('sélectionné'));
    expect(today.flagsCollection.isSelected, ui.Tristate.isTrue);

    final period = tester.getSemantics(
      find.byKey(const Key('cycle-day-2026-03-01')),
    );
    expect(period.label, contains('règles enregistrées'));

    final future = tester.getSemantics(
      find.byKey(const Key('cycle-day-2026-03-06')),
    );
    expect(future.label, contains('date future'));

    final calendarOnly = tester.getSemantics(
      find.byKey(const Key('cycle-day-2026-03-10')),
    );
    expect(calendarOnly.label, isNot(contains('fertilité')));

    final predictedPeriod = tester.getSemantics(
      find.byKey(const Key('cycle-day-2026-03-25')),
    );
    expect(
      predictedPeriod.label,
      contains('date possible du début des prochaines règles, estimation'),
    );

    final daySize = tester.getSize(
      find.byKey(const Key('cycle-day-2026-03-05')),
    );
    expect(daySize.width, greaterThanOrEqualTo(48));
    expect(daySize.height, greaterThanOrEqualTo(48));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche la variabilité et un oubli de saisie possible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = _periodHistory([
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 29),
      DateTime(2026, 2, 26),
      DateTime(2026, 4, 23),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 5, 1),
          initialEntries: entries,
        ),
      ),
    );

    expect(find.byKey(const Key('cycle-variability-warning')), findsOneWidget);
    expect(find.byKey(const Key('cycle-tracking-gap-warning')), findsOneWidget);
    expect(find.byKey(const Key('cycle-prediction-suspended')), findsOneWidget);
    expect(find.byKey(const Key('cycle-next-period-range')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('distingue fréquence atypique et journées non saisies', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = <CycleEntry>[];
    for (var index = 0; index < 10; index++) {
      final start = DateTime(2025, 1, 1 + index * 15);
      entries.add(_periodDay(start));
      entries.add(_periodDay(start.add(const Duration(days: 2))));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2025, 5, 20),
          initialEntries: entries,
        ),
      ),
    );

    expect(
      find.byKey(const Key('cycle-atypical-frequency-warning')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cycle-incomplete-period-warning')),
      findsOneWidget,
    );
    expect(
      find.textContaining('2 jours saisis · période calendaire de 3 jours'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signale un cycle dépassé sans projeter une nouvelle date', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'patient-test',
          now: DateTime(2026, 4, 1),
          initialEntries: _regularHistory(),
        ),
      ),
    );

    expect(find.byKey(const Key('cycle-overdue-notice')), findsOneWidget);
    expect(find.byKey(const Key('cycle-overdue-guidance')), findsOneWidget);
    expect(find.textContaining('dépassée de 5 jours'), findsOneWidget);
    expect(find.byKey(const Key('cycle-next-period-range')), findsNothing);
    expect(find.text('Prochaines règles estimées'), findsNothing);
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
    expect(
      tester.getSize(find.byKey(const Key('cycle-day-2026-03-05'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}

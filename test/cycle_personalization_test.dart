import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_context_form.dart';
import 'package:i_entier/cycle_tracking_page.dart';
import 'package:i_entier/supabase_data.dart';

const natural = CyclePersonalContext(
  lifeStage: CycleLifeStage.menstruating,
  contraception: CycleContraception.none,
);

DateTime add(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

List<CycleEntry> history(
  List<int> lengths, {
  bool symptoms = false,
  int lead = 3,
}) {
  var start = DateTime(2025, 1, 1);
  final entries = <CycleEntry>[];
  for (final length in [...lengths, 0]) {
    for (var day = 0; day < 4; day++) {
      final date = add(start, day);
      entries.add(
        CycleEntry(id: cycleDateKey(date), date: date, isPeriod: true),
      );
    }
    if (symptoms && length > 0) {
      final date = add(start, length - lead);
      entries.add(
        CycleEntry(
          id: cycleDateKey(date),
          date: date,
          symptoms: const ['tenderBreasts'],
        ),
      );
    }
    start = add(start, length);
  }
  return entries;
}

CycleInsights insights(
  List<CycleEntry> entries, {
  CyclePersonalContext context = natural,
  DateTime? now,
}) => CycleInsights.fromEntries(
  entries,
  now: now ?? add(entries.last.date, 3),
  personalContext: context,
);

class MemoryContextRepository implements CycleContextRepository {
  CyclePersonalContext value;
  bool failLoad = false;
  bool failSave = false;
  Completer<CyclePersonalContext>? pending;
  MemoryContextRepository(this.value);
  @override
  Future<CyclePersonalContext> load(String id) async {
    if (pending != null) return pending!.future;
    if (failLoad) throw StateError('offline');
    return value;
  }

  @override
  Future<void> save(String id, CyclePersonalContext context) async {
    if (failSave) throw StateError('offline');
    value = context;
  }
}

void main() {
  test(
    'reprend une grossesse déjà déclarée sans inférer un contexte naturel',
    () {
      expect(
        CyclePersonalContext.fromPatientProfile({
          'pregnancy_status': 'Oui',
        }).suspensionReason,
        'Grossesse',
      );
      expect(
        CyclePersonalContext.fromPatientProfile({
          'pregnancy_status': 'Non',
        }).canUseSymptomTiming,
        isFalse,
      );
      expect(
        CyclePersonalContext.fromPatientProfile({}).lifeStage,
        CycleLifeStage.unspecified,
      );
    },
  );

  test(
    'conserve les résultats de vérification même si le signal est refusé',
    () {
      const pattern = CycleSymptomPattern(
        signal: 'fatigue',
        observedCycles: 7,
        leadDays: 3,
        validationCycles: 4,
        worsenedCycles: 2,
        baselineMeanErrorDays: 2,
        adjustedMeanErrorDays: 1,
      );
      expect(pattern.validationCycles, 4);
      expect(pattern.canAdjustPrediction, isFalse);
    },
  );

  final regular = history(List.filled(9, 28));
  for (final context in [
    const CyclePersonalContext(lifeStage: CycleLifeStage.pregnant),
    const CyclePersonalContext(lifeStage: CycleLifeStage.postpartum),
    const CyclePersonalContext(lifeStage: CycleLifeStage.menopause),
    const CyclePersonalContext(contraception: CycleContraception.hormonal),
    const CyclePersonalContext(breastfeeding: true),
  ]) {
    test('suspend dates et retard en contexte ${context.suspensionReason}', () {
      final result = insights(regular, context: context);
      expect(result.isPredictionSuspended, isTrue);
      expect(result.hasPrediction, isFalse);
      expect(result.nextPeriodStart, isNull);
      expect(result.isOverdue, isFalse);
      expect(result.symptomPatterns, isEmpty);
    });
  }

  for (final context in [
    const CyclePersonalContext(lifeStage: CycleLifeStage.perimenopause),
    const CyclePersonalContext(hasPcos: true),
  ]) {
    test('exige six cycles pour ${context.toRow()}', () {
      final short = insights(history(List.filled(5, 28)), context: context);
      expect(short.hasPrediction, isFalse);
      expect(short.additionalCyclesNeeded, 1);
      final enough = insights(regular, context: context);
      expect(enough.hasPrediction, isTrue);
      expect(enough.historyQuality, CycleHistoryQuality.limited);
      expect(enough.usedSymptomAdjustment, isFalse);
    });
  }

  test('ne tranche pas un épisode à la date de changement de contexte', () {
    final result = insights(
      history(List.filled(5, 28)),
      context: CyclePersonalContext(
        lifeStage: CycleLifeStage.menstruating,
        historyStart: DateTime(2025, 1, 2),
      ),
    );
    expect(result.periodStarts.first, DateTime(2025, 1, 29));
    expect(result.cycleSampleCount, 4);
    expect(result.hasHistoryBreak, isTrue);
  });

  test('reprend uniquement avec des cycles du nouveau contexte', () {
    final result = insights(
      regular,
      context: CyclePersonalContext(
        lifeStage: CycleLifeStage.menstruating,
        historyStart: add(regular.last.date, -59),
      ),
    );
    expect(result.cycleSampleCount, 2);
    expect(result.nextPeriodStart, isNull);
  });

  test('le spotting ne crée pas un nouveau cycle', () {
    final base = insights(regular);
    final date = add(base.lastPeriodStart!, 10);
    final result = insights([
      ...regular,
      CycleEntry(id: 'spot', date: date, isSpotting: true),
    ], now: add(date, 2));
    expect(result.periodStarts, base.periodStarts);
    expect(result.nextPeriodStart, base.nextPeriodStart);
    expect(result.hasRecentAmbiguousBleeding, isFalse);
  });

  test('une contradiction spotting/règles reste exclue de l’ancrage', () {
    final date = add(regular.last.date, 10);
    final result = insights([
      ...regular,
      CycleEntry(id: 'spot', date: date, isPeriod: true, isSpotting: true),
    ]);
    expect(result.periodStarts, insights(regular).periodStarts);
  });

  test(
    'apprend une répétition sans ajuster avant validation chronologique',
    () {
      final result = insights(history([28, 32, 28], symptoms: true));
      expect(result.symptomPatterns.single.leadDays, 3);
      expect(result.symptomPatterns.single.observedCycles, 3);
      expect(result.symptomPatterns.single.canAdjustPrediction, isFalse);
      expect(result.usedSymptomAdjustment, isFalse);
    },
  );

  test(
    'ajuste au plus deux jours grâce à un signal validé sur des cycles ultérieurs',
    () {
      final entries = history([28, 32, 28, 32, 28, 32, 28], symptoms: true);
      final base = insights(entries);
      final today = add(base.lastPeriodStart!, 29);
      final result = insights([
        ...entries,
        CycleEntry(
          id: 'current',
          date: today,
          symptoms: const ['tenderBreasts'],
        ),
      ], now: today);
      expect(result.symptomPatterns.single.validationCycles, 4);
      expect(result.symptomPatterns.single.canAdjustPrediction, isTrue);
      expect(
        result.symptomPatterns.single.adjustedMeanErrorDays!,
        lessThan(result.symptomPatterns.single.baselineMeanErrorDays!),
      );
      expect(result.usedSymptomAdjustment, isTrue);
      expect(result.nextPeriodStart, add(base.nextPeriodStart!, 2));
      expect(result.nextPeriodEarliest, base.nextPeriodEarliest);
      expect(result.nextPeriodLatest, base.nextPeriodLatest);
      expect(result.historyQuality, base.historyQuality);
      expect(result.ovulationDate, isNull);
    },
  );

  test('ne transforme pas un symptôme permanent en signal prémenstruel', () {
    final entries = history(List.filled(8, 28));
    final base = insights(entries);
    for (final start in base.periodStarts.take(8)) {
      for (var day = 5; day < 28; day++) {
        entries.add(
          CycleEntry(
            id: '$start-$day',
            date: add(start, day),
            symptoms: const ['fatigue'],
          ),
        );
      }
    }
    expect(insights(entries).symptomPatterns, isEmpty);
  });

  test('ignore le symptôme actuel trop ancien et les données futures', () {
    final entries = history([28, 32, 28, 32, 28, 32, 28], symptoms: true);
    final base = insights(entries);
    final today = add(base.lastPeriodStart!, 27);
    final result = insights([
      ...entries,
      CycleEntry(
        id: 'early',
        date: add(today, -8),
        symptoms: const ['tenderBreasts'],
      ),
      CycleEntry(
        id: 'future',
        date: add(today, 2),
        symptoms: const ['tenderBreasts'],
      ),
    ], now: today);
    expect(result.usedSymptomAdjustment, isFalse);
    expect(result.nextPeriodStart, base.nextPeriodStart);
  });

  test('n’utilise pas le symptôme pour reporter un cycle dépassé', () {
    final entries = history([28, 32, 28, 32, 28, 32, 28], symptoms: true);
    final base = insights(entries);
    final today = add(base.nextPeriodLatest!, 2);
    final result = insights([
      ...entries,
      CycleEntry(id: 'late', date: today, symptoms: const ['tenderBreasts']),
    ], now: today);
    expect(result.usedSymptomAdjustment, isFalse);
    expect(result.isOverdue, isTrue);
    expect(result.nextPeriodStart, base.nextPeriodStart);
  });

  test('n’ajuste pas sans contexte naturel renseigné', () {
    final entries = history([28, 32, 28, 32, 28, 32, 28], symptoms: true);
    final today = add(insights(entries).lastPeriodStart!, 29);
    final result = insights(
      [
        ...entries,
        CycleEntry(
          id: 'current',
          date: today,
          symptoms: const ['tenderBreasts'],
        ),
      ],
      context: const CyclePersonalContext(),
      now: today,
    );
    expect(result.usedSymptomAdjustment, isFalse);
  });

  test('les doublons ne multiplient pas les cycles d’apprentissage', () {
    final entries = history([28, 32, 28], symptoms: true);
    final result = insights(
      [...entries, ...entries, ...entries].reversed.toList(),
      now: add(entries.last.date, 1),
    );
    expect(result.symptomPatterns.single.observedCycles, 3);
    expect(result.symptomPatterns.single.validationCycles, 0);
  });

  test('un symptôme ne remplace pas un calendrier déjà plus précis', () {
    final entries = history(List.filled(8, 28), symptoms: true);
    final result = insights(entries);
    expect(result.symptomPatterns.single.validationCycles, 5);
    expect(result.symptomPatterns.single.baselineMeanErrorDays, 0);
    expect(result.symptomPatterns.single.canAdjustPrediction, isFalse);
  });

  test('stress et sommeil apprennent leurs propres répétitions', () {
    final entries = history([28, 32, 28, 32], symptoms: true)
        .map(
          (entry) => entry.symptoms.isEmpty
              ? entry
              : CycleEntry(
                  id: entry.id,
                  date: entry.date,
                  stressLevel: 3,
                  sleepHours: 5,
                ),
        )
        .toList();
    final result = insights(entries);
    expect(
      result.symptomPatterns.map((value) => value.signal),
      containsAll(['highStress', 'shortSleep']),
    );
  });

  test(
    'conserve les nouvelles observations dans les conversions et corrections',
    () {
      final entry = CycleEntry(
        id: 'x',
        date: DateTime(2026, 3, 1),
        isSpotting: true,
        stressLevel: 2,
        sleepHours: 7.25,
      );
      final loaded = CycleEntry.fromSupabase(
        QueryDocumentSnapshot('x', entry.toData()),
      );
      expect(loaded.isSpotting, isTrue);
      expect(loaded.stressLevel, 2);
      expect(loaded.sleepHours, 7.25);
      expect(loaded.hasDetails, isTrue);
      final corrected = loaded.copyWith(isPeriod: true, isSpotting: false);
      expect(corrected.stressLevel, 2);
      expect(corrected.sleepHours, 7.25);
      expect(corrected.isSpotting, isFalse);
    },
  );

  test('recharge le contexte et refuse un contexte corrompu', () {
    final value = CyclePersonalContext(
      lifeStage: CycleLifeStage.perimenopause,
      contraception: CycleContraception.nonHormonal,
      breastfeeding: true,
      hasPcos: true,
      historyStart: DateTime(2026, 2, 3),
    );
    expect(CyclePersonalContext.fromRow(value.toRow()).toRow(), value.toRow());
    expect(
      () => CyclePersonalContext.fromRow({
        ...value.toRow(),
        'life_stage': 'unknown-new-value',
      }),
      throwsFormatException,
    );
  });

  testWidgets(
    'enregistre le contexte et suspend immédiatement les prévisions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      CyclePersonalContext? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: CycleTrackingPage(
            patientId: 'test',
            initialEntries: regular,
            initialContext: natural,
            now: add(regular.last.date, 2),
            onSaveContext: (value) async => saved = value,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('cycle-edit-context')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cycle-context-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grossesse').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cycle-save-context')));
      await tester.pumpAndSettle();
      expect(saved!.lifeStage, CycleLifeStage.pregnant);
      expect(saved!.historyStart, add(regular.last.date, 2));
      expect(find.byKey(const Key('cycle-context-suspended')), findsOneWidget);
      expect(find.byKey(const Key('cycle-next-period-range')), findsNothing);
    },
  );

  testWidgets(
    'une erreur de chargement ne réactive pas des prévisions par défaut',
    (tester) async {
      final repository = MemoryContextRepository(
        const CyclePersonalContext(lifeStage: CycleLifeStage.pregnant),
      )..failLoad = true;
      await tester.pumpWidget(
        MaterialApp(
          home: CycleTrackingPage(
            patientId: 'test',
            initialEntries: regular,
            now: add(regular.last.date, 2),
            contextRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Contexte indisponible'), findsOneWidget);
      expect(find.byKey(const Key('cycle-next-period-range')), findsNothing);
      repository.failLoad = false;
      await tester.tap(find.byKey(const Key('cycle-retry-context')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cycle-context-suspended')), findsOneWidget);
    },
  );

  testWidgets('conserve le formulaire si l’enregistrement du contexte échoue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CycleContextForm(
            initialContext: natural,
            today: DateTime(2026, 3, 5),
            onSave: (_) async => throw StateError('offline'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('cycle-save-context')));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrement impossible. Réessayez.'), findsOneWidget);
    expect(find.byKey(const Key('cycle-save-context')), findsOneWidget);
  });

  testWidgets(
    'enregistre spotting, stress et sommeil sans déclarer des règles',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      CycleEntry? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: CycleTrackingPage(
            patientId: 'test',
            initialEntries: const [],
            now: DateTime(2026, 3, 5),
            onSaveEntry: (value) async => saved = value,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('cycle-log-today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cycle-spotting-toggle')));
      await tester.scrollUntilVisible(
        find.byKey(const Key('cycle-stress-2')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.byKey(const Key('cycle-stress-2')));
      await tester.tap(find.byKey(const Key('cycle-stress-2')));
      await tester.ensureVisible(find.byKey(const Key('cycle-sleep-hours')));
      await tester.enterText(find.byKey(const Key('cycle-sleep-hours')), '7,5');
      await tester.ensureVisible(find.byKey(const Key('cycle-save-entry')));
      await tester.tap(find.byKey(const Key('cycle-save-entry')));
      await tester.pumpAndSettle();
      expect(saved!.isSpotting, isTrue);
      expect(saved!.isPeriod, isFalse);
      expect(saved!.stressLevel, 2);
      expect(saved!.sleepHours, 7.5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tendances et contexte restent utilisables sur petit écran', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entries = history([28, 32, 28], symptoms: true);
    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'small',
          initialEntries: entries,
          initialContext: natural,
          now: add(entries.last.date, 2),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-symptom-patterns')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('3 j avant les règles'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('cycle-edit-context')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cycle-save-context')));
    await tester.tap(find.byKey(const Key('cycle-save-context')));
    await tester.pumpAndSettle();
    expect(find.text('Mon contexte'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

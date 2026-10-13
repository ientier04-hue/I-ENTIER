import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

List<CycleEntry> _history(List<int> intervals, {int periodLength = 5}) {
  var start = DateTime(2024, 1, 1);
  final starts = [start];
  for (final interval in intervals) {
    start = _addDays(start, interval);
    starts.add(start);
  }
  return [
    for (final start in starts)
      for (var day = 0; day < periodLength; day++) _entry(_addDays(start, day)),
  ];
}

CycleEntry _entry(DateTime date, {bool isPeriod = true}) =>
    CycleEntry(id: cycleDateKey(date), date: date, isPeriod: isPeriod);

CycleInsights _insights(List<int> intervals, {int periodLength = 5}) {
  final entries = _history(intervals, periodLength: periodLength);
  return CycleInsights.fromEntries(
    entries,
    now: _addDays(entries.last.date, 2),
  );
}

void main() {
  test('adapte le centre à un allongement récent répété', () {
    final insights = _insights([...List.filled(9, 28), 32, 32, 32]);

    expect(insights.typicalCycleLength, 32);
    expect(insights.nextPeriodStart, _addDays(insights.lastPeriodStart!, 32));
    expect(
      insights.nextPeriodEarliest,
      _addDays(insights.lastPeriodStart!, 28),
    );
    expect(insights.nextPeriodLatest, _addDays(insights.lastPeriodStart!, 34));
    expect(insights.cycleSampleCount, 12);
  });

  test('adapte également le centre à un raccourcissement récent répété', () {
    final insights = _insights([...List.filled(9, 32), 28, 28, 28]);

    expect(insights.typicalCycleLength, 28);
    expect(
      insights.nextPeriodEarliest,
      _addDays(insights.lastPeriodStart!, 26),
    );
    expect(insights.nextPeriodLatest, _addDays(insights.lastPeriodStart!, 32));
  });

  for (final outlier in [18, 44]) {
    test('résiste à un dernier cycle isolé de $outlier jours', () {
      final insights = _insights([...List.filled(11, 28), outlier]);

      expect(insights.typicalCycleLength, 28);
      expect(insights.hasPossibleTrackingGap, isFalse);
      expect(insights.hasHighVariability, isTrue);
      expect(insights.historyQuality, CycleHistoryQuality.limited);
      final outlierDate = _addDays(insights.lastPeriodStart!, outlier);
      expect(outlierDate.isBefore(insights.nextPeriodEarliest!), isFalse);
      expect(outlierDate.isAfter(insights.nextPeriodLatest!), isFalse);
    });
  }

  test('ne réduit pas une plage large pour colorier le calendrier', () {
    final insights = _insights([...List.filled(11, 28), 44]);

    expect(insights.hasPrediction, isTrue);
    expect(insights.predictionWindowDays, 19);
    expect(insights.canHighlightPrediction, isFalse);
    expect(insights.isPredictedPeriod(insights.nextPeriodStart!), isFalse);
  });

  test('ne suspend pas une histoire variable pour un seul rapport double', () {
    final insights = _insights([20, 29, 40]);

    expect(insights.hasPossibleTrackingGap, isFalse);
    expect(insights.isPredictionSuspended, isFalse);
    expect(insights.typicalCycleLength, 29);
    expect(insights.hasHighVariability, isTrue);
    expect(insights.canHighlightPrediction, isFalse);
  });

  test('exige que les indices d’oubli concernent la majorité des cycles', () {
    final insights = _insights([20, 20, 40, 28, 33, 49, 72]);

    expect(insights.hasPossibleTrackingGap, isFalse);
    expect(insights.hasPrediction, isTrue);
    expect(insights.historyQuality, CycleHistoryQuality.limited);
  });

  for (final intervals in [
    [28, 28, 56],
    [28, 56, 56],
    [28, 28, 84],
    [27, 29, 57],
  ]) {
    test('conserve la suspension pour un oubli plausible : $intervals', () {
      final insights = _insights(intervals);

      expect(insights.hasPossibleTrackingGap, isTrue);
      expect(insights.isPredictionSuspended, isTrue);
      expect(insights.nextPeriodStart, isNull);
      expect(insights.predictionWindowDays, isNull);
    });
  }

  test('reprend la prévision après ajout des règles oubliées', () {
    final entries = _history([28, 28, 56]);
    final missingStart = DateTime(2024, 1, 1 + 84);
    final now = _addDays(entries.last.date, 2);
    expect(
      CycleInsights.fromEntries(entries, now: now).isPredictionSuspended,
      isTrue,
    );

    final corrected = CycleInsights.fromEntries([
      ...entries,
      for (var day = 0; day < 5; day++) _entry(_addDays(missingStart, day)),
    ], now: now);

    expect(corrected.isPredictionSuspended, isFalse);
    expect(corrected.typicalCycleLength, 28);
    expect(corrected.cycleSampleCount, 4);
  });

  test('ne réutilise pas les anciens cycles hors des douze derniers', () {
    final insights = _insights([
      ...List.filled(4, 28),
      ...List.filled(12, 10),
    ], periodLength: 3);

    expect(insights.cycleSampleCount, 0);
    expect(insights.additionalCyclesNeeded, 3);
    expect(insights.typicalCycleLength, isNull);
    expect(insights.historyQuality, CycleHistoryQuality.insufficient);
    expect(insights.hasOutOfRangeInterval, isTrue);
  });

  test('garde le contexte ambigu juste avant la fenêtre historique', () {
    final insights = _insights([28, 28, 28, 10, 18, ...List.filled(11, 28)]);

    expect(insights.cycleSampleCount, 11);
    expect(insights.typicalCycleLength, 28);
    expect(insights.cycleVariationDays, 0);
  });

  test('une journée explicitement sans règles sépare deux épisodes', () {
    final insights = CycleInsights.fromEntries([
      _entry(DateTime(2026, 1, 1)),
      _entry(DateTime(2026, 1, 2), isPeriod: false),
      _entry(DateTime(2026, 1, 3)),
    ], now: DateTime(2026, 1, 4));

    expect(insights.periodStarts, [DateTime(2026, 1, 1), DateTime(2026, 1, 3)]);
    expect(insights.hasRecentAmbiguousBleeding, isTrue);
    expect(insights.isPredictionSuspended, isTrue);
  });

  test('une journée non saisie reste dans le même épisode', () {
    final insights = CycleInsights.fromEntries([
      _entry(DateTime(2026, 1, 1)),
      _entry(DateTime(2026, 1, 3)),
    ], now: DateTime(2026, 1, 4));

    expect(insights.periodStarts, [DateTime(2026, 1, 1)]);
    expect(insights.hasIncompletePeriodRecord, isTrue);
    expect(insights.hasRecentAmbiguousBleeding, isFalse);
  });

  test('utilise douze épisodes terminés et exclut celui en cours', () {
    final entries = _history(List.filled(12, 28), periodLength: 4);
    final insights = CycleInsights.fromEntries(
      entries,
      now: _addDays(entries.last.date, 2),
    );

    expect(insights.periodSampleCount, 12);
    expect(insights.typicalPeriodLength, 4);
  });

  for (final length in [15, 90]) {
    test('maintient une plage de cinq jours à la borne $length', () {
      final insights = _insights([length, length, length], periodLength: 3);

      expect(insights.typicalCycleLength, length);
      expect(insights.predictionWindowDays, 5);
      expect(
        insights.nextPeriodStart!.isBefore(insights.nextPeriodEarliest!),
        isFalse,
      );
      expect(
        insights.nextPeriodStart!.isAfter(insights.nextPeriodLatest!),
        isFalse,
      );
    });
  }

  test(
    'les doublons, heures, ordre et entrées futures ne changent pas le calcul',
    () {
      final entries = _history([27, 29, 30, 28, 31, 29]);
      final now = _addDays(entries.last.date, 2);
      final expected = CycleInsights.fromEntries(entries, now: now);
      final shuffled = [
        ...entries,
        ...entries.map(
          (entry) => _entry(
            DateTime(entry.date.year, entry.date.month, entry.date.day, 18, 30),
          ),
        ),
        _entry(_addDays(now, 100)),
      ]..shuffle(math.Random(42));
      final actual = CycleInsights.fromEntries(shuffled, now: now);

      expect(actual.periodStarts, expected.periodStarts);
      expect(actual.cycleSampleCount, expected.cycleSampleCount);
      expect(actual.periodSampleCount, expected.periodSampleCount);
      expect(actual.typicalPeriodLength, expected.typicalPeriodLength);
      expect(actual.nextPeriodStart, expected.nextPeriodStart);
      expect(actual.nextPeriodEarliest, expected.nextPeriodEarliest);
      expect(actual.nextPeriodLatest, expected.nextPeriodLatest);
    },
  );

  test(
    'conserve les invariants de prévision sur des historiques variables',
    () {
      final random = math.Random(314);
      for (var sample = 0; sample < 150; sample++) {
        final count = 3 + random.nextInt(18);
        final intervals = List.generate(count, (_) => 24 + random.nextInt(15));
        final insights = _insights(intervals);

        expect(insights.hasPrediction, isTrue);
        expect(insights.cycleSampleCount, math.min(count, 12));
        expect(insights.predictionWindowDays, greaterThanOrEqualTo(5));
        expect(
          insights.nextPeriodStart!.isBefore(insights.nextPeriodEarliest!),
          isFalse,
        );
        expect(
          insights.nextPeriodStart!.isAfter(insights.nextPeriodLatest!),
          isFalse,
        );
        for (final interval in intervals.skip(math.max(0, count - 12))) {
          final observed = _addDays(insights.lastPeriodStart!, interval);
          expect(observed.isBefore(insights.nextPeriodEarliest!), isFalse);
          expect(observed.isAfter(insights.nextPeriodLatest!), isFalse);
        }
        expect(insights.ovulationDate, isNull);
        expect(insights.fertileWindowStart, isNull);
        expect(insights.fertileWindowEnd, isNull);
      }
    },
  );
}

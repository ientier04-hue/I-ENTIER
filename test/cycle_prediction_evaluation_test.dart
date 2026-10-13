import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_prediction_evaluation.dart';
import 'package:i_entier/cycle_tracking_page.dart';

DateTime _add(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

List<DateTime> _starts(List<int> lengths) {
  final starts = [DateTime(2024, 1, 1)];
  for (final length in lengths) {
    starts.add(_add(starts.last, length));
  }
  return starts;
}

List<CycleEntry> _history(List<int> lengths, {bool symptoms = false}) {
  final starts = _starts(lengths);
  return [
    for (final start in starts)
      for (var day = 0; day < 4; day++)
        CycleEntry(
          id: 'sensitive-id-${cycleDateKey(_add(start, day))}',
          date: _add(start, day),
          isPeriod: true,
          note: 'private text',
        ),
    if (symptoms)
      for (final next in starts.skip(1))
        CycleEntry(
          id: 'symptom-$next',
          date: _add(next, -3),
          symptoms: const ['tenderBreasts'],
        ),
  ];
}

const _natural = CyclePersonalContext(
  lifeStage: CycleLifeStage.menstruating,
  contraception: CycleContraception.none,
);

void main() {
  test('reports known forecast errors with distinct accuracy denominators', () {
    final lengths = [28, 28, 28, 35, 28];
    final result = CyclePredictionEvaluator.evaluate(
      _history(lengths),
      now: _add(_starts(lengths).last, 9),
      evaluationCycleDays: [10],
    );
    final summary = result.summary;
    expect(summary.candidateCheckpointCount, 6);
    expect(summary.eligibleCheckpointCount, 6);
    expect(summary.forecastCount, 3);
    expect(summary.forecastAvailabilityRate, .5);
    expect(summary.scorableOutcomeCount, 5);
    expect(summary.scoredForecastCount, 2);
    expect(summary.meanAbsoluteErrorDays, 3.5);
    expect(summary.withinTwoDaysRate, .5);
    expect(summary.windowCoverageRate, .5);
    expect(summary.meanScoredWindowWidthDays, 7.5);
    expect(summary.exclusions[CycleEvaluationExclusion.missingOutcome], 1);
    expect(
      summary.unavailableForecasts[CycleForecastUnavailable
          .insufficientHistory],
      3,
    );
    expect(result.cases.last.absoluteErrorDays, isNull);
    expect(result.cases.last.withinWindow, isNull);
    expect(result.cases.first.absoluteErrorDays, isNull);
  });

  test('keeps day 10 and day 20 separate and pending checkpoints visible', () {
    final lengths = List.filled(6, 28);
    final result = CyclePredictionEvaluator.evaluate(
      _history(lengths),
      now: _add(_starts(lengths).last, 9),
    );
    expect(result.byCycleDay.keys, [10, 20]);
    expect(result.byCycleDay[10]!.eligibleCheckpointCount, 7);
    expect(result.byCycleDay[20]!.eligibleCheckpointCount, 6);
    expect(result.byCycleDay[10]!.forecastCount, 4);
    expect(result.byCycleDay[20]!.forecastCount, 3);
    expect(result.byCycleDay[10]!.scoredForecastCount, 3);
    expect(result.byCycleDay[20]!.scoredForecastCount, 3);
    expect(result.summary.scoredForecastCount, 6);
    expect(result.summary.distinctScoredCycleCount, 3);
    expect(result.summary.meanAbsoluteErrorDays, 0);
    expect(result.summary.withinTwoDaysRate, 1);
    expect(result.summary.windowCoverageRate, 1);
    expect(
      result.cases.last.exclusion,
      CycleEvaluationExclusion.checkpointNotReached,
    );
  });

  test('never moves a checkpoint to before an early observed outcome', () {
    final lengths = [28, 28, 28, 18, 28];
    final starts = _starts(lengths);
    final result = CyclePredictionEvaluator.evaluate(
      _history(lengths),
      now: _add(starts.last, 20),
    );
    final early = result.cases.where((row) => row.cycleStart == starts[3]);
    expect(early.first.evaluationCycleDay, 10);
    expect(early.first.isScored, isTrue);
    expect(early.first.absoluteErrorDays, 10);
    expect(early.last.asOf, _add(starts[3], 19));
    expect(
      early.last.exclusion,
      CycleEvaluationExclusion.outcomeAlreadyObserved,
    );
    expect(early.last.checkpointEligible, isFalse);
    expect(early.last.hasForecast, isFalse);
    expect(result.byCycleDay[10]!.scoredForecastCount, 2);
    expect(result.byCycleDay[20]!.scoredForecastCount, 1);
  });

  test('predicts only from each prefix, including symptom learning', () {
    final lengths = [28, 32, 28, 32, 28, 32, 28, 32];
    final starts = _starts(lengths);
    final entries = _history(lengths, symptoms: true);
    final result = CyclePredictionEvaluator.evaluate(
      entries,
      now: _add(starts.last, 10),
      stableContext: _natural,
      evaluationCycleDays: [28, 30],
    );
    for (final row in result.cases.where((row) => row.checkpointEligible)) {
      final prefix = CycleInsights.fromEntries(
        entries.where((entry) => !entry.date.isAfter(row.asOf)),
        now: row.asOf,
        personalContext: _natural,
      );
      expect(row.predictedNextPeriod, prefix.nextPeriodStart);
      expect(row.trainingCycleCount, prefix.cycleSampleCount);
      expect(row.usedSymptomAdjustment, prefix.usedSymptomAdjustment);
    }
    final current = result.cases.where((row) => row.cycleStart == starts[7]);
    // The day-30 symptom must not leak into the fixed day-28 forecast.
    expect(current.first.usedSymptomAdjustment, isFalse);
    expect(current.first.predictedNextPeriod, _add(starts[7], 28));
    expect(current.last.usedSymptomAdjustment, isTrue);
    expect(current.last.predictedNextPeriod, _add(starts[7], 30));
  });

  test('future outcome changes cannot change an earlier forecast', () {
    final earlier = [28, 28, 28];
    final short = [...earlier, 26];
    final long = [...earlier, 38];
    final now = _add(_starts(long).last, 9);
    final results = [
      for (final lengths in [short, long])
        CyclePredictionEvaluator.evaluate(
          _history(lengths),
          now: now,
          evaluationCycleDays: [10],
        ),
    ];
    final start = _starts(earlier).last;
    final rows = [
      for (final result in results)
        result.cases.singleWhere((row) => row.cycleStart == start),
    ];
    expect(rows[0].predictedNextPeriod, rows[1].predictedNextPeriod);
    expect(rows[0].earliest, rows[1].earliest);
    expect(rows[0].latest, rows[1].latest);
    expect(rows[0].absoluteErrorDays, 2);
    expect(rows[1].absoluteErrorDays, 10);
  });

  test('future entries do not complete the ongoing cycle', () {
    final lengths = List.filled(6, 28);
    final entries = _history(lengths);
    final now = _add(_starts(lengths)[4], 15);
    final all = CyclePredictionEvaluator.evaluate(entries, now: now);
    final prefix = CyclePredictionEvaluator.evaluate(
      entries.where((entry) => !entry.date.isAfter(now)),
      now: now,
    );
    expect(all.toJson(), prefix.toJson());
    expect(all.cases.last.observedNextPeriod, isNull);
    expect(all.summary.exclusions[CycleEvaluationExclusion.missingOutcome], 1);
    expect(all.summary.scoredForecastCount, 2);
  });

  test(
    'suspected missed periods remain excluded with forecasts accounted for',
    () {
      final lengths = [28, 28, 28, 56, 28];
      final result = CyclePredictionEvaluator.evaluate(
        _history(lengths),
        now: _add(_starts(lengths).last, 9),
        evaluationCycleDays: [10],
      );
      final missed = result.cases[3];
      expect(missed.hasForecast, isTrue);
      expect(missed.checkpointEligible, isTrue);
      expect(
        missed.exclusion,
        CycleEvaluationExclusion.ambiguousTrackingHistory,
      );
      expect(missed.absoluteErrorDays, isNull);
      expect(result.summary.forecastCount, 1);
      expect(result.summary.scoredForecastCount, 0);
      expect(result.summary.meanAbsoluteErrorDays, isNull);
      expect(result.summary.windowCoverageRate, isNull);
      expect(
        result.summary.exclusions[CycleEvaluationExclusion
            .ambiguousTrackingHistory],
        2,
      );
      expect(
        result.summary.unavailableForecasts[CycleForecastUnavailable
            .possibleTrackingGap],
        2,
      );
    },
  );

  test(
    'short intervals, their successors and breaks are explicitly excluded',
    () {
      final lengths = [28, 28, 28, 10, 18, 100, 28];
      final result = CyclePredictionEvaluator.evaluate(
        _history(lengths),
        now: _add(_starts(lengths).last, 9),
        evaluationCycleDays: [10],
      );
      expect(
        result.cases[3].exclusion,
        CycleEvaluationExclusion.outcomeTooShort,
      );
      expect(
        result.cases[4].exclusion,
        CycleEvaluationExclusion.outcomeAfterShortInterval,
      );
      expect(
        result.cases[5].exclusion,
        CycleEvaluationExclusion.outcomeHistoryBreak,
      );
      expect(result.cases[6].trainingCycleCount, 0);
      expect(result.cases[6].exclusion, isNull);
      expect(
        result.cases[6].forecastUnavailable,
        CycleForecastUnavailable.insufficientHistory,
      );
    },
  );

  test('retains variable cycles which are neither missing nor malformed', () {
    final lengths = [24, 33, 27, 38, 26, 35];
    final result = CyclePredictionEvaluator.evaluate(
      _history(lengths),
      now: _add(_starts(lengths).last, 19),
    );
    expect(result.summary.scorableOutcomeCount, 12);
    expect(result.summary.scoredForecastCount, 6);
    expect(result.summary.exclusions, {
      CycleEvaluationExclusion.missingOutcome: 2,
    });
    expect(result.summary.meanAbsoluteErrorDays, greaterThan(0));
  });

  test(
    'a context transition cannot turn a partial episode into a new cycle',
    () {
      final lengths = List.filled(9, 28);
      final starts = _starts(lengths);
      final result = CyclePredictionEvaluator.evaluate(
        _history(lengths),
        now: _add(starts.last, 9),
        stableContext: CyclePersonalContext(
          lifeStage: CycleLifeStage.menstruating,
          contraception: CycleContraception.none,
          historyStart: _add(starts[4], 2),
        ),
        evaluationCycleDays: [10],
      );
      expect(result.stableContextExplicitlyProvided, isTrue);
      expect(result.contextKey, 'menstruating/none');
      expect(
        result.summary.exclusions[CycleEvaluationExclusion.beforeContextStart],
        5,
      );
      expect(result.cases[4].checkpointEligible, isFalse);
      expect(result.cases[5].trainingCycleCount, 0);
      expect(result.cases[8].trainingCycleCount, 3);
      expect(result.summary.scoredForecastCount, 1);
      expect(result.cases.map((row) => row.cycleStart), starts);
    },
  );

  test(
    'does not infer a natural context and counts suppressed predictions',
    () {
      final lengths = List.filled(8, 28);
      final entries = _history(lengths);
      final now = _add(_starts(lengths).last, 9);
      final unspecified = CyclePredictionEvaluator.evaluate(
        entries,
        now: now,
        evaluationCycleDays: [10],
      );
      expect(unspecified.stableContextExplicitlyProvided, isFalse);
      expect(unspecified.context.lifeStage, CycleLifeStage.unspecified);
      expect(unspecified.contextKey, 'unspecified/unspecified');
      final pregnant = CyclePredictionEvaluator.evaluate(
        entries,
        now: now,
        stableContext: const CyclePersonalContext(
          lifeStage: CycleLifeStage.pregnant,
        ),
        evaluationCycleDays: [10],
      );
      expect(pregnant.summary.eligibleCheckpointCount, 9);
      expect(pregnant.summary.forecastAvailabilityRate, 0);
      expect(pregnant.summary.scorableOutcomeCount, 8);
      expect(pregnant.summary.scoredForecastCount, 0);
      expect(pregnant.summary.meanAbsoluteErrorDays, isNull);
      expect(pregnant.summary.withinTwoDaysRate, isNull);
      expect(pregnant.summary.windowCoverageRate, isNull);
      expect(
        pregnant.summary.unavailableForecasts[CycleForecastUnavailable
            .personalContext],
        9,
      );
    },
  );

  test(
    'PCOS context preserves its larger training requirement and group label',
    () {
      final lengths = List.filled(8, 28);
      final result = CyclePredictionEvaluator.evaluate(
        _history(lengths),
        now: _add(_starts(lengths).last, 9),
        stableContext: const CyclePersonalContext(
          lifeStage: CycleLifeStage.menstruating,
          contraception: CycleContraception.none,
          hasPcos: true,
        ),
        evaluationCycleDays: [10],
      );
      expect(result.contextKey, 'menstruating/none/pcos');
      expect(result.summary.forecastCount, 3);
      expect(result.summary.scoredForecastCount, 2);
      expect(result.cases[5].hasForecast, isFalse);
      expect(result.cases[6].hasForecast, isTrue);
    },
  );

  test(
    'empty histories have null rates, never fabricated perfect accuracy',
    () {
      final result = CyclePredictionEvaluator.evaluate(
        [],
        now: DateTime(2026, 1, 1),
      );
      expect(result.cases, isEmpty);
      expect(result.summary.scoredForecastCount, 0);
      expect(result.summary.forecastAvailabilityRate, isNull);
      expect(result.summary.meanAbsoluteErrorDays, isNull);
      expect(result.summary.withinTwoDaysRate, isNull);
      expect(result.summary.windowCoverageRate, isNull);
    },
  );

  test(
    'exports dates and metrics without identifiers, notes or raw symptoms',
    () {
      final lengths = List.filled(5, 28);
      final result = CyclePredictionEvaluator.evaluate(
        _history(lengths, symptoms: true),
        now: DateTime(2024, 6, 1, 23, 59),
        evaluationCycleDays: [10],
      );
      final encoded = jsonEncode(result.toJson());
      expect(encoded, isNot(contains('sensitive-id')));
      expect(encoded, isNot(contains('private text')));
      expect(encoded, isNot(contains('tenderBreasts')));
      expect(encoded, isNot(contains('T00:00')));
      expect(jsonDecode(encoded)['as_of'], '2024-06-01');
    },
  );

  test('calendar dates remain stable across leap day and times of day', () {
    final lengths = List.filled(6, 28);
    final entries = _history(lengths);
    final now = _add(_starts(lengths).last, 19);
    final original = CyclePredictionEvaluator.evaluate(entries, now: now);
    final shiftedTimes = CyclePredictionEvaluator.evaluate(
      entries.map(
        (entry) => CycleEntry(
          id: entry.id,
          date: DateTime.utc(
            entry.date.year,
            entry.date.month,
            entry.date.day,
            23,
          ),
          isPeriod: entry.isPeriod,
        ),
      ),
      now: DateTime.utc(now.year, now.month, now.day, 1),
    );
    expect(shiftedTimes.toJson(), original.toJson());
    expect(original.summary.meanAbsoluteErrorDays, 0);
  });

  test('requires distinct fixed positive checkpoints', () {
    for (final days in <List<int>>[
      [],
      [0],
      [-1, 10],
      [10, 10],
    ]) {
      expect(
        () => CyclePredictionEvaluator.evaluate(
          [],
          now: DateTime(2026),
          evaluationCycleDays: days,
        ),
        throwsArgumentError,
      );
    }
  });
}

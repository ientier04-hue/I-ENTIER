import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';

const _natural = CyclePersonalContext(
  lifeStage: CycleLifeStage.menstruating,
  contraception: CycleContraception.none,
);

DateTime _day(DateTime date, int offset) =>
    DateTime(date.year, date.month, date.day + offset);

final _start = DateTime(2025, 1, 1);
const _learningLengths = [28, 28, 28, 30, 30, 30];

DateTime _currentStart(List<int> lengths) =>
    _day(_start, lengths.fold(0, (sum, value) => sum + value));

List<CycleEntry> _thermal(DateTime onset, {double increase = 0.3}) => [
  for (var offset = -6; offset <= 2; offset++)
    CycleEntry(
      id: 'temperature-${cycleDateKey(_day(onset, offset))}',
      date: _day(onset, offset),
      basalTemperatureC: offset < 0 ? 36.2 : 36.2 + increase,
    ),
];

List<CycleEntry> _history(List<int> lengths, {int? lhLead, int? thermalLead}) {
  var start = _start;
  final entries = <CycleEntry>[];
  for (final length in [...lengths, 0]) {
    for (var day = 0; day < 4; day++) {
      final date = _day(start, day);
      entries.add(
        CycleEntry(id: cycleDateKey(date), date: date, isPeriod: true),
      );
    }
    if (length > 0 && lhLead != null) {
      final date = _day(start, length - lhLead);
      entries.add(
        CycleEntry(
          id: 'lh-${cycleDateKey(date)}',
          date: date,
          lhTest: 'positive',
        ),
      );
    }
    if (length > 0 && thermalLead != null) {
      entries.addAll(_thermal(_day(start, length - thermalLead)));
    }
    start = _day(start, length);
  }
  return entries;
}

CycleInsights _insights(
  List<CycleEntry> entries,
  DateTime now, {
  CyclePersonalContext context = _natural,
}) => CycleInsights.fromEntries(entries, now: now, personalContext: context);

void main() {
  test(
    'a contiguous positive LH run is one observation, including duplicate rows',
    () {
      final entries = _history([28, 28, 28]);
      final start = _currentStart([28, 28, 28]);
      final first = _day(start, 15);
      entries.addAll([
        CycleEntry(id: 'a', date: first, lhTest: 'positive'),
        CycleEntry(id: 'duplicate', date: first, lhTest: 'positive'),
        CycleEntry(id: 'b', date: _day(first, 1), lhTest: 'positive'),
        CycleEntry(id: 'c', date: _day(first, 2), lhTest: 'negative'),
      ]);
      final result = _insights(entries, _day(first, 2));
      expect(result.physiology.positiveLhDate, first);
      expect(result.physiology.hasAmbiguousLh, isFalse);
      expect(result.physiology.proposedPeriodStart, isNull);
      expect(result.ovulationDate, isNull);
      expect(result.fertileWindowStart, isNull);
    },
  );

  test(
    'learns a personal LH-to-period interval with three chronological validations',
    () {
      final entries = _history(_learningLengths, lhLead: 12);
      final start = _currentStart(_learningLengths);
      final signal = _day(start, 16);
      entries.add(CycleEntry(id: 'current', date: signal, lhTest: 'positive'));
      final result = _insights(entries, signal);
      final pattern = result.physiology.patterns.single;
      expect(pattern.signal, 'lh');
      expect(pattern.observedCycles, 6);
      expect(pattern.leadDays, 12);
      expect(pattern.validationCycles, 3);
      expect(pattern.canAdjustPrediction, isTrue);
      expect(pattern.adjustedMeanErrorDays, 0);
      expect(result.physiology.proposedPeriodStart, _day(start, 28));
      expect(result.usedPhysiologyAdjustment, isTrue);
      expect(result.nextPeriodStart, _day(start, 28));
      expect(result.nextPeriodEarliest, _day(start, 28));
      expect(result.nextPeriodLatest, _day(start, 32));
    },
  );

  test('does not change prediction with only two validation outcomes', () {
    const lengths = [28, 28, 28, 30, 30];
    final entries = _history(lengths, lhLead: 12);
    final start = _currentStart(lengths);
    entries.add(
      CycleEntry(id: 'current', date: _day(start, 16), lhTest: 'positive'),
    );
    final result = _insights(entries, _day(start, 16));
    expect(result.physiology.patterns.single.validationCycles, 2);
    expect(result.physiology.patterns.single.canAdjustPrediction, isFalse);
    expect(result.usedPhysiologyAdjustment, isFalse);
    expect(result.physiology.proposedPeriodStart, isNull);
  });

  test(
    'does not personalize when signal fails to improve the calendar baseline',
    () {
      final lengths = List.filled(8, 28);
      final entries = _history(lengths, lhLead: 12);
      final start = _currentStart(lengths);
      entries.add(
        CycleEntry(id: 'current', date: _day(start, 14), lhTest: 'positive'),
      );
      final result = _insights(entries, _day(start, 14));
      expect(result.physiology.patterns.single.baselineMeanErrorDays, 0);
      expect(result.physiology.patterns.single.canAdjustPrediction, isFalse);
      expect(result.physiology.proposedPeriodStart, isNull);
    },
  );

  test(
    'separated positive runs are ambiguous and cannot adjust a current forecast',
    () {
      final entries = _history(_learningLengths, lhLead: 12);
      final start = _currentStart(_learningLengths);
      entries.addAll([
        CycleEntry(id: 'first', date: _day(start, 16), lhTest: 'positive'),
        CycleEntry(id: 'second', date: _day(start, 18), lhTest: 'positive'),
      ]);
      final result = _insights(entries, _day(start, 18));
      expect(result.physiology.hasAmbiguousLh, isTrue);
      expect(result.physiology.positiveLhDate, isNull);
      expect(result.physiology.proposedPeriodStart, isNull);
      expect(result.usedPhysiologyAdjustment, isFalse);
    },
  );

  test(
    'contradictory same-day LH records are rejected independent of entry order',
    () {
      final entries = _history(_learningLengths, lhLead: 12);
      final start = _currentStart(_learningLengths);
      final date = _day(start, 16);
      entries.addAll([
        CycleEntry(id: 'a', date: date, lhTest: 'positive'),
        CycleEntry(id: 'b', date: date, lhTest: 'negative'),
      ]);
      for (final ordered in [entries, entries.reversed.toList()]) {
        final result = _insights(ordered, date);
        expect(result.physiology.hasAmbiguousLh, isTrue);
        expect(result.physiology.proposedPeriodStart, isNull);
      }
    },
  );

  test(
    'future outcomes and signals do not train or invalidate today’s forecast',
    () {
      final entries = _history(_learningLengths, lhLead: 12);
      final thirdEnd = _currentStart([28, 28, 28]);
      final early = _insights(entries, _day(thirdEnd, 5));
      expect(early.physiology.patterns.single.observedCycles, 3);
      expect(early.physiology.patterns.single.validationCycles, 0);
      expect(early.physiology.positiveLhDate, isNull);

      final start = _currentStart(_learningLengths);
      final now = _day(start, 16);
      entries.addAll([
        CycleEntry(id: 'now', date: now, lhTest: 'positive'),
        CycleEntry(id: 'future', date: _day(now, 3), lhTest: 'positive'),
      ]);
      final result = _insights(entries, now);
      expect(result.physiology.hasAmbiguousLh, isFalse);
      expect(result.physiology.patterns.single.observedCycles, 6);
      expect(result.physiology.proposedPeriodStart, _day(start, 28));
    },
  );

  test('later ambiguous runs do not retroactively remove a validation', () {
    final entries = _history(_learningLengths, lhLead: 12);
    final fourthStart = _currentStart([28, 28, 28]);
    entries.add(
      CycleEntry(
        id: 'later-run',
        date: _day(fourthStart, 21),
        lhTest: 'positive',
      ),
    );
    final result = _insights(entries, _day(_currentStart(_learningLengths), 5));
    final pattern = result.physiology.patterns.single;
    expect(pattern.observedCycles, 5);
    expect(pattern.validationCycles, 3);
    expect(pattern.adjustedMeanErrorDays, 0);
  });

  test('missing signals count as unchanged baseline during validation', () {
    final entries = _history(_learningLengths, lhLead: 12);
    final fourthStart = _currentStart([28, 28, 28]);
    final missingDay = _day(fourthStart, 18);
    entries.removeWhere(
      (entry) => entry.date == missingDay && entry.lhTest.isNotEmpty,
    );
    final result = _insights(entries, _day(_currentStart(_learningLengths), 5));
    final pattern = result.physiology.patterns.single;
    expect(pattern.validationCycles, 3);
    expect(pattern.observedCycles, 5);
    expect(pattern.adjustedMeanErrorDays, closeTo(2 / 3, 1e-9));
  });

  test(
    'cannot propose outside the original calendar window or after the candidate has passed',
    () {
      final entries = _history(_learningLengths, lhLead: 12);
      final start = _currentStart(_learningLengths);
      entries.add(
        CycleEntry(id: 'too-early', date: _day(start, 10), lhTest: 'positive'),
      );
      expect(
        _insights(entries, _day(start, 10)).physiology.proposedPeriodStart,
        isNull,
      );

      entries.removeLast();
      entries.add(
        CycleEntry(id: 'valid', date: _day(start, 16), lhTest: 'positive'),
      );
      final passed = _insights(entries, _day(start, 29));
      expect(passed.physiology.proposedPeriodStart, isNull);
      expect(passed.nextPeriodStart, _day(start, 30));
      final overdue = _insights(entries, _day(start, 40));
      expect(overdue.physiology.proposedPeriodStart, isNull);
      expect(overdue.nextPeriodStart, _day(start, 30));
    },
  );

  for (final context in [
    const CyclePersonalContext(),
    const CyclePersonalContext(lifeStage: CycleLifeStage.menstruating),
    const CyclePersonalContext(lifeStage: CycleLifeStage.pregnant),
    const CyclePersonalContext(lifeStage: CycleLifeStage.postpartum),
    const CyclePersonalContext(lifeStage: CycleLifeStage.perimenopause),
    const CyclePersonalContext(lifeStage: CycleLifeStage.menopause),
    const CyclePersonalContext(
      lifeStage: CycleLifeStage.menstruating,
      contraception: CycleContraception.hormonal,
    ),
    const CyclePersonalContext(
      lifeStage: CycleLifeStage.menstruating,
      contraception: CycleContraception.none,
      breastfeeding: true,
    ),
    const CyclePersonalContext(
      lifeStage: CycleLifeStage.menstruating,
      contraception: CycleContraception.none,
      hasPcos: true,
    ),
  ]) {
    test(
      'physiology inference requires explicit eligible context: ${context.lifeStage}/${context.contraception}/${context.breastfeeding}/${context.hasPcos}',
      () {
        final entries = _history(_learningLengths, lhLead: 12, thermalLead: 10);
        final start = _currentStart(_learningLengths);
        entries.add(
          CycleEntry(id: 'current', date: _day(start, 16), lhTest: 'positive'),
        );
        entries.addAll(_thermal(_day(start, 18)));
        final result = _insights(entries, _day(start, 20), context: context);
        expect(result.physiology.patterns, isEmpty);
        expect(result.physiology.positiveLhDate, isNull);
        expect(result.physiology.thermalShiftStart, isNull);
        expect(result.physiology.proposedPeriodStart, isNull);
      },
    );
  }

  test(
    'tracking gaps and ambiguous bleeding keep physiology adjustments suspended',
    () {
      for (final extraLength in [56, 14]) {
        final lengths = [..._learningLengths, extraLength];
        final entries = _history(lengths, lhLead: 12);
        final start = _currentStart(lengths);
        entries.add(
          CycleEntry(id: 'current', date: _day(start, 16), lhTest: 'positive'),
        );
        final result = _insights(entries, _day(start, 16));
        expect(result.isPredictionSuspended, isTrue);
        expect(result.physiology.proposedPeriodStart, isNull);
      }
    },
  );

  test('new personal context segments discard old physiology learning', () {
    final entries = _history(_learningLengths, lhLead: 12);
    final start = _currentStart(_learningLengths);
    entries.add(
      CycleEntry(id: 'current', date: _day(start, 16), lhTest: 'positive'),
    );
    final result = _insights(
      entries,
      _day(start, 16),
      context: CyclePersonalContext(
        lifeStage: CycleLifeStage.menstruating,
        contraception: CycleContraception.none,
        historyStart: _currentStart([28, 28, 28, 30]),
      ),
    );
    expect(result.physiology.patterns, isEmpty);
    expect(result.physiology.proposedPeriodStart, isNull);
  });

  test(
    'thermal trend needs six low and three high daily readings before becoming visible',
    () {
      final entries = _history([28, 28, 28]);
      final onset = _day(_currentStart([28, 28, 28]), 17);
      entries.addAll(_thermal(onset));
      expect(
        _insights(entries, _day(onset, 1)).physiology.thermalShiftStart,
        isNull,
      );
      expect(
        _insights(entries, _day(onset, 2)).physiology.thermalShiftStart,
        onset,
      );
      expect(_insights(entries, _day(onset, 2)).ovulationDate, isNull);
    },
  );

  test(
    'a missing or disturbed reading anywhere in the nine-day run breaks thermal evidence',
    () {
      final base = _history([28, 28, 28]);
      final onset = _day(_currentStart([28, 28, 28]), 17);
      for (var offset = -6; offset <= 2; offset++) {
        final missing = [...base, ..._thermal(onset)]
          ..removeWhere((entry) => entry.date == _day(onset, offset));
        expect(
          _insights(missing, _day(onset, 2)).physiology.thermalShiftStart,
          isNull,
          reason: 'missing day $offset',
        );
        final disturbed = [
          ...base,
          ..._thermal(onset),
          CycleEntry(
            id: 'disturbed',
            date: _day(onset, offset),
            temperatureDisturbed: true,
          ),
        ];
        expect(
          _insights(disturbed, _day(onset, 2)).physiology.thermalShiftStart,
          isNull,
          reason: 'disturbed day $offset',
        );
      }
    },
  );

  test(
    'duplicate temperatures do not multiply evidence and contradictions break the run',
    () {
      final base = _history([28, 28, 28]);
      final onset = _day(_currentStart([28, 28, 28]), 17);
      final original = _thermal(onset);
      final identical = [...base, ...original, ...original];
      expect(
        _insights(identical, _day(onset, 2)).physiology.thermalShiftStart,
        onset,
      );
      final conflict = [
        ...identical,
        CycleEntry(id: 'other', date: onset, basalTemperatureC: 36.8),
      ];
      for (final ordered in [conflict, conflict.reversed.toList()]) {
        expect(
          _insights(ordered, _day(onset, 2)).physiology.thermalShiftStart,
          isNull,
        );
      }
    },
  );

  test(
    'invalid temperatures and large transient increases cannot produce a thermal marker',
    () {
      final base = _history([28, 28, 28]);
      final onset = _day(_currentStart([28, 28, 28]), 17);
      for (final invalid in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        33.9,
        42.1,
      ]) {
        final values = _thermal(onset)
          ..removeWhere((entry) => entry.date == onset);
        values.add(
          CycleEntry(id: 'invalid', date: onset, basalTemperatureC: invalid),
        );
        expect(
          _insights([
            ...base,
            ...values,
          ], _day(onset, 2)).physiology.thermalShiftStart,
          isNull,
        );
      }
      expect(
        _insights([
          ...base,
          ..._thermal(onset, increase: 1.2),
        ], _day(onset, 2)).physiology.thermalShiftStart,
        isNull,
      );
    },
  );

  test(
    'thermal learning uses personal observed lead rather than a fixed luteal duration',
    () {
      final entries = _history(_learningLengths, thermalLead: 9);
      final start = _currentStart(_learningLengths);
      final onset = _day(start, 19);
      entries.addAll(_thermal(onset));
      final before = _insights(entries, _day(onset, 1));
      expect(before.physiology.proposedPeriodStart, isNull);
      final result = _insights(entries, _day(onset, 2));
      final pattern = result.physiology.patterns.single;
      expect(pattern.signal, 'thermal');
      expect(pattern.leadDays, 9);
      expect(pattern.validationCycles, 3);
      expect(pattern.adjustedMeanErrorDays, 0);
      expect(result.physiology.thermalShiftStart, onset);
      expect(result.physiology.proposedPeriodStart, _day(start, 28));
      expect(result.nextPeriodStart, _day(start, 28));
    },
  );

  test(
    'conflicting LH and temperature proposals do not get averaged into a forecast',
    () {
      final entries = _history(_learningLengths, lhLead: 12, thermalLead: 9);
      final start = _currentStart(_learningLengths);
      entries.add(
        CycleEntry(id: 'current', date: _day(start, 16), lhTest: 'positive'),
      );
      entries.addAll(_thermal(_day(start, 23)));
      final result = _insights(entries, _day(start, 25));
      expect(result.physiology.patterns.length, 2);
      expect(
        result.physiology.patterns.every(
          (pattern) => pattern.canAdjustPrediction,
        ),
        isTrue,
      );
      expect(result.physiology.proposedPeriodStart, isNull);
      expect(result.usedPhysiologyAdjustment, isFalse);
      expect(result.nextPeriodStart, _day(start, 30));
    },
  );

  test(
    'cervical mucus observations alone do not infer fertility or move period dates',
    () {
      final entries = _history(_learningLengths);
      final start = _currentStart(_learningLengths);
      entries.add(
        CycleEntry(
          id: 'mucus',
          date: _day(start, 16),
          cervicalMucus: 'stretchy',
        ),
      );
      final result = _insights(entries, _day(start, 16));
      expect(result.physiology.patterns, isEmpty);
      expect(result.physiology.proposedPeriodStart, isNull);
      expect(result.ovulationDate, isNull);
      expect(result.fertileWindowStart, isNull);
      expect(result.nextPeriodStart, _day(start, 30));
    },
  );

  List<CycleEntry> symptomHistory() {
    final entries = _history(_learningLengths, lhLead: 12);
    var start = _start;
    for (final length in _learningLengths) {
      entries.add(
        CycleEntry(
          id: 'symptom-${cycleDateKey(start)}',
          date: _day(start, length - 7),
          symptoms: const ['tenderBreasts'],
        ),
      );
      start = _day(start, length);
    }
    return entries;
  }

  test('symptoms and physiology cannot stack adjustments beyond two days', () {
    final entries = symptomHistory();
    final start = _currentStart(_learningLengths);
    entries.addAll([
      CycleEntry(id: 'lh', date: _day(start, 16), lhTest: 'positive'),
      CycleEntry(
        id: 'symptom',
        date: _day(start, 21),
        symptoms: const ['tenderBreasts'],
      ),
    ]);
    final result = _insights(entries, _day(start, 21));
    expect(result.symptomPatterns.single.canAdjustPrediction, isTrue);
    expect(result.physiology.patterns.single.canAdjustPrediction, isTrue);
    expect(result.usedPhysiologyAdjustment, isTrue);
    expect(result.usedSymptomAdjustment, isTrue);
    expect(result.nextPeriodStart, _day(start, 28));
    expect(result.nextPeriodEarliest, _day(start, 28));
    expect(result.nextPeriodLatest, _day(start, 32));
    final baseline = _insights(_history(_learningLengths), _day(start, 21));
    expect(result.historyQuality, baseline.historyQuality);
  });

  test(
    'conflicting symptom and physiology dates preserve the calendar forecast',
    () {
      final entries = symptomHistory();
      final start = _currentStart(_learningLengths);
      entries.addAll([
        CycleEntry(id: 'lh', date: _day(start, 16), lhTest: 'positive'),
        CycleEntry(
          id: 'symptom',
          date: _day(start, 25),
          symptoms: const ['tenderBreasts'],
        ),
      ]);
      final result = _insights(entries, _day(start, 25));
      expect(result.symptomPatterns.single.canAdjustPrediction, isTrue);
      expect(result.physiology.proposedPeriodStart, _day(start, 28));
      expect(result.usedPhysiologyAdjustment, isFalse);
      expect(result.usedSymptomAdjustment, isFalse);
      expect(result.nextPeriodStart, _day(start, 30));
    },
  );

  test('multiple thermal rises in one cycle are ambiguous', () {
    final entries = _history(_learningLengths, thermalLead: 9);
    final start = _currentStart(_learningLengths);
    entries.addAll(_thermal(_day(start, 16)));
    entries.addAll(_thermal(_day(start, 25)));
    final result = _insights(entries, _day(start, 27));
    expect(result.physiology.hasAmbiguousTemperature, isTrue);
    expect(result.physiology.thermalShiftStart, isNull);
    expect(result.physiology.proposedPeriodStart, isNull);
  });

  test(
    'thermal confirmation cannot borrow readings from the following cycle',
    () {
      final entries = _history(_learningLengths, thermalLead: 1);
      final start = _currentStart(_learningLengths);
      final result = _insights(entries, _day(start, 5));
      expect(result.physiology.patterns, isEmpty);
      expect(result.physiology.thermalShiftStart, isNull);
    },
  );

  test(
    'an intermediate physiology average cannot hide conflicting raw signals',
    () {
      final entries = symptomHistory()
          .map(
            (entry) => entry.symptoms.isEmpty
                ? entry
                : entry.copyWith(symptoms: const ['tenderBreasts', 'headache']),
          )
          .toList();
      var pastStart = _start;
      for (final length in _learningLengths) {
        entries.addAll(_thermal(_day(pastStart, length - 9)));
        pastStart = _day(pastStart, length);
      }
      final start = _currentStart(_learningLengths);
      entries.addAll([
        CycleEntry(id: 'lh', date: _day(start, 16), lhTest: 'positive'),
        ..._thermal(_day(start, 21)),
        CycleEntry(
          id: 'symptom',
          date: _day(start, 24),
          symptoms: const ['tenderBreasts', 'headache'],
        ),
      ]);
      final result = _insights(entries, _day(start, 24));
      expect(result.physiology.proposedPeriodStarts, [
        _day(start, 28),
        _day(start, 30),
      ]);
      expect(result.physiology.proposedPeriodStart, _day(start, 29));
      expect(result.usedPhysiologyAdjustment, isFalse);
      expect(result.usedSymptomAdjustment, isFalse);
      expect(result.nextPeriodStart, _day(start, 30));
    },
  );
}

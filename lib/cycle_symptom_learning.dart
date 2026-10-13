part of 'cycle_tracking_page.dart';

class CycleSymptomPattern {
  final String signal;
  final int observedCycles;
  final int leadDays;
  final int validationCycles;
  final int worsenedCycles;
  final double? baselineMeanErrorDays;
  final double? adjustedMeanErrorDays;

  const CycleSymptomPattern({
    required this.signal,
    required this.observedCycles,
    required this.leadDays,
    required this.validationCycles,
    this.worsenedCycles = 0,
    this.baselineMeanErrorDays,
    this.adjustedMeanErrorDays,
  });

  bool get canAdjustPrediction =>
      validationCycles >= 3 &&
      worsenedCycles * 3 <= validationCycles &&
      baselineMeanErrorDays != null &&
      adjustedMeanErrorDays != null &&
      baselineMeanErrorDays! - adjustedMeanErrorDays! >= 0.5;
}

class _ObservedCycle {
  final DateTime start;
  final DateTime end;
  final int length;
  const _ObservedCycle(this.start, this.end, this.length);
}

Set<String> _entrySignals(CycleEntry entry) => {
  ...entry.symptoms,
  if (['irritable', 'sensitive', 'sad'].contains(entry.mood))
    'mood:${entry.mood}',
  if ((entry.stressLevel ?? 0) >= 2) 'highStress',
  if (entry.sleepHours != null && entry.sleepHours! < 6) 'shortSleep',
};

DateTime? _firstSignalDay(
  List<CycleEntry> entries,
  String signal,
  DateTime start,
  DateTime end,
) {
  final dates =
      entries
          .where(
            (entry) =>
                !entry.isPeriod &&
                !entry.isSpotting &&
                !_dateOnly(entry.date).isBefore(start) &&
                _dateOnly(entry.date).isBefore(end) &&
                _entrySignals(entry).contains(signal),
          )
          .map((entry) => _dateOnly(entry.date))
          .toList()
        ..sort();
  return dates.firstOrNull;
}

DateTime? _symptomAdjustedDate(
  DateTime baseline,
  DateTime earliest,
  DateTime latest,
  DateTime signalDay,
  int leadDays,
  DateTime today,
) {
  if (today.isAfter(latest)) return null;
  final candidate = _addCalendarDays(signalDay, leadDays);
  if (candidate.isBefore(earliest) ||
      candidate.isAfter(latest) ||
      candidate.isBefore(today)) {
    return null;
  }
  final shift = _calendarDayDifference(candidate, baseline).clamp(-2, 2);
  final adjusted = _addCalendarDays(baseline, shift);
  return adjusted.isBefore(today) ? null : adjusted;
}

List<CycleSymptomPattern> _learnSymptomPatterns(
  List<_ObservedCycle> cycles,
  List<CycleEntry> entries,
) {
  if (cycles.length < 3) return const [];
  final signals = entries.expand(_entrySignals).toSet().toList()..sort();
  final patterns = <CycleSymptomPattern>[];
  for (final signal in signals) {
    final offsets = <int>[];
    var cyclesWithSignal = 0;
    var validationCycles = 0;
    var baselineError = 0;
    var adjustedError = 0;
    var worsePredictions = 0;
    for (var index = 0; index < cycles.length; index++) {
      final cycle = cycles[index];
      final signalDay = _firstSignalDay(
        entries,
        signal,
        cycle.start,
        cycle.end,
      );
      if (signalDay == null) continue;
      cyclesWithSignal++;
      final lead = _calendarDayDifference(cycle.end, signalDay);
      // Evaluate BEFORE reading this cycle's outcome into the learned offsets.
      if (offsets.length >= 3 &&
          index >= 3 &&
          offsets.reduce(math.max) - offsets.reduce(math.min) <= 3) {
        final past = cycles.take(index).map((item) => item.length).toList();
        if (!_containsPossibleTrackingGap(past)) {
          final center = _recencyWeightedMedian(past);
          final lower = math
              .min(past.reduce(math.min), center - 2)
              .clamp(15, 90);
          final upper = math.max(
            lower + 4,
            math.max(past.reduce(math.max), center + 2),
          );
          final baseline = _addCalendarDays(cycle.start, center);
          final adjusted = _symptomAdjustedDate(
            baseline,
            _addCalendarDays(cycle.start, lower),
            _addCalendarDays(cycle.start, upper),
            signalDay,
            _median(offsets),
            signalDay,
          );
          // Count failed/missing adjustments as the baseline; do not cherry-pick
          // only cycles on which the proposed method was able to help.
          final baseError = _calendarDayDifference(baseline, cycle.end).abs();
          final newError = _calendarDayDifference(
            adjusted ?? baseline,
            cycle.end,
          ).abs();
          validationCycles++;
          baselineError += baseError;
          adjustedError += newError;
          if (newError > baseError) worsePredictions++;
        }
      }
      if (lead >= 1 && lead <= 7) offsets.add(lead);
    }
    // An all-month symptom is not a useful marker of approaching menstruation.
    if (offsets.length < 3 ||
        offsets.length * 4 < cyclesWithSignal * 3 ||
        offsets.reduce(math.max) - offsets.reduce(math.min) > 3) {
      continue;
    }
    patterns.add(
      CycleSymptomPattern(
        signal: signal,
        observedCycles: offsets.length,
        leadDays: _median(offsets),
        validationCycles: validationCycles,
        worsenedCycles: worsePredictions,
        baselineMeanErrorDays: validationCycles == 0
            ? null
            : baselineError / validationCycles,
        adjustedMeanErrorDays: validationCycles == 0
            ? null
            : adjustedError / validationCycles,
      ),
    );
  }
  patterns.sort((a, b) {
    final count = b.observedCycles.compareTo(a.observedCycles);
    return count == 0 ? a.signal.compareTo(b.signal) : count;
  });
  return patterns;
}

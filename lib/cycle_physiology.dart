part of 'cycle_tracking_page.dart';

/// A personal association with the next recorded period, not an ovulation date.
class CyclePhysiologyPattern {
  final String signal;
  final int observedCycles;
  final int leadDays;
  final int validationCycles;
  final int worsenedCycles;
  final double? baselineMeanErrorDays;
  final double? adjustedMeanErrorDays;

  const CyclePhysiologyPattern({
    required this.signal,
    required this.observedCycles,
    required this.leadDays,
    required this.validationCycles,
    required this.worsenedCycles,
    this.baselineMeanErrorDays,
    this.adjustedMeanErrorDays,
  });

  bool get canAdjustPrediction =>
      observedCycles >= 3 &&
      validationCycles >= 3 &&
      worsenedCycles * 3 <= validationCycles &&
      baselineMeanErrorDays != null &&
      adjustedMeanErrorDays != null &&
      baselineMeanErrorDays! - adjustedMeanErrorDays! >= 0.5;
}

class CyclePhysiologyInsights {
  final DateTime? positiveLhDate;
  final DateTime? thermalShiftStart;
  final DateTime? proposedPeriodStart;
  final List<DateTime> proposedPeriodStarts;
  final bool hasAmbiguousLh;
  final bool hasAmbiguousTemperature;
  final List<CyclePhysiologyPattern> patterns;

  const CyclePhysiologyInsights({
    this.positiveLhDate,
    this.thermalShiftStart,
    this.proposedPeriodStart,
    this.proposedPeriodStarts = const [],
    this.hasAmbiguousLh = false,
    this.hasAmbiguousTemperature = false,
    this.patterns = const [],
  });
}

class _PhysiologyMarker {
  final DateTime day;
  final DateTime availableOn;
  const _PhysiologyMarker(this.day, this.availableOn);
}

class _PhysiologyMarkers {
  final List<_PhysiologyMarker> values;
  final bool ambiguous;
  const _PhysiologyMarkers(this.values, {this.ambiguous = false});

  _PhysiologyMarker? get unique =>
      !ambiguous && values.length == 1 ? values.single : null;
}

Map<DateTime, List<CycleEntry>> _physiologyDays(
  List<CycleEntry> entries,
  DateTime start,
  DateTime exclusiveEnd,
) {
  final days = <DateTime, List<CycleEntry>>{};
  for (final entry in entries) {
    final day = _dateOnly(entry.date);
    if (!day.isBefore(start) && day.isBefore(exclusiveEnd)) {
      days.putIfAbsent(day, () => []).add(entry);
    }
  }
  return days;
}

_PhysiologyMarkers _lhMarkers(Map<DateTime, List<CycleEntry>> days) {
  final positiveDays = <DateTime>[];
  var conflicting = false;
  for (final day in days.entries) {
    final results = day.value
        .map((entry) => entry.lhTest)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (results.contains('positive')) {
      positiveDays.add(day.key);
      if (results.length != 1) conflicting = true;
    }
  }
  positiveDays.sort();
  final markers = <_PhysiologyMarker>[];
  DateTime? previous;
  for (final day in positiveDays) {
    if (previous == null || _calendarDayDifference(day, previous) != 1) {
      markers.add(_PhysiologyMarker(day, day));
    }
    previous = day;
  }
  return _PhysiologyMarkers(
    markers,
    ambiguous: conflicting || markers.length > 1,
  );
}

_PhysiologyMarkers _thermalMarkers(Map<DateTime, List<CycleEntry>> days) {
  final temperatures = <DateTime, double>{};
  for (final day in days.entries) {
    // Duplicate identical readings do not add evidence. Any conflicting or
    // disturbed reading makes this day unavailable; input order cannot win.
    if (day.value.any((entry) => entry.temperatureDisturbed)) continue;
    final values = day.value
        .map((entry) => entry.basalTemperatureC)
        .whereType<double>()
        .toSet();
    if (values.length != 1) continue;
    final value = values.single;
    if (value.isFinite && value >= 34 && value <= 42) {
      temperatures[day.key] = value;
    }
  }
  final dates = temperatures.keys.toList()..sort();
  final markers = <_PhysiologyMarker>[];
  for (final onset in dates) {
    final readings = <double>[];
    for (var offset = -6; offset <= 2; offset++) {
      final reading = temperatures[_addCalendarDays(onset, offset)];
      if (reading == null) break;
      readings.add(reading);
    }
    if (readings.length != 9) continue;
    final baseline = readings.take(6).toList();
    final lower = baseline.reduce(math.min);
    final upper = baseline.reduce(math.max);
    // Product heuristic for a sustained thermal trend only. This is not a
    // validated symptothermal method and never confirms ovulation or safe days.
    if (upper - lower > 0.3 + 1e-9 ||
        readings
            .skip(6)
            .any(
              (value) =>
                  value < upper + 0.2 - 1e-9 || value > upper + 0.6 + 1e-9,
            )) {
      continue;
    }
    markers.add(_PhysiologyMarker(onset, _addCalendarDays(onset, 2)));
  }
  return _PhysiologyMarkers(markers, ambiguous: markers.length > 1);
}

_PhysiologyMarkers _markersFor(
  String signal,
  Map<DateTime, List<CycleEntry>> days,
) => signal == 'lh' ? _lhMarkers(days) : _thermalMarkers(days);

bool _stablePhysiologyOffsets(List<int> offsets) =>
    offsets.length >= 3 &&
    offsets.reduce(math.max) - offsets.reduce(math.min) <= 3;

List<CyclePhysiologyPattern> _learnPhysiologyPatterns(
  List<_ObservedCycle> cycles,
  List<CycleEntry> entries,
) {
  final patterns = <CyclePhysiologyPattern>[];
  for (final signal in ['lh', 'thermal']) {
    final offsets = <int>[];
    var validationCycles = 0;
    var baselineError = 0;
    var adjustedError = 0;
    var worsenedCycles = 0;
    for (var index = 0; index < cycles.length; index++) {
      final cycle = cycles[index];
      final markers = _markersFor(
        signal,
        _physiologyDays(entries, cycle.start, cycle.end),
      );
      // Validate before incorporating this cycle's outcome. Only the marker
      // first available at the forecast date is observable then. Later LH runs
      // or thermal trends cannot retroactively remove a validation example.
      if (index >= 3 && _stablePhysiologyOffsets(offsets)) {
        final past = cycles.take(index).map((value) => value.length).toList();
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
          DateTime? adjusted;
          final first = markers.values.firstOrNull;
          if (first != null) {
            // Re-read only the prefix known at the decision time, so conflicting
            // duplicates on that day are rejected without reading later days.
            final knownMarker = _markersFor(
              signal,
              _physiologyDays(
                entries,
                cycle.start,
                _addCalendarDays(first.availableOn, 1),
              ),
            ).unique;
            if (knownMarker != null) {
              adjusted = _symptomAdjustedDate(
                baseline,
                _addCalendarDays(cycle.start, lower),
                _addCalendarDays(cycle.start, upper),
                knownMarker.day,
                _median(offsets),
                knownMarker.availableOn,
              );
            }
          }
          // Missing/unusable signals count as baseline unchanged, rather than
          // selecting only cycles where the new method could issue a forecast.
          final oldError = _calendarDayDifference(baseline, cycle.end).abs();
          final newError = _calendarDayDifference(
            adjusted ?? baseline,
            cycle.end,
          ).abs();
          baselineError += oldError;
          adjustedError += newError;
          validationCycles++;
          if (newError > oldError) worsenedCycles++;
        }
      }
      final marker = markers.unique;
      if (marker != null) {
        final lead = _calendarDayDifference(cycle.end, marker.day);
        if (lead > 0) offsets.add(lead);
      }
    }
    if (!_stablePhysiologyOffsets(offsets)) continue;
    patterns.add(
      CyclePhysiologyPattern(
        signal: signal,
        observedCycles: offsets.length,
        leadDays: _median(offsets),
        validationCycles: validationCycles,
        worsenedCycles: worsenedCycles,
        baselineMeanErrorDays: validationCycles == 0
            ? null
            : baselineError / validationCycles,
        adjustedMeanErrorDays: validationCycles == 0
            ? null
            : adjustedError / validationCycles,
      ),
    );
  }
  return patterns;
}

CyclePhysiologyInsights _analyzePhysiology({
  required List<_ObservedCycle> cycles,
  required List<CycleEntry> entries,
  required DateTime today,
  required DateTime? currentCycleStart,
  required CyclePersonalContext personalContext,
  required DateTime? baseline,
  required DateTime? earliest,
  required DateTime? latest,
}) {
  if (!personalContext.canUseSymptomTiming || currentCycleStart == null) {
    return const CyclePhysiologyInsights();
  }
  final recorded = entries
      .where((entry) => !_dateOnly(entry.date).isAfter(today))
      .toList();
  final completed =
      cycles.where((cycle) => !cycle.end.isAfter(currentCycleStart)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final patterns = _learnPhysiologyPatterns(completed, recorded);
  final currentDays = _physiologyDays(
    recorded,
    currentCycleStart,
    _addCalendarDays(today, 1),
  );
  final lh = _lhMarkers(currentDays);
  final thermal = _thermalMarkers(currentDays);
  final proposals = <int>[];
  if (baseline != null &&
      earliest != null &&
      latest != null &&
      !today.isAfter(latest)) {
    for (final pattern in patterns.where(
      (value) => value.canAdjustPrediction,
    )) {
      final marker = (pattern.signal == 'lh' ? lh : thermal).unique;
      if (marker == null) continue;
      final proposal = _symptomAdjustedDate(
        baseline,
        earliest,
        latest,
        marker.day,
        pattern.leadDays,
        today,
      );
      if (proposal != null) {
        proposals.add(_calendarDayDifference(proposal, baseline));
      }
    }
  }
  return CyclePhysiologyInsights(
    positiveLhDate: lh.unique?.day,
    thermalShiftStart: thermal.unique?.day,
    hasAmbiguousLh: lh.ambiguous,
    hasAmbiguousTemperature: thermal.ambiguous,
    patterns: List.unmodifiable(patterns),
    proposedPeriodStarts: List.unmodifiable([
      if (baseline != null)
        for (final offset in proposals) _addCalendarDays(baseline, offset),
    ]),
    proposedPeriodStart:
        baseline != null &&
            proposals.isNotEmpty &&
            proposals.reduce(math.max) - proposals.reduce(math.min) <= 2
        ? _addCalendarDays(baseline, _median(proposals))
        : null,
  );
}

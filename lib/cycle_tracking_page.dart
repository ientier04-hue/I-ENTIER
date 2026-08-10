import 'supabase_data.dart';
import 'package:flutter/material.dart';

const _rose = Color(0xFFE94C85);
const _roseSoft = Color(0xFFFFE8F1);
const _purple = Color(0xFF7C5CE5);
const _purpleSoft = Color(0xFFF0EBFF);
const _teal = Color(0xFF0A9F8F);
const _tealSoft = Color(0xFFE5F7F3);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF8F7FC);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

int _calendarDayDifference(DateTime later, DateTime earlier) => DateTime.utc(
  later.year,
  later.month,
  later.day,
).difference(DateTime.utc(earlier.year, earlier.month, earlier.day)).inDays;

String cycleDateKey(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

const _monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _shortMonthNames = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _longDate(DateTime date) =>
    '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

String _shortDate(DateTime date) =>
    '${date.day} ${_shortMonthNames[date.month - 1]}';

String _dateRange(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${_monthNames[end.month - 1]} ${end.year}';
  }
  return '${_shortDate(start)} – ${_longDate(end)}';
}

class CycleEntry {
  final String id;
  final DateTime date;
  final bool isPeriod;
  final String flow;
  final List<String> symptoms;
  final String mood;
  final String note;

  const CycleEntry({
    required this.id,
    required this.date,
    this.isPeriod = false,
    this.flow = '',
    this.symptoms = const [],
    this.mood = '',
    this.note = '',
  });

  factory CycleEntry.fromSupabase(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final dateValue = data['date'];
    if (dateValue is! Timestamp || data['isPeriod'] is! bool) {
      throw const FormatException('Invalid cycle entry');
    }
    final symptomsValue = data['symptoms'];
    return CycleEntry(
      id: document.id,
      date: _dateOnly(dateValue.toDate()),
      isPeriod: data['isPeriod'] as bool,
      flow: data['flow']?.toString() ?? '',
      symptoms: symptomsValue is Iterable
          ? symptomsValue.map((value) => value.toString()).toList()
          : const [],
      mood: data['mood']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
    );
  }

  CycleEntry copyWith({
    bool? isPeriod,
    String? flow,
    List<String>? symptoms,
    String? mood,
    String? note,
  }) => CycleEntry(
    id: id,
    date: date,
    isPeriod: isPeriod ?? this.isPeriod,
    flow: flow ?? this.flow,
    symptoms: symptoms ?? this.symptoms,
    mood: mood ?? this.mood,
    note: note ?? this.note,
  );

  bool get hasDetails =>
      isPeriod || symptoms.isNotEmpty || mood.isNotEmpty || note.isNotEmpty;
}

class _PeriodEpisode {
  final DateTime start;
  final DateTime end;
  final List<CycleEntry> entries;

  const _PeriodEpisode({
    required this.start,
    required this.end,
    required this.entries,
  });

  int get length => _calendarDayDifference(end, start) + 1;

  int get recordedDayCount =>
      entries.map((entry) => cycleDateKey(entry.date)).toSet().length;

  bool get hasCompleteDailyRecord => recordedDayCount == length;
}

List<_PeriodEpisode> _periodEpisodes(Iterable<CycleEntry> entries) {
  final periodEntries = entries.where((entry) => entry.isPeriod).toList()
    ..sort((first, second) => first.date.compareTo(second.date));
  final groups = <List<CycleEntry>>[];
  for (final entry in periodEntries) {
    if (groups.isEmpty) {
      groups.add([entry]);
      continue;
    }

    final current = groups.last;
    final gapFromPrevious = _calendarDayDifference(
      entry.date,
      current.last.date,
    );

    // Allow one missed journal day inside an episode. Consecutive bleeding is
    // never split, even when it lasts unusually long: doing so would invent a
    // new cycle. After two unlogged days, a new bleeding episode starts.
    if (gapFromPrevious <= 2) {
      groups.last.add(entry);
    } else {
      groups.add([entry]);
    }
  }
  return groups
      .map(
        (group) => _PeriodEpisode(
          start: _dateOnly(group.first.date),
          end: _dateOnly(group.last.date),
          entries: group,
        ),
      )
      .toList();
}

int _median(List<int> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'Must not be empty');
  }
  final sorted = List<int>.from(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

List<int> _recentValues(List<int> values, [int limit = 12]) =>
    values.length > limit ? values.sublist(values.length - limit) : values;

bool _containsPossibleTrackingGap(List<int> intervals) {
  if (intervals.length < 3) return false;
  for (final shorter in intervals) {
    if (shorter <= 0) continue;
    for (final longer in intervals) {
      if (longer < shorter * 1.75) continue;
      final multiple = (longer / shorter).round();
      if (multiple < 2 || multiple > 3) continue;
      final tolerance = multiple + 1;
      if ((longer - shorter * multiple).abs() <= tolerance) return true;
    }
  }
  return false;
}

Iterable<DateTime> _datesInRange(DateTime start, DateTime end) sync* {
  var date = _dateOnly(start);
  final last = _dateOnly(end);
  while (!date.isAfter(last)) {
    yield date;
    date = _addCalendarDays(date, 1);
  }
}

enum CycleHistoryQuality { insufficient, limited, stable, veryStable }

class CycleInsights {
  final DateTime today;
  final List<DateTime> periodStarts;
  final int? typicalCycleLength;
  final int? typicalPeriodLength;
  final int cycleSampleCount;
  final int periodSampleCount;
  final int? cycleVariationDays;
  final CycleHistoryQuality historyQuality;
  final bool hasPossibleTrackingGap;
  final bool hasOutOfRangeInterval;
  final bool hasRecentAmbiguousBleeding;
  final bool hasHistoryBreak;
  final bool hasAtypicalCycleFrequency;
  final bool hasIncompletePeriodRecord;
  final bool hasProlongedBleeding;
  final DateTime? lastPeriodStart;
  final DateTime? nextPeriodStart;
  final DateTime? nextPeriodEarliest;
  final DateTime? nextPeriodLatest;

  CycleInsights._({
    required this.today,
    required this.periodStarts,
    required this.typicalCycleLength,
    required this.typicalPeriodLength,
    required this.cycleSampleCount,
    required this.periodSampleCount,
    required this.cycleVariationDays,
    required this.historyQuality,
    required this.hasPossibleTrackingGap,
    required this.hasOutOfRangeInterval,
    required this.hasRecentAmbiguousBleeding,
    required this.hasHistoryBreak,
    required this.hasAtypicalCycleFrequency,
    required this.hasIncompletePeriodRecord,
    required this.hasProlongedBleeding,
    required this.lastPeriodStart,
    required this.nextPeriodStart,
    required this.nextPeriodEarliest,
    required this.nextPeriodLatest,
  });

  factory CycleInsights.fromEntries(
    Iterable<CycleEntry> entries, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final episodes = _periodEpisodes(
      entries.where((entry) => !_dateOnly(entry.date).isAfter(today)),
    );
    final starts = episodes.map((episode) => episode.start).toList();
    final allIntervals = <int>[];
    for (var index = 1; index < starts.length; index++) {
      allIntervals.add(
        _calendarDayDifference(starts[index], starts[index - 1]),
      );
    }
    var lastHistoryBreakIndex = -1;
    for (var index = 0; index < allIntervals.length; index++) {
      if (allIntervals[index] > 90) lastHistoryBreakIndex = index;
    }
    final hasHistoryBreak = lastHistoryBreakIndex >= 0;
    final segmentIntervals = lastHistoryBreakIndex < 0
        ? allIntervals
        : allIntervals.sublist(lastHistoryBreakIndex + 1);
    final validIntervals = <int>[];
    var followsVeryShortInterval = false;
    for (final interval in segmentIntervals) {
      if (interval >= 15 && interval <= 90 && !followsVeryShortInterval) {
        validIntervals.add(interval);
      }
      // A bleeding episode less than 15 days after the previous start may be
      // intermenstrual bleeding. The interval immediately after it cannot be
      // assumed to represent a full cycle either.
      followsVeryShortInterval = interval < 15;
    }
    final recentIntervals = _recentValues(validIntervals);
    final recentRawIntervals = _recentValues(segmentIntervals);
    final hasOutOfRangeInterval = recentRawIntervals.any(
      (interval) => interval < 15 || interval > 90,
    );
    final hasRecentAmbiguousBleeding =
        segmentIntervals.isNotEmpty && segmentIntervals.last < 15;
    final hasPossibleTrackingGap = _containsPossibleTrackingGap(
      recentIntervals,
    );
    final hasAtypicalCycleFrequency = recentIntervals.any(
      (interval) => interval < 24 || interval > 38,
    );

    final segmentEpisodes = lastHistoryBreakIndex < 0
        ? episodes
        : episodes.sublist(lastHistoryBreakIndex + 1);
    final recentEpisodes = segmentEpisodes.length > 12
        ? segmentEpisodes.sublist(segmentEpisodes.length - 12)
        : segmentEpisodes;
    final confirmedEpisodes = recentEpisodes.length < 2
        ? const <_PeriodEpisode>[]
        : recentEpisodes.sublist(0, recentEpisodes.length - 1);
    final completedPeriodLengths = confirmedEpisodes
        .where(
          (episode) =>
              episode.length >= 1 &&
              episode.length <= 10 &&
              episode.hasCompleteDailyRecord,
        )
        .map((episode) => episode.length)
        .toList();
    final recentPeriodLengths = _recentValues(completedPeriodLengths);
    final typicalPeriod = recentPeriodLengths.length < 3
        ? null
        : _median(recentPeriodLengths).clamp(1, 10);

    final hasEnoughHistory = recentIntervals.length >= 3;
    final predictionSuspended =
        hasRecentAmbiguousBleeding || hasPossibleTrackingGap;
    final typicalCycle = hasEnoughHistory && !predictionSuspended
        ? _median(recentIntervals)
        : null;
    final sortedIntervals = List<int>.from(recentIntervals)..sort();
    final variation = sortedIntervals.isEmpty
        ? null
        : sortedIntervals.last - sortedIntervals.first;
    final historyQuality = !hasEnoughHistory
        ? CycleHistoryQuality.insufficient
        : hasOutOfRangeInterval ||
              hasPossibleTrackingGap ||
              hasRecentAmbiguousBleeding ||
              hasAtypicalCycleFrequency ||
              (variation ?? 0) > 9
        ? CycleHistoryQuality.limited
        : recentIntervals.length >= 9 && (variation ?? 0) <= 4
        ? CycleHistoryQuality.veryStable
        : recentIntervals.length >= 6 && (variation ?? 0) <= 7
        ? CycleHistoryQuality.stable
        : CycleHistoryQuality.limited;

    final lastStart = starts.isEmpty ? null : starts.last;
    DateTime? nextStart;
    DateTime? earliest;
    DateTime? latest;
    if (lastStart != null && typicalCycle != null) {
      nextStart = _addCalendarDays(lastStart, typicalCycle);
      final earliestLength =
          (sortedIntervals.first < typicalCycle - 2
                  ? sortedIntervals.first
                  : typicalCycle - 2)
              .clamp(15, 90);
      final latestLength =
          (sortedIntervals.last > typicalCycle + 2
                  ? sortedIntervals.last
                  : typicalCycle + 2)
              .clamp(15, 92);
      earliest = _addCalendarDays(lastStart, earliestLength);
      latest = _addCalendarDays(lastStart, latestLength);
    }

    return CycleInsights._(
      today: today,
      periodStarts: starts,
      typicalCycleLength: typicalCycle,
      typicalPeriodLength: typicalPeriod,
      cycleSampleCount: recentIntervals.length,
      periodSampleCount: recentPeriodLengths.length,
      cycleVariationDays: variation,
      historyQuality: historyQuality,
      hasPossibleTrackingGap: hasPossibleTrackingGap,
      hasOutOfRangeInterval: hasOutOfRangeInterval,
      hasRecentAmbiguousBleeding: hasRecentAmbiguousBleeding,
      hasHistoryBreak: hasHistoryBreak,
      hasAtypicalCycleFrequency: hasAtypicalCycleFrequency,
      hasIncompletePeriodRecord: recentEpisodes.any(
        (episode) => !episode.hasCompleteDailyRecord,
      ),
      hasProlongedBleeding: recentEpisodes.any((episode) => episode.length > 8),
      lastPeriodStart: lastStart,
      nextPeriodStart: nextStart,
      nextPeriodEarliest: earliest,
      nextPeriodLatest: latest,
    );
  }

  // Compatibility aliases remain nullable: no population value is presented
  // as a personal average.
  int? get averageCycleLength => typicalCycleLength;
  int? get averagePeriodLength => typicalPeriodLength;

  // Used only to prefill an editable form, never as a displayed insight.
  int get suggestedPeriodLength => typicalPeriodLength ?? 5;

  bool get hasPrediction =>
      historyQuality != CycleHistoryQuality.insufficient &&
      nextPeriodStart != null &&
      nextPeriodEarliest != null &&
      nextPeriodLatest != null;

  bool get isPredictionSuspended =>
      hasRecentAmbiguousBleeding || hasPossibleTrackingGap;

  bool get hasHighVariability => (cycleVariationDays ?? 0) > 9;

  int get additionalCyclesNeeded {
    final missingIntervals = 3 - cycleSampleCount;
    return missingIntervals > 0 ? missingIntervals : 0;
  }

  int? get currentCycleDay => lastPeriodStart == null
      ? null
      : _calendarDayDifference(today, lastPeriodStart!) + 1;

  int? get daysUntilNextPeriod => nextPeriodStart == null
      ? null
      : _calendarDayDifference(nextPeriodStart!, today);

  bool get isOverdue => hasPrediction && today.isAfter(nextPeriodLatest!);

  int? get daysPastPredictionWindow =>
      !isOverdue ? null : _calendarDayDifference(today, nextPeriodLatest!);

  int? get predictionWindowDays => !hasPrediction
      ? null
      : _calendarDayDifference(nextPeriodLatest!, nextPeriodEarliest!) + 1;

  bool get canHighlightPrediction =>
      hasPrediction && !isOverdue && (predictionWindowDays ?? 0) <= 14;

  // Dates of bleeding alone cannot confirm or precisely predict ovulation.
  DateTime? get ovulationDate => null;
  DateTime? get fertileWindowStart => null;
  DateTime? get fertileWindowEnd => null;

  bool isPredictedPeriod(DateTime date) {
    if (!canHighlightPrediction) return false;
    final day = _dateOnly(date);
    return !day.isBefore(nextPeriodEarliest!) &&
        !day.isAfter(nextPeriodLatest!);
  }

  bool isFertile(DateTime date) => false;
}

typedef CycleEntryCallback = Future<void> Function(CycleEntry entry);
typedef CycleDeleteCallback = Future<void> Function(CycleEntry entry);

class CycleTrackingPage extends StatefulWidget {
  final String patientId;
  final DateTime? now;
  final List<CycleEntry>? initialEntries;
  final CycleEntryCallback? onSaveEntry;
  final CycleDeleteCallback? onDeleteEntry;

  const CycleTrackingPage({
    super.key,
    required this.patientId,
    this.now,
    this.initialEntries,
    this.onSaveEntry,
    this.onDeleteEntry,
  });

  @override
  State<CycleTrackingPage> createState() => _CycleTrackingPageState();
}

class _CycleTrackingPageState extends State<CycleTrackingPage> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  List<CycleEntry>? _localEntries;

  DateTime get _today => _dateOnly(widget.now ?? DateTime.now());

  CollectionReference<Map<String, dynamic>> get _entriesReference =>
      SupabaseDatabase.instance
          .collection('patients')
          .doc(widget.patientId)
          .collection('cycleEntries');

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_today.year, _today.month);
    _selectedDate = _today;
    if (widget.initialEntries != null) {
      _localEntries = List<CycleEntry>.from(widget.initialEntries!);
    }
  }

  void _changeMonth(int offset) {
    final nextMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final lastDayOfMonth = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
    final selectedDay = _selectedDate.day > lastDayOfMonth
        ? lastDayOfMonth
        : _selectedDate.day;

    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = DateTime(nextMonth.year, nextMonth.month, selectedDay);
    });
  }

  Future<void> _openPeriodForm(
    List<CycleEntry> entries, {
    _PeriodEpisode? episode,
  }) async {
    final insights = CycleInsights.fromEntries(entries, now: _today);
    final result = await showModalBottomSheet<_PeriodRangeResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PeriodRangeForm(
        today: _today,
        episode: episode,
        suggestedLength: insights.suggestedPeriodLength,
      ),
    );
    if (result == null || !mounted) return;
    await _savePeriodRange(result, entries, previousEpisode: episode);
  }

  Future<void> _savePeriodRange(
    _PeriodRangeResult range,
    List<CycleEntry> entries, {
    _PeriodEpisode? previousEpisode,
  }) async {
    final newDates = range.delete
        ? <DateTime>[]
        : _datesInRange(range.start!, range.end!).toList();
    final newKeys = newDates.map(cycleDateKey).toSet();
    final oldEntries = previousEpisode?.entries ?? const <CycleEntry>[];
    final oldIds = oldEntries.map((entry) => entry.id).toSet();
    final entriesByDay = <String, CycleEntry>{
      for (final entry in entries) cycleDateKey(entry.date): entry,
    };
    final overlapsAnotherPeriod = entries.any(
      (entry) =>
          entry.isPeriod &&
          !oldIds.contains(entry.id) &&
          newKeys.contains(cycleDateKey(entry.date)),
    );
    if (overlapsAnotherPeriod) {
      _showMessage('Cette plage chevauche une autre période enregistrée.');
      return;
    }

    try {
      if (_localEntries != null) {
        final updatedEntries = List<CycleEntry>.from(_localEntries!);

        for (final oldEntry in oldEntries) {
          if (newKeys.contains(cycleDateKey(oldEntry.date))) continue;
          final updated = oldEntry.copyWith(isPeriod: false, flow: '');
          updatedEntries.removeWhere((entry) => entry.id == oldEntry.id);
          if (updated.hasDetails) {
            await widget.onSaveEntry?.call(updated);
            updatedEntries.add(updated);
          } else {
            await widget.onDeleteEntry?.call(oldEntry);
          }
        }

        for (final date in newDates) {
          final key = cycleDateKey(date);
          final existing = entriesByDay[key];
          if (existing?.isPeriod ?? false) continue;
          final updated =
              existing?.copyWith(isPeriod: true, flow: '') ??
              CycleEntry(id: key, date: date, isPeriod: true);
          await widget.onSaveEntry?.call(updated);
          updatedEntries.removeWhere((entry) => entry.id == updated.id);
          updatedEntries.add(updated);
        }

        if (mounted) setState(() => _localEntries = updatedEntries);
      } else {
        final batch = SupabaseDatabase.instance.batch();
        var hasWrites = false;

        for (final oldEntry in oldEntries) {
          if (newKeys.contains(cycleDateKey(oldEntry.date))) continue;
          final reference = _entriesReference.doc(oldEntry.id);
          if (oldEntry.symptoms.isNotEmpty ||
              oldEntry.mood.isNotEmpty ||
              oldEntry.note.isNotEmpty) {
            batch.update(reference, {
              'isPeriod': false,
              'flow': '',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            batch.delete(reference);
          }
          hasWrites = true;
        }

        for (final date in newDates) {
          final key = cycleDateKey(date);
          final existing = entriesByDay[key];
          if (existing?.isPeriod ?? false) continue;
          final reference = _entriesReference.doc(existing?.id ?? key);
          if (existing == null) {
            batch.set(reference, {
              'date': Timestamp.fromDate(date),
              'isPeriod': true,
              'flow': '',
              'symptoms': <String>[],
              'mood': '',
              'note': '',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            batch.update(reference, {
              'isPeriod': true,
              'flow': '',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          hasWrites = true;
        }

        if (hasWrites) await batch.commit();
      }
      if (mounted) {
        _showMessage(
          range.delete
              ? 'La période a été supprimée.'
              : previousEpisode == null
              ? 'Votre période a été enregistrée.'
              : 'Les dates de vos règles ont été corrigées.',
        );
      }
    } on SupabaseDataException catch (error) {
      if (mounted) {
        _showMessage(
          error.code.contains('permission')
              ? 'L’accès à votre suivi de cycle n’est pas autorisé.'
              : 'Impossible d’enregistrer cette période pour le moment.',
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Impossible d’enregistrer cette période.');
    }
  }

  Future<void> _openEntryForm(DateTime date, List<CycleEntry> entries) async {
    final normalizedDate = _dateOnly(date);
    if (normalizedDate.isAfter(_today)) {
      _showMessage(
        'Vous pourrez compléter cette journée lorsqu’elle arrivera.',
      );
      return;
    }
    final existing = entries.cast<CycleEntry?>().firstWhere(
      (entry) => entry != null && _sameDay(entry.date, normalizedDate),
      orElse: () => null,
    );
    final result = await showModalBottomSheet<_EntryFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _CycleEntryForm(date: normalizedDate, entry: existing),
    );
    if (result == null || !mounted) return;

    if (result.delete && existing != null) {
      await _deleteEntry(existing);
      return;
    }
    if (result.entry != null) await _saveEntry(result.entry!, existing != null);
  }

  Future<void> _saveEntry(CycleEntry entry, bool alreadyExists) async {
    try {
      if (_localEntries != null) {
        await widget.onSaveEntry?.call(entry);
        setState(() {
          _localEntries!.removeWhere((item) => _sameDay(item.date, entry.date));
          if (entry.hasDetails) _localEntries!.add(entry);
        });
      } else if (entry.hasDetails) {
        final data = <String, dynamic>{
          'date': Timestamp.fromDate(entry.date),
          'isPeriod': entry.isPeriod,
          'flow': entry.isPeriod ? entry.flow : '',
          'symptoms': entry.symptoms,
          'mood': entry.mood,
          'note': entry.note,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!alreadyExists) 'createdAt': FieldValue.serverTimestamp(),
        };
        if (alreadyExists) {
          await _entriesReference.doc(entry.id).update(data);
        } else {
          await _entriesReference.doc(entry.id).set(data);
        }
      } else if (alreadyExists) {
        await _entriesReference.doc(entry.id).delete();
      }
      if (mounted) _showMessage('Votre journée a été enregistrée.');
    } on SupabaseDataException catch (error) {
      if (mounted) {
        _showMessage(
          error.code.contains('permission')
              ? 'L’accès à votre suivi de cycle n’est pas autorisé.'
              : 'Impossible d’enregistrer cette journée pour le moment.',
        );
      }
    } catch (_) {
      if (mounted) _showMessage('Impossible d’enregistrer cette journée.');
    }
  }

  Future<void> _deleteEntry(CycleEntry entry) async {
    try {
      if (_localEntries != null) {
        await widget.onDeleteEntry?.call(entry);
        setState(
          () => _localEntries!.removeWhere((item) => item.id == entry.id),
        );
      } else {
        await _entriesReference.doc(entry.id).delete();
      }
      if (mounted) _showMessage('Journée supprimée du suivi.');
    } on SupabaseDataException {
      if (mounted) _showMessage('Impossible de supprimer cette journée.');
    } catch (_) {
      if (mounted) _showMessage('Impossible de supprimer cette journée.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Suivi de cycle',
        style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
      ),
    ),
    body: SafeArea(
      top: false,
      child: _localEntries != null
          ? _buildDashboard(_localEntries!)
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _entriesReference
                  .orderBy('date', descending: true)
                  .limit(500)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _PageFeedback(
                    icon: Icons.lock_outline_rounded,
                    title: 'Suivi indisponible',
                    message:
                        'Vos données de cycle ne peuvent pas être chargées pour le moment.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _purple),
                  );
                }
                final entries = <CycleEntry>[];
                for (final document in snapshot.data!.docs) {
                  try {
                    entries.add(CycleEntry.fromSupabase(document));
                  } on FormatException {
                    // Ignore malformed legacy entries instead of hiding the page.
                  }
                }
                return _buildDashboard(entries);
              },
            ),
    ),
  );

  Widget _buildDashboard(List<CycleEntry> entries) {
    final insights = CycleInsights.fromEntries(entries, now: _today);
    final episodes = _periodEpisodes(
      entries.where((entry) => !_dateOnly(entry.date).isAfter(_today)),
    );
    final journalEntries = entries
        .where(
          (entry) =>
              entry.symptoms.isNotEmpty ||
              entry.mood.isNotEmpty ||
              entry.note.isNotEmpty,
        )
        .toList();
    final entriesByDay = <String, CycleEntry>{
      for (final entry in entries) cycleDateKey(entry.date): entry,
    };
    final selectedEntry = entriesByDay[cycleDateKey(_selectedDate)];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CycleHero(
                insights: insights,
                hasEntries: episodes.isNotEmpty,
                onAddPeriod: () => _openPeriodForm(entries),
                onLogToday: () => _openEntryForm(_today, entries),
              ),
              const SizedBox(height: 18),
              const _PrivacyNotice(),
              const SizedBox(height: 22),
              const _MedicalNotice(),
              const SizedBox(height: 22),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final calendar = _CycleCalendar(
                    visibleMonth: _visibleMonth,
                    selectedDate: _selectedDate,
                    today: _today,
                    entriesByDay: entriesByDay,
                    insights: insights,
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onSelectDate: (date) {
                      setState(() => _selectedDate = date);
                      _openEntryForm(date, entries);
                    },
                  );
                  final status = _CycleStatusCard(
                    insights: insights,
                    todayEntry: entriesByDay[cycleDateKey(_today)],
                  );
                  if (!wide) {
                    return Column(
                      children: [status, const SizedBox(height: 18), calendar],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: status),
                      const SizedBox(width: 18),
                      Expanded(flex: 6, child: calendar),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _SelectedDayCard(
                date: _selectedDate,
                entry: selectedEntry,
                onTap: () => _openEntryForm(_selectedDate, entries),
              ),
              if (episodes.isEmpty) ...[
                const SizedBox(height: 18),
                _GettingStarted(onStart: () => _openPeriodForm(entries)),
              ] else ...[
                const SizedBox(height: 26),
                _PeriodHistorySection(
                  episodes: episodes,
                  onEdit: (episode) =>
                      _openPeriodForm(entries, episode: episode),
                ),
              ],
              if (journalEntries.isNotEmpty) ...[
                const SizedBox(height: 26),
                _HistorySection(
                  entries: journalEntries,
                  onEntryTap: (entry) => _openEntryForm(entry.date, entries),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CycleHero extends StatelessWidget {
  final CycleInsights insights;
  final bool hasEntries;
  final VoidCallback onAddPeriod;
  final VoidCallback onLogToday;

  const _CycleHero({
    required this.insights,
    required this.hasEntries,
    required this.onAddPeriod,
    required this.onLogToday,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFE9F3), Color(0xFFECE6FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x147C5CE5),
          blurRadius: 25,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'MON BIEN-ÊTRE',
                style: TextStyle(
                  color: _purple,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              'Comprendre votre cycle,\nun jour à la fois.',
              style: TextStyle(
                color: _navy,
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              hasEntries
                  ? 'Notez vos ressentis et suivez vos tendances personnelles.'
                  : 'Commencez par enregistrer le premier jour de vos dernières règles.',
              style: const TextStyle(color: _ink, height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const Key('cycle-add-period'),
                  onPressed: onAddPeriod,
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                  icon: const Icon(Icons.date_range_rounded),
                  label: const Text('Ajouter mes règles'),
                ),
                TextButton.icon(
                  key: const Key('cycle-log-today'),
                  onPressed: onLogToday,
                  style: TextButton.styleFrom(foregroundColor: _purple),
                  icon: const Icon(Icons.spa_outlined),
                  label: const Text('Noter mes symptômes'),
                ),
              ],
            ),
          ],
        );
        if (compact) return content;
        return Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 20),
            Image.asset(
              'regles.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
              semanticLabel: 'Calendrier de suivi du cycle',
            ),
          ],
        );
      },
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline_rounded, color: _teal, size: 21),
        SizedBox(width: 11),
        Expanded(
          child: Text(
            'Vos informations de cycle sont privées et accessibles uniquement depuis votre compte.',
            style: TextStyle(color: _ink, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _CycleStatusCard extends StatelessWidget {
  final CycleInsights insights;
  final CycleEntry? todayEntry;

  const _CycleStatusCard({required this.insights, required this.todayEntry});

  @override
  Widget build(BuildContext context) {
    final hasCycle = insights.lastPeriodStart != null;
    final inPeriod = todayEntry?.isPeriod ?? false;
    final String title;
    final String subtitle;
    final IconData icon;
    final Key? titleKey;
    if (!hasCycle) {
      title = 'Votre cycle en un coup d’œil';
      subtitle =
          'Ajoutez le premier jour de vos règles pour commencer votre historique.';
      icon = Icons.auto_graph_rounded;
      titleKey = const Key('cycle-history-insufficient');
    } else if (inPeriod) {
      title = 'Règles en cours';
      subtitle = 'Jour ${insights.currentCycleDay ?? 1} de votre cycle';
      icon = Icons.water_drop_rounded;
      titleKey = null;
    } else if (insights.isPredictionSuspended) {
      title = 'Prévision suspendue';
      subtitle = insights.hasRecentAmbiguousBleeding
          ? 'Un saignement très rapproché doit être vérifié avant de servir de nouveau début de cycle.'
          : 'Un intervalle peut correspondre à un ou plusieurs cycles non enregistrés. Vérifiez l’historique.';
      icon = Icons.pause_circle_outline_rounded;
      titleKey = const Key('cycle-prediction-suspended');
    } else if (!insights.hasPrediction) {
      final missing = insights.additionalCyclesNeeded;
      title = insights.hasHistoryBreak
          ? 'Historique récent à compléter'
          : 'Historique insuffisant pour prévoir';
      subtitle = insights.hasHistoryBreak
          ? 'Après une longue interruption, enregistrez encore $missing début${missing == 1 ? '' : 's'} de règles avant une nouvelle estimation.'
          : 'Enregistrez encore $missing début${missing == 1 ? '' : 's'} de règles pour calculer une plage personnelle.';
      icon = Icons.hourglass_top_rounded;
      titleKey = const Key('cycle-history-insufficient');
    } else if (insights.isOverdue) {
      final overdue = insights.daysPastPredictionWindow!;
      title = 'Cycle plus long que la plage estimée';
      subtitle =
          'La plage est dépassée de $overdue jour${overdue == 1 ? '' : 's'}. La prévision n’est pas reportée automatiquement.';
      icon = Icons.update_rounded;
      titleKey = const Key('cycle-overdue-notice');
    } else {
      title = 'Prochaines règles estimées';
      subtitle = _dateRange(
        insights.nextPeriodEarliest!,
        insights.nextPeriodLatest!,
      );
      icon = Icons.event_available_rounded;
      titleKey = const Key('cycle-next-period-range');
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _roseSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: _rose),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: titleKey,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (insights.typicalCycleLength != null)
                _MetricChip(
                  label: 'Cycle habituel',
                  value: '${insights.typicalCycleLength} jours',
                  color: _purple,
                ),
              if (insights.typicalPeriodLength != null)
                _MetricChip(
                  label: 'Durée habituelle',
                  value: '${insights.typicalPeriodLength} jours',
                  color: _rose,
                ),
              if (insights.currentCycleDay != null)
                _MetricChip(
                  label: 'Aujourd’hui',
                  value: 'Jour ${insights.currentCycleDay}',
                  color: _teal,
                ),
            ],
          ),
          if (inPeriod && !insights.hasPrediction) ...[
            const SizedBox(height: 10),
            _InsightWarning(
              key: Key(
                insights.isPredictionSuspended
                    ? 'cycle-prediction-suspended'
                    : 'cycle-history-insufficient',
              ),
              icon: Icons.hourglass_top_rounded,
              message: insights.isPredictionSuspended
                  ? 'La prévision reste suspendue jusqu’à la vérification des épisodes rapprochés ou manquants.'
                  : insights.hasHistoryBreak
                  ? 'Après cette interruption, il faut encore ${insights.additionalCyclesNeeded} débuts de règles pour reconstruire une tendance récente.'
                  : 'Il faut encore ${insights.additionalCyclesNeeded} débuts de règles pour calculer une plage personnelle.',
            ),
          ],
          if (insights.hasPrediction) ...[
            const SizedBox(height: 17),
            Container(
              key: const Key('cycle-history-quality'),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _purpleSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: _purple,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${_historyQualityLabel(insights.historyQuality)} · ${insights.cycleSampleCount} cycles complets analysés${insights.cycleVariationDays == null ? '' : ' · variation de ${insights.cycleVariationDays} jours'}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (insights.isOverdue) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-overdue-guidance'),
              icon: Icons.rule_rounded,
              message:
                  'Vérifiez qu’aucun début de règles n’a été oublié. Si une grossesse est possible, pensez à faire un test ou à demander conseil.',
            ),
          ],
          if (insights.hasPrediction &&
              insights.historyQuality == CycleHistoryQuality.limited) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-estimation-prudent'),
              icon: Icons.info_outline_rounded,
              message:
                  'Estimation prudente : cette plage peut encore changer avec de nouveaux cycles.',
            ),
          ],
          if (insights.hasHighVariability) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-variability-warning'),
              icon: Icons.show_chart_rounded,
              message:
                  'Les durées enregistrées varient beaucoup. L’estimation est donc élargie ou suspendue.',
            ),
          ],
          if (insights.hasPossibleTrackingGap ||
              insights.hasOutOfRangeInterval ||
              insights.hasRecentAmbiguousBleeding) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-tracking-gap-warning'),
              icon: Icons.fact_check_outlined,
              message:
                  'Un intervalle inhabituel peut venir d’un oubli ou d’un saignement rapproché. Vérifiez l’historique et demandez conseil si les dates sont exactes.',
            ),
          ],
          if (insights.hasAtypicalCycleFrequency) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-atypical-frequency-warning'),
              icon: Icons.monitor_heart_outlined,
              message:
                  'Des cycles hors de la plage adulte courante de 24 à 38 jours sont enregistrés. Ce n’est pas un diagnostic; demandez conseil si cela vous inquiète.',
            ),
          ],
          if (insights.hasIncompletePeriodRecord) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-incomplete-period-warning'),
              icon: Icons.edit_calendar_outlined,
              message:
                  'Une période comporte des journées non saisies. Sa durée n’est pas utilisée dans la tendance habituelle.',
            ),
          ],
          if (insights.hasProlongedBleeding) ...[
            const SizedBox(height: 10),
            const _InsightWarning(
              key: Key('cycle-prolonged-bleeding-warning'),
              icon: Icons.health_and_safety_outlined,
              message:
                  'Un saignement de plus de 8 jours est enregistré. En cas d’inquiétude, demandez un avis professionnel.',
            ),
          ],
          if (hasCycle) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('cycle-fertility-unavailable'),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.science_outlined, color: _teal, size: 19),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Ovulation non prédite : les dates de règles seules ne permettent pas de la confirmer avec fiabilité.',
                      style: TextStyle(
                        color: Color(0xFF087568),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _historyQualityLabel(CycleHistoryQuality quality) => switch (quality) {
  CycleHistoryQuality.insufficient => 'Données insuffisantes',
  CycleHistoryQuality.limited => 'Historique court ou variable',
  CycleHistoryQuality.stable => 'Historique assez stable',
  CycleHistoryQuality.veryStable => 'Historique stable',
};

class _InsightWarning extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InsightWarning({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFF4DCA2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFA36800), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF76510A),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CycleCalendar extends StatelessWidget {
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final Map<String, CycleEntry> entriesByDay;
  final CycleInsights insights;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDate;

  const _CycleCalendar({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.entriesByDay,
    required this.insights,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDate,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leadingDays = firstDay.weekday - 1;

    return Container(
      key: const Key('cycle-calendar'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('cycle-previous-month'),
                tooltip: 'Mois précédent',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[visibleMonth.month - 1][0].toUpperCase()}${_monthNames[visibleMonth.month - 1].substring(1)} ${visibleMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                key: const Key('cycle-next-month'),
                tooltip: 'Mois suivant',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final label in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              const minimumTouchExtent = 48.0;
              const preferredSpacing = 5.0;
              final availableSpacing =
                  (constraints.maxWidth - minimumTouchExtent * 7) / 6;
              final spacing = availableSpacing <= 0
                  ? 0.0
                  : availableSpacing < preferredSpacing
                  ? availableSpacing
                  : preferredSpacing;
              final cellWidth = (constraints.maxWidth - spacing * 6) / 7;
              final rowExtent = cellWidth < minimumTouchExtent
                  ? minimumTouchExtent
                  : cellWidth;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  mainAxisExtent: rowExtent,
                ),
                itemCount: 42,
                itemBuilder: (context, index) {
                  final number = index - leadingDays + 1;
                  if (number < 1 || number > daysInMonth) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(
                    visibleMonth.year,
                    visibleMonth.month,
                    number,
                  );
                  final entry = entriesByDay[cycleDateKey(date)];
                  return _CalendarDay(
                    date: date,
                    entry: entry,
                    selected: _sameDay(date, selectedDate),
                    today: _sameDay(date, today),
                    future: date.isAfter(today),
                    predictedPeriod: insights.isPredictedPeriod(date),
                    fertile: insights.isFertile(date),
                    onTap: () => onSelectDate(date),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              const _LegendDot(color: _rose, label: 'Règles enregistrées'),
              if (insights.canHighlightPrediction)
                const _LegendDot(
                  color: _purple,
                  label: 'Début estimé',
                  outlined: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  final DateTime date;
  final CycleEntry? entry;
  final bool selected;
  final bool today;
  final bool future;
  final bool predictedPeriod;
  final bool fertile;
  final VoidCallback onTap;

  const _CalendarDay({
    required this.date,
    required this.entry,
    required this.selected,
    required this.today,
    required this.future,
    required this.predictedPeriod,
    required this.fertile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final period = entry?.isPeriod ?? false;
    final hasDetails = entry?.hasDetails ?? false;
    final semanticsLabel = <String>[
      _longDate(date),
      if (today) 'aujourd’hui',
      if (selected) 'sélectionné',
      if (future) 'date future',
      if (period) 'règles enregistrées',
      if (predictedPeriod && !period)
        'date possible du début des prochaines règles, estimation',
      if (hasDetails) 'informations enregistrées',
    ].join(', ');
    final background = period
        ? _rose
        : fertile
        ? _tealSoft
        : Colors.transparent;
    final foreground = period
        ? Colors.white
        : future
        ? const Color(0xFFAAB2C0)
        : _ink;

    return Semantics(
      key: Key('cycle-day-${cycleDateKey(date)}'),
      label: semanticsLabel,
      hint: future
          ? 'La saisie n’est pas encore disponible pour cette date'
          : hasDetails
          ? 'Modifier les informations de cette journée'
          : 'Ajouter des informations pour cette journée',
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? _navy
                  : predictedPeriod && !period
                  ? _purple
                  : today
                  ? _rose
                  : Colors.transparent,
              width: selected ? 2 : 1.4,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: today || period
                      ? FontWeight.w900
                      : FontWeight.w600,
                ),
              ),
              if (hasDetails && !period)
                const Positioned(
                  bottom: 4,
                  child: SizedBox.square(
                    dimension: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool outlined;

  const _LegendDot({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: outlined ? Border.all(color: color, width: 1.5) : null,
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
    ],
  );
}

class _SelectedDayCard extends StatelessWidget {
  final DateTime date;
  final CycleEntry? entry;
  final VoidCallback onTap;

  const _SelectedDayCard({
    required this.date,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (entry?.isPeriod ?? false)
        'Règles${entry!.flow.isEmpty ? '' : ' · ${_flowLabel(entry!.flow)}'}',
      if (entry?.symptoms.isNotEmpty ?? false)
        entry!.symptoms.map(_symptomLabel).join(', '),
      if (entry?.mood.isNotEmpty ?? false)
        'Humeur : ${_moodLabel(entry!.mood)}',
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('cycle-selected-day-card'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry?.isPeriod ?? false ? _roseSoft : _purpleSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: entry?.isPeriod ?? false ? _rose : _purple,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _longDate(date),
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details.isEmpty
                          ? 'Aucune information enregistrée'
                          : details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                entry == null
                    ? Icons.add_circle_outline_rounded
                    : Icons.edit_outlined,
                color: _purple,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GettingStarted extends StatelessWidget {
  final VoidCallback onStart;

  const _GettingStarted({required this.onStart});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _purpleSoft,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bien démarrer',
          style: TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ajoutez la date de début et la date de fin de vos dernières règles. Si elles sont encore en cours, vous pourrez corriger la date de fin plus tard. Plus votre historique est complet, plus les tendances reflètent votre cycle.',
          style: TextStyle(color: _ink, height: 1.45),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Ajouter mes dernières règles'),
        ),
      ],
    ),
  );
}

class _PeriodHistorySection extends StatelessWidget {
  final List<_PeriodEpisode> episodes;
  final ValueChanged<_PeriodEpisode> onEdit;

  const _PeriodHistorySection({required this.episodes, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final recent = episodes.reversed.take(6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historique des règles',
          style: TextStyle(
            color: _navy,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Vous pouvez corriger le début ou la fin à tout moment.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ...recent.map(
          (episode) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _roseSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.water_drop_outlined, color: _rose),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode.start == episode.end
                              ? _longDate(episode.start)
                              : '${_shortDate(episode.start)} – ${_longDate(episode.end)}',
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          episode.hasCompleteDailyRecord
                              ? '${episode.length} jour${episode.length == 1 ? '' : 's'} enregistré${episode.length == 1 ? '' : 's'}'
                              : '${episode.recordedDayCount} jour${episode.recordedDayCount == 1 ? '' : 's'} saisi${episode.recordedDayCount == 1 ? '' : 's'} · période calendaire de ${episode.length} jours',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    key: Key(
                      'cycle-edit-period-${cycleDateKey(episode.start)}',
                    ),
                    onPressed: () => onEdit(episode),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Modifier'),
                    style: TextButton.styleFrom(foregroundColor: _purple),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  final List<CycleEntry> entries;
  final ValueChanged<CycleEntry> onEntryTap;

  const _HistorySection({required this.entries, required this.onEntryTap});

  @override
  Widget build(BuildContext context) {
    final recent = entries.where((entry) => entry.hasDetails).toList()
      ..sort((first, second) => second.date.compareTo(first.date));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Symptômes et notes',
          style: TextStyle(
            color: _navy,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        ...recent
            .take(5)
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    key: Key('cycle-history-${entry.id}'),
                    onTap: () => onEntryTap(entry),
                    borderRadius: BorderRadius.circular(17),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            entry.isPeriod
                                ? Icons.water_drop_outlined
                                : Icons.spa_outlined,
                            color: entry.isPeriod ? _rose : _teal,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _longDate(entry.date),
                                  style: const TextStyle(
                                    color: _navy,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _entrySummary(entry),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

String _entrySummary(CycleEntry entry) {
  final details = <String>[];
  if (entry.isPeriod) {
    details.add(
      'Règles${entry.flow.isEmpty ? '' : ' · ${_flowLabel(entry.flow)}'}',
    );
  }
  if (entry.symptoms.isNotEmpty) {
    details.add(entry.symptoms.map(_symptomLabel).join(', '));
  }
  if (entry.mood.isNotEmpty) details.add(_moodLabel(entry.mood));
  if (entry.note.isNotEmpty) details.add(entry.note);
  return details.join(' · ');
}

class _MedicalNotice extends StatelessWidget {
  const _MedicalNotice();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('cycle-contraception-warning'),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF4DCA2)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFFA36800), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'N’utilisez pas ces estimations pour éviter une grossesse : aucun jour affiché ne peut être considéré comme sans risque. Le calendrier seul ne confirme pas l’ovulation. Consultez un professionnel en cas de douleur intense, saignement inhabituel ou inquiétude.',
            style: TextStyle(
              color: Color(0xFF76510A),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PeriodRangeResult {
  final DateTime? start;
  final DateTime? end;
  final bool delete;

  const _PeriodRangeResult.save({required this.start, required this.end})
    : delete = false;
  const _PeriodRangeResult.delete() : start = null, end = null, delete = true;
}

class _PeriodRangeForm extends StatefulWidget {
  final DateTime today;
  final _PeriodEpisode? episode;
  final int suggestedLength;

  const _PeriodRangeForm({
    required this.today,
    required this.episode,
    required this.suggestedLength,
  });

  @override
  State<_PeriodRangeForm> createState() => _PeriodRangeFormState();
}

class _PeriodRangeFormState extends State<_PeriodRangeForm> {
  late DateTime _start;
  late DateTime _end;
  late bool _ongoing;
  late bool _suggestedEnd;
  String? _error;

  bool get _editing => widget.episode != null;

  @override
  void initState() {
    super.initState();
    _start = widget.episode?.start ?? widget.today;
    _end = widget.episode?.end ?? widget.today;
    _ongoing = !_editing || _sameDay(_end, widget.today);
    _suggestedEnd = false;
  }

  DateTime get _firstAllowedDate {
    final recentLimit = DateTime(
      widget.today.year - 3,
      widget.today.month,
      widget.today.day,
    );
    final existingStart = widget.episode?.start;
    return existingStart != null && existingStart.isBefore(recentLimit)
        ? existingStart
        : recentLimit;
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: _firstAllowedDate,
      lastDate: widget.today,
      helpText: 'Date de début des règles',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked == null) return;
    setState(() {
      _start = _dateOnly(picked);
      _error = null;
      if (!_editing) {
        final estimatedEnd = _addCalendarDays(
          _start,
          widget.suggestedLength - 1,
        );
        if (estimatedEnd.isAfter(widget.today)) {
          _ongoing = true;
          _end = widget.today;
          _suggestedEnd = false;
        } else {
          _ongoing = false;
          _end = estimatedEnd;
          _suggestedEnd = true;
        }
      } else if (_end.isBefore(_start)) {
        _end = _start;
        _ongoing = _sameDay(_end, widget.today);
        _suggestedEnd = false;
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: widget.today,
      helpText: 'Date de fin des règles',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (picked == null) return;
    setState(() {
      _end = _dateOnly(picked);
      _ongoing = false;
      _suggestedEnd = false;
      _error = null;
    });
  }

  void _toggleOngoing(bool value) {
    setState(() {
      _ongoing = value;
      _error = null;
      if (value) {
        _end = widget.today;
        _suggestedEnd = false;
      } else if (_end.isBefore(_start) || _sameDay(_end, widget.today)) {
        final estimatedEnd = _addCalendarDays(
          _start,
          widget.suggestedLength - 1,
        );
        _end = estimatedEnd.isAfter(widget.today) ? widget.today : estimatedEnd;
        _suggestedEnd = true;
      }
    });
  }

  void _save() {
    final end = _ongoing ? widget.today : _end;
    final length = _calendarDayDifference(end, _start) + 1;
    if (end.isBefore(_start)) {
      setState(() => _error = 'La date de fin doit suivre la date de début.');
      return;
    }
    if (length > 90) {
      setState(
        () => _error =
            'La période sélectionnée dépasse 90 jours. Vérifiez les dates.',
      );
      return;
    }
    Navigator.pop(context, _PeriodRangeResult.save(start: _start, end: end));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette période ?'),
        content: const Text(
          'Les symptômes et notes de ces journées seront conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD92D20),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const _PeriodRangeResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveEnd = _ongoing ? widget.today : _end;
    final length = _calendarDayDifference(effectiveEnd, _start) + 1;
    return Container(
      decoration: const BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCD3DE),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editing ? 'Modifier mes règles' : 'Ajouter mes règles',
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Indiquez une seule fois le début et la fin. Tous les jours compris seront marqués automatiquement.',
                        style: TextStyle(color: _muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _RangeDateTile(
              key: const Key('cycle-range-start'),
              label: 'Premier jour des règles',
              value: _longDate(_start),
              icon: Icons.play_circle_outline_rounded,
              onTap: _pickStart,
            ),
            const SizedBox(height: 12),
            _RangeDateTile(
              key: const Key('cycle-range-end'),
              label: _ongoing
                  ? 'Fin'
                  : _suggestedEnd
                  ? 'Dernier jour estimé · modifiable'
                  : 'Dernier jour des règles',
              value: _ongoing
                  ? 'Toujours en cours · jusqu’à aujourd’hui'
                  : _longDate(_end),
              icon: Icons.stop_circle_outlined,
              onTap: _ongoing ? null : _pickEnd,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: _border),
              ),
              child: SwitchListTile.adaptive(
                key: const Key('cycle-range-ongoing'),
                contentPadding: EdgeInsets.zero,
                value: _ongoing,
                activeTrackColor: _rose,
                title: const Text(
                  'Mes règles sont toujours en cours',
                  style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Vous pourrez modifier la date de fin lorsqu’elles seront terminées.',
                ),
                onChanged: _toggleOngoing,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _roseSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range_rounded, color: _rose, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '$length jour${length == 1 ? '' : 's'} seront marqués dans le calendrier.',
                      style: const TextStyle(
                        color: Color(0xFFA52F5C),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFD92D20),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('cycle-save-period'),
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                minimumSize: const Size.fromHeight(54),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _editing
                    ? 'Enregistrer les nouvelles dates'
                    : 'Enregistrer la période',
              ),
            ),
            if (_editing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('cycle-delete-period'),
                onPressed: _delete,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD92D20),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Supprimer cette période'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeDateTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _RangeDateTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: onTap == null ? const Color(0xFFF1F2F6) : Colors.white,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: onTap == null ? _muted : _rose),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.edit_calendar_outlined, color: _purple),
          ],
        ),
      ),
    ),
  );
}

class _EntryFormResult {
  final CycleEntry? entry;
  final bool delete;

  const _EntryFormResult.save(this.entry) : delete = false;
  const _EntryFormResult.delete() : entry = null, delete = true;
}

class _CycleEntryForm extends StatefulWidget {
  final DateTime date;
  final CycleEntry? entry;

  const _CycleEntryForm({required this.date, required this.entry});

  @override
  State<_CycleEntryForm> createState() => _CycleEntryFormState();
}

class _CycleEntryFormState extends State<_CycleEntryForm> {
  late bool _isPeriod;
  late String _flow;
  late Set<String> _symptoms;
  late String _mood;
  late final TextEditingController _noteController;

  static const _flows = ['light', 'medium', 'heavy'];
  static const _availableSymptoms = [
    'cramps',
    'headache',
    'fatigue',
    'bloating',
    'backache',
    'tenderBreasts',
    'nausea',
    'acne',
  ];
  static const _moods = ['great', 'calm', 'sensitive', 'irritable', 'sad'];

  @override
  void initState() {
    super.initState();
    _isPeriod = widget.entry?.isPeriod ?? false;
    _flow = widget.entry?.flow ?? 'medium';
    _symptoms = {...?widget.entry?.symptoms};
    _mood = widget.entry?.mood ?? '';
    _noteController = TextEditingController(text: widget.entry?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      _EntryFormResult.save(
        CycleEntry(
          id: widget.entry?.id ?? cycleDateKey(widget.date),
          date: widget.date,
          isPeriod: _isPeriod,
          flow: _isPeriod ? _flow : '',
          symptoms: _symptoms.toList()..sort(),
          mood: _mood,
          note: _noteController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette journée ?'),
        content: const Text(
          'Toutes les informations saisies pour cette date seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD92D20),
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const _EntryFormResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: DraggableScrollableSheet(
      initialChildSize: .9,
      minChildSize: .65,
      maxChildSize: .96,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCCD3DE),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(22, 17, 22, 30),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _longDate(widget.date),
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Comment vous sentez-vous ?',
                            style: TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: SwitchListTile.adaptive(
                    key: const Key('cycle-period-toggle'),
                    value: _isPeriod,
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: _rose,
                    title: const Text(
                      'Inclure ce jour dans mes règles',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Correction ponctuelle d’un jour de la période.',
                    ),
                    secondary: const Icon(
                      Icons.water_drop_outlined,
                      color: _rose,
                    ),
                    onChanged: (value) => setState(() => _isPeriod = value),
                  ),
                ),
                if (_isPeriod) ...[
                  const SizedBox(height: 22),
                  const _FormHeading('Intensité du flux'),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _flows
                        .map(
                          (flow) => ChoiceChip(
                            key: Key('cycle-flow-$flow'),
                            label: Text(_flowLabel(flow)),
                            selected: _flow == flow,
                            selectedColor: _roseSoft,
                            side: BorderSide(
                              color: _flow == flow ? _rose : _border,
                            ),
                            onSelected: (_) => setState(() => _flow = flow),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 24),
                const _FormHeading('Symptômes'),
                const SizedBox(height: 5),
                const Text(
                  'Sélectionnez tout ce qui s’applique.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableSymptoms
                      .map(
                        (symptom) => FilterChip(
                          key: Key('cycle-symptom-$symptom'),
                          label: Text(_symptomLabel(symptom)),
                          selected: _symptoms.contains(symptom),
                          selectedColor: _purpleSoft,
                          checkmarkColor: _purple,
                          side: BorderSide(
                            color: _symptoms.contains(symptom)
                                ? _purple
                                : _border,
                          ),
                          onSelected: (selected) => setState(
                            () => selected
                                ? _symptoms.add(symptom)
                                : _symptoms.remove(symptom),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                const _FormHeading('Humeur'),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _moods
                      .map(
                        (mood) => ChoiceChip(
                          key: Key('cycle-mood-$mood'),
                          label: Text(_moodLabel(mood)),
                          selected: _mood == mood,
                          selectedColor: _tealSoft,
                          side: BorderSide(
                            color: _mood == mood ? _teal : _border,
                          ),
                          onSelected: (selected) =>
                              setState(() => _mood = selected ? mood : ''),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                const _FormHeading('Note personnelle'),
                const SizedBox(height: 9),
                TextField(
                  key: const Key('cycle-note-field'),
                  controller: _noteController,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Douleur, énergie, sommeil ou autre observation…',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('cycle-save-entry'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Enregistrer la journée'),
                ),
                if (widget.entry != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Supprimer cette journée'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD92D20),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FormHeading extends StatelessWidget {
  final String label;
  const _FormHeading(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _navy,
      fontSize: 16,
      fontWeight: FontWeight.w900,
    ),
  );
}

String _flowLabel(String value) => switch (value) {
  'light' => 'Léger',
  'medium' => 'Moyen',
  'heavy' => 'Abondant',
  _ => value,
};

String _symptomLabel(String value) => switch (value) {
  'cramps' => 'Crampes',
  'headache' => 'Maux de tête',
  'fatigue' => 'Fatigue',
  'bloating' => 'Ballonnements',
  'backache' => 'Mal de dos',
  'tenderBreasts' => 'Seins sensibles',
  'nausea' => 'Nausée',
  'acne' => 'Acné',
  _ => value,
};

String _moodLabel(String value) => switch (value) {
  'great' => 'Très bien',
  'calm' => 'Calme',
  'sensitive' => 'Sensible',
  'irritable' => 'Irritable',
  'sad' => 'Triste',
  _ => value,
};

class _PageFeedback extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PageFeedback({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _purple, size: 46),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _navy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

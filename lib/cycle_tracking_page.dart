import 'package:cloud_firestore/cloud_firestore.dart';
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

  factory CycleEntry.fromFirestore(
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

class CycleInsights {
  final DateTime today;
  final List<DateTime> periodStarts;
  final int averageCycleLength;
  final int averagePeriodLength;
  final DateTime? lastPeriodStart;
  final DateTime? nextPeriodStart;
  final DateTime? ovulationDate;
  final DateTime? fertileWindowStart;
  final DateTime? fertileWindowEnd;

  CycleInsights._({
    required this.today,
    required this.periodStarts,
    required this.averageCycleLength,
    required this.averagePeriodLength,
    required this.lastPeriodStart,
    required this.nextPeriodStart,
    required this.ovulationDate,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
  });

  factory CycleInsights.fromEntries(
    Iterable<CycleEntry> entries, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final periodDays =
        entries
            .where((entry) => entry.isPeriod && !entry.date.isAfter(today))
            .map((entry) => _dateOnly(entry.date))
            .toSet()
            .toList()
          ..sort();

    final runs = <List<DateTime>>[];
    for (final day in periodDays) {
      // Bleeding days less than 15 days apart belong to the same episode.
      // This keeps a missed journal day from looking like a new cycle.
      if (runs.isEmpty || _calendarDayDifference(day, runs.last.first) >= 15) {
        runs.add([day]);
      } else {
        runs.last.add(day);
      }
    }
    final starts = runs.map((run) => run.first).toList();
    final intervals = <int>[];
    for (var index = 1; index < starts.length; index++) {
      final interval = _calendarDayDifference(starts[index], starts[index - 1]);
      if (interval >= 15 && interval <= 90) intervals.add(interval);
    }
    final recentIntervals = intervals.length > 6
        ? intervals.sublist(intervals.length - 6)
        : intervals;
    final averageCycle = recentIntervals.isEmpty
        ? 28
        : (recentIntervals.reduce((a, b) => a + b) / recentIntervals.length)
              .round();

    final completedRunLengths = runs
        .where((run) => run.length >= 2 && run.length <= 10)
        .map((run) => run.length)
        .toList();
    final recentRunLengths = completedRunLengths.length > 6
        ? completedRunLengths.sublist(completedRunLengths.length - 6)
        : completedRunLengths;
    final averagePeriod = recentRunLengths.isEmpty
        ? 5
        : (recentRunLengths.reduce((a, b) => a + b) / recentRunLengths.length)
              .round()
              .clamp(1, 10);

    final lastStart = starts.isEmpty ? null : starts.last;
    DateTime? nextStart;
    if (lastStart != null) {
      nextStart = _addCalendarDays(lastStart, averageCycle);
      while (nextStart!.isBefore(today)) {
        nextStart = _addCalendarDays(nextStart, averageCycle);
      }
    }
    final ovulation = nextStart == null
        ? null
        : _addCalendarDays(nextStart, -14);

    return CycleInsights._(
      today: today,
      periodStarts: starts,
      averageCycleLength: averageCycle,
      averagePeriodLength: averagePeriod,
      lastPeriodStart: lastStart,
      nextPeriodStart: nextStart,
      ovulationDate: ovulation,
      fertileWindowStart: ovulation == null
          ? null
          : _addCalendarDays(ovulation, -5),
      fertileWindowEnd: ovulation == null
          ? null
          : _addCalendarDays(ovulation, 1),
    );
  }

  int? get currentCycleDay => lastPeriodStart == null
      ? null
      : _calendarDayDifference(today, lastPeriodStart!) + 1;

  int? get daysUntilNextPeriod => nextPeriodStart == null
      ? null
      : _calendarDayDifference(nextPeriodStart!, today);

  bool isPredictedPeriod(DateTime date) {
    if (nextPeriodStart == null) return false;
    final difference = _calendarDayDifference(date, nextPeriodStart!);
    return difference >= 0 && difference < averagePeriodLength;
  }

  bool isFertile(DateTime date) {
    if (fertileWindowStart == null || fertileWindowEnd == null) return false;
    final day = _dateOnly(date);
    return !day.isBefore(fertileWindowStart!) &&
        !day.isAfter(fertileWindowEnd!);
  }
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
      FirebaseFirestore.instance
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
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
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
    } on FirebaseException catch (error) {
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
    } on FirebaseException {
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
                    entries.add(CycleEntry.fromFirestore(document));
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
                hasEntries: entries.isNotEmpty,
                onLogToday: () => _openEntryForm(_today, entries),
              ),
              const SizedBox(height: 18),
              const _PrivacyNotice(),
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
              if (entries.isEmpty) ...[
                const SizedBox(height: 18),
                _GettingStarted(onStart: () => _openEntryForm(_today, entries)),
              ] else ...[
                const SizedBox(height: 26),
                _HistorySection(
                  entries: entries,
                  onEntryTap: (entry) => _openEntryForm(entry.date, entries),
                ),
              ],
              const SizedBox(height: 22),
              const _MedicalNotice(),
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
  final VoidCallback onLogToday;

  const _CycleHero({
    required this.insights,
    required this.hasEntries,
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
            FilledButton.icon(
              key: const Key('cycle-log-today'),
              onPressed: onLogToday,
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Renseigner aujourd’hui'),
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
    final days = insights.daysUntilNextPeriod;
    final String title;
    final String subtitle;
    final IconData icon;
    if (!hasCycle) {
      title = 'Votre cycle en un coup d’œil';
      subtitle =
          'Ajoutez au moins un jour de règles pour obtenir une estimation.';
      icon = Icons.auto_graph_rounded;
    } else if (inPeriod) {
      title = 'Règles en cours';
      subtitle = 'Jour ${insights.currentCycleDay ?? 1} de votre cycle';
      icon = Icons.water_drop_rounded;
    } else if (days == 0) {
      title = 'Règles prévues aujourd’hui';
      subtitle = 'Cette date reste une estimation basée sur votre historique.';
      icon = Icons.event_rounded;
    } else {
      title = 'Prochaines règles dans $days jour${days == 1 ? '' : 's'}';
      subtitle = insights.nextPeriodStart == null
          ? ''
          : 'Autour du ${_longDate(insights.nextPeriodStart!)}';
      icon = Icons.event_available_rounded;
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
              _MetricChip(
                label: 'Cycle moyen',
                value: '${insights.averageCycleLength} jours',
                color: _purple,
              ),
              _MetricChip(
                label: 'Règles moyennes',
                value: '${insights.averagePeriodLength} jours',
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
          if (insights.fertileWindowStart != null) ...[
            const SizedBox(height: 17),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Fenêtre fertile estimée : ${_shortDate(insights.fertileWindowStart!)} – ${_shortDate(insights.fertileWindowEnd!)}',
                style: const TextStyle(
                  color: Color(0xFF087568),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
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
          ),
          const SizedBox(height: 12),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              _LegendDot(color: _rose, label: 'Règles'),
              _LegendDot(color: _purple, label: 'Prévues', outlined: true),
              _LegendDot(color: _teal, label: 'Fertilité estimée'),
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
      label: '${_longDate(date)}${period ? ', règles' : ''}',
      button: true,
      child: InkWell(
        key: Key('cycle-day-${cycleDateKey(date)}'),
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
          'Sélectionnez dans le calendrier le premier jour de vos dernières règles, activez « Règles ce jour » puis enregistrez. Plus votre historique est complet, plus les tendances reflètent votre cycle.',
          style: TextStyle(color: _ink, height: 1.45),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Ajouter une première journée'),
        ),
      ],
    ),
  );
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
          'Journal récent',
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
            'Les dates affichées sont des estimations, pas un diagnostic ni une méthode contraceptive. Consultez un professionnel en cas de douleur intense, saignement inhabituel ou inquiétude.',
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
                      'Règles ce jour',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Activez pour marquer un jour de saignement.',
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

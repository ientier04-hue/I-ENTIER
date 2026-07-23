import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const _appointmentPrimary = Color(0xFF176BFF);
const _appointmentNavy = Color(0xFF102A56);
const _appointmentMuted = Color(0xFF667085);
const _appointmentBorder = Color(0xFFE4EAF2);
const _appointmentCanvas = Color(0xFFF5F8FC);

enum AppointmentStatus { pending, confirmed, cancelled }

enum AppointmentMode { atProvider, homeVisit, video }

extension AppointmentModeText on AppointmentMode {
  String get storageValue => switch (this) {
    AppointmentMode.atProvider => 'inPerson',
    AppointmentMode.homeVisit => 'homeVisit',
    AppointmentMode.video => 'video',
  };

  String get label => switch (this) {
    AppointmentMode.atProvider => 'Sur place',
    AppointmentMode.homeVisit => 'À domicile',
    AppointmentMode.video => 'Visioconférence',
  };

  String get description => switch (this) {
    AppointmentMode.atProvider =>
      'Je me rends chez le personnel ou dans l’institution.',
    AppointmentMode.homeVisit => 'Le professionnel se déplace à mon adresse.',
    AppointmentMode.video => 'La consultation se déroule à distance.',
  };

  IconData get icon => switch (this) {
    AppointmentMode.atProvider => Icons.directions_walk_rounded,
    AppointmentMode.homeVisit => Icons.home_work_rounded,
    AppointmentMode.video => Icons.video_camera_front_rounded,
  };

  static AppointmentMode fromStorage(Object? value) => switch (value) {
    'homeVisit' => AppointmentMode.homeVisit,
    'video' => AppointmentMode.video,
    _ => AppointmentMode.atProvider,
  };
}

extension AppointmentStatusText on AppointmentStatus {
  String get storageValue => switch (this) {
    AppointmentStatus.pending => 'pending',
    AppointmentStatus.confirmed => 'confirmed',
    AppointmentStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    AppointmentStatus.pending => 'En attente',
    AppointmentStatus.confirmed => 'Confirmé',
    AppointmentStatus.cancelled => 'Annulé',
  };

  static AppointmentStatus fromStorage(Object? value) => switch (value) {
    'confirmed' => AppointmentStatus.confirmed,
    'cancelled' => AppointmentStatus.cancelled,
    _ => AppointmentStatus.pending,
  };
}

class Appointment {
  final String id;
  final String patientId;
  final String patientName;
  final String providerId;
  final String providerType;
  final String providerName;
  final String service;
  final AppointmentMode mode;
  final String location;
  final DateTime scheduledAt;
  final String scheduleLabel;
  final AppointmentStatus status;
  final String patientNote;
  final String responseNote;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? respondedAt;

  const Appointment({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.providerId,
    required this.providerType,
    required this.providerName,
    required this.service,
    this.mode = AppointmentMode.atProvider,
    this.location = '',
    required this.scheduledAt,
    required this.scheduleLabel,
    required this.status,
    required this.patientNote,
    required this.responseNote,
    required this.createdAt,
    required this.updatedAt,
    this.respondedAt,
  });

  factory Appointment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    String text(String key) => data[key]?.toString().trim() ?? '';
    DateTime date(String key, [DateTime? fallback]) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return fallback ?? DateTime.now();
    }

    final createdAt = date('createdAt');
    return Appointment(
      id: document.id,
      patientId: text('patientId'),
      patientName: text('patientName'),
      providerId: text('providerId'),
      providerType: text('providerType'),
      providerName: text('providerName'),
      service: text('service'),
      mode: AppointmentModeText.fromStorage(data['appointmentMode']),
      location: text('location'),
      scheduledAt: date('scheduledAt'),
      scheduleLabel: text('scheduleLabel'),
      status: AppointmentStatusText.fromStorage(data['status']),
      patientNote: text('patientNote'),
      responseNote: text('responseNote'),
      createdAt: createdAt,
      updatedAt: date('updatedAt', createdAt),
      respondedAt: data['respondedAt'] is Timestamp
          ? (data['respondedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class ProviderBookingTarget {
  final String id;
  final String type;
  final String name;
  final String service;
  final String schedule;
  final String address;
  final bool available;

  const ProviderBookingTarget({
    required this.id,
    required this.type,
    required this.name,
    required this.service,
    required this.schedule,
    this.address = '',
    required this.available,
  });
}

abstract class PatientAppointmentRepository {
  Stream<List<Appointment>> watchForPatient(String patientId);

  Future<void> create({
    required String patientId,
    required String patientName,
    required ProviderBookingTarget provider,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentMode mode,
    required String location,
  });
}

class FirestorePatientAppointmentRepository
    implements PatientAppointmentRepository {
  final FirebaseFirestore firestore;

  FirestorePatientAppointmentRepository({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<List<Appointment>> watchForPatient(String patientId) => firestore
      .collection('appointments')
      .where('patientId', isEqualTo: patientId)
      .snapshots()
      .map((snapshot) {
        final appointments = snapshot.docs
            .map(Appointment.fromFirestore)
            .toList(growable: false);
        appointments.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
        return appointments;
      });

  @override
  Future<void> create({
    required String patientId,
    required String patientName,
    required ProviderBookingTarget provider,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentMode mode,
    required String location,
  }) {
    final appointmentId =
        '${provider.id}_${scheduledAt.millisecondsSinceEpoch}';
    return firestore.collection('appointments').doc(appointmentId).set({
      'patientId': patientId,
      'patientName': patientName.trim().isEmpty
          ? 'Patient i-ENTIER'
          : patientName.trim(),
      'providerId': provider.id,
      'providerType': provider.type,
      'providerName': provider.name.trim(),
      'service': provider.service.trim(),
      'appointmentMode': mode.storageValue,
      'location': location.trim(),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'scheduleLabel': provider.schedule.trim(),
      'status': AppointmentStatus.pending.storageValue,
      'patientNote': patientNote.trim(),
      'responseNote': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class AppointmentAvailability {
  final Set<int> weekdays;
  final TimeOfDay openingTime;
  final TimeOfDay closingTime;
  final Duration interval;

  const AppointmentAvailability({
    required this.weekdays,
    required this.openingTime,
    required this.closingTime,
    this.interval = const Duration(minutes: 30),
  });

  factory AppointmentAvailability.fromSchedule(String schedule) {
    final normalized = _normalizeSchedule(schedule);
    final weekdays = _parseWeekdays(normalized);
    final timeRange = _parseTimeRange(normalized);
    return AppointmentAvailability(
      weekdays: weekdays.isEmpty ? {1, 2, 3, 4, 5} : weekdays,
      openingTime: timeRange.$1,
      closingTime: timeRange.$2,
    );
  }

  List<DateTime> availableDates({
    DateTime? now,
    int dayCount = 45,
    int maximum = 14,
  }) {
    final reference = now ?? DateTime.now();
    final firstDay = DateTime(reference.year, reference.month, reference.day);
    final result = <DateTime>[];
    for (
      var offset = 0;
      offset < dayCount && result.length < maximum;
      offset++
    ) {
      final date = firstDay.add(Duration(days: offset));
      if (slotsForDate(date, now: reference).isNotEmpty) result.add(date);
    }
    return result;
  }

  List<DateTime> slotsForDate(DateTime date, {DateTime? now}) {
    if (!weekdays.contains(date.weekday)) return const [];
    final reference = now ?? DateTime.now();
    final opening = DateTime(
      date.year,
      date.month,
      date.day,
      openingTime.hour,
      openingTime.minute,
    );
    final closing = DateTime(
      date.year,
      date.month,
      date.day,
      closingTime.hour,
      closingTime.minute,
    );
    if (!closing.isAfter(opening)) return const [];

    final result = <DateTime>[];
    for (
      var slot = opening;
      !slot.add(interval).isAfter(closing);
      slot = slot.add(interval)
    ) {
      if (slot.isAfter(reference.add(const Duration(minutes: 30)))) {
        result.add(slot);
      }
    }
    return result;
  }
}

String _normalizeSchedule(String value) => value
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('à', 'a')
    .replaceAll('–', '-')
    .replaceAll('—', '-');

Set<int> _parseWeekdays(String value) {
  if (value.contains('tous les jours') ||
      value.contains('7j/7') ||
      value.contains('7 jours')) {
    return {1, 2, 3, 4, 5, 6, 7};
  }
  const names = <String, int>{
    'lun': 1,
    'lundi': 1,
    'mar': 2,
    'mardi': 2,
    'mer': 3,
    'mercredi': 3,
    'jeu': 4,
    'jeudi': 4,
    'ven': 5,
    'vendredi': 5,
    'sam': 6,
    'samedi': 6,
    'dim': 7,
    'dimanche': 7,
  };
  const dayPattern =
      r'(lundi|lun|mardi|mar|mercredi|mer|jeudi|jeu|vendredi|ven|samedi|sam|dimanche|dim)';
  final result = <int>{};
  final ranges = RegExp(
    '$dayPattern\\s*(?:-|a|au)\\s*$dayPattern',
  ).allMatches(value);
  for (final range in ranges) {
    final start = names[range.group(1)];
    final end = names[range.group(2)];
    if (start == null || end == null) continue;
    var day = start;
    while (true) {
      result.add(day);
      if (day == end) break;
      day = day == 7 ? 1 : day + 1;
    }
  }
  if (result.isNotEmpty) return result;
  for (final match in RegExp(dayPattern).allMatches(value)) {
    final day = names[match.group(1)];
    if (day != null) result.add(day);
  }
  return result;
}

(TimeOfDay, TimeOfDay) _parseTimeRange(String value) {
  final match = RegExp(
    r'(\d{1,2})(?:\s*(?:h|:)\s*(\d{1,2})?)?\s*(?:-|a|au)\s*(\d{1,2})(?:\s*(?:h|:)\s*(\d{1,2})?)?',
  ).firstMatch(value);
  if (match == null) {
    return (
      const TimeOfDay(hour: 8, minute: 0),
      const TimeOfDay(hour: 17, minute: 0),
    );
  }
  int number(int group, [int fallback = 0]) =>
      int.tryParse(match.group(group) ?? '') ?? fallback;
  final startHour = number(1).clamp(0, 23);
  final startMinute = number(2).clamp(0, 59);
  final endHour = number(3).clamp(0, 23);
  final endMinute = number(4).clamp(0, 59);
  if (endHour * 60 + endMinute <= startHour * 60 + startMinute) {
    return (
      const TimeOfDay(hour: 8, minute: 0),
      const TimeOfDay(hour: 17, minute: 0),
    );
  }
  return (
    TimeOfDay(hour: startHour, minute: startMinute),
    TimeOfDay(hour: endHour, minute: endMinute),
  );
}

class AppointmentBookingPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final ProviderBookingTarget provider;
  final PatientAppointmentRepository repository;
  final DateTime? now;

  AppointmentBookingPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.provider,
    PatientAppointmentRepository? repository,
    this.now,
  }) : repository = repository ?? FirestorePatientAppointmentRepository();

  @override
  State<AppointmentBookingPage> createState() => _AppointmentBookingPageState();
}

class _AppointmentBookingPageState extends State<AppointmentBookingPage> {
  final _noteController = TextEditingController();
  final _addressController = TextEditingController();
  late final AppointmentAvailability _availability;
  late final List<DateTime> _dates;
  AppointmentMode _selectedMode = AppointmentMode.atProvider;
  DateTime? _selectedDate;
  DateTime? _selectedSlot;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _availability = AppointmentAvailability.fromSchedule(
      widget.provider.schedule,
    );
    _dates = widget.provider.available
        ? _availability.availableDates(now: widget.now)
        : const [];
    if (_dates.isNotEmpty) _selectedDate = _dates.first;
  }

  @override
  void dispose() {
    _noteController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final slot = _selectedSlot;
    if (slot == null || _saving) return;
    if (_selectedMode == AppointmentMode.homeVisit &&
        _addressController.text.trim().isEmpty) {
      _showError('Indiquez l’adresse où le professionnel doit se rendre.');
      return;
    }
    final location = switch (_selectedMode) {
      AppointmentMode.atProvider => widget.provider.address,
      AppointmentMode.homeVisit => _addressController.text,
      AppointmentMode.video => '',
    };
    setState(() => _saving = true);
    try {
      await widget.repository.create(
        patientId: widget.patientId,
        patientName: widget.patientName,
        provider: widget.provider,
        scheduledAt: slot,
        patientNote: _noteController.text,
        mode: _selectedMode,
        location: location,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showError(
        error.code == 'permission-denied'
            ? 'Ce créneau vient peut-être d’être réservé. Choisissez-en un autre.'
            : 'La demande n’a pas pu être envoyée. Réessayez.',
      );
    } catch (_) {
      if (mounted) {
        _showError('La demande n’a pas pu être envoyée. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final slots = _selectedDate == null
        ? const <DateTime>[]
        : _availability.slotsForDate(_selectedDate!, now: widget.now);
    return Scaffold(
      backgroundColor: _appointmentCanvas,
      appBar: AppBar(title: const Text('Réserver un rendez-vous')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BookingProviderCard(provider: widget.provider),
                  const SizedBox(height: 20),
                  if (!widget.provider.available)
                    const _AppointmentMessage(
                      icon: Icons.event_busy_outlined,
                      title: 'Réservations indisponibles',
                      message:
                          'Ce profil n’accepte pas de nouvelles demandes pour le moment.',
                    )
                  else if (_dates.isEmpty)
                    const _AppointmentMessage(
                      icon: Icons.calendar_month_outlined,
                      title: 'Aucun créneau disponible',
                      message:
                          'L’horaire publié ne contient aucun créneau à venir. Réessayez plus tard.',
                    )
                  else ...[
                    const _BookingHeading(
                      number: '1',
                      title: 'Choisissez le type de rendez-vous',
                    ),
                    const SizedBox(height: 12),
                    _AppointmentModeSelector(
                      selectedMode: _selectedMode,
                      onSelected: (mode) =>
                          setState(() => _selectedMode = mode),
                    ),
                    if (_selectedMode == AppointmentMode.homeVisit) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('home-visit-address'),
                        controller: _addressController,
                        maxLength: 300,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Adresse de la visite *',
                          hintText: 'Rue, quartier, ville et indication utile',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                    ] else if (_selectedMode == AppointmentMode.video) ...[
                      const SizedBox(height: 12),
                      const _ModeInformation(
                        icon: Icons.link_rounded,
                        message:
                            'Le professionnel pourra transmettre le lien ou les instructions après validation.',
                      ),
                    ],
                    const SizedBox(height: 22),
                    const _BookingHeading(
                      number: '2',
                      title: 'Choisissez la date',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 78,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _dates.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 9),
                        itemBuilder: (context, index) {
                          final date = _dates[index];
                          final selected = _sameDay(date, _selectedDate);
                          return ChoiceChip(
                            key: ValueKey(
                              'appointment-date-${date.toIso8601String()}',
                            ),
                            selected: selected,
                            showCheckmark: false,
                            onSelected: (_) => setState(() {
                              _selectedDate = date;
                              _selectedSlot = null;
                            }),
                            label: SizedBox(
                              width: 62,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _shortWeekday(date),
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : _appointmentMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${date.day} ${_shortMonth(date)}',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : _appointmentNavy,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            selectedColor: _appointmentPrimary,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: _appointmentBorder),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _BookingHeading(
                      number: '3',
                      title: 'Choisissez l’heure',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (final slot in slots)
                          ChoiceChip(
                            key: ValueKey(
                              'appointment-time-${slot.hour}-${slot.minute}',
                            ),
                            label: Text(_timeLabel(slot)),
                            selected: slot == _selectedSlot,
                            showCheckmark: false,
                            selectedColor: _appointmentPrimary,
                            labelStyle: TextStyle(
                              color: slot == _selectedSlot
                                  ? Colors.white
                                  : _appointmentNavy,
                              fontWeight: FontWeight.w800,
                            ),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: _appointmentBorder),
                            onSelected: (_) =>
                                setState(() => _selectedSlot = slot),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const _BookingHeading(
                      number: '4',
                      title: 'Précisez votre demande',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Motif ou note (facultatif)',
                        hintText:
                            'Ajoutez une information utile pour préparer le rendez-vous.',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('submit-appointment'),
                      onPressed: _selectedSlot == null || _saving
                          ? null
                          : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _saving ? 'Envoi en cours…' : 'Envoyer la demande',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Le créneau reste en attente jusqu’à la réponse du personnel ou de l’institution.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _appointmentMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingProviderCard extends StatelessWidget {
  final ProviderBookingTarget provider;

  const _BookingProviderCard({required this.provider});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _appointmentBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            provider.type == 'institution'
                ? Icons.account_balance_rounded
                : Icons.medical_services_rounded,
            color: _appointmentPrimary,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.name,
                style: const TextStyle(
                  color: _appointmentNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                provider.service,
                style: const TextStyle(color: _appointmentMuted),
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 16,
                    color: _appointmentPrimary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      provider.schedule,
                      style: const TextStyle(
                        color: _appointmentNavy,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AppointmentModeSelector extends StatelessWidget {
  final AppointmentMode selectedMode;
  final ValueChanged<AppointmentMode> onSelected;

  const _AppointmentModeSelector({
    required this.selectedMode,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final mode in AppointmentMode.values) ...[
        _AppointmentModeOption(
          mode: mode,
          selected: selectedMode == mode,
          onTap: () => onSelected(mode),
        ),
        if (mode != AppointmentMode.values.last) const SizedBox(height: 9),
      ],
    ],
  );
}

class _AppointmentModeOption extends StatelessWidget {
  final AppointmentMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _AppointmentModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: mode.label,
    child: Material(
      color: selected ? const Color(0xFFEAF1FF) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('appointment-mode-${mode.storageValue}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _appointmentPrimary : _appointmentBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? _appointmentPrimary
                      : const Color(0xFFF1F5FB),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  mode.icon,
                  color: selected ? Colors.white : _appointmentPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: const TextStyle(
                        color: _appointmentNavy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.description,
                      style: const TextStyle(
                        color: _appointmentMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _appointmentPrimary : _appointmentMuted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ModeInformation extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ModeInformation({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF7F4),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF13795B)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF13634D),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BookingHeading extends StatelessWidget {
  final String number;
  final String title;

  const _BookingHeading({required this.number, required this.title});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: _appointmentPrimary,
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _appointmentNavy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class PatientAppointmentsPage extends StatelessWidget {
  final String patientId;
  final Stream<List<Appointment>>? appointmentStream;
  final PatientAppointmentRepository? repository;

  const PatientAppointmentsPage({
    super.key,
    required this.patientId,
    this.appointmentStream,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final stream = appointmentStream ?? repository?.watchForPatient(patientId);
    return Column(
      key: const ValueKey('patient-appointments-page'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rendez-vous',
          style: TextStyle(
            color: _appointmentNavy,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Suivez les demandes envoyées et les réponses reçues.',
          style: TextStyle(color: _appointmentMuted),
        ),
        const SizedBox(height: 22),
        if (stream == null)
          const _AppointmentMessage(
            icon: Icons.calendar_month_outlined,
            title: 'Aucun rendez-vous',
            message:
                'Choisissez un personnel ou une institution dans l’annuaire pour réserver.',
          )
        else
          StreamBuilder<List<Appointment>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _AppointmentMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Rendez-vous indisponibles',
                  message:
                      'La synchronisation est momentanément impossible. Réessayez plus tard.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(36),
                    child: CircularProgressIndicator(
                      color: _appointmentPrimary,
                    ),
                  ),
                );
              }
              final appointments = snapshot.data!;
              if (appointments.isEmpty) {
                return const _AppointmentMessage(
                  icon: Icons.calendar_month_outlined,
                  title: 'Aucun rendez-vous',
                  message:
                      'Choisissez un personnel ou une institution dans l’annuaire pour réserver.',
                );
              }
              return Column(
                children: [
                  for (final appointment in appointments) ...[
                    _PatientAppointmentCard(appointment: appointment),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _PatientAppointmentCard extends StatelessWidget {
  final Appointment appointment;

  const _PatientAppointmentCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (appointment.status) {
      AppointmentStatus.pending => const Color(0xFF98610A),
      AppointmentStatus.confirmed => const Color(0xFF13795B),
      AppointmentStatus.cancelled => const Color(0xFFB42318),
    };
    final statusBackground = switch (appointment.status) {
      AppointmentStatus.pending => const Color(0xFFFFF4DF),
      AppointmentStatus.confirmed => const Color(0xFFE7F7EF),
      AppointmentStatus.cancelled => const Color(0xFFFFECE9),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _appointmentBorder),
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
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: _appointmentPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.providerName,
                      style: const TextStyle(
                        color: _appointmentNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (appointment.service.isNotEmpty)
                      Text(
                        appointment.service,
                        style: const TextStyle(color: _appointmentMuted),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  appointment.status.label,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _AppointmentInfo(
            icon: Icons.event_outlined,
            text: _longDateTime(appointment.scheduledAt),
          ),
          const SizedBox(height: 9),
          _AppointmentInfo(
            icon: appointment.mode.icon,
            text: appointment.mode.label,
          ),
          if (appointment.location.isNotEmpty) ...[
            const SizedBox(height: 9),
            _AppointmentInfo(
              icon: Icons.location_on_outlined,
              text: appointment.location,
            ),
          ],
          if (appointment.patientNote.isNotEmpty) ...[
            const SizedBox(height: 9),
            _AppointmentInfo(
              icon: Icons.notes_rounded,
              text: appointment.patientNote,
            ),
          ],
          if (appointment.responseNote.isNotEmpty) ...[
            const Divider(height: 26, color: _appointmentBorder),
            Text(
              'Réponse : ${appointment.responseNote}',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppointmentInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AppointmentInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _appointmentPrimary, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: _appointmentNavy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _AppointmentMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AppointmentMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _appointmentBorder),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: _appointmentPrimary),
        const SizedBox(height: 11),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _appointmentNavy,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _appointmentMuted, height: 1.4),
        ),
      ],
    ),
  );
}

bool _sameDay(DateTime value, DateTime? other) =>
    other != null &&
    value.year == other.year &&
    value.month == other.month &&
    value.day == other.day;

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _timeLabel(DateTime value) =>
    '${_twoDigits(value.hour)} h ${_twoDigits(value.minute)}';

String _shortWeekday(DateTime value) => const [
  'lun.',
  'mar.',
  'mer.',
  'jeu.',
  'ven.',
  'sam.',
  'dim.',
][value.weekday - 1];

String _shortMonth(DateTime value) => const [
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
][value.month - 1];

String _longDateTime(DateTime value) =>
    '${_shortWeekday(value)} ${value.day} ${_shortMonth(value)} ${value.year} à ${_timeLabel(value)}';

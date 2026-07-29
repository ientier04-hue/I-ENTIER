import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/appointments.dart';

class _FakePatientAppointmentRepository
    implements PatientAppointmentRepository {
  String? patientId;
  String? patientName;
  ProviderBookingTarget? provider;
  DateTime? scheduledAt;
  String? patientNote;
  AppointmentMode? mode;
  AppointmentPaymentMethod? paymentMethod;
  String? location;
  Appointment? updatedAppointment;
  Appointment? cancelledAppointment;
  Appointment? deletedAppointment;
  String? cancellationReason;

  @override
  Future<void> create({
    required String patientId,
    required String patientName,
    required ProviderBookingTarget provider,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentMode mode,
    required AppointmentPaymentMethod paymentMethod,
    required String location,
  }) async {
    this.patientId = patientId;
    this.patientName = patientName;
    this.provider = provider;
    this.scheduledAt = scheduledAt;
    this.patientNote = patientNote;
    this.mode = mode;
    this.paymentMethod = paymentMethod;
    this.location = location;
  }

  @override
  Future<void> update({
    required Appointment appointment,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentPaymentMethod paymentMethod,
    required String location,
  }) async {
    updatedAppointment = appointment;
    this.scheduledAt = scheduledAt;
    this.patientNote = patientNote;
    this.paymentMethod = paymentMethod;
    this.location = location;
  }

  @override
  Future<void> cancel({
    required Appointment appointment,
    required String reason,
  }) async {
    cancelledAppointment = appointment;
    cancellationReason = reason;
  }

  @override
  Future<void> deleteForPatient(Appointment appointment) async {
    deletedAppointment = appointment;
  }

  @override
  Stream<List<Appointment>> watchForPatient(String patientId) =>
      const Stream.empty();
}

void main() {
  test('convertit un horaire français en créneaux de 30 minutes', () {
    final availability = AppointmentAvailability.fromSchedule(
      'Lun–Ven, 8 h–10 h',
    );
    final now = DateTime(2026, 7, 20, 7);
    final dates = availability.availableDates(now: now);
    final slots = availability.slotsForDate(dates.first, now: now);

    expect(availability.hasValidSchedule, isTrue);
    expect(dates.first.weekday, DateTime.monday);
    expect(slots.map((slot) => '${slot.hour}:${slot.minute}'), [
      '8:0',
      '8:30',
      '9:0',
      '9:30',
    ]);
    expect(availability.slotsForDate(DateTime(2026, 7, 25), now: now), isEmpty);
  });

  test('ne fabrique aucun créneau pour un horaire absent ou illisible', () {
    final now = DateTime(2026, 7, 20, 7);
    const invalidSchedules = [
      '',
      'Sur rendez-vous',
      'Lun–Ven',
      '8 h–17 h',
      'Lun–Ven, 18 h–8 h',
      'Lun–Ven, 25 h–27 h',
    ];

    for (final schedule in invalidSchedules) {
      final availability = AppointmentAvailability.fromSchedule(schedule);

      expect(availability.hasValidSchedule, isFalse, reason: schedule);
      expect(availability.availableDates(now: now), isEmpty, reason: schedule);
      expect(
        availability.slotsForDate(DateTime(2026, 7, 20), now: now),
        isEmpty,
        reason: schedule,
      );
    }
  });

  test('respecte la période de disponibilité configurée', () {
    final availability = AppointmentAvailability.fromSchedule(
      'Lun–Ven, 8 h–10 h',
      validFrom: DateTime(2026, 7, 22),
      validUntil: DateTime(2026, 7, 23),
    );

    expect(availability.availableDates(now: DateTime(2026, 7, 20, 7)), [
      DateTime(2026, 7, 22),
      DateTime(2026, 7, 23),
    ]);
  });

  testWidgets(
    'invite à contacter le prestataire quand son horaire est illisible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakePatientAppointmentRepository();
      const provider = ProviderBookingTarget(
        id: 'provider-1',
        type: 'professional',
        name: 'Dre Marie Jean',
        service: 'Pédiatrie',
        schedule: 'Sur rendez-vous',
        available: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentBookingPage(
            patientId: 'patient-1',
            patientName: 'Jean Baptiste',
            provider: provider,
            repository: repository,
            now: DateTime(2026, 7, 20, 7),
          ),
        ),
      );

      expect(find.text('Aucun créneau disponible'), findsOneWidget);
      expect(
        find.text(
          'Aucun horaire de réservation valide n’est publié. Contactez directement le prestataire pour connaître ses disponibilités.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('appointment-time-8-0')), findsNothing);
      expect(find.byKey(const ValueKey('submit-appointment')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('envoie la date, l’heure et la note choisies', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakePatientAppointmentRepository();
    const provider = ProviderBookingTarget(
      id: 'provider-1',
      type: 'professional',
      name: 'Dre Marie Jean',
      service: 'Pédiatrie',
      schedule: 'Lun–Ven, 8 h–10 h',
      available: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentBookingPage(
          patientId: 'patient-1',
          patientName: 'Jean Baptiste',
          provider: provider,
          repository: repository,
          now: DateTime(2026, 7, 20, 7),
        ),
      ),
    );

    final firstSlot = find.byKey(const ValueKey('appointment-time-8-0'));
    await tester.ensureVisible(firstSlot);
    await tester.tap(firstSlot);
    final monCash = find.byKey(const ValueKey('payment-method-monCash'));
    await tester.ensureVisible(monCash);
    await tester.tap(monCash);
    await tester.enterText(find.byType(TextField), 'Consultation de suivi');
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-appointment')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('submit-appointment')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('submit-appointment')));
    await tester.pumpAndSettle();

    expect(repository.patientId, 'patient-1');
    expect(repository.patientName, 'Jean Baptiste');
    expect(repository.provider, provider);
    expect(repository.scheduledAt, DateTime(2026, 7, 20, 8));
    expect(repository.patientNote, 'Consultation de suivi');
    expect(repository.mode, AppointmentMode.atProvider);
    expect(repository.paymentMethod, AppointmentPaymentMethod.monCash);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permet une visite à domicile avec une adresse obligatoire', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakePatientAppointmentRepository();
    const provider = ProviderBookingTarget(
      id: 'provider-1',
      type: 'professional',
      name: 'Dre Marie Jean',
      service: 'Médecine générale',
      schedule: 'Lun–Ven, 8 h–10 h',
      address: 'Clinique Espoir, Pétion-Ville',
      available: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentBookingPage(
          patientId: 'patient-1',
          patientName: 'Jean Baptiste',
          provider: provider,
          repository: repository,
          now: DateTime(2026, 7, 20, 7),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('appointment-mode-homeVisit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-visit-address')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('home-visit-address')),
      '12 rue des Fleurs, Delmas',
    );
    tester.testTextInput.hide();
    await tester.pump();
    final firstSlot = find.byKey(const ValueKey('appointment-time-8-0'));
    await tester.ensureVisible(firstSlot);
    await tester.tap(firstSlot);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-appointment')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('submit-appointment')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('submit-appointment')));
    await tester.pumpAndSettle();

    expect(repository.mode, AppointmentMode.homeVisit);
    expect(repository.location, '12 rue des Fleurs, Delmas');
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les réponses dans la page Rendez-vous', (tester) async {
    final appointment = Appointment(
      id: 'appointment-1',
      patientId: 'patient-1',
      patientName: 'Jean Baptiste',
      providerId: 'provider-1',
      providerType: 'professional',
      providerName: 'Dre Marie Jean',
      service: 'Pédiatrie',
      mode: AppointmentMode.video,
      paymentMethod: AppointmentPaymentMethod.bankTransfer,
      scheduledAt: DateTime(2026, 8, 4, 9, 30),
      scheduleLabel: 'Lun–Ven, 8 h–16 h',
      status: AppointmentStatus.confirmed,
      patientNote: 'Consultation de suivi',
      responseNote: 'Présentez-vous 15 minutes avant.',
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 23),
      respondedAt: DateTime(2026, 7, 23),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatientAppointmentsPage(
            patientId: 'patient-1',
            appointmentStream: Stream.value([appointment]),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dre Marie Jean'), findsOneWidget);
    expect(find.text('Confirmé'), findsOneWidget);
    expect(find.text('Visioconférence'), findsOneWidget);
    expect(find.text('Paiement : Virement bancaire'), findsOneWidget);
    expect(find.textContaining('Présentez-vous 15 minutes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('modifie un rendez-vous en attente', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakePatientAppointmentRepository();
    final appointment = Appointment(
      id: 'appointment-edit',
      patientId: 'patient-1',
      patientName: 'Jean Baptiste',
      providerId: 'provider-1',
      providerType: 'professional',
      providerName: 'Dre Marie Jean',
      service: 'Pédiatrie',
      scheduledAt: DateTime(2026, 7, 20, 8),
      scheduleLabel: 'Lun–Ven, 8 h–10 h',
      status: AppointmentStatus.pending,
      patientNote: 'Première note',
      responseNote: '',
      createdAt: DateTime(2026, 7, 19),
      updatedAt: DateTime(2026, 7, 19),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PatientAppointmentEditPage(
          appointment: appointment,
          repository: repository,
          now: DateTime(2026, 7, 20, 7),
        ),
      ),
    );

    final newTime = find.byKey(const ValueKey('edit-appointment-time-8-30'));
    await tester.ensureVisible(newTime);
    await tester.tap(newTime);
    final natCash = find.byKey(const ValueKey('payment-method-natCash'));
    await tester.ensureVisible(natCash);
    await tester.tap(natCash);
    await tester.enterText(
      find.byKey(const ValueKey('edit-appointment-note')),
      'Nouvelle note',
    );
    final save = find.byKey(const ValueKey('save-appointment-changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.updatedAppointment, appointment);
    expect(repository.scheduledAt, DateTime(2026, 7, 20, 8, 30));
    expect(repository.patientNote, 'Nouvelle note');
    expect(repository.paymentMethod, AppointmentPaymentMethod.natCash);
    expect(tester.takeException(), isNull);
  });

  testWidgets('annule puis permet de supprimer un rendez-vous', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakePatientAppointmentRepository();
    final pending = Appointment(
      id: 'appointment-cancel',
      patientId: 'patient-1',
      patientName: 'Jean Baptiste',
      providerId: 'provider-1',
      providerType: 'professional',
      providerName: 'Dre Marie Jean',
      service: 'Pédiatrie',
      scheduledAt: DateTime(2026, 8, 4, 9, 30),
      scheduleLabel: 'Lun–Ven, 8 h–16 h',
      status: AppointmentStatus.pending,
      patientNote: '',
      responseNote: '',
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatientAppointmentsPage(
              patientId: 'patient-1',
              appointmentStream: Stream.value([pending]),
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('cancel-patient-appointment-appointment-cancel'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('patient-cancellation-reason')),
      'Empêchement',
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-patient-cancellation')),
    );
    await tester.pumpAndSettle();

    expect(repository.cancelledAppointment, pending);
    expect(repository.cancellationReason, 'Empêchement');

    final cancelled = Appointment(
      id: 'appointment-delete',
      patientId: pending.patientId,
      patientName: pending.patientName,
      providerId: pending.providerId,
      providerType: pending.providerType,
      providerName: pending.providerName,
      service: pending.service,
      scheduledAt: pending.scheduledAt,
      scheduleLabel: pending.scheduleLabel,
      status: AppointmentStatus.cancelled,
      patientNote: '',
      responseNote: '',
      createdAt: pending.createdAt,
      updatedAt: pending.updatedAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PatientAppointmentsPage(
              patientId: 'patient-1',
              appointmentStream: Stream.value([cancelled]),
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('delete-patient-appointment-appointment-delete'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-patient-deletion')));
    await tester.pumpAndSettle();

    expect(repository.deletedAppointment, cancelled);
    expect(tester.takeException(), isNull);
  });
}

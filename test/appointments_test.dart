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
  String? location;

  @override
  Future<void> create({
    required String patientId,
    required String patientName,
    required ProviderBookingTarget provider,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentMode mode,
    required String location,
  }) async {
    this.patientId = patientId;
    this.patientName = patientName;
    this.provider = provider;
    this.scheduledAt = scheduledAt;
    this.patientNote = patientNote;
    this.mode = mode;
    this.location = location;
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

    expect(dates.first.weekday, DateTime.monday);
    expect(slots.map((slot) => '${slot.hour}:${slot.minute}'), [
      '8:0',
      '8:30',
      '9:0',
      '9:30',
    ]);
    expect(availability.slotsForDate(DateTime(2026, 7, 25), now: now), isEmpty);
  });

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
    expect(find.textContaining('Présentez-vous 15 minutes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

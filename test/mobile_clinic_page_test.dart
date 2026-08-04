import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/appointments.dart';
import 'package:i_entier/mobile_clinic_page.dart';

void main() {
  final clinic = MobileClinic(
    id: 'clinic-1',
    ownerProviderId: 'provider-1',
    ownerAccountType: 'institution',
    name: 'Clinique Mobile Espoir',
    responsibleName: 'Dr Marie Jean',
    description: 'Soins maternels et médecine générale.',
    phone: '+509 3700 0000',
    baseAddress: 'Place communautaire de Jacmel',
    department: 'Sud-Est',
    commune: 'Jacmel',
    latitude: 18.235,
    longitude: -72.535,
    isDeployed: true,
    badge: 'Clinique Mobile Certifiée I-Entier',
  );
  final service = const MobileClinicService(
    id: 'service-1',
    name: 'Consultation générale',
    description: 'Consultation de proximité',
    durationMinutes: 30,
    priceHtg: 500,
  );
  final tour = MobileClinicTour(
    id: 'tour-1',
    clinicId: 'clinic-1',
    zoneName: 'Jacmel Centre',
    locationLabel: 'Place communautaire de Jacmel',
    department: 'Sud-Est',
    commune: 'Jacmel',
    latitude: 18.235,
    longitude: -72.535,
    startsAt: DateTime.now().add(const Duration(days: 2)),
    endsAt: DateTime.now().add(const Duration(days: 4)),
    dailySchedule: 'Tous les jours 08h-16h',
    status: 'planned',
  );

  testWidgets('affiche les cliniques certifiées, services et tournées', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeCommunityRepository(
      clinics: [clinic],
      services: [service],
      tours: [tour],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MobileClinicPage(
          patientId: 'patient-1',
          patientName: 'Jean Patient',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cliniques disponibles'), findsOneWidget);
    expect(find.text('Clinique Mobile Espoir'), findsOneWidget);
    expect(find.text('Certifiée'), findsOneWidget);
    expect(find.text('Déployée maintenant'), findsOneWidget);

    await tester.tap(find.text('Clinique Mobile Espoir'));
    await tester.pumpAndSettle();

    expect(find.text('Clinique Mobile Certifiée I-Entier'), findsOneWidget);
    expect(find.textContaining('Consultation générale'), findsOneWidget);
    expect(find.text('Jacmel Centre'), findsOneWidget);
    expect(find.text('Réserver dans une tournée'), findsOneWidget);
  });

  test('la réservation mobile délègue au workflow partagé', () async {
    final community = _FakeCommunityRepository(
      clinics: [clinic],
      services: [service],
      tours: [tour],
    );
    final repository = MobileClinicAppointmentRepository(
      mobileClinicRepository: community,
      clinic: clinic,
      tour: tour,
      service: service,
      delegate: _FakePatientAppointmentRepository(),
    );
    final scheduledAt = DateTime.now().add(const Duration(days: 3));

    await repository.create(
      patientId: 'patient-1',
      patientName: 'Jean Patient',
      provider: const ProviderBookingTarget(
        id: 'provider-1',
        type: 'institution',
        name: 'Clinique Mobile Espoir',
        service: 'Consultation générale',
        schedule: 'Tous les jours 08h-16h',
        available: true,
      ),
      scheduledAt: scheduledAt,
      patientNote: 'Fièvre',
      mode: AppointmentMode.atProvider,
      paymentMethod: AppointmentPaymentMethod.monCash,
      location: tour.locationLabel,
    );

    expect(community.bookings, hasLength(1));
    expect(community.bookings.single.$1, 'clinic-1');
    expect(community.bookings.single.$2, 'tour-1');
    expect(community.bookings.single.$3, 'service-1');
    expect(community.bookings.single.$4, scheduledAt);
  });

  test('calcule une distance communautaire plausible', () {
    final distance = approximateDistanceKm(18.5392, -72.3364, 18.235, -72.535);
    expect(distance, inInclusiveRange(35, 50));
  });
}

class _FakeCommunityRepository implements MobileClinicCommunityRepository {
  final List<MobileClinic> clinics;
  final List<MobileClinicService> services;
  final List<MobileClinicTour> tours;
  final List<(String, String, String, DateTime)> bookings = [];

  _FakeCommunityRepository({
    required this.clinics,
    required this.services,
    required this.tours,
  });

  @override
  Stream<List<MobileClinic>> watchAvailableClinics() => Stream.value(clinics);

  @override
  Stream<List<MobileClinicService>> watchServices(String clinicId) =>
      Stream.value(services);

  @override
  Stream<List<MobileClinicTour>> watchTours(String clinicId) =>
      Stream.value(tours);

  @override
  Future<void> bookAppointment({
    required MobileClinic clinic,
    required MobileClinicTour tour,
    required MobileClinicService service,
    required String patientName,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentPaymentMethod paymentMethod,
  }) async {
    bookings.add((clinic.id, tour.id, service.id, scheduledAt));
  }
}

class _FakePatientAppointmentRepository
    implements PatientAppointmentRepository {
  @override
  Stream<List<Appointment>> watchForPatient(String patientId) =>
      const Stream.empty();

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
  }) async {}

  @override
  Future<void> update({
    required Appointment appointment,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentPaymentMethod paymentMethod,
    required String location,
  }) async {}

  @override
  Future<void> cancel({
    required Appointment appointment,
    required String reason,
  }) async {}

  @override
  Future<void> deleteForPatient(Appointment appointment) async {}
}

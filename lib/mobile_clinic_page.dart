import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'appointments.dart';
import 'app_theme.dart';
import 'supabase_config.dart';

const _mobileClinicGreen = Color(0xFF087F5B);
const _mobileClinicNavy = Color(0xFF102A43);
const _mobileClinicMuted = Color(0xFF667085);
const _mobileClinicBorder = Color(0xFFE1E8ED);

class MobileClinic {
  final String id;
  final String ownerProviderId;
  final String ownerAccountType;
  final String name;
  final String responsibleName;
  final String description;
  final String phone;
  final String baseAddress;
  final String department;
  final String commune;
  final double? latitude;
  final double? longitude;
  final bool isDeployed;
  final String badge;

  const MobileClinic({
    required this.id,
    required this.ownerProviderId,
    required this.ownerAccountType,
    required this.name,
    required this.responsibleName,
    required this.description,
    required this.phone,
    required this.baseAddress,
    required this.department,
    required this.commune,
    required this.latitude,
    required this.longitude,
    required this.isDeployed,
    required this.badge,
  });

  factory MobileClinic.fromRow(Map<String, dynamic> row) => MobileClinic(
    id: _text(row, 'mobile_clinic_id'),
    ownerProviderId: _text(row, 'owner_provider_id'),
    ownerAccountType: _text(row, 'owner_account_type'),
    name: _text(row, 'name'),
    responsibleName: _text(row, 'responsible_name'),
    description: _text(row, 'description'),
    phone: _text(row, 'phone'),
    baseAddress: _text(row, 'base_address'),
    department: _text(row, 'department'),
    commune: _text(row, 'commune'),
    latitude: _number(row['latitude']),
    longitude: _number(row['longitude']),
    isDeployed: row['is_deployed'] == true,
    badge: _text(row, 'certification_badge'),
  );

  String get area =>
      [commune, department].where((value) => value.isNotEmpty).join(', ');
}

class MobileClinicService {
  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final double? priceHtg;

  const MobileClinicService({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.priceHtg,
  });

  factory MobileClinicService.fromRow(Map<String, dynamic> row) =>
      MobileClinicService(
        id: _text(row, 'mobile_clinic_service_id'),
        name: _text(row, 'name'),
        description: _text(row, 'description'),
        durationMinutes: (row['duration_minutes'] as num?)?.toInt() ?? 30,
        priceHtg: _number(row['price_htg']),
      );
}

class MobileClinicTour {
  final String id;
  final String clinicId;
  final String zoneName;
  final String locationLabel;
  final String department;
  final String commune;
  final double? latitude;
  final double? longitude;
  final DateTime startsAt;
  final DateTime endsAt;
  final String dailySchedule;
  final String status;

  const MobileClinicTour({
    required this.id,
    required this.clinicId,
    required this.zoneName,
    required this.locationLabel,
    required this.department,
    required this.commune,
    required this.latitude,
    required this.longitude,
    required this.startsAt,
    required this.endsAt,
    required this.dailySchedule,
    required this.status,
  });

  factory MobileClinicTour.fromRow(Map<String, dynamic> row) =>
      MobileClinicTour(
        id: _text(row, 'mobile_clinic_tour_id'),
        clinicId: _text(row, 'mobile_clinic_id'),
        zoneName: _text(row, 'zone_name'),
        locationLabel: _text(row, 'location_label'),
        department: _text(row, 'department'),
        commune: _text(row, 'commune'),
        latitude: _number(row['latitude']),
        longitude: _number(row['longitude']),
        startsAt: _date(row['starts_at']),
        endsAt: _date(row['ends_at']),
        dailySchedule: _text(row, 'daily_schedule'),
        status: _text(row, 'status'),
      );

  bool get acceptsBookings =>
      (status == 'planned' || status == 'active') &&
      endsAt.isAfter(DateTime.now());
}

abstract class MobileClinicCommunityRepository {
  Stream<List<MobileClinic>> watchAvailableClinics();

  Stream<List<MobileClinicService>> watchServices(String clinicId);

  Stream<List<MobileClinicTour>> watchTours(String clinicId);

  Future<void> bookAppointment({
    required MobileClinic clinic,
    required MobileClinicTour tour,
    required MobileClinicService service,
    required String patientName,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentPaymentMethod paymentMethod,
  });
}

class SupabaseMobileClinicCommunityRepository
    implements MobileClinicCommunityRepository {
  final SupabaseClient client;

  SupabaseMobileClinicCommunityRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Stream<List<MobileClinic>> watchAvailableClinics() => client
      .schema('ientier')
      .from('mobile_clinics')
      .stream(primaryKey: ['mobile_clinic_id'])
      .eq('verification_status', 'approved')
      .order('updated_at', ascending: false)
      .map(
        (rows) => rows
            .where((row) => row['is_published'] == true)
            .map(MobileClinic.fromRow)
            .toList(growable: false),
      );

  @override
  Stream<List<MobileClinicService>> watchServices(String clinicId) => client
      .schema('ientier')
      .from('mobile_clinic_services')
      .stream(primaryKey: ['mobile_clinic_service_id'])
      .eq('mobile_clinic_id', clinicId)
      .order('name')
      .map(
        (rows) => rows
            .where((row) => row['active'] == true)
            .map(MobileClinicService.fromRow)
            .toList(growable: false),
      );

  @override
  Stream<List<MobileClinicTour>> watchTours(String clinicId) => client
      .schema('ientier')
      .from('mobile_clinic_tours')
      .stream(primaryKey: ['mobile_clinic_tour_id'])
      .eq('mobile_clinic_id', clinicId)
      .order('starts_at')
      .map(
        (rows) => rows
            .map(MobileClinicTour.fromRow)
            .where((tour) => tour.acceptsBookings)
            .toList(growable: false),
      );

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
    await client
        .schema('ientier')
        .rpc(
          'book_mobile_clinic_appointment',
          params: {
            'p_mobile_clinic_id': clinic.id,
            'p_tour_id': tour.id,
            'p_service_id': service.id,
            'p_patient_name': patientName.trim(),
            'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'p_patient_note': patientNote.trim(),
            'p_payment_method': paymentMethod.storageValue,
          },
        );
  }
}

class MobileClinicAppointmentRepository
    implements PatientAppointmentRepository {
  final MobileClinicCommunityRepository mobileClinicRepository;
  final MobileClinic clinic;
  final MobileClinicTour tour;
  final MobileClinicService service;
  final PatientAppointmentRepository _delegate;

  MobileClinicAppointmentRepository({
    required this.mobileClinicRepository,
    required this.clinic,
    required this.tour,
    required this.service,
    PatientAppointmentRepository? delegate,
  }) : _delegate = delegate ?? SupabasePatientAppointmentRepository();

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
  }) => mobileClinicRepository.bookAppointment(
    clinic: clinic,
    tour: tour,
    service: service,
    patientName: patientName,
    scheduledAt: scheduledAt,
    patientNote: patientNote,
    paymentMethod: paymentMethod,
  );

  @override
  Stream<List<Appointment>> watchForPatient(String patientId) =>
      _delegate.watchForPatient(patientId);

  @override
  Future<void> update({
    required Appointment appointment,
    required DateTime scheduledAt,
    required String patientNote,
    required AppointmentPaymentMethod paymentMethod,
    required String location,
  }) => _delegate.update(
    appointment: appointment,
    scheduledAt: scheduledAt,
    patientNote: patientNote,
    paymentMethod: paymentMethod,
    location: location,
  );

  @override
  Future<void> cancel({
    required Appointment appointment,
    required String reason,
  }) => _delegate.cancel(appointment: appointment, reason: reason);

  @override
  Future<void> deleteForPatient(Appointment appointment) =>
      _delegate.deleteForPatient(appointment);
}

class MobileClinicPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final MobileClinicCommunityRepository? repository;

  const MobileClinicPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.repository,
  });

  @override
  State<MobileClinicPage> createState() => _MobileClinicPageState();
}

class _MobileClinicPageState extends State<MobileClinicPage> {
  late final MobileClinicCommunityRepository _repository =
      widget.repository ?? SupabaseMobileClinicCommunityRepository();
  Position? _position;
  bool _locating = false;
  String? _locationMessage;

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Activez la localisation de votre appareil.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Autorisez la localisation pour classer les cliniques par distance.',
        );
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _position = position);
    } catch (error) {
      if (mounted) {
        setState(
          () => _locationMessage = error is StateError
              ? error.message
              : 'Votre position n’a pas pu être obtenue.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  List<MobileClinic> _sortClinics(List<MobileClinic> source) {
    final position = _position;
    if (position == null) return source;
    final result = List<MobileClinic>.of(source);
    result.sort(
      (a, b) => _distanceTo(a, position).compareTo(_distanceTo(b, position)),
    );
    return result;
  }

  double _distanceTo(MobileClinic clinic, Position position) {
    if (clinic.latitude == null || clinic.longitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          clinic.latitude!,
          clinic.longitude!,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(title: const Text('Clinique Mobile')),
    body: SafeArea(
      child: StreamBuilder<List<MobileClinic>>(
        stream: _repository.watchAvailableClinics(),
        builder: (context, snapshot) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MobileClinicHero(onLocate: _locate, locating: _locating),
                  if (_locationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _locationMessage!,
                      style: const TextStyle(color: _mobileClinicMuted),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Cliniques disponibles',
                          style: TextStyle(
                            color: _mobileClinicNavy,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (_position != null)
                        const _SmallPill(
                          icon: Icons.near_me_rounded,
                          label: 'Par distance',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (snapshot.hasError)
                    const _ClinicMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Réseau momentanément indisponible',
                      message: 'Réessayez dans quelques instants.',
                    )
                  else if (!snapshot.hasData)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(
                          color: _mobileClinicGreen,
                        ),
                      ),
                    )
                  else if (snapshot.data!.isEmpty)
                    const _ClinicMessage(
                      icon: Icons.local_shipping_outlined,
                      title: 'Aucune clinique publiée',
                      message:
                          'Les nouvelles cliniques certifiées apparaîtront ici dès leur déploiement.',
                    )
                  else
                    for (final clinic in _sortClinics(snapshot.data!)) ...[
                      _MobileClinicCard(
                        clinic: clinic,
                        distanceKm: _position == null
                            ? null
                            : _distanceTo(clinic, _position!),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _MobileClinicDetailPage(
                              clinic: clinic,
                              patientId: widget.patientId,
                              patientName: widget.patientName,
                              repository: _repository,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MobileClinicHero extends StatelessWidget {
  final VoidCallback onLocate;
  final bool locating;

  const _MobileClinicHero({required this.onLocate, required this.locating});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF075E4C), Color(0xFF0B9270)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Wrap(
      spacing: 24,
      runSpacing: 20,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 570),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Les soins viennent jusqu’à votre communauté',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'Repérez les tournées certifiées, consultez les services et réservez votre passage.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .86),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 17),
              FilledButton.icon(
                onPressed: locating ? null : onLocate,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF075E4C),
                ),
                icon: locating
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
                label: Text(locating ? 'Localisation…' : 'Autour de moi'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MobileClinicCard extends StatelessWidget {
  final MobileClinic clinic;
  final double? distanceKm;
  final VoidCallback onTap;

  const _MobileClinicCard({
    required this.clinic,
    required this.distanceKm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(21),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: _mobileClinicBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F6F0),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
                color: _mobileClinicGreen,
                size: 29,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        clinic.name,
                        style: const TextStyle(
                          color: _mobileClinicNavy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const _CertifiedBadge(),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    clinic.area,
                    style: const TextStyle(color: _mobileClinicMuted),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 7,
                    children: [
                      _SmallPill(
                        icon: clinic.isDeployed
                            ? Icons.sensors_rounded
                            : Icons.event_available_outlined,
                        label: clinic.isDeployed
                            ? 'Déployée maintenant'
                            : 'Tournées planifiées',
                      ),
                      if (distanceKm != null && distanceKm!.isFinite)
                        _SmallPill(
                          icon: Icons.near_me_outlined,
                          label: '${distanceKm!.toStringAsFixed(1)} km',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _mobileClinicMuted),
          ],
        ),
      ),
    ),
  );
}

class _MobileClinicDetailPage extends StatelessWidget {
  final MobileClinic clinic;
  final String patientId;
  final String patientName;
  final MobileClinicCommunityRepository repository;

  const _MobileClinicDetailPage({
    required this.clinic,
    required this.patientId,
    required this.patientName,
    required this.repository,
  });

  Future<void> _openDirections(MobileClinicTour tour) async {
    final query = tour.latitude != null && tour.longitude != null
        ? '${tour.latitude},${tour.longitude}'
        : Uri.encodeComponent(tour.locationLabel);
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _book(
    BuildContext context,
    List<MobileClinicService> services,
    List<MobileClinicTour> tours,
  ) async {
    final selection =
        await showModalBottomSheet<(MobileClinicService, MobileClinicTour)>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) =>
              _ClinicBookingSelection(services: services, tours: tours),
        );
    if (selection == null || !context.mounted) return;
    final (service, tour) = selection;
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AppointmentBookingPage(
          patientId: patientId,
          patientName: patientName,
          provider: ProviderBookingTarget(
            id: clinic.ownerProviderId,
            type: clinic.ownerAccountType,
            name: clinic.name,
            service: service.name,
            schedule: tour.dailySchedule,
            address: tour.locationLabel,
            available: true,
            enabledModes: const {AppointmentMode.atProvider},
            hasModeConfiguration: true,
            defaultPrice: service.priceHtg == null
                ? ''
                : service.priceHtg!.toStringAsFixed(0),
            availabilityPeriods: {
              AppointmentMode.atProvider: DateTimeRange(
                start: tour.startsAt,
                end: tour.endsAt,
              ),
            },
          ),
          repository: MobileClinicAppointmentRepository(
            mobileClinicRepository: repository,
            clinic: clinic,
            tour: tour,
            service: service,
          ),
        ),
      ),
    );
    if (booked == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande envoyée. Elle est maintenant visible dans Rendez-vous.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(title: Text(clinic.name)),
    body: SafeArea(
      child: StreamBuilder<List<MobileClinicService>>(
        stream: repository.watchServices(clinic.id),
        builder: (context, serviceSnapshot) => StreamBuilder<List<MobileClinicTour>>(
          stream: repository.watchTours(clinic.id),
          builder: (context, tourSnapshot) {
            final services = serviceSnapshot.data ?? const [];
            final tours = tourSnapshot.data ?? const [];
            final loading = !serviceSnapshot.hasData || !tourSnapshot.hasData;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ClinicProfilePanel(clinic: clinic),
                      const SizedBox(height: 22),
                      const _DetailHeading(
                        title: 'Services disponibles',
                        icon: Icons.medical_services_outlined,
                      ),
                      const SizedBox(height: 11),
                      if (loading)
                        const LinearProgressIndicator(color: _mobileClinicGreen)
                      else if (services.isEmpty)
                        const _ClinicMessage(
                          icon: Icons.medical_services_outlined,
                          title: 'Services en préparation',
                          message:
                              'Cette clinique publiera bientôt sa liste de soins.',
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final service in services)
                              _ServiceChip(service: service),
                          ],
                        ),
                      const SizedBox(height: 24),
                      const _DetailHeading(
                        title: 'Prochaines tournées',
                        icon: Icons.route_outlined,
                      ),
                      const SizedBox(height: 11),
                      if (!loading && tours.isEmpty)
                        const _ClinicMessage(
                          icon: Icons.event_busy_outlined,
                          title: 'Aucune tournée ouverte',
                          message:
                              'Revenez bientôt pour consulter le prochain passage.',
                        )
                      else
                        for (final tour in tours) ...[
                          _TourCard(
                            tour: tour,
                            onDirections: () => _openDirections(tour),
                          ),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: services.isEmpty || tours.isEmpty
                              ? null
                              : () => _book(context, services, tours),
                          icon: const Icon(Icons.edit_calendar_rounded),
                          label: const Text('Réserver dans une tournée'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _mobileClinicGreen,
                            minimumSize: const Size(0, 54),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _ClinicProfilePanel extends StatelessWidget {
  final MobileClinic clinic;

  const _ClinicProfilePanel({required this.clinic});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _mobileClinicBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CertifiedBadge(large: true),
        const SizedBox(height: 14),
        Text(
          clinic.name,
          style: const TextStyle(
            color: _mobileClinicNavy,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          clinic.description.isEmpty
              ? 'Soins de proximité au service des communautés.'
              : clinic.description,
          style: const TextStyle(color: _mobileClinicMuted, height: 1.5),
        ),
        const SizedBox(height: 15),
        _InfoLine(icon: Icons.place_outlined, text: clinic.baseAddress),
        _InfoLine(
          icon: Icons.person_outline_rounded,
          text: 'Responsable : ${clinic.responsibleName}',
        ),
        if (clinic.phone.isNotEmpty)
          _InfoLine(icon: Icons.phone_outlined, text: clinic.phone),
      ],
    ),
  );
}

class _TourCard extends StatelessWidget {
  final MobileClinicTour tour;
  final VoidCallback onDirections;

  const _TourCard({required this.tour, required this.onDirections});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _mobileClinicBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.route_rounded, color: _mobileClinicGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tour.zoneName,
                style: const TextStyle(
                  color: _mobileClinicNavy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_dateLabel(tour.startsAt)} – ${_dateLabel(tour.endsAt)} · ${tour.dailySchedule}',
                style: const TextStyle(color: _mobileClinicMuted, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(tour.locationLabel),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Itinéraire',
          onPressed: onDirections,
          icon: const Icon(Icons.directions_outlined),
        ),
      ],
    ),
  );
}

class _ClinicBookingSelection extends StatefulWidget {
  final List<MobileClinicService> services;
  final List<MobileClinicTour> tours;

  const _ClinicBookingSelection({required this.services, required this.tours});

  @override
  State<_ClinicBookingSelection> createState() =>
      _ClinicBookingSelectionState();
}

class _ClinicBookingSelectionState extends State<_ClinicBookingSelection> {
  MobileClinicService? _service;
  MobileClinicTour? _tour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      22 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Préparer la réservation',
          style: TextStyle(
            color: _mobileClinicNavy,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<MobileClinicService>(
          initialValue: _service,
          decoration: const InputDecoration(
            labelText: 'Service recherché',
            prefixIcon: Icon(Icons.medical_services_outlined),
          ),
          items: [
            for (final service in widget.services)
              DropdownMenuItem(value: service, child: Text(service.name)),
          ],
          onChanged: (value) => setState(() => _service = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<MobileClinicTour>(
          initialValue: _tour,
          decoration: const InputDecoration(
            labelText: 'Tournée',
            prefixIcon: Icon(Icons.route_outlined),
          ),
          items: [
            for (final tour in widget.tours)
              DropdownMenuItem(
                value: tour,
                child: Text('${tour.zoneName} · ${_dateLabel(tour.startsAt)}'),
              ),
          ],
          onChanged: (value) => setState(() => _tour = value),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _service == null || _tour == null
              ? null
              : () => Navigator.pop(context, (_service!, _tour!)),
          style: FilledButton.styleFrom(backgroundColor: _mobileClinicGreen),
          child: const Text('Choisir mon créneau'),
        ),
      ],
    ),
  );
}

class _ServiceChip extends StatelessWidget {
  final MobileClinicService service;

  const _ServiceChip({required this.service});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFE6F6F0),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Text(
      service.priceHtg == null
          ? service.name
          : '${service.name} · ${service.priceHtg!.toStringAsFixed(0)} HTG',
      style: const TextStyle(
        color: Color(0xFF075E4C),
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DetailHeading extends StatelessWidget {
  final String title;
  final IconData icon;

  const _DetailHeading({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _mobileClinicGreen),
      const SizedBox(width: 9),
      Text(
        title,
        style: const TextStyle(
          color: _mobileClinicNavy,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _CertifiedBadge extends StatelessWidget {
  final bool large;

  const _CertifiedBadge({this.large = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: large ? 11 : 8,
      vertical: large ? 7 : 4,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFFE6F6F0),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.verified_rounded,
          color: _mobileClinicGreen,
          size: large ? 18 : 14,
        ),
        const SizedBox(width: 5),
        Text(
          large ? 'Clinique Mobile Certifiée I-Entier' : 'Certifiée',
          style: TextStyle(
            color: const Color(0xFF075E4C),
            fontSize: large ? 12 : 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _SmallPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F5F7),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _mobileClinicMuted),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: _mobileClinicMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ClinicMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ClinicMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: _mobileClinicBorder),
    ),
    child: Column(
      children: [
        Icon(icon, color: _mobileClinicGreen, size: 35),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _mobileClinicMuted),
        ),
      ],
    ),
  );
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: _mobileClinicGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

String _text(Map<String, dynamic> row, String key) =>
    row[key]?.toString().trim() ?? '';

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

DateTime _date(Object? value) {
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

String _dateLabel(DateTime date) {
  const months = [
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
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

// Gardé ici pour les plateformes où Geolocator ne fournit pas encore un calcul
// natif lors des tests web.
double approximateDistanceKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const radius = 6371.0;
  final dLatitude = (latitudeB - latitudeA) * math.pi / 180;
  final dLongitude = (longitudeB - longitudeA) * math.pi / 180;
  final a =
      math.sin(dLatitude / 2) * math.sin(dLatitude / 2) +
      math.cos(latitudeA * math.pi / 180) *
          math.cos(latitudeB * math.pi / 180) *
          math.sin(dLongitude / 2) *
          math.sin(dLongitude / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

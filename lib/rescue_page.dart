import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'supabase_config.dart';

const _rescueRed = Color(0xFFD92D20);
const _rescueRedDark = Color(0xFF9D2018);
const _rescueRedSoft = Color(0xFFFFEAE8);
const _rescueOrange = Color(0xFFF79009);
const _rescueGreen = Color(0xFF087A5B);

enum RescueVolunteerProfession {
  generalPractitioner,
  specialistDoctor,
  nurse,
  midwife,
  paramedic,
  firstResponder,
  pharmacist,
  psychologist,
  healthStudent,
  other,
}

extension RescueVolunteerProfessionDetails on RescueVolunteerProfession {
  String get databaseValue => switch (this) {
    RescueVolunteerProfession.generalPractitioner => 'general_practitioner',
    RescueVolunteerProfession.specialistDoctor => 'specialist_doctor',
    RescueVolunteerProfession.nurse => 'nurse',
    RescueVolunteerProfession.midwife => 'midwife',
    RescueVolunteerProfession.paramedic => 'paramedic',
    RescueVolunteerProfession.firstResponder => 'first_responder',
    RescueVolunteerProfession.pharmacist => 'pharmacist',
    RescueVolunteerProfession.psychologist => 'psychologist',
    RescueVolunteerProfession.healthStudent => 'health_student',
    RescueVolunteerProfession.other => 'other',
  };

  String get label => switch (this) {
    RescueVolunteerProfession.generalPractitioner => 'Médecin généraliste',
    RescueVolunteerProfession.specialistDoctor => 'Médecin spécialiste',
    RescueVolunteerProfession.nurse => 'Infirmière',
    RescueVolunteerProfession.midwife => 'Sage-femme',
    RescueVolunteerProfession.paramedic => 'Ambulancier',
    RescueVolunteerProfession.firstResponder => 'Secouriste',
    RescueVolunteerProfession.pharmacist => 'Pharmacien',
    RescueVolunteerProfession.psychologist => 'Psychologue',
    RescueVolunteerProfession.healthStudent => 'Étudiant en santé',
    RescueVolunteerProfession.other => 'Autre professionnel volontaire',
  };

  IconData get icon => switch (this) {
    RescueVolunteerProfession.generalPractitioner ||
    RescueVolunteerProfession.specialistDoctor =>
      Icons.medical_services_rounded,
    RescueVolunteerProfession.nurse => Icons.medical_services_outlined,
    RescueVolunteerProfession.midwife => Icons.pregnant_woman_rounded,
    RescueVolunteerProfession.paramedic => Icons.emergency_rounded,
    RescueVolunteerProfession.firstResponder =>
      Icons.health_and_safety_outlined,
    RescueVolunteerProfession.pharmacist => Icons.medication_outlined,
    RescueVolunteerProfession.psychologist => Icons.psychology_outlined,
    RescueVolunteerProfession.healthStudent => Icons.school_outlined,
    RescueVolunteerProfession.other => Icons.volunteer_activism_outlined,
  };

  static RescueVolunteerProfession fromDatabase(String value) =>
      RescueVolunteerProfession.values.firstWhere(
        (item) => item.databaseValue == value,
        orElse: () => RescueVolunteerProfession.other,
      );
}

enum RescueVerificationStatus { pending, verified, suspended }

extension RescueVerificationStatusDetails on RescueVerificationStatus {
  String get databaseValue => switch (this) {
    RescueVerificationStatus.pending => 'pending',
    RescueVerificationStatus.verified => 'verified',
    RescueVerificationStatus.suspended => 'suspended',
  };

  String get label => switch (this) {
    RescueVerificationStatus.pending => 'En attente',
    RescueVerificationStatus.verified => 'Vérifié',
    RescueVerificationStatus.suspended => 'Suspendu',
  };

  Color get color => switch (this) {
    RescueVerificationStatus.pending => _rescueOrange,
    RescueVerificationStatus.verified => _rescueGreen,
    RescueVerificationStatus.suspended => _rescueRed,
  };

  static RescueVerificationStatus fromDatabase(String value) => switch (value) {
    'verified' => RescueVerificationStatus.verified,
    'suspended' => RescueVerificationStatus.suspended,
    _ => RescueVerificationStatus.pending,
  };
}

enum RescueAvailability { available, busy, offline }

extension RescueAvailabilityDetails on RescueAvailability {
  String get databaseValue => switch (this) {
    RescueAvailability.available => 'available',
    RescueAvailability.busy => 'busy',
    RescueAvailability.offline => 'offline',
  };

  String get label => switch (this) {
    RescueAvailability.available => 'Disponible',
    RescueAvailability.busy => 'Occupé',
    RescueAvailability.offline => 'Hors ligne',
  };

  Color get color => switch (this) {
    RescueAvailability.available => _rescueGreen,
    RescueAvailability.busy => _rescueOrange,
    RescueAvailability.offline => AppColors.muted,
  };

  static RescueAvailability fromDatabase(String value) => switch (value) {
    'available' => RescueAvailability.available,
    'busy' => RescueAvailability.busy,
    _ => RescueAvailability.offline,
  };
}

enum RescueMissionStatus {
  sent,
  accepted,
  enRoute,
  onSite,
  completed,
  declined,
}

extension RescueMissionStatusDetails on RescueMissionStatus {
  String get databaseValue => switch (this) {
    RescueMissionStatus.sent => 'sent',
    RescueMissionStatus.accepted => 'accepted',
    RescueMissionStatus.enRoute => 'en_route',
    RescueMissionStatus.onSite => 'on_site',
    RescueMissionStatus.completed => 'completed',
    RescueMissionStatus.declined => 'declined',
  };

  String get label => switch (this) {
    RescueMissionStatus.sent => 'Envoyé',
    RescueMissionStatus.accepted => 'Accepté',
    RescueMissionStatus.enRoute => 'En route',
    RescueMissionStatus.onSite => 'Sur place',
    RescueMissionStatus.completed => 'Mission terminée',
    RescueMissionStatus.declined => 'Refusé',
  };

  static RescueMissionStatus fromDatabase(String value) => switch (value) {
    'accepted' => RescueMissionStatus.accepted,
    'en_route' => RescueMissionStatus.enRoute,
    'on_site' => RescueMissionStatus.onSite,
    'completed' => RescueMissionStatus.completed,
    'declined' => RescueMissionStatus.declined,
    _ => RescueMissionStatus.sent,
  };
}

class RescueVolunteerProfile {
  final String id;
  final String fullName;
  final String phone;
  final RescueVolunteerProfession profession;
  final String specialty;
  final String organization;
  final List<String> skills;
  final RescueVerificationStatus verificationStatus;
  final RescueAvailability availability;
  final int interventionRadiusKm;
  final bool locationConsent;
  final double? latitude;
  final double? longitude;

  const RescueVolunteerProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.profession,
    required this.specialty,
    required this.organization,
    required this.skills,
    required this.verificationStatus,
    required this.availability,
    required this.interventionRadiusKm,
    required this.locationConsent,
    this.latitude,
    this.longitude,
  });

  factory RescueVolunteerProfile.fromRow(Map<String, dynamic> row) =>
      RescueVolunteerProfile(
        id: row['volunteer_id'].toString(),
        fullName: row['full_name']?.toString() ?? '',
        phone: row['phone']?.toString() ?? '',
        profession: RescueVolunteerProfessionDetails.fromDatabase(
          row['profession']?.toString() ?? '',
        ),
        specialty: row['specialty']?.toString() ?? '',
        organization: row['organization']?.toString() ?? '',
        skills: List<String>.from(row['skills'] as List? ?? const []),
        verificationStatus: RescueVerificationStatusDetails.fromDatabase(
          row['verification_status']?.toString() ?? '',
        ),
        availability: RescueAvailabilityDetails.fromDatabase(
          row['availability']?.toString() ?? '',
        ),
        interventionRadiusKm:
            (row['intervention_radius_km'] as num?)?.toInt() ?? 25,
        locationConsent: row['location_consent'] == true,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
      );
}

class RescueMission {
  final String assignmentId;
  final String title;
  final String eventType;
  final String severity;
  final String zone;
  final String instructions;
  final RescueMissionStatus status;
  final DateTime createdAt;

  const RescueMission({
    required this.assignmentId,
    required this.title,
    required this.eventType,
    required this.severity,
    required this.zone,
    required this.instructions,
    required this.status,
    required this.createdAt,
  });

  factory RescueMission.fromRow(Map<String, dynamic> row) {
    final alert = row['rescue_alerts'] as Map<String, dynamic>? ?? const {};
    final event = alert['rescue_events'] as Map<String, dynamic>? ?? const {};
    return RescueMission(
      assignmentId: row['assignment_id'].toString(),
      title: alert['title']?.toString() ?? 'Mission Rescue',
      eventType: event['event_type']?.toString() ?? 'urgence',
      severity: event['severity']?.toString() ?? 'medium',
      zone: event['zone_name']?.toString() ?? '',
      instructions: alert['instructions']?.toString() ?? '',
      status: RescueMissionStatusDetails.fromDatabase(
        row['status']?.toString() ?? '',
      ),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RescueVolunteerApplication {
  final String userId;
  final String fullName;
  final String phone;
  final RescueVolunteerProfession profession;
  final String specialty;
  final String organization;
  final List<String> skills;
  final int interventionRadiusKm;
  final Uint8List identityDocument;
  final String identityDocumentName;
  final Uint8List? professionalLicense;
  final String professionalLicenseName;

  const RescueVolunteerApplication({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.profession,
    required this.specialty,
    required this.organization,
    required this.skills,
    required this.interventionRadiusKm,
    required this.identityDocument,
    required this.identityDocumentName,
    required this.professionalLicense,
    required this.professionalLicenseName,
  });
}

class RescueMapPoint {
  final String id;
  final String type;
  final String label;
  final double latitude;
  final double longitude;
  final String detail;

  const RescueMapPoint({
    required this.id,
    required this.type,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.detail,
  });

  factory RescueMapPoint.fromRow(Map<String, dynamic> row) => RescueMapPoint(
    id: row['point_id']?.toString() ?? '',
    type: row['point_type']?.toString() ?? 'other',
    label: row['label']?.toString() ?? '',
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    detail: row['detail']?.toString() ?? '',
  );
}

abstract class RescueRepository {
  Stream<RescueVolunteerProfile?> watchProfile(String userId);

  Stream<List<RescueMission>> watchMissions(String userId);

  Future<void> submitApplication(RescueVolunteerApplication application);

  Future<void> setAvailability(String volunteerId, RescueAvailability status);

  Future<void> setLocationConsent(String volunteerId, bool consent);

  Future<void> updateLocation(String volunteerId, Position position);

  Future<void> updateMissionStatus(
    String assignmentId,
    RescueMissionStatus status,
  );

  Future<List<RescueMapPoint>> loadMapPoints({
    RescueVolunteerProfession? profession,
    String specialty = '',
  });
}

class SupabaseRescueRepository implements RescueRepository {
  final SupabaseClient client;

  SupabaseRescueRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Stream<RescueVolunteerProfile?> watchProfile(String userId) => client
      .schema('ientier')
      .from('rescue_volunteers')
      .stream(primaryKey: ['volunteer_id'])
      .eq('user_id', userId)
      .map(
        (rows) =>
            rows.isEmpty ? null : RescueVolunteerProfile.fromRow(rows.first),
      );

  @override
  Stream<List<RescueMission>> watchMissions(String userId) => client
      .schema('ientier')
      .from('rescue_assignments')
      .stream(primaryKey: ['assignment_id'])
      .eq('volunteer_user_id', userId)
      .order('created_at', ascending: false)
      .asyncMap((rows) async {
        if (rows.isEmpty) return <RescueMission>[];
        final ids = rows.map((row) => row['assignment_id'].toString()).toList();
        final hydrated = await client
            .schema('ientier')
            .from('rescue_assignments')
            .select(
              '*, rescue_alerts(title, instructions, rescue_events(event_type, severity, zone_name))',
            )
            .inFilter('assignment_id', ids)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(
          hydrated,
        ).map(RescueMission.fromRow).toList(growable: false);
      });

  @override
  Future<void> submitApplication(RescueVolunteerApplication application) async {
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final identityPath =
        '${application.userId}/identity-$stamp-${_safeName(application.identityDocumentName)}';
    await client.storage
        .from('rescue-documents')
        .uploadBinary(identityPath, application.identityDocument);

    String? licensePath;
    if (application.professionalLicense != null) {
      licensePath =
          '${application.userId}/license-$stamp-${_safeName(application.professionalLicenseName)}';
      await client.storage
          .from('rescue-documents')
          .uploadBinary(licensePath, application.professionalLicense!);
    }

    final volunteer = await client
        .schema('ientier')
        .from('rescue_volunteers')
        .upsert({
          'user_id': application.userId,
          'full_name': application.fullName.trim(),
          'phone': application.phone.trim(),
          'profession': application.profession.databaseValue,
          'specialty': application.specialty.trim(),
          'organization': application.organization.trim(),
          'skills': application.skills,
          'intervention_radius_km': application.interventionRadiusKm,
          'verification_status': 'pending',
          'availability': 'offline',
        }, onConflict: 'user_id')
        .select('volunteer_id')
        .single();
    final volunteerId = volunteer['volunteer_id'].toString();
    await client.schema('ientier').from('rescue_volunteer_documents').insert([
      {
        'volunteer_id': volunteerId,
        'document_type': 'identity',
        'storage_path': identityPath,
        'file_name': application.identityDocumentName,
      },
      if (licensePath != null)
        {
          'volunteer_id': volunteerId,
          'document_type': 'professional_license',
          'storage_path': licensePath,
          'file_name': application.professionalLicenseName,
        },
    ]);
  }

  String _safeName(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-')
      .replaceAll(RegExp('-+'), '-');

  @override
  Future<void> setAvailability(String volunteerId, RescueAvailability status) =>
      client
          .schema('ientier')
          .from('rescue_volunteers')
          .update({'availability': status.databaseValue})
          .eq('volunteer_id', volunteerId);

  @override
  Future<void> setLocationConsent(String volunteerId, bool consent) => client
      .schema('ientier')
      .from('rescue_volunteers')
      .update({
        'location_consent': consent,
        if (!consent) 'latitude': null,
        if (!consent) 'longitude': null,
        if (!consent) 'last_location_at': null,
      })
      .eq('volunteer_id', volunteerId);

  @override
  Future<void> updateLocation(String volunteerId, Position position) => client
      .schema('ientier')
      .from('rescue_volunteers')
      .update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'last_location_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('volunteer_id', volunteerId);

  @override
  Future<void> updateMissionStatus(
    String assignmentId,
    RescueMissionStatus status,
  ) => client
      .schema('ientier')
      .rpc(
        'rescue_update_assignment_status',
        params: {
          'p_assignment_id': assignmentId,
          'p_new_status': status.databaseValue,
        },
      );

  @override
  Future<List<RescueMapPoint>> loadMapPoints({
    RescueVolunteerProfession? profession,
    String specialty = '',
  }) async {
    final rows = await client
        .schema('ientier')
        .rpc(
          'rescue_operational_map_points',
          params: {
            'p_profession': profession?.databaseValue,
            'p_specialty': specialty.trim().isEmpty ? null : specialty.trim(),
          },
        );
    return List<Map<String, dynamic>>.from(
      rows as List,
    ).map(RescueMapPoint.fromRow).toList(growable: false);
  }
}

class RescuePage extends StatefulWidget {
  final String userId;
  final String userDisplayName;
  final RescueRepository? repository;

  const RescuePage({
    super.key,
    required this.userId,
    required this.userDisplayName,
    this.repository,
  });

  @override
  State<RescuePage> createState() => _RescuePageState();
}

class _RescuePageState extends State<RescuePage> {
  late final RescueRepository _repository =
      widget.repository ?? SupabaseRescueRepository();
  late final Stream<RescueVolunteerProfile?> _profile = _repository
      .watchProfile(widget.userId);
  late final Stream<List<RescueMission>> _missions = _repository.watchMissions(
    widget.userId,
  );
  int _index = 0;

  @override
  Widget build(BuildContext context) => StreamBuilder<RescueVolunteerProfile?>(
    stream: _profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _rescueRed)),
        );
      }
      final profile = snapshot.data;
      final pages = <Widget>[
        _RescueOverview(
          profile: profile,
          onRegister: () => setState(() => _index = 3),
          onMissions: () => setState(() => _index = 1),
        ),
        _RescueMissions(
          profile: profile,
          missions: _missions,
          repository: _repository,
        ),
        _RescueOperationalMap(profile: profile, repository: _repository),
        _RescueProfile(
          userId: widget.userId,
          displayName: widget.userDisplayName,
          profile: profile,
          repository: _repository,
        ),
      ];
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          titleSpacing: 12,
          title: const Row(
            children: [
              _RescueMark(size: 38),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('I-Entier Rescue', style: TextStyle(fontSize: 18)),
                    Text(
                      'Réseau National de Volontaires',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          indicatorColor: _rescueRedSoft,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded, color: _rescueRed),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.campaign_outlined),
              selectedIcon: Icon(Icons.campaign_rounded, color: _rescueRed),
              label: 'Missions',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded, color: _rescueRed),
              label: 'Carte',
            ),
            NavigationDestination(
              icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge_rounded, color: _rescueRed),
              label: 'Profil',
            ),
          ],
        ),
      );
    },
  );
}

class _RescueOverview extends StatelessWidget {
  final RescueVolunteerProfile? profile;
  final VoidCallback onRegister;
  final VoidCallback onMissions;

  const _RescueOverview({
    required this.profile,
    required this.onRegister,
    required this.onMissions,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('rescue-overview'),
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_rescueRedDark, _rescueRed],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33D92D20),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _RescueMark(size: 50, inverted: true),
                Spacer(),
                _LivePill(),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              profile == null
                  ? 'Des compétences mobilisées au bon endroit.'
                  : 'Bonjour ${profile!.fullName.split(' ').first}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              profile == null
                  ? 'Rejoignez le réseau national qui coordonne les secours pendant les catastrophes, urgences sanitaires et crises humanitaires.'
                  : profile!.verificationStatus ==
                        RescueVerificationStatus.verified
                  ? 'Votre profil est vérifié. Activez votre disponibilité pour recevoir des missions adaptées.'
                  : 'Votre dossier est en cours d’examen par l’équipe I-Entier Rescue.',
              style: const TextStyle(color: Color(0xFFFFEDEC), height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('rescue-primary-action'),
              onPressed: profile == null ? onRegister : onMissions,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _rescueRedDark,
              ),
              icon: Icon(
                profile == null
                    ? Icons.volunteer_activism_rounded
                    : Icons.campaign_rounded,
              ),
              label: Text(
                profile == null ? 'Devenir volontaire' : 'Voir mes missions',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      if (profile != null)
        _VolunteerStatusCard(profile: profile!)
      else
        const _RescueValues(),
      const SizedBox(height: 22),
      Text(
        'Coordination opérationnelle',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      const _CapabilityGrid(),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFDDA8)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'En danger immédiat, appelez d’abord les services d’urgence. Rescue coordonne des volontaires vérifiés et ne remplace pas les secours publics.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RescueValues extends StatelessWidget {
  const _RescueValues();

  @override
  Widget build(BuildContext context) => Row(
    children: const [
      Expanded(
        child: _MiniMetric(value: '10', label: 'profils métiers'),
      ),
      SizedBox(width: 10),
      Expanded(
        child: _MiniMetric(value: '24/7', label: 'centre d’alertes'),
      ),
      SizedBox(width: 10),
      Expanded(
        child: _MiniMetric(value: 'GPS', label: 'avec consentement'),
      ),
    ],
  );
}

class _MiniMetric extends StatelessWidget {
  final String value;
  final String label;

  const _MiniMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _rescueRed,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.warning_amber_rounded, 'Alertes', 'Push, SMS et e-mail'),
      (Icons.groups_2_outlined, 'Équipes', 'Affectation intelligente'),
      (Icons.inventory_2_outlined, 'Besoins', 'Ressources prioritaires'),
      (Icons.route_outlined, 'Suivi', 'Progression de mission'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth >= 700 ? 4 : 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 132,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.$1, color: _rescueRed),
                const Spacer(),
                Text(
                  item.$2,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  item.$3,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VolunteerStatusCard extends StatelessWidget {
  final RescueVolunteerProfile profile;

  const _VolunteerStatusCard({required this.profile});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: _rescueRedSoft,
          child: Icon(profile.profession.icon, color: _rescueRed),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.profession.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (profile.specialty.isNotEmpty)
                Text(
                  profile.specialty,
                  style: const TextStyle(color: AppColors.muted),
                ),
            ],
          ),
        ),
        _StatusPill(
          label: profile.verificationStatus.label,
          color: profile.verificationStatus.color,
        ),
      ],
    ),
  );
}

class _RescueMissions extends StatelessWidget {
  final RescueVolunteerProfile? profile;
  final Stream<List<RescueMission>> missions;
  final RescueRepository repository;

  const _RescueMissions({
    required this.profile,
    required this.missions,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    if (profile?.verificationStatus != RescueVerificationStatus.verified) {
      return const _CenteredMessage(
        icon: Icons.verified_user_outlined,
        title: 'Vérification requise',
        message:
            'Les missions apparaîtront ici après la validation de votre identité et de vos qualifications.',
      );
    }
    return StreamBuilder<List<RescueMission>>(
      stream: missions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _rescueRed),
          );
        }
        if (snapshot.hasError) {
          return const _CenteredMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Missions indisponibles',
            message: 'Vérifiez votre connexion puis réessayez.',
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const _CenteredMessage(
            icon: Icons.notifications_active_outlined,
            title: 'Aucune alerte pour le moment',
            message:
                'Restez disponible : les alertes correspondant à votre zone et vos compétences s’afficheront ici.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _MissionCard(
            mission: items[index],
            onStatus: (status) async {
              try {
                await repository.updateMissionStatus(
                  items[index].assignmentId,
                  status,
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Le statut de la mission n’a pas pu être mis à jour.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }
}

class _MissionCard extends StatelessWidget {
  final RescueMission mission;
  final ValueChanged<RescueMissionStatus> onStatus;

  const _MissionCard({required this.mission, required this.onStatus});

  RescueMissionStatus? get _nextStatus => switch (mission.status) {
    RescueMissionStatus.accepted => RescueMissionStatus.enRoute,
    RescueMissionStatus.enRoute => RescueMissionStatus.onSite,
    RescueMissionStatus.onSite => RescueMissionStatus.completed,
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.crisis_alert_rounded, color: _rescueRed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mission.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusPill(label: mission.status.label, color: _rescueRed),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${mission.eventType.toUpperCase()} • ${mission.zone}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (mission.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              mission.instructions,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 16),
          if (mission.status == RescueMissionStatus.sent)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onStatus(RescueMissionStatus.declined),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onStatus(RescueMissionStatus.accepted),
                    style: FilledButton.styleFrom(backgroundColor: _rescueRed),
                    child: const Text('Accepter'),
                  ),
                ),
              ],
            )
          else if (_nextStatus != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => onStatus(_nextStatus!),
                style: FilledButton.styleFrom(backgroundColor: _rescueRed),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text('Passer à « ${_nextStatus!.label} »'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RescueOperationalMap extends StatefulWidget {
  final RescueVolunteerProfile? profile;
  final RescueRepository repository;

  const _RescueOperationalMap({
    required this.profile,
    required this.repository,
  });

  @override
  State<_RescueOperationalMap> createState() => _RescueOperationalMapState();
}

class _RescueOperationalMapState extends State<_RescueOperationalMap> {
  final _specialty = TextEditingController();
  RescueVolunteerProfession? _profession;
  late Future<List<RescueMapPoint>> _points = _load();

  Future<List<RescueMapPoint>> _load() {
    if (widget.profile?.verificationStatus !=
        RescueVerificationStatus.verified) {
      return Future.value(const []);
    }
    return widget.repository.loadMapPoints(
      profession: _profession,
      specialty: _specialty.text,
    );
  }

  @override
  void didUpdateWidget(covariant _RescueOperationalMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.verificationStatus !=
        widget.profile?.verificationStatus) {
      _points = _load();
    }
  }

  @override
  void dispose() {
    _specialty.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _points = _load());

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Carte opérationnelle',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 7),
      const Text(
        'Vue partagée des zones sinistrées, structures ouvertes, abris, distributions et volontaires disponibles.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      if (widget.profile?.verificationStatus ==
          RescueVerificationStatus.verified)
        LayoutBuilder(
          builder: (context, constraints) {
            final profession =
                DropdownButtonFormField<RescueVolunteerProfession?>(
                  key: const ValueKey('rescue-map-profession-filter'),
                  initialValue: _profession,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Profession',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Toutes')),
                    for (final item in RescueVolunteerProfession.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) {
                    _profession = value;
                    _refresh();
                  },
                );
            final specialty = TextField(
              key: const ValueKey('rescue-map-specialty-filter'),
              controller: _specialty,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _refresh(),
              decoration: InputDecoration(
                labelText: 'Spécialité',
                hintText: 'Ex. pédiatrie',
                suffixIcon: IconButton(
                  tooltip: 'Appliquer le filtre',
                  onPressed: _refresh,
                  icon: const Icon(Icons.search_rounded),
                ),
              ),
            );
            if (constraints.maxWidth < 650) {
              return Column(
                children: [profession, const SizedBox(height: 10), specialty],
              );
            }
            return Row(
              children: [
                Expanded(child: profession),
                const SizedBox(width: 10),
                Expanded(child: specialty),
              ],
            );
          },
        )
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _rescueRedSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline_rounded, color: _rescueRed),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'La carte opérationnelle en direct est réservée aux volontaires vérifiés.',
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 18),
      AspectRatio(
        aspectRatio: 1.15,
        child: Container(
          key: const ValueKey('rescue-operational-map'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1EE),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: FutureBuilder<List<RescueMapPoint>>(
            future: _points,
            builder: (context, snapshot) => Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _MapPainter()),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                    child: CircularProgressIndicator(color: _rescueRed),
                  )
                else if (snapshot.hasError)
                  Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Recharger la carte'),
                    ),
                  )
                else if ((snapshot.data ?? const []).isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun point opérationnel ne correspond aux filtres.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                else
                  for (final point in snapshot.data!)
                    Align(
                      alignment: _mapAlignment(point),
                      child: _MapMarker(
                        icon: _mapPointIcon(point.type),
                        color: _mapPointColor(point.type),
                        label: point.detail.isEmpty
                            ? point.label
                            : '${point.label}\n${point.detail}',
                      ),
                    ),
                if (widget.profile?.locationConsent == true)
                  const Align(
                    alignment: Alignment.center,
                    child: _MapMarker(
                      icon: Icons.my_location_rounded,
                      color: Color(0xFF7656D8),
                      label: 'Ma position',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Legend(
            icon: Icons.warning_rounded,
            label: 'Zones sinistrées',
            color: _rescueRed,
          ),
          _Legend(
            icon: Icons.local_hospital_rounded,
            label: 'Centres de santé',
            color: AppColors.primary,
          ),
          _Legend(
            icon: Icons.home_work_outlined,
            label: 'Abris',
            color: _rescueOrange,
          ),
          _Legend(
            icon: Icons.inventory_2_outlined,
            label: 'Points de distribution',
            color: _rescueGreen,
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'La carte en direct est alimentée par les événements, sites et positions consenties enregistrés dans Rescue. Les coordonnées exactes restent réservées aux équipes autorisées.',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    ],
  );

  Alignment _mapAlignment(RescueMapPoint point) {
    final x = (((point.longitude + 74.6) / 3) * 2 - 1).clamp(-.92, .92);
    final y = (1 - ((point.latitude - 17.9) / 2.2) * 2).clamp(-.92, .92);
    return Alignment(x, y);
  }

  IconData _mapPointIcon(String type) => switch (type) {
    'disaster' => Icons.warning_rounded,
    'health_center' || 'partner_hospital' => Icons.local_hospital_rounded,
    'temporary_shelter' => Icons.home_work_outlined,
    'distribution_point' => Icons.inventory_2_outlined,
    'volunteer' => Icons.health_and_safety_outlined,
    _ => Icons.place_outlined,
  };

  Color _mapPointColor(String type) => switch (type) {
    'disaster' => _rescueRed,
    'health_center' || 'partner_hospital' => AppColors.primary,
    'temporary_shelter' => _rescueOrange,
    'distribution_point' => _rescueGreen,
    'volunteer' => const Color(0xFF7656D8),
    _ => AppColors.muted,
  };
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    final minor = Paint()
      ..color = const Color(0xFFD4E1DB)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(-20, size.height * .7)
        ..quadraticBezierTo(
          size.width * .35,
          size.height * .45,
          size.width + 20,
          size.height * .58,
        ),
      road,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .25, -10)
        ..quadraticBezierTo(
          size.width * .55,
          size.height * .45,
          size.width * .68,
          size.height + 10,
        ),
      road,
    );
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 6),
        Offset(size.width, size.height * (i + .6) / 6),
        minor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RescueProfile extends StatelessWidget {
  final String userId;
  final String displayName;
  final RescueVolunteerProfile? profile;
  final RescueRepository repository;

  const _RescueProfile({
    required this.userId,
    required this.displayName,
    required this.profile,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return _VolunteerRegistrationForm(
        userId: userId,
        displayName: displayName,
        repository: repository,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: _rescueRedSoft,
              child: Icon(
                profile!.profession.icon,
                color: _rescueRed,
                size: 32,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile!.fullName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    profile!.profession.label,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _StatusPill(
              label: profile!.verificationStatus.label,
              color: profile!.verificationStatus.color,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Disponibilité', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        SegmentedButton<RescueAvailability>(
          segments: [
            for (final status in RescueAvailability.values)
              ButtonSegment(value: status, label: Text(status.label)),
          ],
          selected: {profile!.availability},
          onSelectionChanged:
              profile!.verificationStatus == RescueVerificationStatus.verified
              ? (value) => repository.setAvailability(profile!.id, value.first)
              : null,
        ),
        const SizedBox(height: 20),
        _LocationConsentCard(profile: profile!, repository: repository),
        const SizedBox(height: 20),
        _ProfileDetails(profile: profile!),
      ],
    );
  }
}

class _LocationConsentCard extends StatefulWidget {
  final RescueVolunteerProfile profile;
  final RescueRepository repository;

  const _LocationConsentCard({required this.profile, required this.repository});

  @override
  State<_LocationConsentCard> createState() => _LocationConsentCardState();
}

class _LocationConsentCardState extends State<_LocationConsentCard> {
  bool _working = false;

  Future<void> _toggle(bool enabled) async {
    setState(() => _working = true);
    try {
      if (!enabled) {
        await widget.repository.setLocationConsent(widget.profile.id, false);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('permission');
      }
      await widget.repository.setLocationConsent(widget.profile.id, true);
      final position = await Geolocator.getCurrentPosition();
      await widget.repository.updateLocation(widget.profile.id, position);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La position n’est pas accessible. Vérifiez les autorisations GPS.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: SwitchListTile(
      key: const ValueKey('rescue-location-consent'),
      value: widget.profile.locationConsent,
      onChanged:
          _working ||
              widget.profile.verificationStatus !=
                  RescueVerificationStatus.verified
          ? null
          : _toggle,
      secondary: _working
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location_rounded, color: _rescueRed),
      title: const Text(
        'Partager ma position',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text(
        'Uniquement pendant votre disponibilité et avec votre consentement.',
      ),
    ),
  );
}

class _ProfileDetails extends StatelessWidget {
  final RescueVolunteerProfile profile;

  const _ProfileDetails({required this.profile});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Téléphone',
            value: profile.phone,
          ),
          _DetailRow(
            icon: Icons.workspace_premium_outlined,
            label: 'Spécialité',
            value: profile.specialty.isEmpty
                ? 'Non précisée'
                : profile.specialty,
          ),
          _DetailRow(
            icon: Icons.apartment_outlined,
            label: 'Organisation',
            value: profile.organization.isEmpty
                ? 'Indépendant'
                : profile.organization,
          ),
          _DetailRow(
            icon: Icons.radar_rounded,
            label: 'Rayon',
            value: '${profile.interventionRadiusKm} km',
          ),
          _DetailRow(
            icon: Icons.handyman_outlined,
            label: 'Compétences',
            value: profile.skills.isEmpty
                ? 'Non précisées'
                : profile.skills.join(', '),
            last: true,
          ),
        ],
      ),
    ),
  );
}

class _VolunteerRegistrationForm extends StatefulWidget {
  final String userId;
  final String displayName;
  final RescueRepository repository;

  const _VolunteerRegistrationForm({
    required this.userId,
    required this.displayName,
    required this.repository,
  });

  @override
  State<_VolunteerRegistrationForm> createState() =>
      _VolunteerRegistrationFormState();
}

class _VolunteerRegistrationFormState
    extends State<_VolunteerRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.displayName);
  final _phone = TextEditingController();
  final _specialty = TextEditingController();
  final _organization = TextEditingController();
  final _skills = TextEditingController();
  final _picker = ImagePicker();
  RescueVolunteerProfession _profession =
      RescueVolunteerProfession.generalPractitioner;
  double _radius = 25;
  XFile? _identity;
  XFile? _license;
  bool _submitting = false;

  bool get _licenseRequired => !const {
    RescueVolunteerProfession.healthStudent,
    RescueVolunteerProfession.firstResponder,
    RescueVolunteerProfession.other,
  }.contains(_profession);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _specialty.dispose();
    _organization.dispose();
    _skills.dispose();
    super.dispose();
  }

  Future<void> _pick(bool identity) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (file != null && mounted) {
      setState(() => identity ? _identity = file : _license = file);
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_identity == null || (_licenseRequired && _license == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _identity == null
                ? 'Ajoutez votre pièce d’identité.'
                : 'Ajoutez votre licence professionnelle.',
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.submitApplication(
        RescueVolunteerApplication(
          userId: widget.userId,
          fullName: _name.text,
          phone: _phone.text,
          profession: _profession,
          specialty: _specialty.text,
          organization: _organization.text,
          skills: _skills.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          interventionRadiusKm: _radius.round(),
          identityDocument: await _identity!.readAsBytes(),
          identityDocumentName: _identity!.name,
          professionalLicense: await _license?.readAsBytes(),
          professionalLicenseName: _license?.name ?? '',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Candidature envoyée. Votre dossier est maintenant en attente de vérification.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La candidature n’a pas pu être envoyée. Réessayez.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: ListView(
      key: const ValueKey('rescue-registration-form'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Rejoindre le réseau',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 7),
        const Text(
          'Votre identité et vos qualifications seront contrôlées avant toute mission.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        TextFormField(
          key: const ValueKey('rescue-full-name'),
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Nom complet *',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) => value == null || value.trim().length < 3
              ? 'Indiquez votre nom complet.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('rescue-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone *',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          validator: (value) => value == null || value.trim().length < 8
              ? 'Indiquez un numéro valide.'
              : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<RescueVolunteerProfession>(
          key: const ValueKey('rescue-profession'),
          initialValue: _profession,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Type de volontaire *',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          items: [
            for (final item in RescueVolunteerProfession.values)
              DropdownMenuItem(value: item, child: Text(item.label)),
          ],
          onChanged: (value) =>
              setState(() => _profession = value ?? _profession),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('rescue-specialty'),
          controller: _specialty,
          decoration: const InputDecoration(
            labelText: 'Spécialité',
            prefixIcon: Icon(Icons.workspace_premium_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _organization,
          decoration: const InputDecoration(
            labelText: 'Organisation (optionnelle)',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('rescue-skills'),
          controller: _skills,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Compétences, séparées par des virgules *',
            hintText: 'Triage, premiers soins, santé maternelle...',
          ),
          validator: (value) => value == null || value.trim().length < 3
              ? 'Ajoutez au moins une compétence.'
              : null,
        ),
        const SizedBox(height: 18),
        Text(
          'Rayon d’intervention : ${_radius.round()} km',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Slider(
          value: _radius,
          min: 5,
          max: 100,
          divisions: 19,
          activeColor: _rescueRed,
          label: '${_radius.round()} km',
          onChanged: (value) => setState(() => _radius = value),
        ),
        const SizedBox(height: 8),
        _DocumentPicker(
          key: const ValueKey('rescue-identity-document'),
          title: 'Pièce d’identité *',
          fileName: _identity?.name,
          onTap: () => _pick(true),
        ),
        const SizedBox(height: 10),
        _DocumentPicker(
          key: const ValueKey('rescue-license-document'),
          title:
              'Licence professionnelle${_licenseRequired ? ' *' : ' (si applicable)'}',
          fileName: _license?.name,
          onTap: () => _pick(false),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('rescue-submit-application'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: _rescueRed),
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: Text(
            _submitting ? 'Envoi en cours...' : 'Envoyer ma candidature',
          ),
        ),
      ],
    ),
  );
}

class _DocumentPicker extends StatelessWidget {
  final String title;
  final String? fileName;
  final VoidCallback onTap;

  const _DocumentPicker({
    super.key,
    required this.title,
    required this.fileName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fileName == null ? Colors.white : const Color(0xFFEAF7F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fileName == null ? AppColors.border : _rescueGreen,
        ),
      ),
      child: Row(
        children: [
          Icon(
            fileName == null
                ? Icons.upload_file_outlined
                : Icons.check_circle_rounded,
            color: fileName == null ? _rescueRed : _rescueGreen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (fileName != null)
                  Text(
                    fileName!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            fileName == null ? 'Ajouter' : 'Changer',
            style: const TextStyle(
              color: _rescueRed,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RescueMark extends StatelessWidget {
  final double size;
  final bool inverted;

  const _RescueMark({required this.size, this.inverted = false});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: inverted ? Colors.white : _rescueRedSoft,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(
      Icons.health_and_safety_rounded,
      color: _rescueRed,
      size: size * .65,
    ),
  );
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: .3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.circle, color: Colors.white, size: 8),
        SizedBox(width: 6),
        Text(
          'RÉSEAU ACTIF',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          children: [
            Icon(icon, color: _rescueRed, size: 52),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _MapMarker({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 22),
    ),
  );
}

class _Legend extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Legend({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _rescueRed, size: 21),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

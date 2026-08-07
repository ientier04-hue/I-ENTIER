import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'supabase_config.dart';

const _traditionalGreen = Color(0xFF18794E);
const _traditionalGreenDark = Color(0xFF0D5635);
const _traditionalGreenSoft = Color(0xFFE7F5EC);
const _traditionalRed = Color(0xFFD92D20);

enum NaturalJournalEntryType {
  consultation,
  recommendation,
  naturalProduct,
  observation,
  wellbeing,
}

extension NaturalJournalEntryTypeText on NaturalJournalEntryType {
  String get databaseValue => switch (this) {
    NaturalJournalEntryType.consultation => 'consultation',
    NaturalJournalEntryType.recommendation => 'recommendation',
    NaturalJournalEntryType.naturalProduct => 'natural_product',
    NaturalJournalEntryType.observation => 'observation',
    NaturalJournalEntryType.wellbeing => 'wellbeing',
  };

  String get label => switch (this) {
    NaturalJournalEntryType.consultation => 'Consultation',
    NaturalJournalEntryType.recommendation => 'Recommandation',
    NaturalJournalEntryType.naturalProduct => 'Produit naturel utilisé',
    NaturalJournalEntryType.observation => 'Observation',
    NaturalJournalEntryType.wellbeing => 'Évolution du bien-être',
  };

  IconData get icon => switch (this) {
    NaturalJournalEntryType.consultation => Icons.forum_outlined,
    NaturalJournalEntryType.recommendation => Icons.lightbulb_outline_rounded,
    NaturalJournalEntryType.naturalProduct => Icons.eco_outlined,
    NaturalJournalEntryType.observation => Icons.visibility_outlined,
    NaturalJournalEntryType.wellbeing => Icons.monitor_heart_outlined,
  };

  static NaturalJournalEntryType fromDatabase(Object? value) => switch (value) {
    'recommendation' => NaturalJournalEntryType.recommendation,
    'natural_product' => NaturalJournalEntryType.naturalProduct,
    'observation' => NaturalJournalEntryType.observation,
    'wellbeing' => NaturalJournalEntryType.wellbeing,
    _ => NaturalJournalEntryType.consultation,
  };
}

class TraditionalPractitioner {
  final String id;
  final String name;
  final String description;
  final String phone;
  final String address;
  final String schedule;
  final int experienceYears;
  final List<String> practiceDomains;
  final List<String> languages;
  final List<String> interventionZones;
  final int trustScore;
  final bool onlineAvailable;

  const TraditionalPractitioner({
    required this.id,
    required this.name,
    required this.description,
    required this.phone,
    required this.address,
    required this.schedule,
    required this.experienceYears,
    required this.practiceDomains,
    required this.languages,
    required this.interventionZones,
    required this.trustScore,
    required this.onlineAvailable,
  });

  String get trustLevel => switch (trustScore) {
    >= 85 => 'Confiance excellente',
    >= 70 => 'Confiance élevée',
    >= 50 => 'Confiance établie',
    _ => 'Confiance en progression',
  };

  factory TraditionalPractitioner.fromRows(
    Map<String, dynamic> traditional,
    Map<String, dynamic> provider,
  ) {
    List<String> list(String key) => (traditional[key] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    int integer(String key) => (traditional[key] as num?)?.toInt() ?? 0;
    String text(String key) => provider[key]?.toString().trim() ?? '';

    return TraditionalPractitioner(
      id: traditional['provider_id']?.toString() ?? '',
      name: text('display_name'),
      description: text('description'),
      phone: text('phone'),
      address: text('address'),
      schedule: text('schedule_summary'),
      experienceYears: integer('experience_years'),
      practiceDomains: list('practice_domains'),
      languages: list('languages'),
      interventionZones: list('intervention_zones'),
      trustScore: integer('trust_score'),
      onlineAvailable: traditional['online_available'] == true,
    );
  }
}

class NaturalHealthJournalEntry {
  final String id;
  final NaturalJournalEntryType type;
  final String title;
  final String details;
  final String productName;
  final int? wellnessRating;
  final DateTime occurredAt;

  const NaturalHealthJournalEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.details,
    required this.productName,
    required this.wellnessRating,
    required this.occurredAt,
  });

  factory NaturalHealthJournalEntry.fromRow(Map<String, dynamic> row) =>
      NaturalHealthJournalEntry(
        id: row['entry_id']?.toString() ?? '',
        type: NaturalJournalEntryTypeText.fromDatabase(row['entry_type']),
        title: row['title']?.toString() ?? '',
        details: row['details']?.toString() ?? '',
        productName: row['product_name']?.toString() ?? '',
        wellnessRating: (row['wellness_rating'] as num?)?.toInt(),
        occurredAt:
            DateTime.tryParse(
              row['occurred_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
      );
}

class NaturalHealthSharingGrant {
  final String id;
  final String practitionerId;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  const NaturalHealthSharingGrant({
    required this.id,
    required this.practitionerId,
    required this.expiresAt,
    required this.revokedAt,
  });

  bool get isActive =>
      revokedAt == null &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory NaturalHealthSharingGrant.fromRow(Map<String, dynamic> row) =>
      NaturalHealthSharingGrant(
        id: row['grant_id']?.toString() ?? '',
        practitionerId: row['practitioner_id']?.toString() ?? '',
        expiresAt: DateTime.tryParse(
          row['expires_at']?.toString() ?? '',
        )?.toLocal(),
        revokedAt: DateTime.tryParse(
          row['revoked_at']?.toString() ?? '',
        )?.toLocal(),
      );
}

class TraditionalPreventionContent {
  final String id;
  final String title;
  final String summary;
  final String category;
  final int priority;

  const TraditionalPreventionContent({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.priority,
  });

  factory TraditionalPreventionContent.fromRow(Map<String, dynamic> row) =>
      TraditionalPreventionContent(
        id: row['content_id']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        summary: row['summary']?.toString() ?? '',
        category: row['category']?.toString() ?? 'seasonal',
        priority: (row['priority'] as num?)?.toInt() ?? 0,
      );
}

class TraditionalPatientRecommendation {
  final String id;
  final String type;
  final String title;
  final String content;
  final DateTime? reminderAt;
  final DateTime createdAt;

  const TraditionalPatientRecommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.reminderAt,
    required this.createdAt,
  });

  factory TraditionalPatientRecommendation.fromRow(Map<String, dynamic> row) =>
      TraditionalPatientRecommendation(
        id: row['recommendation_id']?.toString() ?? '',
        type: row['recommendation_type']?.toString() ?? 'prevention',
        title: row['title']?.toString() ?? '',
        content: row['content']?.toString() ?? '',
        reminderAt: DateTime.tryParse(
          row['reminder_at']?.toString() ?? '',
        )?.toLocal(),
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class TraditionalCareOrientation {
  final String id;
  final String targetType;
  final String targetName;
  final String reason;
  final String urgency;
  final String status;
  final DateTime createdAt;

  const TraditionalCareOrientation({
    required this.id,
    required this.targetType,
    required this.targetName,
    required this.reason,
    required this.urgency,
    required this.status,
    required this.createdAt,
  });

  factory TraditionalCareOrientation.fromRow(Map<String, dynamic> row) =>
      TraditionalCareOrientation(
        id: row['orientation_id']?.toString() ?? '',
        targetType: row['target_type']?.toString() ?? '',
        targetName: row['target_name']?.toString() ?? '',
        reason: row['reason']?.toString() ?? '',
        urgency: row['urgency']?.toString() ?? 'routine',
        status: row['status']?.toString() ?? 'proposed',
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

abstract class TraditionalMedicineRepository {
  Stream<List<TraditionalPractitioner>> watchPractitioners();
  Stream<List<NaturalHealthJournalEntry>> watchJournal(String patientId);
  Stream<List<NaturalHealthSharingGrant>> watchSharingGrants(String patientId);
  Stream<List<TraditionalPreventionContent>> watchPreventionContent(
    String regionCode,
  );
  Stream<List<TraditionalPatientRecommendation>> watchRecommendations(
    String patientId,
  );
  Stream<List<TraditionalCareOrientation>> watchOrientations(String patientId);

  Future<void> addJournalEntry(
    String patientId,
    NaturalJournalEntryType type,
    String title,
    String details,
    String productName,
    int? wellnessRating,
  );

  Future<void> bookConsultation({
    required String patientId,
    required String patientName,
    required TraditionalPractitioner practitioner,
    required bool video,
    required DateTime scheduledAt,
    required String note,
  });

  Future<void> setJournalSharing({
    required String patientId,
    required String practitionerId,
    required bool enabled,
  });

  Future<void> reportPractitioner({
    required String reporterId,
    required String practitionerId,
    required String category,
    required String details,
  });

  Future<void> acceptOrientation(String orientationId, {bool booked = false});
}

class SupabaseTraditionalMedicineRepository
    implements TraditionalMedicineRepository {
  final SupabaseClient client;

  SupabaseTraditionalMedicineRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Stream<List<TraditionalPractitioner>> watchPractitioners() => client
      .schema('ientier')
      .from('traditional_practitioner_profiles')
      .stream(primaryKey: ['provider_id'])
      .eq('validation_status', 'approved')
      .order('trust_score', ascending: false)
      .asyncMap((rows) async {
        final practitioners = <TraditionalPractitioner>[];
        for (final row in rows) {
          final provider = await client
              .schema('ientier')
              .from('provider_profiles')
              .select(
                'display_name,description,phone,address,schedule_summary,'
                'verification_status,is_visible',
              )
              .eq('provider_id', row['provider_id'] as Object)
              .maybeSingle();
          if (provider == null ||
              provider['verification_status'] != 'approved' ||
              provider['is_visible'] != true) {
            continue;
          }
          practitioners.add(TraditionalPractitioner.fromRows(row, provider));
        }
        return practitioners;
      });

  @override
  Stream<List<NaturalHealthJournalEntry>> watchJournal(String patientId) =>
      client
          .schema('ientier')
          .from('natural_health_journal_entries')
          .stream(primaryKey: ['entry_id'])
          .eq('patient_id', patientId)
          .order('occurred_at', ascending: false)
          .map(
            (rows) => rows
                .map(NaturalHealthJournalEntry.fromRow)
                .toList(growable: false),
          );

  @override
  Stream<List<NaturalHealthSharingGrant>> watchSharingGrants(
    String patientId,
  ) => client
      .schema('ientier')
      .from('natural_health_sharing_grants')
      .stream(primaryKey: ['grant_id'])
      .eq('patient_id', patientId)
      .map(
        (rows) => rows
            .map(NaturalHealthSharingGrant.fromRow)
            .where((grant) => grant.isActive)
            .toList(growable: false),
      );

  @override
  Stream<List<TraditionalPreventionContent>> watchPreventionContent(
    String regionCode,
  ) => client
      .schema('ientier')
      .from('traditional_prevention_content')
      .stream(primaryKey: ['content_id'])
      .eq('is_published', true)
      .order('priority', ascending: false)
      .map(
        (rows) => rows
            .where(
              (row) =>
                  row['region_code'] == 'HT' ||
                  row['region_code'] == regionCode,
            )
            .map(TraditionalPreventionContent.fromRow)
            .toList(growable: false),
      );

  @override
  Stream<List<TraditionalPatientRecommendation>> watchRecommendations(
    String patientId,
  ) => client
      .schema('ientier')
      .from('traditional_prevention_recommendations')
      .stream(primaryKey: ['recommendation_id'])
      .eq('patient_id', patientId)
      .order('created_at', ascending: false)
      .map(
        (rows) => rows
            .map(TraditionalPatientRecommendation.fromRow)
            .toList(growable: false),
      );

  @override
  Stream<List<TraditionalCareOrientation>> watchOrientations(
    String patientId,
  ) => client
      .schema('ientier')
      .from('traditional_care_orientations')
      .stream(primaryKey: ['orientation_id'])
      .eq('patient_id', patientId)
      .order('created_at', ascending: false)
      .map(
        (rows) => rows
            .map(TraditionalCareOrientation.fromRow)
            .toList(growable: false),
      );

  @override
  Future<void> addJournalEntry(
    String patientId,
    NaturalJournalEntryType type,
    String title,
    String details,
    String productName,
    int? wellnessRating,
  ) => client.schema('ientier').from('natural_health_journal_entries').insert({
    'patient_id': patientId,
    'entry_type': type.databaseValue,
    'title': title,
    'details': details,
    'product_name': type == NaturalJournalEntryType.naturalProduct
        ? productName
        : '',
    'wellness_rating': wellnessRating,
  });

  @override
  Future<void> bookConsultation({
    required String patientId,
    required String patientName,
    required TraditionalPractitioner practitioner,
    required bool video,
    required DateTime scheduledAt,
    required String note,
  }) => client.schema('ientier').from('appointments').insert({
    'patient_id': patientId,
    'patient_name_snapshot': patientName,
    'provider_id': practitioner.id,
    'provider_type_snapshot': 'professional',
    'provider_name_snapshot': practitioner.name,
    'service_name_snapshot': 'Accompagnement traditionnel de bien-être',
    'mode': video ? 'video' : 'inPerson',
    'location': video ? 'À distance dans I-Entier' : practitioner.address,
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'schedule_label': practitioner.schedule.isEmpty
        ? 'Créneau demandé par le patient'
        : practitioner.schedule,
    'status': 'pending',
    'patient_note': note,
  });

  @override
  Future<void> setJournalSharing({
    required String patientId,
    required String practitionerId,
    required bool enabled,
  }) async {
    final active = await client
        .schema('ientier')
        .from('natural_health_sharing_grants')
        .select('grant_id')
        .eq('patient_id', patientId)
        .eq('practitioner_id', practitionerId)
        .filter('revoked_at', 'is', null)
        .maybeSingle();
    if (enabled && active == null) {
      await client
          .schema('ientier')
          .from('natural_health_sharing_grants')
          .insert({
            'patient_id': patientId,
            'practitioner_id': practitionerId,
            'can_view_journal': true,
          });
    } else if (!enabled && active != null) {
      await client
          .schema('ientier')
          .from('natural_health_sharing_grants')
          .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
          .eq('grant_id', active['grant_id'] as Object);
    }
  }

  @override
  Future<void> reportPractitioner({
    required String reporterId,
    required String practitionerId,
    required String category,
    required String details,
  }) => client.schema('ientier').from('traditional_safety_reports').insert({
    'reporter_id': reporterId,
    'practitioner_id': practitionerId,
    'category': category,
    'details': details,
  });

  @override
  Future<void> acceptOrientation(String orientationId, {bool booked = false}) =>
      client
          .schema('ientier')
          .from('traditional_care_orientations')
          .update({'status': booked ? 'booked' : 'accepted'})
          .eq('orientation_id', orientationId);
}

class TraditionalMedicinePage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String regionCode;
  final TraditionalMedicineRepository? repository;
  final Stream<List<TraditionalPractitioner>>? practitionerStream;
  final Stream<List<NaturalHealthJournalEntry>>? journalStream;
  final Stream<List<NaturalHealthSharingGrant>>? sharingStream;
  final Stream<List<TraditionalPreventionContent>>? preventionStream;
  final Stream<List<TraditionalPatientRecommendation>>? recommendationStream;
  final Stream<List<TraditionalCareOrientation>>? orientationStream;
  final VoidCallback? onOpenCareDirectory;
  final VoidCallback? onOpenMobileClinic;
  final VoidCallback? onEmergency;

  const TraditionalMedicinePage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.regionCode = 'HT',
    this.repository,
    this.practitionerStream,
    this.journalStream,
    this.sharingStream,
    this.preventionStream,
    this.recommendationStream,
    this.orientationStream,
    this.onOpenCareDirectory,
    this.onOpenMobileClinic,
    this.onEmergency,
  });

  @override
  State<TraditionalMedicinePage> createState() =>
      _TraditionalMedicinePageState();
}

class _TraditionalMedicinePageState extends State<TraditionalMedicinePage> {
  late final TraditionalMedicineRepository? _repository =
      widget.repository ??
      (SupabaseConfig.isInitialized
          ? SupabaseTraditionalMedicineRepository()
          : null);
  int _section = 0;
  String _query = '';

  Stream<List<TraditionalPractitioner>> get _practitioners =>
      widget.practitionerStream ??
      _repository?.watchPractitioners() ??
      Stream.value(const []);
  Stream<List<NaturalHealthJournalEntry>> get _journal =>
      widget.journalStream ??
      _repository?.watchJournal(widget.patientId) ??
      Stream.value(const []);
  Stream<List<NaturalHealthSharingGrant>> get _sharing =>
      widget.sharingStream ??
      _repository?.watchSharingGrants(widget.patientId) ??
      Stream.value(const []);
  Stream<List<TraditionalPreventionContent>> get _prevention =>
      widget.preventionStream ??
      _repository?.watchPreventionContent(widget.regionCode) ??
      Stream.value(const []);
  Stream<List<TraditionalPatientRecommendation>> get _recommendations =>
      widget.recommendationStream ??
      _repository?.watchRecommendations(widget.patientId) ??
      Stream.value(const []);
  Stream<List<TraditionalCareOrientation>> get _orientations =>
      widget.orientationStream ??
      _repository?.watchOrientations(widget.patientId) ??
      Stream.value(const []);

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L’action n’a pas été enregistrée. Réessayez.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7FAF8),
    appBar: AppBar(
      title: const Text(
        'Médecine Traditionnelle',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    body: StreamBuilder<List<NaturalHealthSharingGrant>>(
      stream: _sharing,
      builder: (context, sharingSnapshot) => CustomScrollView(
        key: const ValueKey('traditional-medicine-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: _TraditionalHero(onEmergency: _showEmergencyAlert),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SectionHeaderDelegate(
              selected: _section,
              onSelected: (value) => setState(() => _section = value),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: switch (_section) {
                    0 => _PractitionersSection(
                      stream: _practitioners,
                      query: _query,
                      onQueryChanged: (value) => setState(() => _query = value),
                      activeSharing: sharingSnapshot.data ?? const [],
                      onOpen: _openPractitioner,
                    ),
                    1 => _JournalSection(
                      stream: _journal,
                      recommendationStream: _recommendations,
                      grants: sharingSnapshot.data ?? const [],
                      onAdd: _addJournalEntry,
                      onRevoke: _revokeGrant,
                    ),
                    2 => _PreventionSection(stream: _prevention),
                    _ => _OrientationsSection(
                      stream: _orientations,
                      onOpen: _openOrientation,
                    ),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _showEmergencyAlert() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.emergency_rounded, color: _traditionalRed),
        title: const Text('Une urgence ne peut pas attendre'),
        content: const Text(
          'Difficulté à respirer, perte de connaissance, saignement important, '
          'convulsions ou douleur intense : contactez immédiatement les services '
          'd’urgence ou rendez-vous au service de santé le plus proche.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            key: const ValueKey('traditional-open-emergency'),
            onPressed: () {
              Navigator.pop(context);
              widget.onEmergency?.call();
            },
            style: FilledButton.styleFrom(backgroundColor: _traditionalRed),
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('Obtenir de l’aide'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPractitioner(
    TraditionalPractitioner practitioner,
    bool sharingEnabled,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PractitionerSheet(
        practitioner: practitioner,
        sharingEnabled: sharingEnabled,
        onBook: () {
          Navigator.pop(context);
          _bookPractitioner(practitioner);
        },
        onSharingChanged: (enabled) => _run(
          () =>
              _repository?.setJournalSharing(
                patientId: widget.patientId,
                practitionerId: practitioner.id,
                enabled: enabled,
              ) ??
              Future.value(),
          enabled
              ? 'Partage du carnet activé. Vous pouvez le révoquer à tout moment.'
              : 'Accès au carnet révoqué.',
        ),
        onReport: () {
          Navigator.pop(context);
          _reportPractitioner(practitioner);
        },
      ),
    );
  }

  Future<void> _bookPractitioner(TraditionalPractitioner practitioner) async {
    final request = await showModalBottomSheet<_BookingRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BookingSheet(practitioner: practitioner),
    );
    if (request == null) return;
    await _run(
      () =>
          _repository?.bookConsultation(
            patientId: widget.patientId,
            patientName: widget.patientName,
            practitioner: practitioner,
            video: request.video,
            scheduledAt: request.scheduledAt,
            note: request.note,
          ) ??
          Future.value(),
      'Demande envoyée à ${practitioner.name}.',
    );
  }

  Future<void> _addJournalEntry() async {
    final entry = await showModalBottomSheet<_JournalDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _JournalEntrySheet(),
    );
    if (entry == null) return;
    await _run(
      () =>
          _repository?.addJournalEntry(
            widget.patientId,
            entry.type,
            entry.title,
            entry.details,
            entry.productName,
            entry.wellnessRating,
          ) ??
          Future.value(),
      'Ajout enregistré dans votre carnet privé.',
    );
  }

  Future<void> _revokeGrant(NaturalHealthSharingGrant grant) => _run(
    () =>
        _repository?.setJournalSharing(
          patientId: widget.patientId,
          practitionerId: grant.practitionerId,
          enabled: false,
        ) ??
        Future.value(),
    'Accès au carnet révoqué.',
  );

  Future<void> _reportPractitioner(TraditionalPractitioner practitioner) async {
    final report = await showDialog<_ReportDraft>(
      context: context,
      builder: (_) => _ReportDialog(practitionerName: practitioner.name),
    );
    if (report == null) return;
    await _run(
      () =>
          _repository?.reportPractitioner(
            reporterId: widget.patientId,
            practitionerId: practitioner.id,
            category: report.category,
            details: report.details,
          ) ??
          Future.value(),
      'Signalement transmis de façon confidentielle à I-Entier.',
    );
  }

  Future<void> _openOrientation(TraditionalCareOrientation orientation) async {
    if (orientation.urgency == 'emergency') {
      _showEmergencyAlert();
      return;
    }
    await _run(
      () =>
          _repository?.acceptOrientation(orientation.id, booked: true) ??
          Future.value(),
      'Orientation acceptée. Choisissez maintenant votre rendez-vous.',
    );
    if (orientation.targetType == 'mobile_clinic') {
      widget.onOpenMobileClinic?.call();
    } else {
      widget.onOpenCareDirectory?.call();
    }
  }
}

class _TraditionalHero extends StatelessWidget {
  final VoidCallback onEmergency;
  const _TraditionalHero({required this.onEmergency});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_traditionalGreenDark, _traditionalGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeafMark(),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Des pratiques traditionnelles encadrées',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.12,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Prévention, bien-être et accompagnement avec des praticiens vérifiés par I-Entier.',
                          style: TextStyle(
                            color: Color(0xFFD9F5E5),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFFFEDEC),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('traditional-emergency-banner'),
                onTap: onEmergency,
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: _traditionalRed),
                      SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Signe d’urgence ? N’attendez pas une consultation traditionnelle.',
                          style: TextStyle(
                            color: Color(0xFF8E1B14),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: _traditionalRed),
                    ],
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

class _LeafMark extends StatelessWidget {
  const _LeafMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.spa_rounded, color: Colors.white, size: 31),
  );
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int selected;
  final ValueChanged<int> onSelected;

  const _SectionHeaderDelegate({
    required this.selected,
    required this.onSelected,
  });

  @override
  double get minExtent => 68;
  @override
  double get maxExtent => 68;
  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.selected != selected;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: Colors.white,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.people_alt_outlined),
            label: Text('Praticiens'),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.menu_book_outlined),
            label: Text('Mon carnet'),
          ),
          ButtonSegment(
            value: 2,
            icon: Icon(Icons.shield_outlined),
            label: Text('Prévention'),
          ),
          ButtonSegment(
            value: 3,
            icon: Icon(Icons.alt_route_rounded),
            label: Text('Orientations'),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (value) => onSelected(value.first),
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _traditionalGreenDark
                : AppColors.muted,
          ),
        ),
      ),
    ),
  );
}

class _PractitionersSection extends StatelessWidget {
  final Stream<List<TraditionalPractitioner>> stream;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final List<NaturalHealthSharingGrant> activeSharing;
  final void Function(TraditionalPractitioner, bool) onOpen;

  const _PractitionersSection({
    required this.stream,
    required this.query,
    required this.onQueryChanged,
    required this.activeSharing,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('traditional-practitioner-search'),
        onChanged: onQueryChanged,
        decoration: InputDecoration(
          hintText: 'Nom, domaine, langue ou zone',
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDDE9E1)),
          ),
        ),
      ),
      const SizedBox(height: 18),
      StreamBuilder<List<TraditionalPractitioner>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _traditionalGreen),
            );
          }
          if (snapshot.hasError) {
            return const _TraditionalEmpty(
              icon: Icons.cloud_off_outlined,
              title: 'Registre momentanément indisponible',
              message: 'Réessayez dans quelques instants.',
            );
          }
          final normalized = query.trim().toLowerCase();
          final practitioners = (snapshot.data ?? const [])
              .where((item) {
                if (normalized.isEmpty) return true;
                return [
                  item.name,
                  ...item.practiceDomains,
                  ...item.languages,
                  ...item.interventionZones,
                ].any((value) => value.toLowerCase().contains(normalized));
              })
              .toList(growable: false);
          if (practitioners.isEmpty) {
            return const _TraditionalEmpty(
              icon: Icons.person_search_outlined,
              title: 'Aucun praticien ne correspond',
              message: 'Modifiez la recherche ou revenez prochainement.',
            );
          }
          return Column(
            children: practitioners
                .map((practitioner) {
                  final sharing = activeSharing.any(
                    (grant) => grant.practitionerId == practitioner.id,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PractitionerCard(
                      practitioner: practitioner,
                      onTap: () => onOpen(practitioner, sharing),
                    ),
                  );
                })
                .toList(growable: false),
          );
        },
      ),
    ],
  );
}

class _PractitionerCard extends StatelessWidget {
  final TraditionalPractitioner practitioner;
  final VoidCallback onTap;
  const _PractitionerCard({required this.practitioner, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    key: ValueKey('traditional-practitioner-${practitioner.id}'),
    color: Colors.white,
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFDDE9E1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: _traditionalGreenSoft,
              child: Text(
                practitioner.name.isEmpty
                    ? '?'
                    : practitioner.name[0].toUpperCase(),
                style: const TextStyle(
                  color: _traditionalGreenDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        practitioner.name,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const _VerifiedBadge(),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    practitioner.practiceDomains.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 7,
                    children: [
                      _MiniPill(
                        icon: Icons.shield_outlined,
                        label: '${practitioner.trustScore}/100',
                      ),
                      _MiniPill(
                        icon: Icons.workspace_premium_outlined,
                        label: '${practitioner.experienceYears} ans',
                      ),
                      _MiniPill(
                        icon: Icons.circle,
                        label: practitioner.onlineAvailable
                            ? 'Disponible'
                            : 'Hors ligne',
                        color: practitioner.onlineAvailable
                            ? _traditionalGreen
                            : AppColors.muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _traditionalGreenSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 14, color: _traditionalGreen),
        SizedBox(width: 4),
        Text(
          'Vérifié',
          style: TextStyle(
            color: _traditionalGreenDark,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MiniPill({
    required this.icon,
    required this.label,
    this.color = _traditionalGreen,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 8 : 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _JournalSection extends StatelessWidget {
  final Stream<List<NaturalHealthJournalEntry>> stream;
  final Stream<List<TraditionalPatientRecommendation>> recommendationStream;
  final List<NaturalHealthSharingGrant> grants;
  final VoidCallback onAdd;
  final ValueChanged<NaturalHealthSharingGrant> onRevoke;

  const _JournalSection({
    required this.stream,
    required this.recommendationStream,
    required this.grants,
    required this.onAdd,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PrivacyPanel(grants: grants, onRevoke: onRevoke),
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Carnet Santé Naturel',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton.icon(
            key: const ValueKey('traditional-add-journal-entry'),
            onPressed: onAdd,
            style: FilledButton.styleFrom(backgroundColor: _traditionalGreen),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      StreamBuilder<List<TraditionalPatientRecommendation>>(
        stream: recommendationStream,
        builder: (context, snapshot) {
          final recommendations = snapshot.data ?? const [];
          if (recommendations.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recommandations reçues',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ...recommendations.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecommendationCard(recommendation: item),
                ),
              ),
              const SizedBox(height: 6),
            ],
          );
        },
      ),
      StreamBuilder<List<NaturalHealthJournalEntry>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _traditionalGreen),
            );
          }
          if (snapshot.hasError) {
            return const _TraditionalEmpty(
              icon: Icons.lock_outline,
              title: 'Votre carnet est indisponible',
              message: 'Vos données restent protégées. Réessayez plus tard.',
            );
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const _TraditionalEmpty(
              icon: Icons.menu_book_outlined,
              title: 'Votre carnet est encore vide',
              message:
                  'Ajoutez une consultation, une recommandation, un produit ou une observation.',
            );
          }
          return Column(
            children: entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _JournalCard(entry: entry),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    ],
  );
}

class _RecommendationCard extends StatelessWidget {
  final TraditionalPatientRecommendation recommendation;
  const _RecommendationCard({required this.recommendation});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _traditionalGreenSoft,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFB9DDC7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              color: _traditionalGreen,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recommendation.title,
                style: const TextStyle(
                  color: _traditionalGreenDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          recommendation.content,
          style: const TextStyle(color: Color(0xFF34664D), height: 1.4),
        ),
        if (recommendation.reminderAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Rappel prévu le ${recommendation.reminderAt!.day.toString().padLeft(2, '0')}/'
            '${recommendation.reminderAt!.month.toString().padLeft(2, '0')}/'
            '${recommendation.reminderAt!.year}',
            style: const TextStyle(
              color: _traditionalGreenDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    ),
  );
}

class _PrivacyPanel extends StatelessWidget {
  final List<NaturalHealthSharingGrant> grants;
  final ValueChanged<NaturalHealthSharingGrant> onRevoke;
  const _PrivacyPanel({required this.grants, required this.onRevoke});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF0FF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFC8D5F5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.lock_rounded, color: Color(0xFF2457D6)),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Privé par défaut, partagé par vous uniquement',
                style: TextStyle(
                  color: Color(0xFF183B91),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          grants.isEmpty
              ? 'Aucun praticien n’a actuellement accès à votre carnet.'
              : '${grants.length} accès actif${grants.length > 1 ? 's' : ''}. Vous pouvez les révoquer immédiatement.',
          style: const TextStyle(color: Color(0xFF3E5796)),
        ),
        if (grants.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            children: grants
                .map(
                  (grant) => ActionChip(
                    key: ValueKey('revoke-sharing-${grant.practitionerId}'),
                    avatar: const Icon(Icons.person_remove_outlined, size: 18),
                    label: const Text('Révoquer un accès'),
                    onPressed: () => onRevoke(grant),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    ),
  );
}

class _JournalCard extends StatelessWidget {
  final NaturalHealthJournalEntry entry;
  const _JournalCard({required this.entry});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFDDE9E1)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: _traditionalGreenSoft,
          foregroundColor: _traditionalGreen,
          child: Icon(entry.type.icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.type.label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                entry.title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (entry.details.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  entry.details,
                  style: const TextStyle(color: AppColors.muted, height: 1.35),
                ),
              ],
              if (entry.productName.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  'Produit : ${entry.productName}',
                  style: const TextStyle(color: _traditionalGreenDark),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _PreventionSection extends StatelessWidget {
  final Stream<List<TraditionalPreventionContent>> stream;
  const _PreventionSection({required this.stream});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1D8A5)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF9A6700)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ces contenus soutiennent la prévention et le bien-être. Ils ne constituent ni un diagnostic médical ni une prescription de médicament.',
                style: TextStyle(
                  color: Color(0xFF76520B),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Centre de Prévention',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 21,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 5),
      const Text(
        'Conseils revus par I-Entier et adaptés à votre région.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      StreamBuilder<List<TraditionalPreventionContent>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _traditionalGreen),
            );
          }
          final content = snapshot.data ?? const [];
          if (snapshot.hasError || content.isEmpty) {
            return const _TraditionalEmpty(
              icon: Icons.shield_outlined,
              title: 'Conseils en cours de mise à jour',
              message:
                  'Revenez bientôt pour les recommandations de votre région.',
            );
          }
          return Column(
            children: content
                .map((item) => _PreventionCard(content: item))
                .toList(growable: false),
          );
        },
      ),
    ],
  );
}

class _PreventionCard extends StatelessWidget {
  final TraditionalPreventionContent content;
  const _PreventionCard({required this.content});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDDE9E1)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: _traditionalGreenSoft,
          foregroundColor: _traditionalGreen,
          child: Icon(switch (content.category) {
            'hygiene' => Icons.wash_outlined,
            'regional_alert' => Icons.notifications_active_outlined,
            'common_illness' => Icons.health_and_safety_outlined,
            _ => Icons.wb_sunny_outlined,
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                content.title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                content.summary,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OrientationsSection extends StatelessWidget {
  final Stream<List<TraditionalCareOrientation>> stream;
  final ValueChanged<TraditionalCareOrientation> onOpen;
  const _OrientationsSection({required this.stream, required this.onOpen});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Mes orientations',
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 21,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Passez du conseil traditionnel au professionnel ou à la structure adaptée sans quitter I-Entier.',
        style: TextStyle(color: AppColors.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      StreamBuilder<List<TraditionalCareOrientation>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _traditionalGreen),
            );
          }
          final orientations = snapshot.data ?? const [];
          if (snapshot.hasError || orientations.isEmpty) {
            return const _TraditionalEmpty(
              icon: Icons.alt_route_rounded,
              title: 'Aucune orientation en attente',
              message:
                  'Les orientations proposées par votre praticien apparaîtront ici et dans vos notifications.',
            );
          }
          return Column(
            children: orientations
                .map(
                  (item) => _OrientationCard(
                    orientation: item,
                    onOpen: () => onOpen(item),
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    ],
  );
}

class _OrientationCard extends StatelessWidget {
  final TraditionalCareOrientation orientation;
  final VoidCallback onOpen;
  const _OrientationCard({required this.orientation, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final urgent = orientation.urgency == 'emergency';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFFFFEDEC) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: urgent ? const Color(0xFFF4B5B0) : const Color(0xFFDDE9E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                urgent ? Icons.emergency_rounded : Icons.alt_route_rounded,
                color: urgent ? _traditionalRed : _traditionalGreen,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  orientation.targetName,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            orientation.reason,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          if (orientation.status == 'proposed') ...[
            const SizedBox(height: 13),
            FilledButton.icon(
              key: ValueKey('open-orientation-${orientation.id}'),
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: urgent ? _traditionalRed : _traditionalGreen,
              ),
              icon: Icon(
                urgent
                    ? Icons.health_and_safety_outlined
                    : Icons.calendar_month_outlined,
              ),
              label: Text(
                urgent ? 'Obtenir de l’aide maintenant' : 'Prendre rendez-vous',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PractitionerSheet extends StatefulWidget {
  final TraditionalPractitioner practitioner;
  final bool sharingEnabled;
  final VoidCallback onBook;
  final ValueChanged<bool> onSharingChanged;
  final VoidCallback onReport;

  const _PractitionerSheet({
    required this.practitioner,
    required this.sharingEnabled,
    required this.onBook,
    required this.onSharingChanged,
    required this.onReport,
  });

  @override
  State<_PractitionerSheet> createState() => _PractitionerSheetState();
}

class _PractitionerSheetState extends State<_PractitionerSheet> {
  late bool _sharing = widget.sharingEnabled;

  @override
  Widget build(BuildContext context) {
    final p = widget.practitioner;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .86,
      minChildSize: .55,
      maxChildSize: .95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const CircleAvatar(
                radius: 31,
                backgroundColor: _traditionalGreenSoft,
                child: Icon(
                  Icons.spa_rounded,
                  color: _traditionalGreen,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const _VerifiedBadge(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _traditionalGreenSoft,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Score de confiance',
                        value: '${p.trustScore}/100',
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Expérience',
                        value: '${p.experienceYears} ans',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  p.trustLevel,
                  style: const TextStyle(
                    color: _traditionalGreenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _DetailBlock(
            title: 'Domaines de pratique',
            value: p.practiceDomains.join(', '),
            icon: Icons.eco_outlined,
          ),
          _DetailBlock(
            title: 'Langues',
            value: p.languages.join(', '),
            icon: Icons.translate_rounded,
          ),
          _DetailBlock(
            title: 'Zone d’intervention',
            value: p.interventionZones.join(', '),
            icon: Icons.location_on_outlined,
          ),
          if (p.description.isNotEmpty)
            _DetailBlock(
              title: 'À propos',
              value: p.description,
              icon: Icons.person_outline,
            ),
          const SizedBox(height: 5),
          SwitchListTile.adaptive(
            key: const ValueKey('traditional-share-journal'),
            value: _sharing,
            onChanged: (value) {
              setState(() => _sharing = value);
              widget.onSharingChanged(value);
            },
            activeTrackColor: _traditionalGreen,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text(
              'Partager mon carnet',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Accès révocable à tout moment depuis Mon carnet.',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              'Ce praticien accompagne la prévention et le bien-être. Il ne pose pas de diagnostic médical et ne prescrit pas de médicament.',
              style: TextStyle(
                color: Color(0xFF76520B),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('traditional-book-practitioner'),
            onPressed: p.onlineAvailable ? widget.onBook : null,
            style: FilledButton.styleFrom(
              backgroundColor: _traditionalGreen,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.video_call_outlined),
            label: Text(
              p.onlineAvailable
                  ? 'Demander une consultation'
                  : 'Praticien indisponible',
            ),
          ),
          TextButton.icon(
            key: const ValueKey('traditional-report-practitioner'),
            onPressed: widget.onReport,
            icon: const Icon(Icons.flag_outlined, color: _traditionalRed),
            label: const Text(
              'Signaler ce profil ou un conseil',
              style: TextStyle(color: _traditionalRed),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: _traditionalGreenDark,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: _traditionalGreen, fontSize: 11),
      ),
    ],
  );
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _DetailBlock({
    required this.title,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: _traditionalGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(color: AppColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BookingRequest {
  final bool video;
  final DateTime scheduledAt;
  final String note;
  const _BookingRequest({
    required this.video,
    required this.scheduledAt,
    required this.note,
  });
}

class _BookingSheet extends StatefulWidget {
  final TraditionalPractitioner practitioner;
  const _BookingSheet({required this.practitioner});
  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  bool _video = true;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consultation avec ${widget.practitioner.name}',
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 15),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.video_call_outlined),
                label: Text('À distance'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.place_outlined),
                label: Text('Sur place'),
              ),
            ],
            selected: {_video},
            onSelectionChanged: (value) => setState(() => _video = value.first),
          ),
          const SizedBox(height: 13),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.calendar_month_outlined,
              color: _traditionalGreen,
            ),
            title: const Text('Date souhaitée'),
            subtitle: Text(
              '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year} à 09:00',
            ),
            trailing: TextButton(
              onPressed: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (chosen != null) setState(() => _date = chosen);
              },
              child: const Text('Modifier'),
            ),
          ),
          TextField(
            key: const ValueKey('traditional-booking-note'),
            controller: _note,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Motif de bien-être (facultatif)',
              hintText: 'Prévention, habitudes, suivi…',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('traditional-confirm-booking'),
            onPressed: () => Navigator.pop(
              context,
              _BookingRequest(
                video: _video,
                scheduledAt: DateTime(_date.year, _date.month, _date.day, 9),
                note: _note.text.trim(),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _traditionalGreen,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    ),
  );
}

class _JournalDraft {
  final NaturalJournalEntryType type;
  final String title;
  final String details;
  final String productName;
  final int? wellnessRating;
  const _JournalDraft({
    required this.type,
    required this.title,
    required this.details,
    required this.productName,
    required this.wellnessRating,
  });
}

class _JournalEntrySheet extends StatefulWidget {
  const _JournalEntrySheet();
  @override
  State<_JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends State<_JournalEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _product = TextEditingController();
  NaturalJournalEntryType _type = NaturalJournalEntryType.observation;
  int? _wellness;
  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _product.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ajouter à mon carnet',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<NaturalJournalEntryType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type d’entrée'),
              items: NaturalJournalEntryType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('traditional-journal-title'),
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Titre'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Un titre est requis.'
                  : null,
            ),
            if (_type == NaturalJournalEntryType.naturalProduct) ...[
              TextFormField(
                key: const ValueKey('traditional-journal-product'),
                controller: _product,
                maxLength: 180,
                decoration: const InputDecoration(
                  labelText: 'Nom du produit naturel',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom du produit est requis.'
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _details,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Notes (facultatif)',
                alignLabelWithHint: true,
              ),
            ),
            if (_type == NaturalJournalEntryType.wellbeing) ...[
              const Text('Mon niveau de bien-être'),
              Slider(
                value: (_wellness ?? 3).toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '${_wellness ?? 3}/5',
                activeColor: _traditionalGreen,
                onChanged: (value) => setState(() => _wellness = value.round()),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('traditional-save-journal'),
              onPressed: () {
                if (_formKey.currentState?.validate() != true) return;
                Navigator.pop(
                  context,
                  _JournalDraft(
                    type: _type,
                    title: _title.text.trim(),
                    details: _details.text.trim(),
                    productName: _product.text.trim(),
                    wellnessRating: _type == NaturalJournalEntryType.wellbeing
                        ? (_wellness ?? 3)
                        : null,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _traditionalGreen,
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Enregistrer dans mon carnet'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReportDraft {
  final String category;
  final String details;
  const _ReportDraft(this.category, this.details);
}

class _ReportDialog extends StatefulWidget {
  final String practitionerName;
  const _ReportDialog({required this.practitionerName});
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  String _category = 'dangerous_advice';
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Signaler ${widget.practitionerName}'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Motif'),
              items: const [
                DropdownMenuItem(
                  value: 'dangerous_advice',
                  child: Text('Conseil dangereux'),
                ),
                DropdownMenuItem(
                  value: 'fake_profile',
                  child: Text('Faux profil'),
                ),
                DropdownMenuItem(
                  value: 'misleading_advertising',
                  child: Text('Publicité trompeuse'),
                ),
                DropdownMenuItem(
                  value: 'inappropriate_behavior',
                  child: Text('Comportement inapproprié'),
                ),
              ],
              onChanged: (value) => _category = value ?? _category,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('traditional-report-details'),
              controller: _details,
              minLines: 4,
              maxLines: 6,
              maxLength: 1600,
              decoration: const InputDecoration(
                labelText: 'Décrivez les faits',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().length < 10
                  ? 'Ajoutez au moins 10 caractères.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const ValueKey('traditional-submit-report'),
        onPressed: () {
          if (_formKey.currentState?.validate() == true) {
            Navigator.pop(
              context,
              _ReportDraft(_category, _details.text.trim()),
            );
          }
        },
        style: FilledButton.styleFrom(backgroundColor: _traditionalRed),
        child: const Text('Transmettre'),
      ),
    ],
  );
}

class _TraditionalEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _TraditionalEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDDE9E1)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 40, color: _traditionalGreen),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
      ],
    ),
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'diagnostic_assessment.dart';
import 'supabase_config.dart';

class SymptomAssessmentRecord {
  final String id;
  final String patientId;
  final String pathwayId;
  final String pathwayTitle;
  final int pathwayVersion;
  final Map<String, dynamic> pathwaySnapshot;
  final String status;
  final String? currentQuestionId;
  final Map<String, String> answers;
  final Map<String, bool> consents;
  final Map<String, dynamic> contextSnapshot;
  final AssessmentResult? result;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const SymptomAssessmentRecord({
    required this.id,
    required this.patientId,
    required this.pathwayId,
    required this.pathwayTitle,
    this.pathwayVersion = 1,
    this.pathwaySnapshot = const {},
    required this.status,
    required this.currentQuestionId,
    required this.answers,
    required this.consents,
    required this.contextSnapshot,
    required this.result,
    required this.startedAt,
    required this.updatedAt,
    required this.completedAt,
  });

  bool get isCompleted => status == 'completed';

  SymptomAssessmentRecord copyWith({
    String? status,
    String? currentQuestionId,
    bool clearCurrentQuestion = false,
    Map<String, String>? answers,
    Map<String, bool>? consents,
    Map<String, dynamic>? contextSnapshot,
    AssessmentResult? result,
    bool clearResult = false,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) => SymptomAssessmentRecord(
    id: id,
    patientId: patientId,
    pathwayId: pathwayId,
    pathwayTitle: pathwayTitle,
    pathwayVersion: pathwayVersion,
    pathwaySnapshot: pathwaySnapshot,
    status: status ?? this.status,
    currentQuestionId: clearCurrentQuestion
        ? null
        : currentQuestionId ?? this.currentQuestionId,
    answers: answers ?? this.answers,
    consents: consents ?? this.consents,
    contextSnapshot: contextSnapshot ?? this.contextSnapshot,
    result: clearResult ? null : result ?? this.result,
    startedAt: startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: completedAt ?? this.completedAt,
  );

  Map<String, dynamic> toRow() => {
    'assessment_id': id,
    'patient_id': patientId,
    'category_id': pathwayId,
    'category_title': pathwayTitle,
    'pathway_version': pathwayVersion,
    'pathway_snapshot': pathwaySnapshot,
    'status': status,
    'current_question_id': currentQuestionId,
    'answers': answers,
    'consents': consents,
    'context_snapshot': contextSnapshot,
    'result': result?.toMap() ?? const <String, dynamic>{},
    'started_at': startedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
  };

  factory SymptomAssessmentRecord.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> map(String key) {
      final value = row[key];
      return value is Map ? Map<String, dynamic>.from(value) : {};
    }

    final rawAnswers = map('answers');
    final rawConsents = map('consents');
    final rawResult = map('result');
    return SymptomAssessmentRecord(
      id: row['assessment_id']?.toString() ?? '',
      patientId: row['patient_id']?.toString() ?? '',
      pathwayId: row['category_id']?.toString() ?? '',
      pathwayTitle: row['category_title']?.toString() ?? '',
      pathwayVersion: (row['pathway_version'] as num?)?.round() ?? 1,
      pathwaySnapshot: map('pathway_snapshot'),
      status: row['status']?.toString() ?? 'draft',
      currentQuestionId: row['current_question_id']?.toString(),
      answers: rawAnswers.map((key, value) => MapEntry(key, value.toString())),
      consents: rawConsents.map((key, value) => MapEntry(key, value == true)),
      contextSnapshot: map('context_snapshot'),
      result: rawResult.isEmpty ? null : AssessmentResult.fromMap(rawResult),
      startedAt: _dateFrom(row['started_at']) ?? DateTime.now(),
      updatedAt: _dateFrom(row['updated_at']) ?? DateTime.now(),
      completedAt: _dateFrom(row['completed_at']),
    );
  }
}

abstract class SymptomAssessmentRepository {
  Stream<List<SymptomAssessmentRecord>> watch(String patientId);

  Future<void> save(SymptomAssessmentRecord assessment);

  Future<Map<String, dynamic>> loadAuthorizedContext({
    required String patientId,
    required Map<String, dynamic> patientProfile,
    required Map<String, bool> consents,
  });
}

class SupabaseSymptomAssessmentRepository
    implements SymptomAssessmentRepository {
  SupabaseClient get _client => SupabaseConfig.client;

  @override
  Stream<List<SymptomAssessmentRecord>> watch(String patientId) => _client
      .schema('ientier')
      .from('symptom_assessments')
      .stream(primaryKey: ['assessment_id'])
      .eq('patient_id', patientId)
      .order('started_at', ascending: false)
      .map(
        (rows) =>
            rows.map(SymptomAssessmentRecord.fromRow).toList(growable: false),
      );

  @override
  Future<void> save(SymptomAssessmentRecord assessment) async {
    await _client
        .schema('ientier')
        .from('symptom_assessments')
        .upsert(assessment.toRow(), onConflict: 'assessment_id');
  }

  @override
  Future<Map<String, dynamic>> loadAuthorizedContext({
    required String patientId,
    required Map<String, dynamic> patientProfile,
    required Map<String, bool> consents,
  }) async {
    final context = <String, dynamic>{};
    if (consents['profile'] == true) {
      final birthDate = _dateFrom(patientProfile['birthDate']);
      context.addAll({
        'age': birthDate == null ? null : _ageAt(birthDate, DateTime.now()),
        'ageMonths': birthDate == null
            ? null
            : _ageInMonths(birthDate, DateTime.now()),
        'sex': patientProfile['sex']?.toString(),
        'pregnancy': _profileIndicatesPregnancy(patientProfile),
        'conditions': _stringList(patientProfile['medicalConditions']),
        'allergies': _stringList(patientProfile['allergies']),
        'medications': _stringList(patientProfile['currentMedications']),
      });
    }

    if (consents['measurements'] == true) {
      final rows = List<Map<String, dynamic>>.from(
        await _client
            .schema('ientier')
            .from('health_measurements')
            .select('kind,value,secondary_value,unit,measured_at')
            .eq('patient_id', patientId)
            .order('measured_at', ascending: false)
            .limit(12),
      );
      context['recentMeasurements'] = rows;
      final recentTemperatures = rows
          .where((row) {
            if (row['kind'] != 'temperature') return false;
            final measuredAt = _dateFrom(row['measured_at']);
            return measuredAt != null &&
                DateTime.now().difference(measuredAt.toLocal()).inHours <= 48;
          })
          .map((row) => (row['value'] as num?)?.toDouble())
          .whereType<double>()
          .toList(growable: false);
      context['recentMaxTemperature'] = recentTemperatures.isEmpty
          ? null
          : recentTemperatures.reduce(math.max);
      context['recentHighTemperature'] = recentTemperatures.any(
        (value) => value >= 38,
      );
    }

    if (consents['cycle'] == true) {
      context['recentCycleEntries'] = List<Map<String, dynamic>>.from(
        await _client
            .schema('ientier')
            .from('cycle_entries')
            .select('entry_date,is_period,flow,mood')
            .eq('patient_id', patientId)
            .order('entry_date', ascending: false)
            .limit(12),
      );
    }

    if (consents['mood'] == true) {
      context['recentMoodEntries'] = List<Map<String, dynamic>>.from(
        await _client
            .schema('ientier')
            .from('mental_health_entries')
            .select('mood,mood_score,created_at')
            .eq('patient_id', patientId)
            .order('created_at', ascending: false)
            .limit(7),
      );
    }
    return context;
  }
}

class _MemorySymptomAssessmentRepository
    implements SymptomAssessmentRepository {
  final Map<String, SymptomAssessmentRecord> _records = {};
  final StreamController<List<SymptomAssessmentRecord>> _controller =
      StreamController<List<SymptomAssessmentRecord>>.broadcast();

  @override
  Stream<List<SymptomAssessmentRecord>> watch(String patientId) async* {
    yield _forPatient(patientId);
    yield* _controller.stream.map(
      (records) =>
          records.where((record) => record.patientId == patientId).toList(),
    );
  }

  List<SymptomAssessmentRecord> _forPatient(String patientId) {
    final records = _records.values
        .where((record) => record.patientId == patientId)
        .toList();
    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return records;
  }

  @override
  Future<void> save(SymptomAssessmentRecord assessment) async {
    _records[assessment.id] = assessment;
    _controller.add(_records.values.toList());
  }

  @override
  Future<Map<String, dynamic>> loadAuthorizedContext({
    required String patientId,
    required Map<String, dynamic> patientProfile,
    required Map<String, bool> consents,
  }) async {
    if (consents['profile'] != true) return {};
    final birthDate = _dateFrom(patientProfile['birthDate']);
    return {
      'age': birthDate == null ? null : _ageAt(birthDate, DateTime.now()),
      'ageMonths': birthDate == null
          ? null
          : _ageInMonths(birthDate, DateTime.now()),
      'sex': patientProfile['sex']?.toString(),
      'pregnancy': _profileIndicatesPregnancy(patientProfile),
      'conditions': _stringList(patientProfile['medicalConditions']),
      'allergies': _stringList(patientProfile['allergies']),
      'medications': _stringList(patientProfile['currentMedications']),
    };
  }
}

class DiagnosticAssessmentPage extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientProfile;
  final SymptomAssessmentRepository? repository;
  final Stream<List<SymptomAssessmentRecord>>? assessmentStream;
  final VoidCallback? onOpenAppointments;
  final Future<void> Function(String text)? onSpeak;

  const DiagnosticAssessmentPage({
    super.key,
    required this.patientId,
    required this.patientProfile,
    this.repository,
    this.assessmentStream,
    this.onOpenAppointments,
    this.onSpeak,
  });

  @override
  State<DiagnosticAssessmentPage> createState() =>
      _DiagnosticAssessmentPageState();
}

class _DiagnosticAssessmentPageState extends State<DiagnosticAssessmentPage> {
  late final SymptomAssessmentRepository _repository =
      widget.repository ??
      (SupabaseConfig.isInitialized
          ? SupabaseSymptomAssessmentRepository()
          : _MemorySymptomAssessmentRepository());
  List<AssessmentPathway> _pathways = assessmentPathways;

  Stream<List<SymptomAssessmentRecord>> get _stream =>
      widget.assessmentStream ?? _repository.watch(widget.patientId);

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.isInitialized) unawaited(_loadPublishedPathways());
  }

  Future<void> _loadPublishedPathways() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await SupabaseConfig.client
            .schema('ientier')
            .from('diagnostic_pathway_versions')
            .select('version_number,definition')
            .eq('status', 'published')
            .order('pathway_id'),
      );
      final published = <AssessmentPathway>[];
      for (final row in rows) {
        final raw = row['definition'];
        if (raw is! Map) continue;
        try {
          published.add(
            assessmentPathwayFromMap(
              Map<String, dynamic>.from(raw),
              version: (row['version_number'] as num?)?.round() ?? 1,
            ),
          );
        } on FormatException {
          // Un parcours publié invalide est ignoré.
        }
      }
      if (mounted) {
        setState(
          () => _pathways = mergeNewestAssessmentPathways(
            assessmentPathways,
            published,
          ),
        );
      }
    } catch (_) {
      // Le catalogue intégré garantit un repli sûr hors connexion.
    }
  }

  AssessmentPathway? _pathwayById(String id) {
    for (final pathway in _pathways) {
      if (pathway.id == id) return pathway;
    }
    return assessmentPathwayById(id);
  }

  AssessmentPathway? _pathwayForAssessment(SymptomAssessmentRecord assessment) {
    if (assessment.pathwaySnapshot.isNotEmpty) {
      try {
        return assessmentPathwayFromMap(
          assessment.pathwaySnapshot,
          version: assessment.pathwayVersion,
        );
      } on FormatException {
        // Les anciennes évaluations utilisent le catalogue disponible.
      }
    }
    return _pathwayById(assessment.pathwayId);
  }

  Future<void> _startAssessment() async {
    final consents = await Navigator.of(context).push<Map<String, bool>>(
      MaterialPageRoute(builder: (_) => const _AssessmentConsentPage()),
    );
    if (!mounted || consents == null) return;

    final pathway = await Navigator.of(context).push<AssessmentPathway>(
      MaterialPageRoute(
        builder: (_) => _PathwayPickerPage(pathways: _pathways),
      ),
    );
    if (!mounted || pathway == null) return;

    Map<String, dynamic> contextSnapshot;
    try {
      contextSnapshot = await _repository.loadAuthorizedContext(
        patientId: widget.patientId,
        patientProfile: widget.patientProfile,
        consents: consents,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Les données autorisées n’ont pas pu être chargées. Vérifiez votre connexion.',
          ),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final assessment = SymptomAssessmentRecord(
      id: _newAssessmentId(widget.patientId, now),
      patientId: widget.patientId,
      pathwayId: pathway.id,
      pathwayTitle: pathway.title,
      pathwayVersion: pathway.version,
      pathwaySnapshot: assessmentPathwayToMap(pathway),
      status: 'draft',
      currentQuestionId: pathway.questions.first.id,
      answers: const {},
      consents: consents,
      contextSnapshot: contextSnapshot,
      result: null,
      startedAt: now,
      updatedAt: now,
      completedAt: null,
    );
    try {
      await _repository.save(assessment);
      if (!mounted) return;
      await _openQuestionnaire(assessment);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de synchroniser cette évaluation. Réessayez lorsque la connexion est disponible.',
          ),
        ),
      );
    }
  }

  Future<void> _openQuestionnaire(SymptomAssessmentRecord assessment) async {
    final pathway = _pathwayForAssessment(assessment);
    if (pathway == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce parcours n’est plus disponible.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _QuestionnairePage(
          initialAssessment: assessment,
          pathway: pathway,
          repository: _repository,
          onOpenAppointments: widget.onOpenAppointments,
          onSpeak: widget.onSpeak,
        ),
      ),
    );
  }

  Future<void> _openRecord(SymptomAssessmentRecord assessment) async {
    if (assessment.isCompleted && assessment.result != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _AssessmentResultPage(
            assessment: assessment,
            result: assessment.result!,
            onOpenAppointments: widget.onOpenAppointments,
            onSpeak: widget.onSpeak,
          ),
        ),
      );
      return;
    }
    await _openQuestionnaire(assessment);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Évaluation assistée')),
    body: StreamBuilder<List<SymptomAssessmentRecord>>(
      stream: _stream,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <SymptomAssessmentRecord>[];
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            children: [
              _AssessmentHero(onStart: _startAssessment),
              const SizedBox(height: 18),
              const _MedicalBoundaryCard(),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mes évaluations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (records.isNotEmpty)
                    Text(
                      '${records.length} au total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                const _HistoryError()
              else if (snapshot.connectionState == ConnectionState.waiting &&
                  records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (records.isEmpty)
                const _EmptyAssessmentHistory()
              else
                for (final assessment in records) ...[
                  _AssessmentHistoryCard(
                    assessment: assessment,
                    pathway: _pathwayForAssessment(assessment),
                    onTap: () => _openRecord(assessment),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    ),
  );
}

class _AssessmentHero extends StatelessWidget {
  final VoidCallback onStart;
  const _AssessmentHero({required this.onStart});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF155FD8), Color(0xFF0C8EA1)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x30155FD8),
          blurRadius: 28,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.health_and_safety_outlined,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Comprendre ce que votre corps vous signale',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Répondez à des questions simples, une étape à la fois, puis recevez une orientation prudente.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: .9),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('assessment-start'),
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF155FD8),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nouvelle évaluation'),
        ),
      ],
    ),
  );
}

class _MedicalBoundaryCard extends StatelessWidget {
  const _MedicalBoundaryCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      border: Border.all(color: const Color(0xFFF5D48D)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: AppColors.warning),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Ce service ne pose pas de diagnostic. En cas de danger immédiat, appelez le Centre Ambulancier National au 116.',
          ),
        ),
      ],
    ),
  );
}

class _HistoryError extends StatelessWidget {
  const _HistoryError();

  @override
  Widget build(BuildContext context) => const _FeedbackCard(
    icon: Icons.cloud_off_outlined,
    title: 'Historique indisponible',
    message:
        'Vérifiez votre connexion. Vos évaluations réapparaîtront après synchronisation.',
  );
}

class _EmptyAssessmentHistory extends StatelessWidget {
  const _EmptyAssessmentHistory();

  @override
  Widget build(BuildContext context) => const _FeedbackCard(
    icon: Icons.assignment_outlined,
    title: 'Aucune évaluation',
    message:
        'Lancez votre première évaluation. Chaque réponse confirmée sera enregistrée dans votre compte.',
  );
}

class _FeedbackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _FeedbackCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _AssessmentHistoryCard extends StatelessWidget {
  final SymptomAssessmentRecord assessment;
  final AssessmentPathway? pathway;
  final VoidCallback onTap;
  const _AssessmentHistoryCard({
    required this.assessment,
    required this.pathway,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentPathway = pathway;
    final color = currentPathway?.color ?? AppColors.primary;
    final progress = currentPathway == null
        ? 0
        : const AssessmentEngine().progress(currentPathway, assessment.answers);
    final urgency = assessment.result?.urgency;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  pathway?.icon ?? Icons.health_and_safety_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assessment.pathwayTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      assessment.isCompleted
                          ? '${urgency?.label ?? 'Évaluation terminée'} · ${_shortDate(assessment.completedAt ?? assessment.updatedAt)}'
                          : 'À reprendre · $progress % complété',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: urgency == AssessmentUrgency.emergency
                            ? Theme.of(context).colorScheme.error
                            : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                assessment.isCompleted
                    ? Icons.description_outlined
                    : Icons.play_arrow_rounded,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssessmentConsentPage extends StatefulWidget {
  const _AssessmentConsentPage();

  @override
  State<_AssessmentConsentPage> createState() => _AssessmentConsentPageState();
}

class _AssessmentConsentPageState extends State<_AssessmentConsentPage> {
  final Map<String, bool> _consents = {
    'profile': true,
    'measurements': true,
    'cycle': false,
    'mood': false,
  };
  bool _understood = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vos données, votre choix')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const _ConsentIntro(),
        const SizedBox(height: 20),
        Text(
          'Autoriser pour cette évaluation',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _ConsentTile(
          key: const Key('consent-profile'),
          icon: Icons.badge_outlined,
          title: 'Profil médical',
          subtitle:
              'Âge, grossesse, antécédents, allergies et traitements actuels',
          value: _consents['profile']!,
          onChanged: (value) => setState(() => _consents['profile'] = value),
        ),
        _ConsentTile(
          key: const Key('consent-measurements'),
          icon: Icons.monitor_heart_outlined,
          title: 'Mesures de santé',
          subtitle: 'Température et dernières valeurs de votre suivi',
          value: _consents['measurements']!,
          onChanged: (value) =>
              setState(() => _consents['measurements'] = value),
        ),
        _ConsentTile(
          key: const Key('consent-cycle'),
          icon: Icons.calendar_month_outlined,
          title: 'Suivi de cycle',
          subtitle: 'Dernières règles et informations de cycle',
          value: _consents['cycle']!,
          onChanged: (value) => setState(() => _consents['cycle'] = value),
        ),
        _ConsentTile(
          key: const Key('consent-mood'),
          icon: Icons.mood_outlined,
          title: 'Journal d’humeur',
          subtitle: 'Tendances récentes, sans recopier vos notes personnelles',
          value: _consents['mood']!,
          onChanged: (value) => setState(() => _consents['mood'] = value),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const Key('consent-understood'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _understood,
          onChanged: (value) => setState(() => _understood = value == true),
          title: const Text(
            'Je comprends que cette évaluation ne remplace pas un professionnel de santé.',
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('consent-continue'),
          onPressed: _understood
              ? () => Navigator.of(context).pop(Map.of(_consents))
              : null,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Continuer'),
        ),
        const SizedBox(height: 8),
        Text(
          'Les autorisations sont enregistrées avec cette évaluation. Les données restent protégées par l’accès privé de votre compte.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _ConsentIntro extends StatelessWidget {
  const _ConsentIntro();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_person_outlined, color: AppColors.primary, size: 30),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            'Vous décidez quelles informations peuvent aider à personnaliser l’orientation. Vous pouvez tout désactiver et continuer.',
          ),
        ),
      ],
    ),
  );
}

class _ConsentTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ConsentTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: SwitchListTile(
      secondary: Icon(icon, color: AppColors.primary),
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    ),
  );
}

class _PathwayPickerPage extends StatelessWidget {
  final List<AssessmentPathway> pathways;
  const _PathwayPickerPage({required this.pathways});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Que ressentez-vous ?')),
    body: GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width >= 760 ? 3 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: MediaQuery.sizeOf(context).width < 360 ? .76 : .84,
      ),
      itemCount: pathways.length,
      itemBuilder: (context, index) {
        final pathway = pathways[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('pathway-${pathway.id}'),
            onTap: () => Navigator.of(context).pop(pathway),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: pathway.color.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          pathway.icon,
                          color: pathway.color,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    pathway.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    pathway.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _QuestionnairePage extends StatefulWidget {
  final SymptomAssessmentRecord initialAssessment;
  final AssessmentPathway pathway;
  final SymptomAssessmentRepository repository;
  final VoidCallback? onOpenAppointments;
  final Future<void> Function(String text)? onSpeak;

  const _QuestionnairePage({
    required this.initialAssessment,
    required this.pathway,
    required this.repository,
    required this.onOpenAppointments,
    required this.onSpeak,
  });

  @override
  State<_QuestionnairePage> createState() => _QuestionnairePageState();
}

enum _EmergencyDecision { stop, continueAssessment }

class _QuestionnairePageState extends State<_QuestionnairePage> {
  static const _engine = AssessmentEngine();
  late SymptomAssessmentRecord _assessment = widget.initialAssessment;
  Set<String> _selectedOptionIds = {};
  bool _saving = false;
  final FlutterTts _tts = FlutterTts();

  AssessmentQuestion get _question =>
      widget.pathway.questionById(_assessment.currentQuestionId) ??
      _engine.nextQuestion(widget.pathway, _assessment.answers) ??
      widget.pathway.questions.first;

  @override
  void initState() {
    super.initState();
    _selectedOptionIds = _decodeSelected(_assessment.answers[_question.id]);
    unawaited(_configureTts());
  }

  Set<String> _decodeSelected(String? encoded) => encoded == null
      ? <String>{}
      : encoded
            .split('|')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();

  String _encodeSelected(AssessmentQuestion question) {
    final ids = _selectedOptionIds.toList()..sort();
    return question.allowMultiple ? ids.join('|') : ids.first;
  }

  void _toggleOption(AssessmentOption option) {
    setState(() {
      if (!_question.allowMultiple) {
        _selectedOptionIds = {option.id};
        return;
      }
      final updated = Set<String>.of(_selectedOptionIds);
      if (option.tags.isEmpty) {
        updated
          ..clear()
          ..add(option.id);
      } else {
        for (final neutral in _question.options.where(
          (item) => item.tags.isEmpty,
        )) {
          updated.remove(neutral.id);
        }
        if (!updated.remove(option.id)) updated.add(option.id);
      }
      _selectedOptionIds = updated;
    });
  }

  Future<void> _configureTts() async {
    if (widget.onSpeak != null) return;
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(.43);
      await _tts.setPitch(1);
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      // L’évaluation reste entièrement utilisable sans synthèse vocale.
    }
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _speakQuestion() async {
    final selected = _question.options
        .where((option) => _selectedOptionIds.contains(option.id))
        .toList(growable: false);
    final text = [
      _question.prompt,
      if (_question.allowMultiple) 'Plusieurs réponses sont possibles.',
      'Choix proposés.',
      for (final option in _question.options) option.label,
      if (selected.isNotEmpty)
        'Choix sélectionnés : ${selected.map((item) => item.label).join(', ')}',
    ].join('. ');
    try {
      if (widget.onSpeak != null) {
        await widget.onSpeak!(text);
      } else {
        await _tts.stop();
        await _tts.speak(text);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La lecture audio n’est pas disponible sur cet appareil.',
          ),
        ),
      );
    }
  }

  Future<void> _confirm() async {
    if (_selectedOptionIds.isEmpty || _saving) return;
    final answers = Map<String, String>.of(_assessment.answers)
      ..[_question.id] = _encodeSelected(_question);
    final now = DateTime.now();
    final next = _engine.nextQuestion(
      widget.pathway,
      answers,
      afterQuestionId: _question.id,
    );
    final evaluated = _engine.evaluate(
      widget.pathway,
      answers,
      context: _assessment.contextSnapshot,
    );
    final previousWasEmergency =
        _assessment.answers.isNotEmpty &&
        _engine
                .evaluate(
                  widget.pathway,
                  _assessment.answers,
                  context: _assessment.contextSnapshot,
                )
                .urgency ==
            AssessmentUrgency.emergency;
    final becameEmergency =
        evaluated.urgency == AssessmentUrgency.emergency &&
        !previousWasEmergency;

    var stopNow = false;
    if (becameEmergency) {
      final decision = await _showEmergencyDecision(
        evaluated.redFlags,
        canContinue: next != null,
      );
      if (!mounted) return;
      stopNow = next == null || decision == _EmergencyDecision.stop;
    }

    setState(() => _saving = true);
    final completed = stopNow || next == null;
    final result = completed ? evaluated : null;
    final updated = _assessment.copyWith(
      status: completed ? 'completed' : 'draft',
      currentQuestionId: completed ? null : next.id,
      clearCurrentQuestion: completed,
      answers: answers,
      result: result,
      updatedAt: now,
      completedAt: completed ? now : null,
    );
    try {
      await widget.repository.save(updated);
      if (!mounted) return;
      setState(() {
        _assessment = updated;
        _saving = false;
        _selectedOptionIds = next == null
            ? <String>{}
            : _decodeSelected(answers[next.id]);
      });
      if (completed && result != null) {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => _AssessmentResultPage(
              assessment: updated,
              result: result,
              onOpenAppointments: widget.onOpenAppointments,
              onSpeak: widget.onSpeak,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assessment = updated;
        _saving = false;
        _selectedOptionIds = next == null
            ? <String>{}
            : _decodeSelected(answers[next.id]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            completed
                ? 'Orientation affichée, mais non synchronisée. Réessayez plus tard.'
                : 'Réponse non synchronisée. Vérifiez la connexion puis confirmez à nouveau.',
          ),
        ),
      );
      if (completed && result != null) {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => _AssessmentResultPage(
              assessment: updated,
              result: result,
              onOpenAppointments: widget.onOpenAppointments,
              onSpeak: widget.onSpeak,
            ),
          ),
        );
      }
    }
  }

  Future<_EmergencyDecision> _showEmergencyDecision(
    List<String> redFlags, {
    required bool canContinue,
  }) async {
    final decision = await showDialog<_EmergencyDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: Icon(
            Icons.emergency_outlined,
            color: Theme.of(dialogContext).colorScheme.error,
            size: 42,
          ),
          title: const Text('Signe d’urgence détecté'),
          content: Text(
            'Une de vos réponses peut correspondre à une urgence médicale. '
            'N’attendez pas si votre état est grave ou s’aggrave : appelez le '
            '116 ou allez aux urgences.'
            '${redFlags.isEmpty ? '' : '\n\nSigne d’alerte : ${redFlags.first}.'}'
            '\n\nVous pouvez afficher l’orientation maintenant ou continuer '
            'les questions sous votre responsabilité.',
          ),
          actions: [
            TextButton.icon(
              key: const Key('assessment-emergency-call'),
              onPressed: () async {
                final opened = await launchUrl(Uri(scheme: 'tel', path: '116'));
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Impossible d’ouvrir le téléphone. Composez manuellement le 116.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.call_outlined),
              label: const Text('Appeler le 116'),
            ),
            if (canContinue)
              TextButton(
                key: const Key('assessment-emergency-continue'),
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_EmergencyDecision.continueAssessment),
                child: const Text('Continuer les questions'),
              ),
            FilledButton.icon(
              key: const Key('assessment-emergency-stop'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_EmergencyDecision.stop),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('Voir l’orientation urgente'),
            ),
          ],
        ),
      ),
    );
    return decision ?? _EmergencyDecision.stop;
  }

  Future<void> _finishAfterEmergency() async {
    if (_saving || _assessment.answers.isEmpty) return;
    final now = DateTime.now();
    final result = _engine.evaluate(
      widget.pathway,
      _assessment.answers,
      context: _assessment.contextSnapshot,
    );
    final updated = _assessment.copyWith(
      status: 'completed',
      clearCurrentQuestion: true,
      result: result,
      updatedAt: now,
      completedAt: now,
    );
    setState(() => _saving = true);
    try {
      await widget.repository.save(updated);
      if (!mounted) return;
      setState(() {
        _assessment = updated;
        _saving = false;
        _selectedOptionIds = {};
      });
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => _AssessmentResultPage(
            assessment: updated,
            result: result,
            onOpenAppointments: widget.onOpenAppointments,
            onSpeak: widget.onSpeak,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assessment = updated;
        _saving = false;
        _selectedOptionIds = {};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orientation affichée, mais non synchronisée. Réessayez plus tard.',
          ),
        ),
      );
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => _AssessmentResultPage(
            assessment: updated,
            result: result,
            onOpenAppointments: widget.onOpenAppointments,
            onSpeak: widget.onSpeak,
          ),
        ),
      );
    }
  }

  Future<void> _goBackOneQuestion() async {
    if (_saving) return;
    final answered = widget.pathway.questions
        .where((question) => _assessment.answers.containsKey(question.id))
        .toList();
    if (answered.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final currentIndex = widget.pathway.questions.indexWhere(
      (item) => item.id == _question.id,
    );
    final previous = answered.lastWhere(
      (item) =>
          widget.pathway.questions.indexWhere((q) => q.id == item.id) <
          currentIndex,
      orElse: () => answered.last,
    );
    final previousIndex = widget.pathway.questions.indexWhere(
      (item) => item.id == previous.id,
    );
    final answers = Map<String, String>.of(_assessment.answers)
      ..removeWhere((questionId, _) {
        final index = widget.pathway.questions.indexWhere(
          (question) => question.id == questionId,
        );
        return index >= previousIndex;
      });
    final updated = _assessment.copyWith(
      status: 'draft',
      currentQuestionId: previous.id,
      answers: answers,
      clearResult: true,
      updatedAt: DateTime.now(),
    );
    setState(() => _saving = true);
    try {
      await widget.repository.save(updated);
      if (!mounted) return;
      setState(() {
        _assessment = updated;
        _selectedOptionIds = {};
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    final progress = _engine.progress(widget.pathway, _assessment.answers);
    final hasEmergencyAnswer =
        _assessment.answers.isNotEmpty &&
        _engine
                .evaluate(
                  widget.pathway,
                  _assessment.answers,
                  context: _assessment.contextSnapshot,
                )
                .urgency ==
            AssessmentUrgency.emergency;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Question précédente',
            onPressed: _saving ? null : _goBackOneQuestion,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(widget.pathway.title),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 18),
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Tooltip(
                  message: 'Progression synchronisée',
                  child: Icon(
                    Icons.cloud_done_outlined,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: progress == 0 ? .04 : progress / 100,
                minHeight: 7,
                color: widget.pathway.color,
                backgroundColor: widget.pathway.color.withValues(alpha: .12),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                child: Row(
                  children: [
                    Text(
                      'Progression : ${math.max(1, progress)} %',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text('Privé', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (hasEmergencyAnswer)
                _EmergencyContinuationBanner(
                  onStop: _saving ? null : _finishAfterEmergency,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: ListView(
                    key: ValueKey(question.id),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: widget.pathway.color.withValues(
                                alpha: .12,
                              ),
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: Icon(
                              question.icon,
                              color: widget.pathway.color,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  question.title,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: widget.pathway.color),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  question.prompt,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                if (question.allowMultiple) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Plusieurs réponses possibles',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: widget.pathway.color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            key: const Key('assessment-read-question'),
                            tooltip: 'Lire la question et les choix',
                            onPressed: _speakQuestion,
                            icon: const Icon(Icons.volume_up_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      for (final option in question.options) ...[
                        _AnswerOptionCard(
                          key: Key('answer-${question.id}-${option.id}'),
                          option: option,
                          color: widget.pathway.color,
                          selected: _selectedOptionIds.contains(option.id),
                          multiSelect: question.allowMultiple,
                          onTap: () => _toggleOption(option),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: FilledButton.icon(
                  key: const Key('assessment-confirm-answer'),
                  onPressed: _selectedOptionIds.isEmpty || _saving
                      ? null
                      : _confirm,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    _selectedOptionIds.isEmpty
                        ? 'Choisissez une réponse'
                        : 'Confirmer et continuer',
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

class _EmergencyContinuationBanner extends StatelessWidget {
  final VoidCallback? onStop;

  const _EmergencyContinuationBanner({required this.onStop});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      key: const Key('assessment-emergency-banner'),
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.emergency_outlined, color: color),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Alerte urgente active. Vous pouvez arrêter à tout moment.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            key: const Key('assessment-emergency-finish-now'),
            onPressed: onStop,
            style: TextButton.styleFrom(foregroundColor: color),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
  }
}

class _AnswerOptionCard extends StatelessWidget {
  final AssessmentOption option;
  final Color color;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  const _AnswerOptionCard({
    super.key,
    required this.option,
    required this.color,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: option.label,
    child: Material(
      color: selected ? color.withValues(alpha: .1) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: BorderSide(
          color: selected ? color : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(option.icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  option.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : multiSelect
                    ? Icons.check_box_outline_blank_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? color : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AssessmentResultPage extends StatefulWidget {
  final SymptomAssessmentRecord assessment;
  final AssessmentResult result;
  final VoidCallback? onOpenAppointments;
  final Future<void> Function(String text)? onSpeak;
  const _AssessmentResultPage({
    required this.assessment,
    required this.result,
    required this.onOpenAppointments,
    required this.onSpeak,
  });

  @override
  State<_AssessmentResultPage> createState() => _AssessmentResultPageState();
}

class _AssessmentResultPageState extends State<_AssessmentResultPage> {
  final FlutterTts _tts = FlutterTts();

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _speak() async {
    final result = widget.result;
    final text = [
      result.urgency.label,
      result.urgency.description,
      if (result.redFlags.isNotEmpty) 'Signes d’alerte.',
      ...result.redFlags,
      'Possibilités compatibles.',
      for (final match in result.matches)
        '${match.title}, ${match.compatibilityLabel}. ${match.explanation}',
      'Prochaines étapes.',
      ...result.nextSteps,
    ].join('. ');
    try {
      if (widget.onSpeak != null) {
        await widget.onSpeak!(text);
      } else {
        await _tts.setLanguage('fr-FR');
        await _tts.setSpeechRate(.43);
        await _tts.speak(text);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lecture audio indisponible.')),
      );
    }
  }

  void _openAppointments() {
    final callback = widget.onOpenAppointments;
    if (callback == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    callback();
  }

  Future<void> _callEmergencyNumber() async {
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: '116'));
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impossible d’ouvrir le téléphone. Composez manuellement le 116.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final urgencyColor = switch (result.urgency) {
      AssessmentUrgency.emergency => Theme.of(context).colorScheme.error,
      AssessmentUrgency.consultationToday => AppColors.warning,
      AssessmentUrgency.consultationSoon => AppColors.primary,
      AssessmentUrgency.selfCare => AppColors.success,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Votre orientation'),
        actions: [
          IconButton(
            tooltip: 'Lire le résultat',
            onPressed: _speak,
            icon: const Icon(Icons.volume_up_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: .1),
              border: Border.all(color: urgencyColor.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.urgency == AssessmentUrgency.emergency
                      ? Icons.emergency_outlined
                      : Icons.health_and_safety_outlined,
                  size: 40,
                  color: urgencyColor,
                ),
                const SizedBox(height: 12),
                Text(
                  result.urgency.label,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: urgencyColor),
                ),
                const SizedBox(height: 7),
                Text(result.urgency.description),
                if (result.urgency == AssessmentUrgency.emergency) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('assessment-call-116'),
                    onPressed: _callEmergencyNumber,
                    style: FilledButton.styleFrom(
                      backgroundColor: urgencyColor,
                    ),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Appeler le 116'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (result.redFlags.isNotEmpty) ...[
            _ResultSection(
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Signes d’alerte détectés',
              items: result.redFlags,
            ),
          ],
          Text(
            'Possibilités à vérifier',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            'La compatibilité est qualitative et non calibrée. Ce n’est ni une probabilité de maladie ni un diagnostic.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final match in result.matches) ...[
            _CompatibilityCard(match: match),
            const SizedBox(height: 10),
          ],
          _ResultSection(
            icon: Icons.route_outlined,
            title: 'Ce que vous devriez faire',
            items: result.nextSteps,
          ),
          if (result.contextNotes.isNotEmpty)
            _ResultSection(
              icon: Icons.manage_accounts_outlined,
              title: 'Données prises en compte',
              items: result.contextNotes,
            ),
          if (result.selfCare.isNotEmpty)
            _ResultSection(
              icon: Icons.self_improvement_outlined,
              title: 'En attendant',
              items: result.selfCare,
            ),
          if (result.pharmacyAdvice.isNotEmpty)
            _ResultSection(
              icon: Icons.local_pharmacy_outlined,
              title: 'Conseils prudents en pharmacie',
              items: result.pharmacyAdvice,
            ),
          const SizedBox(height: 8),
          if (result.urgency != AssessmentUrgency.emergency)
            FilledButton.icon(
              key: const Key('assessment-book-appointment'),
              onPressed: widget.onOpenAppointments == null
                  ? null
                  : _openAppointments,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Prendre rendez-vous'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.history_outlined),
            label: const Text('Retour à mes évaluations'),
          ),
          const SizedBox(height: 18),
          Text(
            'Contenu d’orientation à faire valider par un professionnel de santé avant diffusion clinique. En cas d’aggravation, ne vous fiez pas à ce résultat.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CompatibilityCard extends StatelessWidget {
  final AssessmentMatch match;
  const _CompatibilityCard({required this.match});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  match.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(
                avatar: Icon(
                  match.urgentReason
                      ? Icons.warning_amber_rounded
                      : Icons.fact_check_outlined,
                  size: 18,
                ),
                label: Text(match.compatibilityLabel),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(match.explanation),
        ],
      ),
    ),
  );
}

class _ResultSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;
  const _ResultSection({
    required this.icon,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(items[index])),
                    ],
                  ),
                  if (index < items.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String _newAssessmentId(String patientId, DateTime now) {
  final random = math.Random().nextInt(0xFFFFFF).toRadixString(16);
  return 'assessment-${now.microsecondsSinceEpoch}-$random';
}

DateTime? _dateFrom(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  try {
    final dynamic dynamicValue = value;
    final converted = dynamicValue.toDate();
    return converted is DateTime ? converted : null;
  } catch (_) {
    return null;
  }
}

int _ageAt(DateTime birthDate, DateTime date) {
  var age = date.year - birthDate.year;
  if (date.month < birthDate.month ||
      (date.month == birthDate.month && date.day < birthDate.day)) {
    age--;
  }
  return age;
}

int _ageInMonths(DateTime birthDate, DateTime date) {
  var months = (date.year - birthDate.year) * 12 + date.month - birthDate.month;
  if (date.day < birthDate.day) months--;
  return months;
}

bool _profileIndicatesPregnancy(Map<String, dynamic> profile) {
  final value = profile['pregnancyStatus']?.toString().toLowerCase() ?? '';
  return value.isNotEmpty &&
      !value.contains('non') &&
      !value.contains('not') &&
      !value.contains('aucun');
}

List<String> _stringList(Object? value) => value is Iterable
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
    : const [];

String _shortDate(DateTime date) {
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
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

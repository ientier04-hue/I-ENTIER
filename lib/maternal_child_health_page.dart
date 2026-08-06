import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'diagnostic_assessment_page.dart';
import 'supabase_config.dart';

enum PregnancyReminderCategory {
  consultation,
  ultrasound,
  laboratory,
  vaccination,
  supplementation,
  birthPreparation,
  custom,
}

extension PregnancyReminderCategoryDetails on PregnancyReminderCategory {
  String get databaseValue => switch (this) {
    PregnancyReminderCategory.birthPreparation => 'birth_preparation',
    _ => name,
  };

  String get label => switch (this) {
    PregnancyReminderCategory.consultation => 'Consultation',
    PregnancyReminderCategory.ultrasound => 'Échographie',
    PregnancyReminderCategory.laboratory => 'Analyses',
    PregnancyReminderCategory.vaccination => 'Vaccination',
    PregnancyReminderCategory.supplementation => 'Supplémentation',
    PregnancyReminderCategory.birthPreparation => 'Préparation',
    PregnancyReminderCategory.custom => 'Personnel',
  };

  IconData get icon => switch (this) {
    PregnancyReminderCategory.consultation => Icons.medical_services_outlined,
    PregnancyReminderCategory.ultrasound => Icons.monitor_heart_outlined,
    PregnancyReminderCategory.laboratory => Icons.science_outlined,
    PregnancyReminderCategory.vaccination => Icons.vaccines_outlined,
    PregnancyReminderCategory.supplementation => Icons.medication_outlined,
    PregnancyReminderCategory.birthPreparation => Icons.baby_changing_station,
    PregnancyReminderCategory.custom => Icons.event_note_outlined,
  };

  static PregnancyReminderCategory fromDatabase(Object? value) {
    final name = value?.toString() ?? '';
    return PregnancyReminderCategory.values.firstWhere(
      (item) => item.databaseValue == name,
      orElse: () => PregnancyReminderCategory.custom,
    );
  }
}

class PregnancyProfile {
  final String id;
  final String patientId;
  final DateTime lastMenstrualPeriod;
  final DateTime estimatedDueDate;
  final int gravida;
  final int parity;
  final List<String> previousComplications;
  final Set<String> riskFactors;
  final Set<String> nutritionHabits;
  final String status;

  const PregnancyProfile({
    required this.id,
    required this.patientId,
    required this.lastMenstrualPeriod,
    required this.estimatedDueDate,
    this.gravida = 1,
    this.parity = 0,
    this.previousComplications = const [],
    this.riskFactors = const {},
    this.nutritionHabits = const {},
    this.status = 'active',
  });

  int weekAt(DateTime now) => math.max(
    0,
    math.min(42, now.difference(_dateOnly(lastMenstrualPeriod)).inDays ~/ 7),
  );

  int daysUntilDue(DateTime now) =>
      _dateOnly(estimatedDueDate).difference(_dateOnly(now)).inDays;

  PregnancyProfile copyWith({Set<String>? nutritionHabits}) => PregnancyProfile(
    id: id,
    patientId: patientId,
    lastMenstrualPeriod: lastMenstrualPeriod,
    estimatedDueDate: estimatedDueDate,
    gravida: gravida,
    parity: parity,
    previousComplications: previousComplications,
    riskFactors: riskFactors,
    nutritionHabits: nutritionHabits ?? this.nutritionHabits,
    status: status,
  );

  Map<String, dynamic> toRow() => {
    'pregnancy_id': id,
    'patient_id': patientId,
    'last_menstrual_period': _dateString(lastMenstrualPeriod),
    'estimated_due_date': _dateString(estimatedDueDate),
    'gravida': gravida,
    'parity': parity,
    'previous_complications': previousComplications,
    'risk_factors': riskFactors.toList(growable: false),
    'nutrition_habits': nutritionHabits.toList(growable: false),
    'status': status,
  };

  factory PregnancyProfile.fromRow(Map<String, dynamic> row) =>
      PregnancyProfile(
        id: row['pregnancy_id']?.toString() ?? '',
        patientId: row['patient_id']?.toString() ?? '',
        lastMenstrualPeriod:
            _parseDate(row['last_menstrual_period']) ?? DateTime.now(),
        estimatedDueDate:
            _parseDate(row['estimated_due_date']) ?? DateTime.now(),
        gravida: (row['gravida'] as num?)?.round() ?? 1,
        parity: (row['parity'] as num?)?.round() ?? 0,
        previousComplications: _stringList(row['previous_complications']),
        riskFactors: _stringList(row['risk_factors']).toSet(),
        nutritionHabits: _stringList(row['nutrition_habits']).toSet(),
        status: row['status']?.toString() ?? 'active',
      );
}

class PregnancyReminder {
  final String id;
  final String pregnancyId;
  final String patientId;
  final PregnancyReminderCategory category;
  final String title;
  final String details;
  final DateTime dueAt;
  final bool completed;
  final DateTime? completedAt;

  const PregnancyReminder({
    required this.id,
    required this.pregnancyId,
    required this.patientId,
    required this.category,
    required this.title,
    required this.dueAt,
    this.details = '',
    this.completed = false,
    this.completedAt,
  });

  PregnancyReminder copyWith({
    required bool completed,
    DateTime? completedAt,
  }) => PregnancyReminder(
    id: id,
    pregnancyId: pregnancyId,
    patientId: patientId,
    category: category,
    title: title,
    details: details,
    dueAt: dueAt,
    completed: completed,
    completedAt: completedAt,
  );

  Map<String, dynamic> toRow() => {
    'reminder_id': id,
    'pregnancy_id': pregnancyId,
    'patient_id': patientId,
    'category': category.databaseValue,
    'title': title,
    'details': details,
    'due_at': dueAt.toUtc().toIso8601String(),
    'status': completed ? 'completed' : 'planned',
    'completed_at': completedAt?.toUtc().toIso8601String(),
  };

  factory PregnancyReminder.fromRow(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    return PregnancyReminder(
      id: row['reminder_id']?.toString() ?? '',
      pregnancyId: row['pregnancy_id']?.toString() ?? '',
      patientId: row['patient_id']?.toString() ?? '',
      category: PregnancyReminderCategoryDetails.fromDatabase(row['category']),
      title: row['title']?.toString() ?? '',
      details: row['details']?.toString() ?? '',
      dueAt: _parseDate(row['due_at']) ?? DateTime.now(),
      completed: status == 'completed',
      completedAt: _parseDate(row['completed_at']),
    );
  }
}

class ChildProfile {
  final String id;
  final String guardianPatientId;
  final String firstName;
  final DateTime birthDate;
  final String sex;
  final double? birthWeightKg;
  final double? birthLengthCm;

  const ChildProfile({
    required this.id,
    required this.guardianPatientId,
    required this.firstName,
    required this.birthDate,
    required this.sex,
    this.birthWeightKg,
    this.birthLengthCm,
  });

  int ageInMonths(DateTime now) {
    var months = (now.year - birthDate.year) * 12 + now.month - birthDate.month;
    if (now.day < birthDate.day) months--;
    return math.max(0, months);
  }

  Map<String, dynamic> toRow() => {
    'child_id': id,
    'guardian_patient_id': guardianPatientId,
    'first_name': firstName,
    'birth_date': _dateString(birthDate),
    'sex': sex,
    'birth_weight_kg': birthWeightKg,
    'birth_length_cm': birthLengthCm,
  };

  factory ChildProfile.fromRow(Map<String, dynamic> row) => ChildProfile(
    id: row['child_id']?.toString() ?? '',
    guardianPatientId: row['guardian_patient_id']?.toString() ?? '',
    firstName: row['first_name']?.toString() ?? 'Enfant',
    birthDate: _parseDate(row['birth_date']) ?? DateTime.now(),
    sex: row['sex']?.toString() ?? 'non_precise',
    birthWeightKg: (row['birth_weight_kg'] as num?)?.toDouble(),
    birthLengthCm: (row['birth_length_cm'] as num?)?.toDouble(),
  );
}

class ChildGrowthRecord {
  final String id;
  final String childId;
  final String guardianPatientId;
  final DateTime measuredAt;
  final double weightKg;
  final double heightCm;
  final double? headCircumferenceCm;

  const ChildGrowthRecord({
    required this.id,
    required this.childId,
    required this.guardianPatientId,
    required this.measuredAt,
    required this.weightKg,
    required this.heightCm,
    this.headCircumferenceCm,
  });

  Map<String, dynamic> toRow() => {
    'growth_record_id': id,
    'child_id': childId,
    'guardian_patient_id': guardianPatientId,
    'measured_at': _dateString(measuredAt),
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'head_circumference_cm': headCircumferenceCm,
  };

  factory ChildGrowthRecord.fromRow(Map<String, dynamic> row) =>
      ChildGrowthRecord(
        id: row['growth_record_id']?.toString() ?? '',
        childId: row['child_id']?.toString() ?? '',
        guardianPatientId: row['guardian_patient_id']?.toString() ?? '',
        measuredAt: _parseDate(row['measured_at']) ?? DateTime.now(),
        weightKg: (row['weight_kg'] as num?)?.toDouble() ?? 0,
        heightCm: (row['height_cm'] as num?)?.toDouble() ?? 0,
        headCircumferenceCm: (row['head_circumference_cm'] as num?)?.toDouble(),
      );
}

class ChildVaccinationRecord {
  final String id;
  final String childId;
  final String guardianPatientId;
  final String vaccineCode;
  final String vaccineName;
  final String doseLabel;
  final DateTime dueOn;
  final DateTime? administeredOn;
  final String facilityName;

  const ChildVaccinationRecord({
    required this.id,
    required this.childId,
    required this.guardianPatientId,
    required this.vaccineCode,
    required this.vaccineName,
    required this.doseLabel,
    required this.dueOn,
    this.administeredOn,
    this.facilityName = '',
  });

  bool get completed => administeredOn != null;

  ChildVaccinationRecord copyWith({
    DateTime? administeredOn,
    bool clearAdministration = false,
    String? facilityName,
  }) => ChildVaccinationRecord(
    id: id,
    childId: childId,
    guardianPatientId: guardianPatientId,
    vaccineCode: vaccineCode,
    vaccineName: vaccineName,
    doseLabel: doseLabel,
    dueOn: dueOn,
    administeredOn: clearAdministration ? null : administeredOn,
    facilityName: facilityName ?? this.facilityName,
  );

  Map<String, dynamic> toRow() => {
    'vaccination_record_id': id,
    'child_id': childId,
    'guardian_patient_id': guardianPatientId,
    'vaccine_code': vaccineCode,
    'vaccine_name': vaccineName,
    'dose_label': doseLabel,
    'due_on': _dateString(dueOn),
    'administered_on': administeredOn == null
        ? null
        : _dateString(administeredOn!),
    'facility_name': facilityName,
  };

  factory ChildVaccinationRecord.fromRow(Map<String, dynamic> row) =>
      ChildVaccinationRecord(
        id: row['vaccination_record_id']?.toString() ?? '',
        childId: row['child_id']?.toString() ?? '',
        guardianPatientId: row['guardian_patient_id']?.toString() ?? '',
        vaccineCode: row['vaccine_code']?.toString() ?? '',
        vaccineName: row['vaccine_name']?.toString() ?? '',
        doseLabel: row['dose_label']?.toString() ?? '',
        dueOn: _parseDate(row['due_on']) ?? DateTime.now(),
        administeredOn: _parseDate(row['administered_on']),
        facilityName: row['facility_name']?.toString() ?? '',
      );
}

class MaternalChildSnapshot {
  final PregnancyProfile? pregnancy;
  final List<PregnancyReminder> reminders;
  final List<ChildProfile> children;
  final List<ChildGrowthRecord> growthRecords;
  final List<ChildVaccinationRecord> vaccinationRecords;

  const MaternalChildSnapshot({
    this.pregnancy,
    this.reminders = const [],
    this.children = const [],
    this.growthRecords = const [],
    this.vaccinationRecords = const [],
  });
}

abstract class MaternalChildRepository {
  Future<MaternalChildSnapshot> load(String patientId);
  Future<void> savePregnancy(PregnancyProfile profile);
  Future<void> saveReminder(PregnancyReminder reminder);
  Future<void> saveChild(ChildProfile child);
  Future<void> saveGrowth(ChildGrowthRecord record);
  Future<void> saveVaccination(ChildVaccinationRecord record);
}

class SupabaseMaternalChildRepository implements MaternalChildRepository {
  SupabaseClient get _client => SupabaseConfig.client;

  @override
  Future<MaternalChildSnapshot> load(String patientId) async {
    final responses = await Future.wait<dynamic>([
      _client
          .schema('ientier')
          .from('pregnancy_profiles')
          .select()
          .eq('patient_id', patientId)
          .eq('status', 'active')
          .order('updated_at', ascending: false)
          .limit(1),
      _client
          .schema('ientier')
          .from('pregnancy_reminders')
          .select()
          .eq('patient_id', patientId)
          .order('due_at'),
      _client
          .schema('ientier')
          .from('child_profiles')
          .select()
          .eq('guardian_patient_id', patientId)
          .order('birth_date', ascending: false),
      _client
          .schema('ientier')
          .from('child_growth_records')
          .select()
          .eq('guardian_patient_id', patientId)
          .order('measured_at', ascending: false),
      _client
          .schema('ientier')
          .from('child_vaccination_records')
          .select()
          .eq('guardian_patient_id', patientId)
          .order('due_on'),
    ]);

    List<Map<String, dynamic>> rows(int index) =>
        List<Map<String, dynamic>>.from(responses[index] as List);
    final pregnancyRows = rows(0);
    return MaternalChildSnapshot(
      pregnancy: pregnancyRows.isEmpty
          ? null
          : PregnancyProfile.fromRow(pregnancyRows.first),
      reminders: rows(1).map(PregnancyReminder.fromRow).toList(),
      children: rows(2).map(ChildProfile.fromRow).toList(),
      growthRecords: rows(3).map(ChildGrowthRecord.fromRow).toList(),
      vaccinationRecords: rows(4).map(ChildVaccinationRecord.fromRow).toList(),
    );
  }

  @override
  Future<void> savePregnancy(PregnancyProfile profile) => _client
      .schema('ientier')
      .from('pregnancy_profiles')
      .upsert(profile.toRow(), onConflict: 'pregnancy_id');

  @override
  Future<void> saveReminder(PregnancyReminder reminder) => _client
      .schema('ientier')
      .from('pregnancy_reminders')
      .upsert(reminder.toRow(), onConflict: 'reminder_id');

  @override
  Future<void> saveChild(ChildProfile child) => _client
      .schema('ientier')
      .from('child_profiles')
      .upsert(child.toRow(), onConflict: 'child_id');

  @override
  Future<void> saveGrowth(ChildGrowthRecord record) => _client
      .schema('ientier')
      .from('child_growth_records')
      .upsert(record.toRow(), onConflict: 'growth_record_id');

  @override
  Future<void> saveVaccination(ChildVaccinationRecord record) => _client
      .schema('ientier')
      .from('child_vaccination_records')
      .upsert(record.toRow(), onConflict: 'vaccination_record_id');
}

class MaternalHealthScore {
  final int total;
  final int medicalFollowUp;
  final int examinations;
  final int nutrition;
  final int riskProtection;
  final bool needsReinforcedSupport;

  const MaternalHealthScore({
    required this.total,
    required this.medicalFollowUp,
    required this.examinations,
    required this.nutrition,
    required this.riskProtection,
    required this.needsReinforcedSupport,
  });
}

MaternalHealthScore calculateMaternalHealthScore(
  PregnancyProfile pregnancy,
  Iterable<PregnancyReminder> reminders, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final relevant = reminders
      .where((item) => !item.dueAt.isAfter(today.add(const Duration(days: 7))))
      .toList();
  int sectionScore(PregnancyReminderCategory category, int maximum) {
    final items = relevant.where((item) => item.category == category).toList();
    if (items.isEmpty) return maximum ~/ 2;
    final completed = items.where((item) => item.completed).length;
    return (maximum * completed / items.length).round();
  }

  final medical = sectionScore(PregnancyReminderCategory.consultation, 35);
  final examinations = math.min(
    25,
    sectionScore(PregnancyReminderCategory.ultrasound, 12) +
        sectionScore(PregnancyReminderCategory.laboratory, 13),
  );
  final nutrition = (20 * pregnancy.nutritionHabits.length / 3).round().clamp(
    0,
    20,
  );
  final riskProtection = math.max(4, 20 - pregnancy.riskFactors.length * 4);
  final total = (medical + examinations + nutrition + riskProtection).clamp(
    0,
    100,
  );
  final highRisk = pregnancy.riskFactors.any(_highRiskFactorIds.contains);
  return MaternalHealthScore(
    total: total,
    medicalFollowUp: medical,
    examinations: examinations,
    nutrition: nutrition,
    riskProtection: riskProtection,
    needsReinforcedSupport: total < 60 || highRisk,
  );
}

List<PregnancyReminder> buildPregnancyCalendar(PregnancyProfile pregnancy) {
  DateTime atWeek(int week) =>
      pregnancy.lastMenstrualPeriod.add(Duration(days: week * 7));

  PregnancyReminder reminder(
    String suffix,
    PregnancyReminderCategory category,
    String title,
    int week,
    String details,
  ) => PregnancyReminder(
    id: '${pregnancy.id}-$suffix',
    pregnancyId: pregnancy.id,
    patientId: pregnancy.patientId,
    category: category,
    title: title,
    dueAt: atWeek(week),
    details: details,
  );

  final contacts = <int>[12, 20, 26, 30, 34, 36, 38, 40];
  return [
    for (var index = 0; index < contacts.length; index++)
      reminder(
        'contact-${index + 1}',
        PregnancyReminderCategory.consultation,
        'Contact prénatal ${index + 1}',
        contacts[index],
        'Repère OMS indicatif à confirmer avec votre sage-femme ou médecin.',
      ),
    reminder(
      'analyses-initiales',
      PregnancyReminderCategory.laboratory,
      'Bilan prénatal initial',
      10,
      'Tension et analyses adaptées par un professionnel.',
    ),
    reminder(
      'echographie-avant-24',
      PregnancyReminderCategory.ultrasound,
      'Échographie avant 24 semaines',
      20,
      'Date exacte à fixer avec l’équipe de soins.',
    ),
    reminder(
      'analyses-suivi',
      PregnancyReminderCategory.laboratory,
      'Analyses de suivi',
      28,
      'Examens à adapter selon le dossier et les résultats antérieurs.',
    ),
    reminder(
      'vaccination',
      PregnancyReminderCategory.vaccination,
      'Vérifier la vaccination maternelle',
      20,
      'Le besoin dépend du carnet vaccinal et des recommandations nationales.',
    ),
    reminder(
      'supplementation',
      PregnancyReminderCategory.supplementation,
      'Faire le point sur la supplémentation',
      8,
      'Fer, acide folique ou autre supplément uniquement selon l’avis reçu.',
    ),
    reminder(
      'naissance',
      PregnancyReminderCategory.birthPreparation,
      'Préparer le plan de naissance et d’urgence',
      32,
      'Choisir la maternité, le trajet, les contacts et une solution de secours.',
    ),
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
}

List<ChildVaccinationRecord> buildChildVaccinationCalendar(ChildProfile child) {
  DateTime weeks(int value) => child.birthDate.add(Duration(days: value * 7));
  DateTime months(int value) => DateTime(
    child.birthDate.year,
    child.birthDate.month + value,
    child.birthDate.day,
  );
  ChildVaccinationRecord item(
    String code,
    String name,
    String dose,
    DateTime due,
  ) => ChildVaccinationRecord(
    id: '${child.id}-$code-$dose',
    childId: child.id,
    guardianPatientId: child.guardianPatientId,
    vaccineCode: code,
    vaccineName: name,
    doseLabel: dose,
    dueOn: due,
  );

  return [
    item('bcg', 'BCG', 'Naissance', child.birthDate),
    item('polio', 'Poliomyélite', 'Dose naissance', child.birthDate),
    for (final entry in const [
      (6, 'Dose 1'),
      (10, 'Dose 2'),
      (14, 'Dose 3'),
    ]) ...[
      item('penta', 'Pentavalent', entry.$2, weeks(entry.$1)),
      item('polio', 'Poliomyélite', entry.$2, weeks(entry.$1)),
      item('pcv', 'Pneumocoque', entry.$2, weeks(entry.$1)),
    ],
    item('rota', 'Rotavirus', 'Dose 1', weeks(6)),
    item('rota', 'Rotavirus', 'Dose 2', weeks(10)),
    item('rr', 'Rougeole–rubéole', 'Dose 1', months(9)),
    item('rr', 'Rougeole–rubéole', 'Dose 2', months(15)),
    item('dtc', 'Diphtérie–tétanos–coqueluche', 'Rappel 2–5 ans', months(24)),
  ]..sort((a, b) => a.dueOn.compareTo(b.dueOn));
}

List<String> detectChildHealthRisks(
  ChildProfile child,
  Iterable<ChildGrowthRecord> growth,
  Iterable<ChildVaccinationRecord> vaccinations, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final risks = <String>[];
  final records = growth.toList()
    ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
  if (child.birthWeightKg != null && child.birthWeightKg! < 2.5) {
    risks.add(
      'Poids de naissance inférieur à 2,5 kg : suivi renforcé conseillé.',
    );
  }
  if (records.isEmpty ||
      today.difference(records.first.measuredAt).inDays > 90) {
    risks.add('Aucune mesure de croissance récente depuis plus de 3 mois.');
  }
  if (records.length >= 2) {
    final latest = records[0];
    final previous = records[1];
    if (latest.weightKg < previous.weightKg * .95) {
      risks.add(
        'Baisse de poids enregistrée : faites vérifier la courbe rapidement.',
      );
    }
  }
  final overdue = vaccinations.where(
    (item) => !item.completed && item.dueOn.isBefore(today),
  );
  if (overdue.isNotEmpty) {
    risks.add('${overdue.length} vaccin(s) à vérifier ou à rattraper.');
  }
  return risks;
}

class MaternalChildHealthPage extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientProfile;
  final MaternalChildRepository? repository;
  final MaternalChildSnapshot? initialSnapshot;
  final DateTime? now;
  final VoidCallback? onOpenCareDirectory;
  final VoidCallback? onOpenEmergencyTransport;

  const MaternalChildHealthPage({
    super.key,
    required this.patientId,
    required this.patientProfile,
    this.repository,
    this.initialSnapshot,
    this.now,
    this.onOpenCareDirectory,
    this.onOpenEmergencyTransport,
  });

  @override
  State<MaternalChildHealthPage> createState() =>
      _MaternalChildHealthPageState();
}

class _MaternalChildHealthPageState extends State<MaternalChildHealthPage> {
  late final MaternalChildRepository? _repository =
      widget.repository ??
      (SupabaseConfig.isInitialized ? SupabaseMaternalChildRepository() : null);
  MaternalChildSnapshot _snapshot = const MaternalChildSnapshot();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _section = 0;
  String? _selectedChildId;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot!;
      _selectedChildId = _snapshot.children.firstOrNull?.id;
      _loading = false;
    } else {
      _reload();
    }
  }

  Future<void> _reload() async {
    final repository = _repository;
    if (repository == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await repository.load(widget.patientId);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _selectedChildId ??= snapshot.children.firstOrNull?.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Le dossier Maman & Bébé ne peut pas être synchronisé pour le moment.';
      });
    }
  }

  Future<void> _persist(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      if (_repository != null) await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enregistrement impossible. Vérifiez la connexion.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editPregnancy() async {
    final result = await showModalBottomSheet<PregnancyProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PregnancyProfileForm(
        patientId: widget.patientId,
        initial: _snapshot.pregnancy,
        now: _now,
      ),
    );
    if (result == null || !mounted) return;
    final isNew = _snapshot.pregnancy == null;
    await _persist(() async {
      final repository = _repository;
      if (repository != null) {
        await repository.savePregnancy(result);
        if (isNew) {
          for (final reminder in buildPregnancyCalendar(result)) {
            await repository.saveReminder(reminder);
          }
        }
      } else {
        setState(() {
          _snapshot = MaternalChildSnapshot(
            pregnancy: result,
            reminders: isNew
                ? buildPregnancyCalendar(result)
                : _snapshot.reminders,
            children: _snapshot.children,
            growthRecords: _snapshot.growthRecords,
            vaccinationRecords: _snapshot.vaccinationRecords,
          );
        });
      }
    });
  }

  Future<void> _toggleReminder(PregnancyReminder reminder, bool completed) =>
      _persist(() async {
        final updated = reminder.copyWith(
          completed: completed,
          completedAt: completed ? _now : null,
        );
        if (_repository != null) {
          await _repository.saveReminder(updated);
        } else {
          setState(() {
            _snapshot = MaternalChildSnapshot(
              pregnancy: _snapshot.pregnancy,
              reminders: [
                for (final item in _snapshot.reminders)
                  if (item.id == reminder.id) updated else item,
              ],
              children: _snapshot.children,
              growthRecords: _snapshot.growthRecords,
              vaccinationRecords: _snapshot.vaccinationRecords,
            );
          });
        }
      });

  Future<void> _toggleNutrition(String id, bool enabled) async {
    final pregnancy = _snapshot.pregnancy;
    if (pregnancy == null) return;
    final habits = Set<String>.of(pregnancy.nutritionHabits);
    enabled ? habits.add(id) : habits.remove(id);
    final updated = pregnancy.copyWith(nutritionHabits: habits);
    await _persist(() async {
      if (_repository != null) {
        await _repository.savePregnancy(updated);
      } else {
        setState(() {
          _snapshot = MaternalChildSnapshot(
            pregnancy: updated,
            reminders: _snapshot.reminders,
            children: _snapshot.children,
            growthRecords: _snapshot.growthRecords,
            vaccinationRecords: _snapshot.vaccinationRecords,
          );
        });
      }
    });
  }

  Future<void> _startPregnancyAssessment() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DiagnosticAssessmentPage(
        patientId: widget.patientId,
        patientProfile: {...widget.patientProfile, 'pregnancyStatus': 'Oui'},
        initialPathwayId: 'pregnancy',
      ),
    ),
  );

  Future<void> _callEmergency() async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: '116'));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Composez manuellement le 116.')),
      );
    }
  }

  Future<void> _addChild() async {
    final child = await showModalBottomSheet<ChildProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ChildProfileForm(patientId: widget.patientId, now: _now),
    );
    if (child == null || !mounted) return;
    await _persist(() async {
      final vaccines = buildChildVaccinationCalendar(child);
      if (_repository != null) {
        await _repository.saveChild(child);
        for (final vaccine in vaccines) {
          await _repository.saveVaccination(vaccine);
        }
      } else {
        setState(() {
          _snapshot = MaternalChildSnapshot(
            pregnancy: _snapshot.pregnancy,
            reminders: _snapshot.reminders,
            children: [..._snapshot.children, child],
            growthRecords: _snapshot.growthRecords,
            vaccinationRecords: [..._snapshot.vaccinationRecords, ...vaccines],
          );
        });
      }
      _selectedChildId = child.id;
    });
  }

  Future<void> _addGrowth(ChildProfile child) async {
    final record = await showModalBottomSheet<ChildGrowthRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GrowthForm(child: child, now: _now),
    );
    if (record == null || !mounted) return;
    await _persist(() async {
      if (_repository != null) {
        await _repository.saveGrowth(record);
      } else {
        setState(() {
          _snapshot = MaternalChildSnapshot(
            pregnancy: _snapshot.pregnancy,
            reminders: _snapshot.reminders,
            children: _snapshot.children,
            growthRecords: [record, ..._snapshot.growthRecords],
            vaccinationRecords: _snapshot.vaccinationRecords,
          );
        });
      }
    });
  }

  Future<void> _toggleVaccination(
    ChildVaccinationRecord vaccine,
    bool completed,
  ) => _persist(() async {
    final updated = vaccine.copyWith(
      administeredOn: completed ? _now : null,
      clearAdministration: !completed,
    );
    if (_repository != null) {
      await _repository.saveVaccination(updated);
    } else {
      setState(() {
        _snapshot = MaternalChildSnapshot(
          pregnancy: _snapshot.pregnancy,
          reminders: _snapshot.reminders,
          children: _snapshot.children,
          growthRecords: _snapshot.growthRecords,
          vaccinationRecords: [
            for (final item in _snapshot.vaccinationRecords)
              if (item.id == vaccine.id) updated else item,
          ],
        );
      });
    }
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Maman & Bébé'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _repository == null ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Column(
      children: [
        _SectionNavigation(
          selected: _section,
          onSelected: (value) => setState(() => _section = value),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    key: ValueKey('maternal-section-$_section'),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      if (_error != null) ...[
                        _FeedbackCard(
                          icon: Icons.cloud_off_outlined,
                          title: 'Mode hors connexion',
                          message: _error!,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_section == 0) _buildOverview(),
                      if (_section == 1) _buildPregnancy(),
                      if (_section == 2) _buildChildren(),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _buildOverview() {
    final pregnancy = _snapshot.pregnancy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          pregnancy: pregnancy,
          now: _now,
          onCreateProfile: _editPregnancy,
        ),
        const SizedBox(height: 16),
        _DangerAlertCard(
          onAssessment: _startPregnancyAssessment,
          onEmergencyCall: _callEmergency,
          onTransport: widget.onOpenEmergencyTransport,
        ),
        if (pregnancy != null) ...[
          const SizedBox(height: 16),
          _HealthScoreCard(
            score: calculateMaternalHealthScore(
              pregnancy,
              _snapshot.reminders,
              now: _now,
            ),
          ),
          const SizedBox(height: 16),
          _UpcomingReminders(
            reminders: _snapshot.reminders,
            now: _now,
            onChanged: _toggleReminder,
          ),
        ],
        const SizedBox(height: 16),
        _CareNetworkCard(onOpenDirectory: widget.onOpenCareDirectory),
      ],
    );
  }

  Widget _buildPregnancy() {
    final pregnancy = _snapshot.pregnancy;
    if (pregnancy == null) {
      return _EmptyAction(
        icon: Icons.pregnant_woman_outlined,
        title: 'Créez votre profil grossesse',
        message:
            'La date des dernières règles permet de calculer le terme et de préparer votre calendrier.',
        action: 'Créer mon profil',
        onTap: _editPregnancy,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Mon suivi de grossesse',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _editPregnancy,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PregnancyProgressCard(pregnancy: pregnancy, now: _now),
        const SizedBox(height: 16),
        _RiskFactorCard(pregnancy: pregnancy),
        const SizedBox(height: 16),
        _NutritionChecklist(
          selected: pregnancy.nutritionHabits,
          onChanged: _toggleNutrition,
        ),
        const SizedBox(height: 20),
        Text(
          'Calendrier intelligent',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Repères indicatifs à confirmer avec votre équipe de soins.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final reminder in _snapshot.reminders)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReminderTile(
              reminder: reminder,
              now: _now,
              onChanged: (value) => _toggleReminder(reminder, value),
            ),
          ),
      ],
    );
  }

  Widget _buildChildren() {
    if (_snapshot.children.isEmpty) {
      return _EmptyAction(
        icon: Icons.child_care_outlined,
        title: 'Ajoutez un enfant de 0 à 5 ans',
        message:
            'Centralisez son carnet vaccinal, ses mesures de croissance et ses repères nutritionnels.',
        action: 'Ajouter un enfant',
        onTap: _addChild,
      );
    }
    final selected = _snapshot.children.firstWhere(
      (child) => child.id == _selectedChildId,
      orElse: () => _snapshot.children.first,
    );
    final growth =
        _snapshot.growthRecords
            .where((item) => item.childId == selected.id)
            .toList()
          ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    final vaccines =
        _snapshot.vaccinationRecords
            .where((item) => item.childId == selected.id)
            .toList()
          ..sort((a, b) => a.dueOn.compareTo(b.dueOn));
    final risks = detectChildHealthRisks(selected, growth, vaccines, now: _now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final child in _snapshot.children)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: child.id == selected.id,
                          label: Text(child.firstName),
                          avatar: const Icon(Icons.child_care, size: 18),
                          onSelected: (_) =>
                              setState(() => _selectedChildId = child.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ajouter un enfant',
              onPressed: _addChild,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ChildSummaryCard(child: selected, now: _now, risks: risks),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Croissance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              key: const Key('maternal-add-growth'),
              onPressed: () => _addGrowth(selected),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle mesure'),
            ),
          ],
        ),
        _GrowthCard(records: growth),
        const SizedBox(height: 18),
        Text(
          'Conseils nutritionnels',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        _NutritionAdvice(ageMonths: selected.ageInMonths(_now)),
        const SizedBox(height: 18),
        Text(
          'Carnet de vaccination',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Calendrier indicatif Haïti : faites valider chaque dose par un centre de vaccination.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        for (final vaccine in vaccines)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _VaccineTile(
              vaccine: vaccine,
              now: _now,
              onChanged: (value) => _toggleVaccination(vaccine, value),
            ),
          ),
      ],
    );
  }
}

class _SectionNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;

  const _SectionNavigation({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          icon: Icon(Icons.home_outlined),
          label: Text('Aperçu'),
        ),
        ButtonSegment(
          value: 1,
          icon: Icon(Icons.pregnant_woman_outlined),
          label: Text('Grossesse'),
        ),
        ButtonSegment(
          value: 2,
          icon: Icon(Icons.child_care_outlined),
          label: Text('Enfant 0–5 ans'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onSelected(values.first),
    ),
  );
}

class _HeroCard extends StatelessWidget {
  final PregnancyProfile? pregnancy;
  final DateTime now;
  final VoidCallback onCreateProfile;

  const _HeroCard({
    required this.pregnancy,
    required this.now,
    required this.onCreateProfile,
  });

  @override
  Widget build(BuildContext context) {
    final week = pregnancy?.weekAt(now);
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE8EF), Color(0xFFFFF7EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFF5CCD7)),
      ),
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.pregnant_woman_rounded,
              color: Color(0xFFC23D68),
              size: 38,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pregnancy == null
                      ? 'Votre parcours Maman & Bébé'
                      : 'Semaine ${week!} de grossesse',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 5),
                Text(
                  pregnancy == null
                      ? 'Un suivi simple, personnel et relié à vos services de santé.'
                      : 'Terme prévu le ${_formatDate(pregnancy!.estimatedDueDate)}.',
                ),
                if (pregnancy == null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('maternal-create-pregnancy'),
                    onPressed: onCreateProfile,
                    child: const Text('Créer mon profil grossesse'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerAlertCard extends StatelessWidget {
  final VoidCallback onAssessment;
  final VoidCallback onEmergencyCall;
  final VoidCallback? onTransport;

  const _DangerAlertCard({
    required this.onAssessment,
    required this.onEmergencyCall,
    required this.onTransport,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF3F2),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Alerte grossesse',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Saignement, douleur sévère, fièvre, fort mal de tête, vision trouble ou diminution des mouvements du bébé ? Évaluez la situation sans attendre.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('maternal-pregnancy-alert'),
                onPressed: onAssessment,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Évaluer mes symptômes'),
              ),
              OutlinedButton.icon(
                onPressed: onEmergencyCall,
                icon: const Icon(Icons.call_outlined),
                label: const Text('Appeler le 116'),
              ),
              if (onTransport != null)
                OutlinedButton.icon(
                  key: const Key('maternal-emergency-transport'),
                  onPressed: onTransport,
                  icon: const Icon(Icons.airport_shuttle_outlined),
                  label: const Text('Transport médical'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _HealthScoreCard extends StatelessWidget {
  final MaternalHealthScore score;
  const _HealthScoreCard({required this.score});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score.total / 100,
                  strokeWidth: 9,
                  backgroundColor: AppColors.border,
                  color: score.needsReinforcedSupport
                      ? const Color(0xFFE77C22)
                      : AppColors.success,
                ),
                Text(
                  '${score.total}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score Santé Maman & Bébé',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  score.needsReinforcedSupport
                      ? 'Un accompagnement renforcé est recommandé.'
                      : 'Votre suivi enregistré est globalement à jour.',
                  style: TextStyle(
                    color: score.needsReinforcedSupport
                        ? AppColors.warning
                        : AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Suivi ${score.medicalFollowUp}/35 • Examens ${score.examinations}/25 • Nutrition ${score.nutrition}/20 • Risques ${score.riskProtection}/20',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _UpcomingReminders extends StatelessWidget {
  final List<PregnancyReminder> reminders;
  final DateTime now;
  final Future<void> Function(PregnancyReminder, bool) onChanged;

  const _UpcomingReminders({
    required this.reminders,
    required this.now,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final upcoming = reminders
        .where((item) => !item.completed)
        .take(3)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prochaines étapes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (upcoming.isEmpty)
              const Text('Toutes les étapes enregistrées sont terminées.')
            else
              for (final reminder in upcoming)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reminder.completed,
                  onChanged: (value) => onChanged(reminder, value == true),
                  secondary: Icon(
                    reminder.category.icon,
                    color: AppColors.primary,
                  ),
                  title: Text(reminder.title),
                  subtitle: Text(_dueLabel(reminder.dueAt, now)),
                ),
          ],
        ),
      ),
    );
  }
}

class _CareNetworkCard extends StatelessWidget {
  final VoidCallback? onOpenDirectory;
  const _CareNetworkCard({required this.onOpenDirectory});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.primarySoft,
            child: Icon(Icons.diversity_1_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Votre réseau de soins',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                const Text(
                  'Sages-femmes, médecins, centres de santé et maternités vérifiés.',
                ),
              ],
            ),
          ),
          if (onOpenDirectory != null)
            IconButton(
              tooltip: 'Ouvrir l’annuaire',
              onPressed: onOpenDirectory,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
        ],
      ),
    ),
  );
}

class _PregnancyProgressCard extends StatelessWidget {
  final PregnancyProfile pregnancy;
  final DateTime now;
  const _PregnancyProgressCard({required this.pregnancy, required this.now});

  @override
  Widget build(BuildContext context) {
    final week = pregnancy.weekAt(now);
    final progress = (week / 40).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Semaine $week sur 40',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${pregnancy.daysUntilDue(now)} jours avant le terme',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 12),
            Text(_weeklyPregnancyMessage(week)),
            const SizedBox(height: 8),
            Text(
              'DDR : ${_formatDate(pregnancy.lastMenstrualPeriod)} • Terme : ${_formatDate(pregnancy.estimatedDueDate)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskFactorCard extends StatelessWidget {
  final PregnancyProfile pregnancy;
  const _RiskFactorCard({required this.pregnancy});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Antécédents & facteurs de risque',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (pregnancy.riskFactors.isEmpty &&
              pregnancy.previousComplications.isEmpty)
            const Text(
              'Aucun facteur déclaré. Continuez le suivi prénatal régulier.',
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in pregnancy.riskFactors)
                  Chip(
                    avatar: const Icon(Icons.priority_high, size: 17),
                    label: Text(_riskLabels[id] ?? id),
                    backgroundColor: const Color(0xFFFFF0E6),
                  ),
              ],
            ),
            if (pregnancy.previousComplications.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Antécédents : ${pregnancy.previousComplications.join(', ')}',
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

class _NutritionChecklist extends StatelessWidget {
  final Set<String> selected;
  final Future<void> Function(String, bool) onChanged;

  const _NutritionChecklist({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrition & protection',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            'Cochez ce que vous suivez actuellement.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final item in const {
            'balancedMeals': 'Repas variés et réguliers',
            'hydration': 'Hydratation suffisante',
            'supplements': 'Suppléments validés par un professionnel',
          }.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected.contains(item.key),
              onChanged: (value) => onChanged(item.key, value == true),
              title: Text(item.value),
            ),
        ],
      ),
    ),
  );
}

class _ReminderTile extends StatelessWidget {
  final PregnancyReminder reminder;
  final DateTime now;
  final ValueChanged<bool> onChanged;

  const _ReminderTile({
    required this.reminder,
    required this.now,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: CheckboxListTile(
      value: reminder.completed,
      onChanged: (value) => onChanged(value == true),
      secondary: CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        child: Icon(reminder.category.icon, color: AppColors.primary, size: 21),
      ),
      title: Text(reminder.title),
      subtitle: Text(
        '${reminder.category.label} • ${_dueLabel(reminder.dueAt, now)}\n${reminder.details}',
      ),
      isThreeLine: true,
    ),
  );
}

class _ChildSummaryCard extends StatelessWidget {
  final ChildProfile child;
  final DateTime now;
  final List<String> risks;

  const _ChildSummaryCard({
    required this.child,
    required this.now,
    required this.risks,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE9F8F3),
                child: Icon(Icons.child_care, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.firstName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${child.ageInMonths(now)} mois • Né(e) le ${_formatDate(child.birthDate)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (risks.isNotEmpty) ...[
            const Divider(height: 26),
            Text(
              'Points à vérifier',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            for (final risk in risks)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 19,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 7),
                    Expanded(child: Text(risk)),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class _GrowthCard extends StatelessWidget {
  final List<ChildGrowthRecord> records;
  const _GrowthCard({required this.records});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: records.isEmpty
          ? const Text(
              'Aucune mesure. Ajoutez le poids et la taille pour commencer la courbe.',
            )
          : Column(
              children: [
                for (final record in records.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.monitor_weight_outlined,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      '${_number(record.weightKg)} kg  •  ${_number(record.heightCm)} cm',
                    ),
                    subtitle: Text(
                      '${_formatDate(record.measuredAt)}${record.headCircumferenceCm == null ? '' : ' • Tête ${_number(record.headCircumferenceCm!)} cm'}',
                    ),
                  ),
                const Divider(),
                Text(
                  'La tendance doit être interprétée sur les courbes OMS par un professionnel de santé.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    ),
  );
}

class _NutritionAdvice extends StatelessWidget {
  final int ageMonths;
  const _NutritionAdvice({required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final advice = switch (ageMonths) {
      < 6 =>
        'L’allaitement exclusif est recommandé pendant les six premiers mois. Demandez de l’aide rapidement en cas de difficulté.',
      < 9 =>
        'Introduisez à 6 mois de petites quantités d’aliments sûrs et riches en nutriments, 2 à 3 fois par jour, tout en poursuivant l’allaitement.',
      < 24 =>
        'Proposez 3 à 4 repas variés, avec 1 à 2 collations selon les besoins. Continuez l’allaitement jusqu’à 2 ans ou au-delà.',
      _ =>
        'Proposez des repas familiaux variés, de l’eau potable et limitez boissons sucrées et aliments très transformés.',
    };
    return Card(
      color: const Color(0xFFEFFAF6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.restaurant_outlined, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(child: Text(advice)),
          ],
        ),
      ),
    );
  }
}

class _VaccineTile extends StatelessWidget {
  final ChildVaccinationRecord vaccine;
  final DateTime now;
  final ValueChanged<bool> onChanged;

  const _VaccineTile({
    required this.vaccine,
    required this.now,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final overdue =
        !vaccine.completed && vaccine.dueOn.isBefore(_dateOnly(now));
    return Card(
      child: CheckboxListTile(
        value: vaccine.completed,
        onChanged: (value) => onChanged(value == true),
        secondary: Icon(
          vaccine.completed ? Icons.verified_rounded : Icons.vaccines_outlined,
          color: vaccine.completed
              ? AppColors.success
              : overdue
              ? Theme.of(context).colorScheme.error
              : AppColors.primary,
        ),
        title: Text('${vaccine.vaccineName} — ${vaccine.doseLabel}'),
        subtitle: Text(
          vaccine.completed
              ? 'Reçu le ${_formatDate(vaccine.administeredOn!)}'
              : '${overdue ? 'À vérifier maintenant' : 'Prévu'} • ${_formatDate(vaccine.dueOn)}',
        ),
      ),
    );
  }
}

class _EmptyAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;

  const _EmptyAction({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    ),
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
    child: ListTile(
      leading: Icon(icon, color: AppColors.warning),
      title: Text(title),
      subtitle: Text(message),
    ),
  );
}

class _PregnancyProfileForm extends StatefulWidget {
  final String patientId;
  final PregnancyProfile? initial;
  final DateTime now;

  const _PregnancyProfileForm({
    required this.patientId,
    required this.initial,
    required this.now,
  });

  @override
  State<_PregnancyProfileForm> createState() => _PregnancyProfileFormState();
}

class _PregnancyProfileFormState extends State<_PregnancyProfileForm> {
  late DateTime _lastPeriod =
      widget.initial?.lastMenstrualPeriod ??
      widget.now.subtract(const Duration(days: 70));
  late DateTime _dueDate =
      widget.initial?.estimatedDueDate ??
      _lastPeriod.add(const Duration(days: 280));
  late final TextEditingController _gravida = TextEditingController(
    text: '${widget.initial?.gravida ?? 1}',
  );
  late final TextEditingController _parity = TextEditingController(
    text: '${widget.initial?.parity ?? 0}',
  );
  late final TextEditingController _history = TextEditingController(
    text: widget.initial?.previousComplications.join(', ') ?? '',
  );
  late final Set<String> _risks = Set.of(
    widget.initial?.riskFactors ?? const {},
  );

  @override
  void dispose() {
    _gravida.dispose();
    _parity.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _pickLastPeriod() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _lastPeriod,
      firstDate: widget.now.subtract(const Duration(days: 315)),
      lastDate: widget.now,
      helpText: 'Date des dernières règles',
    );
    if (value == null) return;
    setState(() {
      _lastPeriod = value;
      _dueDate = value.add(const Duration(days: 280));
    });
  }

  void _submit() {
    final gravida = int.tryParse(_gravida.text) ?? 1;
    final parity = int.tryParse(_parity.text) ?? 0;
    if (gravida < 1 || parity < 0 || parity > gravida) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vérifiez le nombre de grossesses et d’accouchements.'),
        ),
      );
      return;
    }
    final history = _history.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      PregnancyProfile(
        id:
            widget.initial?.id ??
            'pregnancy-${widget.patientId}-${widget.now.microsecondsSinceEpoch}',
        patientId: widget.patientId,
        lastMenstrualPeriod: _lastPeriod,
        estimatedDueDate: _dueDate,
        gravida: gravida,
        parity: parity,
        previousComplications: history,
        riskFactors: _risks,
        nutritionHabits: widget.initial?.nutritionHabits ?? const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null
                ? 'Créer le profil grossesse'
                : 'Modifier le profil grossesse',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          ListTile(
            key: const Key('pregnancy-last-period'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Date des dernières règles'),
            subtitle: Text(_formatDate(_lastPeriod)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickLastPeriod,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: const Text('Terme prévu'),
            subtitle: Text('${_formatDate(_dueDate)} • calculé à 40 semaines'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _gravida,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Grossesses'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _parity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Accouchements'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _history,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Antécédents ou complications',
              hintText: 'Séparez les éléments par une virgule',
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Facteurs de risque connus',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _riskLabels.entries)
                FilterChip(
                  selected: _risks.contains(item.key),
                  label: Text(item.value),
                  onSelected: (selected) => setState(
                    () => selected
                        ? _risks.add(item.key)
                        : _risks.remove(item.key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: const Key('pregnancy-save-profile'),
            onPressed: _submit,
            child: const Text('Enregistrer et préparer mon calendrier'),
          ),
          const SizedBox(height: 8),
          Text(
            'Le terme calculé est une estimation. Une échographie et un professionnel peuvent l’ajuster.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _ChildProfileForm extends StatefulWidget {
  final String patientId;
  final DateTime now;
  const _ChildProfileForm({required this.patientId, required this.now});

  @override
  State<_ChildProfileForm> createState() => _ChildProfileFormState();
}

class _ChildProfileFormState extends State<_ChildProfileForm> {
  final _name = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  late DateTime _birthDate = widget.now.subtract(const Duration(days: 30));
  String _sex = 'non_precise';

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    _length.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(
        widget.now.year - 6,
        widget.now.month,
        widget.now.day,
      ),
      lastDate: widget.now,
      helpText: 'Date de naissance',
    );
    if (value != null) setState(() => _birthDate = value);
  }

  void _submit() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      ChildProfile(
        id: 'child-${widget.patientId}-${widget.now.microsecondsSinceEpoch}',
        guardianPatientId: widget.patientId,
        firstName: _name.text.trim(),
        birthDate: _birthDate,
        sex: _sex,
        birthWeightKg: double.tryParse(_weight.text.replaceAll(',', '.')),
        birthLengthCm: double.tryParse(_length.text.replaceAll(',', '.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ajouter un enfant',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Prénom de l’enfant'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cake_outlined),
            title: const Text('Date de naissance'),
            subtitle: Text(_formatDate(_birthDate)),
            onTap: _pickBirthDate,
          ),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sexe'),
            items: const [
              DropdownMenuItem(
                value: 'non_precise',
                child: Text('Non précisé'),
              ),
              DropdownMenuItem(value: 'feminin', child: Text('Féminin')),
              DropdownMenuItem(value: 'masculin', child: Text('Masculin')),
              DropdownMenuItem(value: 'intersexe', child: Text('Intersexe')),
            ],
            onChanged: (value) => _sex = value ?? _sex,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Poids naissance (kg)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _length,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Taille naissance (cm)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('child-save-profile'),
            onPressed: _submit,
            child: const Text('Créer le carnet'),
          ),
        ],
      ),
    ),
  );
}

class _GrowthForm extends StatefulWidget {
  final ChildProfile child;
  final DateTime now;
  const _GrowthForm({required this.child, required this.now});

  @override
  State<_GrowthForm> createState() => _GrowthFormState();
}

class _GrowthFormState extends State<_GrowthForm> {
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _head = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _head.dispose();
    super.dispose();
  }

  void _submit() {
    final weight = double.tryParse(_weight.text.replaceAll(',', '.'));
    final height = double.tryParse(_height.text.replaceAll(',', '.'));
    if (weight == null || height == null || weight <= 0 || height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez un poids et une taille valides.')),
      );
      return;
    }
    Navigator.of(context).pop(
      ChildGrowthRecord(
        id: 'growth-${widget.child.id}-${widget.now.microsecondsSinceEpoch}',
        childId: widget.child.id,
        guardianPatientId: widget.child.guardianPatientId,
        measuredAt: widget.now,
        weightKg: weight,
        heightCm: height,
        headCircumferenceCm: double.tryParse(_head.text.replaceAll(',', '.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mesure de ${widget.child.firstName}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Poids (kg)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _height,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Taille (cm)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _head,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Tour de tête (cm, facultatif)',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('growth-save'),
          onPressed: _submit,
          child: const Text('Enregistrer la mesure'),
        ),
      ],
    ),
  );
}

const _riskLabels = <String, String>{
  'hypertension': 'Hypertension',
  'diabetes': 'Diabète',
  'anemia': 'Anémie',
  'multiplePregnancy': 'Grossesse multiple',
  'previousCesarean': 'Césarienne antérieure',
  'previousLoss': 'Perte de grossesse antérieure',
  'ageUnder18': 'Moins de 18 ans',
  'ageOver35': 'Plus de 35 ans',
};

const _highRiskFactorIds = {
  'hypertension',
  'diabetes',
  'multiplePregnancy',
  'previousLoss',
  'ageUnder18',
  'ageOver35',
};

String _weeklyPregnancyMessage(int week) => switch (week) {
  < 13 =>
    'Premier trimestre : organisez le premier contact prénatal et le bilan initial.',
  < 25 =>
    'Deuxième trimestre : suivez les examens prévus et signalez tout signe inhabituel.',
  < 37 =>
    'Troisième trimestre : préparez la naissance, le transport et la maternité.',
  _ =>
    'Le terme approche : gardez les contacts d’urgence et le plan de transport accessibles.',
};

String _dueLabel(DateTime date, DateTime now) {
  final days = _dateOnly(date).difference(_dateOnly(now)).inDays;
  if (days < 0) return 'En retard de ${-days} jour${days == -1 ? '' : 's'}';
  if (days == 0) return 'Aujourd’hui';
  if (days == 1) return 'Demain';
  return 'Dans $days jours • ${_formatDate(date)}';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

List<String> _stringList(Object? value) => value is Iterable
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatDate(DateTime date) {
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

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

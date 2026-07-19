import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _primary = Color(0xFF176BFF);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF5F8FC);
const _green = Color(0xFF079A7B);

enum PreventiveCareCategory {
  checkup,
  vaccine,
  screening,
  dental,
  vision,
  habit,
}

extension PreventiveCareCategoryDetails on PreventiveCareCategory {
  String get id => switch (this) {
    PreventiveCareCategory.checkup => 'checkup',
    PreventiveCareCategory.vaccine => 'vaccine',
    PreventiveCareCategory.screening => 'screening',
    PreventiveCareCategory.dental => 'dental',
    PreventiveCareCategory.vision => 'vision',
    PreventiveCareCategory.habit => 'habit',
  };

  String get label => switch (this) {
    PreventiveCareCategory.checkup => 'Bilan médical',
    PreventiveCareCategory.vaccine => 'Vaccination',
    PreventiveCareCategory.screening => 'Dépistage',
    PreventiveCareCategory.dental => 'Santé dentaire',
    PreventiveCareCategory.vision => 'Santé visuelle',
    PreventiveCareCategory.habit => 'Habitudes de vie',
  };

  IconData get icon => switch (this) {
    PreventiveCareCategory.checkup => Icons.health_and_safety_outlined,
    PreventiveCareCategory.vaccine => Icons.vaccines_outlined,
    PreventiveCareCategory.screening => Icons.fact_check_outlined,
    PreventiveCareCategory.dental => Icons.sentiment_satisfied_alt_outlined,
    PreventiveCareCategory.vision => Icons.visibility_outlined,
    PreventiveCareCategory.habit => Icons.directions_run_outlined,
  };

  Color get color => switch (this) {
    PreventiveCareCategory.checkup => const Color(0xFF176BFF),
    PreventiveCareCategory.vaccine => const Color(0xFF7257D9),
    PreventiveCareCategory.screening => const Color(0xFF0A9F8F),
    PreventiveCareCategory.dental => const Color(0xFFE77C22),
    PreventiveCareCategory.vision => const Color(0xFF3468C0),
    PreventiveCareCategory.habit => const Color(0xFF079A7B),
  };

  static PreventiveCareCategory? fromId(String value) {
    for (final category in PreventiveCareCategory.values) {
      if (category.id == value) return category;
    }
    return null;
  }
}

class PreventiveCareRecord {
  final String id;
  final PreventiveCareCategory category;
  final String title;
  final String planItemId;
  final DateTime completedAt;
  final DateTime? nextDueAt;
  final String provider;
  final String note;

  const PreventiveCareRecord({
    required this.id,
    required this.category,
    required this.title,
    required this.completedAt,
    this.planItemId = '',
    this.nextDueAt,
    this.provider = '',
    this.note = '',
  });

  static PreventiveCareRecord? fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final category = PreventiveCareCategoryDetails.fromId(
      data['category']?.toString() ?? '',
    );
    final completedAt = _dateFromValue(data['completedAt']);
    if (category == null || completedAt == null) return null;
    return PreventiveCareRecord(
      id: snapshot.id,
      category: category,
      title: data['title']?.toString() ?? category.label,
      planItemId: data['planItemId']?.toString() ?? '',
      completedAt: completedAt,
      nextDueAt: _dateFromValue(data['nextDueAt']),
      provider: data['provider']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
    );
  }
}

class PreventiveCareReminder {
  final String id;
  final PreventiveCareCategory category;
  final String title;
  final String planItemId;
  final DateTime dueAt;
  final String note;

  const PreventiveCareReminder({
    required this.id,
    required this.category,
    required this.title,
    required this.dueAt,
    this.planItemId = '',
    this.note = '',
  });

  static PreventiveCareReminder? fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final category = PreventiveCareCategoryDetails.fromId(
      data['category']?.toString() ?? '',
    );
    final dueAt = _dateFromValue(data['dueAt']);
    if (category == null || dueAt == null) return null;
    return PreventiveCareReminder(
      id: snapshot.id,
      category: category,
      title: data['title']?.toString() ?? category.label,
      planItemId: data['planItemId']?.toString() ?? '',
      dueAt: dueAt,
      note: data['note']?.toString() ?? '',
    );
  }
}

enum PreventivePlanSection { essentials, cancer }

class PreventivePlanItem {
  final String id;
  final PreventiveCareCategory category;
  final String title;
  final String description;
  final String timing;
  final bool priority;
  final PreventivePlanSection section;

  const PreventivePlanItem({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.timing,
    this.priority = false,
    this.section = PreventivePlanSection.essentials,
  });
}

/// Construit des sujets de prévention à discuter, jamais des prescriptions.
/// Les échéances exactes restent celles fixées par un professionnel de santé.
List<PreventivePlanItem> buildPreventivePlan(
  Map<String, dynamic> patientProfile, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final birthDate = _dateFromValue(patientProfile['birthDate']);
  final age = birthDate == null ? null : _ageOn(birthDate, today);
  final sex = patientProfile['sex']?.toString().trim().toLowerCase() ?? '';
  final pregnancy =
      patientProfile['pregnancyStatus']?.toString().trim().toLowerCase() ?? '';
  final conditions = _stringList(patientProfile['medicalConditions']);
  final loweredConditions = conditions
      .map((condition) => condition.toLowerCase())
      .toList();
  final livingWithHiv = loweredConditions.any(
    (condition) => condition.contains('vih') || condition.contains('hiv'),
  );

  final items = <PreventivePlanItem>[
    const PreventivePlanItem(
      id: 'preventive-review',
      category: PreventiveCareCategory.checkup,
      title: 'Faire le point sur ma santé',
      description:
          'Revoir vos antécédents, traitements, mesures et facteurs de risque avec un professionnel.',
      timing: 'À planifier avec votre professionnel',
      priority: true,
    ),
    const PreventivePlanItem(
      id: 'vaccine-record',
      category: PreventiveCareCategory.vaccine,
      title: 'Vérifier mon carnet de vaccination',
      description:
          'Confirmer les doses reçues et les rattrapages utiles selon le calendrier haïtien et votre situation.',
      timing: 'À vérifier à chaque étape de vie',
      priority: true,
    ),
    const PreventivePlanItem(
      id: 'blood-pressure-risk',
      category: PreventiveCareCategory.screening,
      title: 'Évaluer mes risques cardiovasculaires',
      description:
          'Parler de la tension, du diabète, du cholestérol et des antécédents familiaux.',
      timing: 'Fréquence à personnaliser',
    ),
    const PreventivePlanItem(
      id: 'oral-health',
      category: PreventiveCareCategory.dental,
      title: 'Préserver ma santé bucco-dentaire',
      description:
          'Faire évaluer les dents et les gencives, surtout en cas de douleur ou de saignement.',
      timing: 'Selon votre risque et vos symptômes',
    ),
    const PreventivePlanItem(
      id: 'vision-health',
      category: PreventiveCareCategory.vision,
      title: 'Faire contrôler ma vision',
      description:
          'Signaler toute baisse de vision, douleur, diabète ou difficulté dans les activités quotidiennes.',
      timing: 'Selon votre risque et vos symptômes',
    ),
    const PreventivePlanItem(
      id: 'healthy-eating',
      category: PreventiveCareCategory.habit,
      title: 'Construire des repas variés',
      description:
          'Privilégier légumes, fruits, légumineuses et aliments peu transformés, en limitant sel et boissons sucrées.',
      timing: 'Un équilibre à construire au quotidien',
    ),
    const PreventivePlanItem(
      id: 'hydration-habit',
      category: PreventiveCareCategory.habit,
      title: 'Boire de l’eau régulièrement',
      description:
          'Garder de l’eau potable à portée de main et boire davantage avec la chaleur ou l’activité.',
      timing: 'Tout au long de la journée',
    ),
  ];

  if (sex == 'femme' && (age == null || age >= 18)) {
    items.add(
      const PreventivePlanItem(
        id: 'breast-awareness',
        category: PreventiveCareCategory.screening,
        title: 'Connaître l’aspect habituel de mes seins',
        description:
            'Observer et palper doucement seins et aisselles pour repérer une nouvelle masse ou un changement persistant.',
        timing: 'Repère régulier, sans calendrier obligatoire',
        section: PreventivePlanSection.cancer,
      ),
    );
  }

  if (sex == 'femme' && age != null && age >= 40 && age <= 74) {
    items.add(
      const PreventivePlanItem(
        id: 'breast-screening',
        category: PreventiveCareCategory.screening,
        title: 'Discuter du dépistage du cancer du sein',
        description:
            'Évaluer avec un professionnel l’intérêt et la disponibilité d’une mammographie selon votre risque.',
        timing: 'À discuter entre 40 et 74 ans',
        priority: true,
        section: PreventivePlanSection.cancer,
      ),
    );
  }

  final cervicalScreeningAge = livingWithHiv ? 25 : 30;
  if (sex == 'femme' && age != null && age >= cervicalScreeningAge) {
    items.add(
      PreventivePlanItem(
        id: 'cervical-screening',
        category: PreventiveCareCategory.screening,
        title: 'Parler du dépistage du col de l’utérus',
        description:
            'Vérifier le test HPV ou l’examen disponible et la date du prochain dépistage, même sans symptôme.',
        timing: livingWithHiv
            ? 'Dès 25 ans en cas de VIH'
            : 'Dès 30 ans selon les recommandations locales',
        priority: true,
        section: PreventivePlanSection.cancer,
      ),
    );
  }

  if (age != null && age >= 45 && age <= 75) {
    items.add(
      const PreventivePlanItem(
        id: 'colorectal-screening',
        category: PreventiveCareCategory.screening,
        title: 'Parler du dépistage colorectal',
        description:
            'Choisir avec un professionnel un test adapté; les antécédents familiaux peuvent modifier le calendrier.',
        timing: 'À discuter entre 45 et 75 ans',
        priority: true,
        section: PreventivePlanSection.cancer,
      ),
    );
  }

  if (sex == 'homme' && age != null && age >= 55 && age <= 69) {
    items.add(
      const PreventivePlanItem(
        id: 'prostate-screening',
        category: PreventiveCareCategory.screening,
        title: 'Décider si le dépistage de la prostate me convient',
        description:
            'Discuter du test PSA, de ses bénéfices possibles, des faux positifs et du surdiagnostic avant de décider.',
        timing: 'Décision partagée entre 55 et 69 ans',
        priority: true,
        section: PreventivePlanSection.cancer,
      ),
    );
  }

  if (conditions.isNotEmpty) {
    items.add(
      PreventivePlanItem(
        id: 'known-condition-follow-up',
        category: PreventiveCareCategory.checkup,
        title: 'Prévenir les complications',
        description:
            'Adapter votre suivi à vos conditions connues : ${conditions.take(2).join(', ')}.',
        timing: 'Selon le plan de votre équipe soignante',
        priority: true,
      ),
    );
  }

  if (pregnancy == 'oui') {
    items.insert(
      0,
      const PreventivePlanItem(
        id: 'prenatal-care',
        category: PreventiveCareCategory.checkup,
        title: 'Organiser mon suivi prénatal',
        description:
            'Contacter rapidement un professionnel pour les consultations, examens et vaccins adaptés.',
        timing: 'Prioritaire pendant la grossesse',
        priority: true,
      ),
    );
  }

  return items;
}

class PreventiveMedicinePage extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientProfile;
  final DateTime? now;
  final Stream<List<PreventiveCareRecord>>? recordStream;
  final Stream<List<PreventiveCareReminder>>? reminderStream;
  final Future<void> Function(Map<String, dynamic> data)? onSaveRecord;
  final Future<void> Function(String recordId)? onDeleteRecord;
  final Future<void> Function(Map<String, dynamic> data)? onSaveReminder;
  final Future<void> Function(String reminderId)? onDeleteReminder;

  const PreventiveMedicinePage({
    super.key,
    required this.patientId,
    required this.patientProfile,
    this.now,
    this.recordStream,
    this.reminderStream,
    this.onSaveRecord,
    this.onDeleteRecord,
    this.onSaveReminder,
    this.onDeleteReminder,
  });

  @override
  State<PreventiveMedicinePage> createState() => _PreventiveMedicinePageState();
}

class _PreventiveMedicinePageState extends State<PreventiveMedicinePage> {
  DateTime get _today => widget.now ?? DateTime.now();

  CollectionReference<Map<String, dynamic>> get _records => FirebaseFirestore
      .instance
      .collection('patients')
      .doc(widget.patientId)
      .collection('preventiveCareRecords');

  CollectionReference<Map<String, dynamic>> get _reminders => FirebaseFirestore
      .instance
      .collection('patients')
      .doc(widget.patientId)
      .collection('preventiveCareReminders');

  Stream<List<PreventiveCareRecord>> get _recordStream {
    final injected = widget.recordStream;
    if (injected != null) return injected;
    return _records
        .orderBy('completedAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(PreventiveCareRecord.fromFirestore)
              .whereType<PreventiveCareRecord>()
              .toList(),
        );
  }

  Stream<List<PreventiveCareReminder>> get _reminderStream {
    final injected = widget.reminderStream;
    if (injected != null) return injected;
    return _reminders
        .orderBy('dueAt')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(PreventiveCareReminder.fromFirestore)
              .whereType<PreventiveCareReminder>()
              .toList(),
        );
  }

  Future<void> _saveRecord(Map<String, dynamic> data) async {
    final injected = widget.onSaveRecord;
    if (injected != null) {
      await injected(data);
      return;
    }
    final completedAt = data['completedAt'] as DateTime;
    final nextDueAt = data['nextDueAt'] as DateTime?;
    await _records.add({
      ...data,
      'completedAt': Timestamp.fromDate(completedAt),
      if (nextDueAt != null) 'nextDueAt': Timestamp.fromDate(nextDueAt),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _saveReminder(Map<String, dynamic> data) async {
    final injected = widget.onSaveReminder;
    if (injected != null) {
      await injected(data);
      return;
    }
    await _reminders.add({
      ...data,
      'dueAt': Timestamp.fromDate(data['dueAt'] as DateTime),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _openRecordForm({
    PreventivePlanItem? planItem,
    String? title,
    PreventiveCareCategory? category,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PreventiveRecordForm(
        now: _today,
        planItem: planItem,
        initialTitle: title,
        initialCategory: category,
        onSave: _saveRecord,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action de prévention enregistrée.')),
      );
    }
    return saved == true;
  }

  Future<void> _openReminderForm({PreventivePlanItem? planItem}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PreventiveReminderForm(
        now: _today,
        planItem: planItem,
        onSave: _saveReminder,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rappel ajouté à votre plan.')),
      );
    }
  }

  Future<void> _removeReminder(
    PreventiveCareReminder reminder, {
    bool showFeedback = true,
  }) async {
    final injected = widget.onDeleteReminder;
    if (injected != null) {
      await injected(reminder.id);
    } else {
      await _reminders.doc(reminder.id).delete();
    }
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rappel supprimé.')));
    }
  }

  Future<void> _deleteReminder(PreventiveCareReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce rappel ?'),
        content: Text('${reminder.title} · ${_longDate(reminder.dueAt)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _removeReminder(reminder);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suppression impossible. Réessayez.')),
        );
      }
    }
  }

  Future<void> _completeReminder(PreventiveCareReminder reminder) async {
    PreventivePlanItem? planItem;
    for (final item in buildPreventivePlan(
      widget.patientProfile,
      now: _today,
    )) {
      if (item.id == reminder.planItemId) {
        planItem = item;
        break;
      }
    }
    final saved = await _openRecordForm(
      planItem: planItem,
      title: reminder.title,
      category: reminder.category,
    );
    if (!saved) return;
    try {
      await _removeReminder(reminder, showFeedback: false);
    } on FirebaseException {
      // L’action reste enregistrée; le rappel pourra être supprimé plus tard.
    }
  }

  Future<void> _deleteRecord(PreventiveCareRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette action ?'),
        content: Text(record.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final injected = widget.onDeleteRecord;
      if (injected != null) {
        await injected(record.id);
      } else {
        await _records.doc(record.id).delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Action supprimée.')));
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suppression impossible. Réessayez.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = buildPreventivePlan(widget.patientProfile, now: _today);
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        title: const Text('Médecine préventive'),
        actions: [
          IconButton(
            key: const Key('preventive-add-record'),
            tooltip: 'Ajouter une action',
            onPressed: _openRecordForm,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          IconButton(
            key: const Key('preventive-add-reminder'),
            tooltip: 'Créer un rappel',
            onPressed: _openReminderForm,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<PreventiveCareRecord>>(
        stream: _recordStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _PreventiveFeedback(
              icon: Icons.lock_outline_rounded,
              title: 'Votre carnet est indisponible',
              message:
                  'La lecture de vos données privées est momentanément impossible.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _primary),
            );
          }
          final records = [...snapshot.data!]
            ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
          return StreamBuilder<List<PreventiveCareReminder>>(
            stream: _reminderStream,
            initialData: const <PreventiveCareReminder>[],
            builder: (context, reminderSnapshot) {
              final reminders = [...?reminderSnapshot.data]
                ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
              return _PreventiveDashboard(
                plan: plan,
                records: records,
                reminders: reminders,
                reminderStorageError: reminderSnapshot.hasError,
                today: _today,
                profile: widget.patientProfile,
                onPlanItemTap: (item) => _openRecordForm(planItem: item),
                onPlanReminderTap: (item) => _openReminderForm(planItem: item),
                onAddRecord: _openRecordForm,
                onAddReminder: _openReminderForm,
                onDeleteRecord: _deleteRecord,
                onDeleteReminder: _deleteReminder,
                onCompleteReminder: _completeReminder,
              );
            },
          );
        },
      ),
    );
  }
}

class _PreventiveDashboard extends StatelessWidget {
  final List<PreventivePlanItem> plan;
  final List<PreventiveCareRecord> records;
  final List<PreventiveCareReminder> reminders;
  final bool reminderStorageError;
  final DateTime today;
  final Map<String, dynamic> profile;
  final ValueChanged<PreventivePlanItem> onPlanItemTap;
  final ValueChanged<PreventivePlanItem> onPlanReminderTap;
  final VoidCallback onAddRecord;
  final VoidCallback onAddReminder;
  final ValueChanged<PreventiveCareRecord> onDeleteRecord;
  final ValueChanged<PreventiveCareReminder> onDeleteReminder;
  final ValueChanged<PreventiveCareReminder> onCompleteReminder;

  const _PreventiveDashboard({
    required this.plan,
    required this.records,
    required this.reminders,
    required this.reminderStorageError,
    required this.today,
    required this.profile,
    required this.onPlanItemTap,
    required this.onPlanReminderTap,
    required this.onAddRecord,
    required this.onAddReminder,
    required this.onDeleteRecord,
    required this.onDeleteReminder,
    required this.onCompleteReminder,
  });

  @override
  Widget build(BuildContext context) {
    final completed = plan
        .where((item) => _isCurrent(item, records, today))
        .length;
    final essentialPlan = plan
        .where((item) => item.section == PreventivePlanSection.essentials)
        .toList();
    final cancerPlan = plan
        .where((item) => item.section == PreventivePlanSection.cancer)
        .toList();
    final hydrationPlanItem = essentialPlan.firstWhere(
      (item) => item.id == 'hydration-habit',
    );
    final dueRecords =
        records.where((record) => record.nextDueAt != null).toList()
          ..sort((a, b) => a.nextDueAt!.compareTo(b.nextDueAt!));
    final birthDate = _dateFromValue(profile['birthDate']);
    final age = birthDate == null ? null : _ageOn(birthDate, today);
    final profileLabel = age == null
        ? 'Plan adapté à votre profil'
        : 'Plan adapté à votre âge · $age ans';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 16, wide ? 34 : 18, 42),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PreventionHero(
                    completed: completed,
                    total: plan.length,
                    profileLabel: profileLabel,
                    onAdd: onAddRecord,
                  ),
                  const SizedBox(height: 16),
                  const _ClinicalNotice(),
                  const SizedBox(height: 28),
                  _SectionTitle(
                    title: 'Mes rappels',
                    subtitle: reminders.isEmpty
                        ? 'Planifiez un check-up ou un dépistage sans attendre d’y penser.'
                        : '${reminders.length} rappel${reminders.length > 1 ? 's' : ''} dans votre plan.',
                    actionLabel: 'Nouveau rappel',
                    onAction: onAddReminder,
                  ),
                  const SizedBox(height: 14),
                  _ReminderPanel(
                    reminders: reminders,
                    today: today,
                    storageError: reminderStorageError,
                    onAdd: onAddReminder,
                    onComplete: onCompleteReminder,
                    onDelete: onDeleteReminder,
                  ),
                  const SizedBox(height: 30),
                  const _SectionTitle(
                    title: 'Mon plan de prévention',
                    subtitle:
                        'Des sujets personnalisés à préparer avec votre équipe soignante.',
                  ),
                  const SizedBox(height: 14),
                  _PlanItemsLayout(
                    wide: wide,
                    items: essentialPlan,
                    records: records,
                    today: today,
                    onComplete: onPlanItemTap,
                    onReminder: onPlanReminderTap,
                  ),
                  if (cancerPlan.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    const _CancerSectionIntro(),
                    const SizedBox(height: 14),
                    _PlanItemsLayout(
                      wide: wide,
                      items: cancerPlan,
                      records: records,
                      today: today,
                      onComplete: onPlanItemTap,
                      onReminder: onPlanReminderTap,
                    ),
                    const SizedBox(height: 14),
                    _CancerWarningSigns(
                      showBreastGuide: cancerPlan.any(
                        (item) => item.id == 'breast-awareness',
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (dueRecords.isNotEmpty) ...[
                    const _SectionTitle(
                      title: 'Mes prochaines échéances',
                      subtitle:
                          'Les dates que vous avez choisies dans votre carnet.',
                    ),
                    const SizedBox(height: 14),
                    _DueDateStrip(records: dueRecords, today: today),
                    const SizedBox(height: 30),
                  ],
                  const _SectionTitle(
                    title: 'Repères protecteurs',
                    subtitle:
                        'De petits gestes réguliers comptent aussi dans la prévention.',
                  ),
                  const SizedBox(height: 14),
                  const _ProtectiveHabits(),
                  const SizedBox(height: 30),
                  _NutritionHydrationSection(
                    profile: profile,
                    onHydrationReminder: () =>
                        onPlanReminderTap(hydrationPlanItem),
                  ),
                  const SizedBox(height: 30),
                  _SectionTitle(
                    title: 'Mon carnet',
                    subtitle: records.isEmpty
                        ? 'Conservez ici les bilans, vaccins et dépistages réalisés.'
                        : '${records.length} action${records.length > 1 ? 's' : ''} enregistrée${records.length > 1 ? 's' : ''}.',
                    actionLabel: 'Ajouter',
                    onAction: onAddRecord,
                  ),
                  const SizedBox(height: 14),
                  if (records.isEmpty)
                    _PreventiveFeedback(
                      icon: Icons.inventory_2_outlined,
                      title: 'Votre carnet commence ici',
                      message:
                          'Ajoutez un bilan, un vaccin ou un dépistage pour garder vos prochaines étapes en vue.',
                      actionLabel: 'Ajouter une action',
                      onAction: onAddRecord,
                    )
                  else
                    _RecordList(records: records, onDelete: onDeleteRecord),
                  const SizedBox(height: 28),
                  const _EvidenceCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _isCurrent(
  PreventivePlanItem item,
  List<PreventiveCareRecord> records,
  DateTime today,
) {
  final matches =
      records.where((record) => record.planItemId == item.id).toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  if (matches.isEmpty) return false;
  final nextDue = matches.first.nextDueAt;
  return nextDue == null || !_dateOnly(nextDue).isBefore(_dateOnly(today));
}

class _PreventionHero extends StatelessWidget {
  final int completed;
  final int total;
  final String profileLabel;
  final VoidCallback onAdd;

  const _PreventionHero({
    required this.completed,
    required this.total,
    required this.profileLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E4AB8), Color(0xFF1676F3), Color(0xFF0AA29A)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B176BFF),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Text(
              profileLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Prévenir aujourd’hui,\nprotéger demain.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Préparez vos bilans et gardez une trace claire de vos actions de prévention.',
            style: TextStyle(
              color: Color(0xFFE7F2FF),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completed sur $total préparés',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: progress,
                        backgroundColor: const Color(0x35FFFFFF),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF8EF0D7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              FilledButton.icon(
                key: const Key('preventive-hero-add'),
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _navy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicalNotice extends StatelessWidget {
  const _ClinicalNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF4D78E)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF9C6800), size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Ce plan vous aide à préparer une consultation. Il ne pose aucun diagnostic et ne remplace pas les recommandations d’un professionnel.',
            style: TextStyle(
              color: Color(0xFF684A0D),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: _muted, height: 1.35)),
          ],
        ),
      ),
      if (actionLabel != null)
        TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  );
}

class _ReminderPanel extends StatelessWidget {
  final List<PreventiveCareReminder> reminders;
  final DateTime today;
  final bool storageError;
  final VoidCallback onAdd;
  final ValueChanged<PreventiveCareReminder> onComplete;
  final ValueChanged<PreventiveCareReminder> onDelete;

  const _ReminderPanel({
    required this.reminders,
    required this.today,
    required this.storageError,
    required this.onAdd,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (storageError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2C2BC)),
        ),
        child: const Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: Color(0xFFD92D20)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Les rappels sont momentanément indisponibles. Votre carnet reste accessible.',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    if (reminders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF1F6FF), Color(0xFFF1FCF9)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFCFE0F5)),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.notifications_active_outlined,
                color: _primary,
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ne laissez pas votre prochain contrôle au hasard',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Choisissez une date; le rappel apparaîtra ici et remontera lorsqu’il sera dû.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const Key('preventive-empty-add-reminder'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_alarm_rounded, size: 19),
              label: const Text('Créer un rappel'),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < reminders.length; index++) ...[
            _ReminderTile(
              reminder: reminders[index],
              today: today,
              onComplete: () => onComplete(reminders[index]),
              onDelete: () => onDelete(reminders[index]),
            ),
            if (index < reminders.length - 1)
              const Divider(height: 1, indent: 72, color: _border),
          ],
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final PreventiveCareReminder reminder;
  final DateTime today;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _ReminderTile({
    required this.reminder,
    required this.today,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dayDifference = _dateOnly(
      reminder.dueAt,
    ).difference(_dateOnly(today)).inDays;
    final overdue = dayDifference < 0;
    final timing = dayDifference == 0
        ? 'Aujourd’hui'
        : dayDifference == 1
        ? 'Demain'
        : dayDifference > 1
        ? 'Dans $dayDifference jours'
        : 'En retard de ${-dayDifference} jour${dayDifference < -1 ? 's' : ''}';
    final statusColor = overdue ? const Color(0xFFD92D20) : _primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.alarm_rounded, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      reminder.title,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    _StatusPill(label: timing, color: statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _longDate(reminder.dueAt),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (reminder.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reminder.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: Key('preventive-complete-reminder-${reminder.id}'),
                  onPressed: onComplete,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('C’est fait'),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Supprimer le rappel',
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _CancerSectionIntro extends StatelessWidget {
  const _CancerSectionIntro();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFEEF2), Color(0xFFFFF7EA)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF2C9CF)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Color(0xFFC9365C), size: 30),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prévention et détection précoce des cancers',
                style: TextStyle(
                  color: _navy,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Ces repères utilisent votre âge et votre sexe médical. Ils servent à lancer la bonne conversation, pas à confirmer ou exclure un cancer.',
                style: TextStyle(color: _ink, height: 1.4, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CancerWarningSigns extends StatelessWidget {
  final bool showBreastGuide;
  const _CancerWarningSigns({required this.showBreastGuide});

  static const _signs = [
    'Masse ou épaississement nouveau',
    'Saignement inexpliqué',
    'Plaie ou changement persistant',
    'Perte de poids inexpliquée',
    'Toux ou enrouement persistant',
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        ExpansionTile(
          key: const Key('preventive-cancer-warning-signs'),
          leading: const Icon(
            Icons.visibility_outlined,
            color: Color(0xFFC9365C),
          ),
          title: const Text(
            'Changements à ne pas ignorer',
            style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Un signe persistant mérite une évaluation, même sans douleur.',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _signs
                  .map(
                    (sign) => Chip(
                      avatar: const Icon(
                        Icons.circle,
                        size: 8,
                        color: Color(0xFFC9365C),
                      ),
                      label: Text(sign),
                      side: const BorderSide(color: Color(0xFFF0D5DA)),
                      backgroundColor: const Color(0xFFFFF8F9),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ces changements ont souvent d’autres causes. Seul un professionnel peut les évaluer; n’attendez pas le prochain rappel si quelque chose vous inquiète.',
              style: TextStyle(color: _muted, height: 1.4, fontSize: 12.5),
            ),
          ],
        ),
        if (showBreastGuide) ...[
          const Divider(height: 1, color: _border),
          const ExpansionTile(
            key: Key('preventive-breast-awareness-guide'),
            leading: Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFFC9365C),
            ),
            title: Text(
              'Comment observer mes seins ?',
              style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              'Un repère simple pour connaître ce qui est habituel pour vous.',
            ),
            childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: [
              _GuideStep(
                number: '1',
                text:
                    'Regardez leur forme, la peau et les mamelons devant un miroir, bras baissés puis levés.',
              ),
              _GuideStep(
                number: '2',
                text:
                    'Avec les doigts à plat, parcourez doucement chaque sein et chaque aisselle sans chercher à vous diagnostiquer.',
              ),
              _GuideStep(
                number: '3',
                text:
                    'Consultez rapidement pour une masse nouvelle, une peau creusée ou rouge, un mamelon modifié ou un écoulement sanglant.',
              ),
              SizedBox(height: 8),
              Text(
                'Il n’existe pas de jour obligatoire. Cette observation ne remplace ni l’examen clinique ni une mammographie recommandée.',
                style: TextStyle(color: _muted, height: 1.4, fontSize: 12.5),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String text;
  const _GuideStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFFFE7EC),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFFC9365C),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: _ink, height: 1.4)),
        ),
      ],
    ),
  );
}

class _PlanItemsLayout extends StatelessWidget {
  final bool wide;
  final List<PreventivePlanItem> items;
  final List<PreventiveCareRecord> records;
  final DateTime today;
  final ValueChanged<PreventivePlanItem> onComplete;
  final ValueChanged<PreventivePlanItem> onReminder;

  const _PlanItemsLayout({
    required this.wide,
    required this.items,
    required this.records,
    required this.today,
    required this.onComplete,
    required this.onReminder,
  });

  @override
  Widget build(BuildContext context) {
    Widget card(PreventivePlanItem item) => _PlanItemCard(
      item: item,
      current: _isCurrent(item, records, today),
      onTap: () => onComplete(item),
      onReminder: () => onReminder(item),
    );

    if (!wide) {
      return Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card(item),
              ),
            )
            .toList(),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 264,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => card(items[index]),
    );
  }
}

class _PlanItemCard extends StatelessWidget {
  final PreventivePlanItem item;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onReminder;

  const _PlanItemCard({
    required this.item,
    required this.current,
    required this.onTap,
    required this.onReminder,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      key: Key('preventive-plan-${item.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: current ? const Color(0xFF9BDFC9) : _border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.category.color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.category.icon, color: item.category.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (item.priority && !current)
                  const _StatusPill(label: 'Priorité', color: Color(0xFFE77C22))
                else if (current)
                  const _StatusPill(label: 'Préparé', color: _green),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, height: 1.35, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, color: _muted, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.timing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                OutlinedButton.icon(
                  key: Key('preventive-reminder-${item.id}'),
                  onPressed: onReminder,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Color(0xFFB9CEF2)),
                  ),
                  icon: const Icon(Icons.notifications_none_rounded, size: 17),
                  label: const Text('Rappel'),
                ),
                const Spacer(),
                TextButton(
                  key: Key('preventive-complete-${item.id}'),
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: item.category.color,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(current ? 'Mettre à jour' : 'C’est fait'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DueDateStrip extends StatelessWidget {
  final List<PreventiveCareRecord> records;
  final DateTime today;
  const _DueDateStrip({required this.records, required this.today});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 146,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: records.length,
      separatorBuilder: (context, index) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final record = records[index];
        final due = record.nextDueAt!;
        final overdue = _dateOnly(due).isBefore(_dateOnly(today));
        return Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: overdue ? const Color(0xFFF1B4AE) : _border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    record.category.icon,
                    color: record.category.color,
                    size: 21,
                  ),
                  const Spacer(),
                  _StatusPill(
                    label: overdue ? 'À replanifier' : 'À venir',
                    color: overdue ? const Color(0xFFD92D20) : _primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _longDate(due),
                style: TextStyle(
                  color: overdue ? const Color(0xFFD92D20) : _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _ProtectiveHabits extends StatelessWidget {
  const _ProtectiveHabits();

  static const _habits = [
    (
      Icons.directions_walk_rounded,
      'Bouger',
      'Viser au moins 150 minutes d’activité physique modérée par semaine.',
      Color(0xFF176BFF),
    ),
    (
      Icons.smoke_free_rounded,
      'Réduire les risques',
      'Éviter le tabac, limiter l’alcool et demander de l’aide si nécessaire.',
      Color(0xFFE77C22),
    ),
    (
      Icons.bedtime_outlined,
      'Dormir et récupérer',
      'Protéger un temps de sommeil régulier et parler des difficultés persistantes.',
      Color(0xFF7257D9),
    ),
    (
      Icons.groups_2_outlined,
      'Garder du lien',
      'Entretenir les liens sociaux et demander du soutien pendant les périodes difficiles.',
      Color(0xFF079A7B),
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _habits.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 186,
        ),
        itemBuilder: (context, index) {
          final habit = _habits[index];
          return Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(habit.$1, color: habit.$4, size: 27),
                const SizedBox(height: 12),
                Text(
                  habit.$2,
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  habit.$3,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _NutritionHydrationSection extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onHydrationReminder;

  const _NutritionHydrationSection({
    required this.profile,
    required this.onHydrationReminder,
  });

  @override
  Widget build(BuildContext context) {
    final conditions = _stringList(
      profile['medicalConditions'],
    ).map((condition) => condition.toLowerCase()).toList();
    final fluidRestrictionRisk = conditions.any(
      (condition) =>
          condition.contains('rein') ||
          condition.contains('rénal') ||
          condition.contains('dialyse') ||
          condition.contains('insuffisance cardiaque'),
    );
    final pregnancy =
        profile['pregnancyStatus']?.toString().trim().toLowerCase() == 'oui';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Alimentation & hydratation',
          subtitle:
              'Des repères simples, adaptés aux aliments disponibles et à votre santé.',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final cards = [
              const _NutritionAdviceCard(),
              _HydrationAdviceCard(
                fluidRestrictionRisk: fluidRestrictionRisk,
                pregnancy: pregnancy,
                onReminder: onHydrationReminder,
              ),
            ];
            if (!wide) {
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const _HydrationSignalsCard(),
      ],
    );
  }
}

class _NutritionAdviceCard extends StatelessWidget {
  const _NutritionAdviceCard();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFCFE8D9)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D079A7B),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdviceHeader(
          icon: Icons.restaurant_menu_rounded,
          color: Color(0xFF079A7B),
          title: 'Composer des repas nourrissants',
          subtitle: 'Variété, équilibre, modération et sécurité.',
        ),
        SizedBox(height: 18),
        _AdviceLine(
          icon: Icons.eco_outlined,
          title: 'Misez sur la variété',
          text:
              'Associez légumes ou fruits, haricots ou autres légumineuses, céréales ou tubercules et une source de protéines.',
        ),
        _AdviceLine(
          icon: Icons.local_grocery_store_outlined,
          title: 'Choisissez peu transformé',
          text:
              'Préférez les aliments frais ou simples aux produits très salés, très sucrés ou souvent frits.',
        ),
        _AdviceLine(
          icon: Icons.spa_outlined,
          title: 'Fruits et légumes chaque jour',
          text:
              'Lorsque possible, l’OMS conseille au moins 400 g par jour après 10 ans, en variant les couleurs.',
        ),
        _AdviceLine(
          icon: Icons.soup_kitchen_outlined,
          title: 'Dosez sel, cubes et sauces',
          text:
              'Goûtez avant de resaler et utilisez herbes, ail, citron ou épices pour relever les plats.',
          isLast: true,
        ),
      ],
    ),
  );
}

class _HydrationAdviceCard extends StatelessWidget {
  final bool fluidRestrictionRisk;
  final bool pregnancy;
  final VoidCallback onReminder;

  const _HydrationAdviceCard({
    required this.fluidRestrictionRisk,
    required this.pregnancy,
    required this.onReminder,
  });

  @override
  Widget build(BuildContext context) {
    final personalNote = fluidRestrictionRisk
        ? 'Votre profil mentionne une condition rénale ou cardiaque. Si un professionnel a limité vos boissons, respectez ce plan avant d’augmenter l’eau.'
        : pregnancy
        ? 'Pendant la grossesse, les besoins peuvent augmenter. Gardez de l’eau potable à portée de main et validez vos besoins pendant le suivi prénatal.'
        : 'Les besoins varient avec la chaleur, l’activité, la fièvre, la diarrhée et les traitements. Buvez régulièrement sans attendre une soif intense.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF5FF), Color(0xFFF1FBFF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFBDDDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AdviceHeader(
            icon: Icons.water_drop_outlined,
            color: Color(0xFF1676C3),
            title: 'Boire de l’eau régulièrement',
            subtitle: 'Une habitude simple, à adapter à votre corps.',
          ),
          const SizedBox(height: 18),
          const _AdviceLine(
            icon: Icons.water_outlined,
            title: 'Gardez l’eau visible',
            text:
                'Prenez de l’eau potable au réveil, aux repas et pendant vos déplacements; gardez une bouteille propre près de vous.',
          ),
          const _AdviceLine(
            icon: Icons.sunny_snowing,
            title: 'Adaptez-vous à la journée',
            text:
                'Buvez davantage par forte chaleur, pendant l’exercice ou en cas de pertes de liquides.',
          ),
          const _AdviceLine(
            icon: Icons.no_drinks_outlined,
            title: 'L’eau en premier choix',
            text:
                'Remplacez le plus souvent sodas, boissons énergisantes et jus très sucrés par de l’eau sûre.',
            isLast: true,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: fluidRestrictionRisk
                  ? const Color(0xFFFFF4E8)
                  : const Color(0xBFFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: fluidRestrictionRisk
                    ? const Color(0xFFF2D09D)
                    : const Color(0xFFD4E6F3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  fluidRestrictionRisk
                      ? Icons.medical_information_outlined
                      : Icons.tips_and_updates_outlined,
                  color: fluidRestrictionRisk
                      ? const Color(0xFFA86400)
                      : const Color(0xFF1676C3),
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    personalNote,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('preventive-hydration-reminder'),
              onPressed: onReminder,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1676C3),
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: Color(0xFF9DCBEA)),
              ),
              icon: const Icon(Icons.add_alarm_rounded, size: 19),
              label: const Text('Me rappeler de boire de l’eau'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdviceHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _AdviceHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _navy,
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AdviceLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool isLast;

  const _AdviceLine({
    required this.icon,
    required this.title,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F7FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _muted, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11.7,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HydrationSignalsCard extends StatelessWidget {
  const _HydrationSignalsCard();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBF0),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFF0DCA7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.health_and_safety_outlined, color: Color(0xFF9A6B00)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Écoutez les signes de déshydratation',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _SignalChip(label: 'Soif importante'),
            _SignalChip(label: 'Bouche sèche'),
            _SignalChip(label: 'Urines foncées ou rares'),
            _SignalChip(label: 'Fatigue ou étourdissement'),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Consultez rapidement si la personne est confuse, s’évanouit, urine très peu ou ne peut pas boire, surtout après diarrhée, vomissements ou forte chaleur.',
          style: TextStyle(color: Color(0xFF6E5216), fontSize: 12, height: 1.4),
        ),
      ],
    ),
  );
}

class _SignalChip extends StatelessWidget {
  final String label;
  const _SignalChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8D59D)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF6E5216),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _RecordList extends StatelessWidget {
  final List<PreventiveCareRecord> records;
  final ValueChanged<PreventiveCareRecord> onDelete;
  const _RecordList({required this.records, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        for (var index = 0; index < records.length; index++) ...[
          _RecordTile(
            record: records[index],
            onDelete: () => onDelete(records[index]),
          ),
          if (index < records.length - 1)
            const Divider(height: 1, indent: 72, color: _border),
        ],
      ],
    ),
  );
}

class _RecordTile extends StatelessWidget {
  final PreventiveCareRecord record;
  final VoidCallback onDelete;
  const _RecordTile({required this.record, required this.onDelete});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: record.category.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(record.category.icon, color: record.category.color, size: 22),
    ),
    title: Text(
      record.title,
      style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        [
          _longDate(record.completedAt),
          if (record.provider.isNotEmpty) record.provider,
          if (record.nextDueAt != null)
            'Prochaine : ${_shortDate(record.nextDueAt!)}',
        ].join(' · '),
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
    ),
    trailing: IconButton(
      tooltip: 'Supprimer',
      onPressed: onDelete,
      icon: const Icon(Icons.delete_outline_rounded, color: _muted),
    ),
  );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard();

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4FF),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFC7DDF8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.verified_outlined, color: _primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Repères issus de sources sanitaires officielles',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Les calendriers et dépistages varient selon le pays, les ressources et chaque personne. Validez toujours votre plan avec un professionnel en Haïti.',
          style: TextStyle(color: _ink, height: 1.4, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _open(
                'https://immunizationdata.who.int/global/wiise-detail-page/vaccination-schedule-for-country_name?ISO_3_CODE=HTI',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Calendrier Haïti'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.who.int/tools/your-life-your-health/life-phase/early-and-middle-adulthood/keeping-well-in-adulthood',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Conseils OMS'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.who.int/news-room/fact-sheets/detail/breast-cancer',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Cancer du sein'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.who.int/news-room/fact-sheets/detail/cervical-cancer',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Cancer du col'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.uspreventiveservicestaskforce.org/uspstf/recommendation/colorectal-cancer-screening',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Dépistage colorectal'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.uspreventiveservicestaskforce.org/uspstf/recommendation/prostate-cancer-screening',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Dépistage prostate'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.who.int/fr/news-room/fact-sheets/detail/healthy-diet',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Alimentation saine'),
            ),
            TextButton.icon(
              onPressed: () => _open(
                'https://www.who.int/news-room/questions-and-answers/item/guidelines-for-drinking-water-quality---frequently-asked-questions',
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Eau potable'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PreventiveFeedback extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PreventiveFeedback({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primary, size: 42),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class _PreventiveRecordForm extends StatefulWidget {
  final DateTime now;
  final PreventivePlanItem? planItem;
  final String? initialTitle;
  final PreventiveCareCategory? initialCategory;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const _PreventiveRecordForm({
    required this.now,
    required this.planItem,
    this.initialTitle,
    this.initialCategory,
    required this.onSave,
  });

  @override
  State<_PreventiveRecordForm> createState() => _PreventiveRecordFormState();
}

class _PreventiveRecordFormState extends State<_PreventiveRecordForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _providerController;
  late final TextEditingController _noteController;
  late PreventiveCareCategory _category;
  late DateTime _completedAt;
  DateTime? _nextDueAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category =
        widget.initialCategory ??
        widget.planItem?.category ??
        PreventiveCareCategory.checkup;
    _titleController = TextEditingController(
      text: widget.initialTitle ?? widget.planItem?.title ?? '',
    );
    _providerController = TextEditingController();
    _noteController = TextEditingController();
    _completedAt = _dateOnly(widget.now);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _providerController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickCompletedAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _completedAt,
      firstDate: DateTime(1920),
      lastDate: _dateOnly(widget.now),
      helpText: 'Date de réalisation',
    );
    if (picked != null) setState(() => _completedAt = picked);
  }

  Future<void> _pickNextDueAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueAt ?? _completedAt.add(const Duration(days: 365)),
      firstDate: _completedAt.add(const Duration(days: 1)),
      lastDate: DateTime(widget.now.year + 20, 12, 31),
      helpText: 'Prochaine échéance',
    );
    if (picked != null) setState(() => _nextDueAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'category': _category.id,
        'title': _titleController.text.trim(),
        'planItemId': widget.planItem?.id ?? '',
        'completedAt': _completedAt,
        if (_nextDueAt != null) 'nextDueAt': _nextDueAt,
        'provider': _providerController.text.trim(),
        'note': _noteController.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enregistrement impossible. Réessayez.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ajouter à mon carnet',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Enregistrez ce qui a été réalisé. Vous pouvez ajouter la prochaine date conseillée par votre professionnel.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<PreventiveCareCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: PreventiveCareCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(category.icon, color: category.color, size: 20),
                          const SizedBox(width: 10),
                          Text(category.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('preventive-title-field'),
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Action réalisée',
                hintText: 'Ex. Consultation générale',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indiquez l’action réalisée.'
                  : null,
            ),
            const SizedBox(height: 4),
            _DateField(
              label: 'Réalisée le',
              value: _longDate(_completedAt),
              icon: Icons.event_available_outlined,
              onTap: _pickCompletedAt,
            ),
            const SizedBox(height: 14),
            _DateField(
              key: const Key('preventive-next-date-field'),
              label: 'Prochaine échéance (facultatif)',
              value: _nextDueAt == null
                  ? 'Ajouter une date'
                  : _longDate(_nextDueAt!),
              icon: Icons.notifications_active_outlined,
              onTap: _pickNextDueAt,
              onClear: _nextDueAt == null
                  ? null
                  : () => setState(() => _nextDueAt = null),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('preventive-provider-field'),
              controller: _providerController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Professionnel ou établissement (facultatif)',
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              key: const Key('preventive-note-field'),
              controller: _noteController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note privée (facultatif)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('preventive-save-record'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outline_rounded, size: 20),
                label: Text(
                  _saving ? 'Enregistrement…' : 'Enregistrer dans mon carnet',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreventiveReminderForm extends StatefulWidget {
  final DateTime now;
  final PreventivePlanItem? planItem;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const _PreventiveReminderForm({
    required this.now,
    required this.planItem,
    required this.onSave,
  });

  @override
  State<_PreventiveReminderForm> createState() =>
      _PreventiveReminderFormState();
}

class _PreventiveReminderFormState extends State<_PreventiveReminderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late PreventiveCareCategory _category;
  late DateTime _dueAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = widget.planItem?.category ?? PreventiveCareCategory.checkup;
    _titleController = TextEditingController(
      text: widget.planItem?.title ?? 'Faire mon prochain check-up',
    );
    _noteController = TextEditingController();
    _dueAt = _dateOnly(widget.now.add(const Duration(days: 30)));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _usePreset(int months) {
    final now = _dateOnly(widget.now);
    final targetMonth = now.month - 1 + months;
    final year = now.year + targetMonth ~/ 12;
    final month = targetMonth % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    setState(
      () =>
          _dueAt = DateTime(year, month, now.day > lastDay ? lastDay : now.day),
    );
  }

  Future<void> _pickDueAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: _dateOnly(widget.now),
      lastDate: DateTime(widget.now.year + 20, 12, 31),
      helpText: 'Date du rappel',
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'category': _category.id,
        'title': _titleController.text.trim(),
        'planItemId': widget.planItem?.id ?? '',
        'dueAt': _dueAt,
        'note': _noteController.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Création du rappel impossible.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.add_alarm_rounded, color: _primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Créer un rappel',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Visible dans votre plan I-ENTIER',
                        style: TextStyle(color: _muted, fontSize: 12),
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
            const SizedBox(height: 20),
            DropdownButtonFormField<PreventiveCareCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: PreventiveCareCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('preventive-reminder-title-field'),
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Objet du rappel'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indiquez ce que vous souhaitez planifier.'
                  : null,
            ),
            const SizedBox(height: 4),
            _DateField(
              key: const Key('preventive-reminder-date-field'),
              label: 'Me le rappeler le',
              value: _longDate(_dueAt),
              icon: Icons.event_outlined,
              onTap: _pickDueAt,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choix rapide',
              style: TextStyle(
                color: _navy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const Key('preventive-reminder-preset-1'),
                  onPressed: () => _usePreset(1),
                  label: const Text('1 mois'),
                ),
                ActionChip(
                  onPressed: () => _usePreset(3),
                  label: const Text('3 mois'),
                ),
                ActionChip(
                  onPressed: () => _usePreset(6),
                  label: const Text('6 mois'),
                ),
                ActionChip(
                  onPressed: () => _usePreset(12),
                  label: const Text('1 an'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('preventive-reminder-note-field'),
              controller: _noteController,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note privée (facultatif)',
                hintText: 'Ex. appeler la clinique pour confirmer',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('preventive-save-reminder'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.notifications_active_outlined, size: 20),
                label: Text(_saving ? 'Création…' : 'Ajouter à mes rappels'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: _primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Retirer la date',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: _muted, size: 20),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.chevron_right_rounded, color: _muted),
              ),
          ],
        ),
      ),
    ),
  );
}

DateTime? _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> _stringList(dynamic value) {
  if (value is Iterable) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

int _ageOn(DateTime birthDate, DateTime today) {
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

const _months = [
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

String _longDate(DateTime value) =>
    '${value.day} ${_months[value.month - 1]} ${value.year}';

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

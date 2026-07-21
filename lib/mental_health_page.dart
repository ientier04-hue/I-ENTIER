import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _primary = Color(0xFF7656D8);
const _primaryDark = Color(0xFF4E369B);
const _primarySoft = Color(0xFFF1ECFF);
const _rose = Color(0xFFDB5F88);
const _roseSoft = Color(0xFFFFECF2);
const _teal = Color(0xFF078C83);
const _tealSoft = Color(0xFFE4F7F3);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF7F7FC);

/// Contact public du Centre Haïtien de Réhabilitation Psychosociale et
/// d'Épanouissement (PSYCREPH): https://psycreph.org/nos-actions-et-services/
const _psycrephPhone = '+50931112640';
const _psycrephWebsite = 'https://psycreph.org/nos-actions-et-services/';
const _canEmergencyNumber = '116';

enum _MentalHealthSection { overview, journal, tools, support }

extension _MentalHealthSectionDetails on _MentalHealthSection {
  String get label => switch (this) {
    _MentalHealthSection.overview => 'Accueil',
    _MentalHealthSection.journal => 'Journal',
    _MentalHealthSection.tools => 'Outils',
    _MentalHealthSection.support => 'Soutien',
  };

  IconData get icon => switch (this) {
    _MentalHealthSection.overview => Icons.home_outlined,
    _MentalHealthSection.journal => Icons.auto_stories_outlined,
    _MentalHealthSection.tools => Icons.self_improvement_outlined,
    _MentalHealthSection.support => Icons.support_agent_outlined,
  };
}

enum MentalHealthMood { veryLow, low, neutral, good, veryGood }

extension MentalHealthMoodDetails on MentalHealthMood {
  String get id => switch (this) {
    MentalHealthMood.veryLow => 'veryLow',
    MentalHealthMood.low => 'low',
    MentalHealthMood.neutral => 'neutral',
    MentalHealthMood.good => 'good',
    MentalHealthMood.veryGood => 'veryGood',
  };

  String get label => switch (this) {
    MentalHealthMood.veryLow => 'Très mal',
    MentalHealthMood.low => 'Difficile',
    MentalHealthMood.neutral => 'Moyen',
    MentalHealthMood.good => 'Bien',
    MentalHealthMood.veryGood => 'Très bien',
  };

  int get score => index + 1;

  IconData get icon => switch (this) {
    MentalHealthMood.veryLow => Icons.sentiment_very_dissatisfied_rounded,
    MentalHealthMood.low => Icons.sentiment_dissatisfied_rounded,
    MentalHealthMood.neutral => Icons.sentiment_neutral_rounded,
    MentalHealthMood.good => Icons.sentiment_satisfied_alt_rounded,
    MentalHealthMood.veryGood => Icons.sentiment_very_satisfied_rounded,
  };

  Color get color => switch (this) {
    MentalHealthMood.veryLow => const Color(0xFFD6455D),
    MentalHealthMood.low => const Color(0xFFE77B55),
    MentalHealthMood.neutral => const Color(0xFFE0A128),
    MentalHealthMood.good => const Color(0xFF2D9D78),
    MentalHealthMood.veryGood => const Color(0xFF087D77),
  };

  static MentalHealthMood? fromId(String value) {
    for (final mood in MentalHealthMood.values) {
      if (mood.id == value) return mood;
    }
    return null;
  }
}

class MentalHealthEntry {
  final String id;
  final MentalHealthMood mood;
  final List<String> feelings;
  final String note;
  final DateTime createdAt;

  const MentalHealthEntry({
    required this.id,
    required this.mood,
    required this.feelings,
    required this.note,
    required this.createdAt,
  });

  factory MentalHealthEntry.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final mood = MentalHealthMoodDetails.fromId(data['mood']?.toString() ?? '');
    final timestamp = data['createdAt'];
    return MentalHealthEntry(
      id: document.id,
      mood: mood ?? MentalHealthMood.neutral,
      feelings: data['feelings'] is List
          ? (data['feelings'] as List)
                .map((value) => value.toString())
                .where(_feelingLabels.containsKey)
                .toList()
          : const [],
      note: data['note']?.toString() ?? '',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
    );
  }
}

class MentalHealthProfessional {
  final String id;
  final String name;
  final String specialty;
  final String description;
  final String phone;
  final String email;
  final String address;
  final bool available;

  const MentalHealthProfessional({
    required this.id,
    required this.name,
    required this.specialty,
    this.description = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.available = false,
  });

  factory MentalHealthProfessional.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return MentalHealthProfessional(
      id: document.id,
      name: _firstText(data, ['name', 'fullName', 'nom', 'nomComplet']),
      specialty: _firstText(data, [
        'specialty',
        'specialite',
        'profession',
        'role',
        'title',
      ]),
      description: _firstText(data, [
        'description',
        'bio',
        'services',
        'expertise',
      ]),
      phone: _firstText(data, ['phone', 'telephone', 'phoneNumber']),
      email: _firstText(data, ['email', 'courriel']),
      address: _firstText(data, ['address', 'adresse', 'location']),
      available: data['available'] == true || data['disponible'] == true,
    );
  }

  bool get isMentalHealthProfessional {
    final searchable = '$specialty $description'.toLowerCase();
    return const [
      'psycholog',
      'psychiatr',
      'psychothé',
      'psychothe',
      'santé mentale',
      'sante mentale',
      'psychosocial',
    ].any(searchable.contains);
  }
}

const _feelingLabels = <String, String>{
  'anxious': 'Anxieux·se',
  'sad': 'Triste',
  'stressed': 'Stressé·e',
  'tired': 'Fatigué·e',
  'lonely': 'Seul·e',
  'angry': 'En colère',
  'calm': 'Calme',
  'hopeful': 'Plein·e d’espoir',
};

class MentalHealthPage extends StatefulWidget {
  final String patientId;
  final Map<String, dynamic> patientProfile;
  final Stream<List<MentalHealthEntry>>? entryStream;
  final Stream<List<MentalHealthProfessional>>? professionalStream;
  final Future<void> Function(Map<String, dynamic> data)? onSaveEntry;
  final Future<void> Function(String entryId)? onDeleteEntry;

  const MentalHealthPage({
    super.key,
    required this.patientId,
    this.patientProfile = const <String, dynamic>{},
    this.entryStream,
    this.professionalStream,
    this.onSaveEntry,
    this.onDeleteEntry,
  });

  @override
  State<MentalHealthPage> createState() => _MentalHealthPageState();
}

class _MentalHealthPageState extends State<MentalHealthPage> {
  final _noteController = TextEditingController();
  _MentalHealthSection _section = _MentalHealthSection.overview;
  MentalHealthMood? _selectedMood;
  final Set<String> _selectedFeelings = <String>{};
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _entries => FirebaseFirestore
      .instance
      .collection('patients')
      .doc(widget.patientId)
      .collection('mentalHealthEntries');

  Stream<List<MentalHealthEntry>> get _entriesStream =>
      widget.entryStream ??
      _entries
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(MentalHealthEntry.fromFirestore).toList(),
          );

  Stream<List<MentalHealthProfessional>> get _professionalsStream =>
      widget.professionalStream ??
      FirebaseFirestore.instance
          .collection('personnelMedical')
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(MentalHealthProfessional.fromFirestore)
                .where(
                  (professional) =>
                      professional.name.isNotEmpty &&
                      professional.isMentalHealthProfessional,
                )
                .toList(),
          );

  String get _emergencyContactPhone {
    final contact = widget.patientProfile['emergencyContact'];
    if (contact is Map) {
      final value = contact['phone'] ?? contact['telephone'];
      if (value != null) return value.toString().trim();
    }
    return _firstText(widget.patientProfile, [
      'emergencyContactPhone',
      'telephoneUrgence',
    ]);
  }

  String get _emergencyContactName {
    final contact = widget.patientProfile['emergencyContact'];
    if (contact is Map) {
      final value = contact['name'] ?? contact['nom'];
      if (value != null) return value.toString().trim();
    }
    return _firstText(widget.patientProfile, ['emergencyContactName']);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _saveCheckIn() async {
    final mood = _selectedMood;
    if (mood == null || _saving) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'mood': mood.id,
      'moodScore': mood.score,
      'feelings': _selectedFeelings.toList()..sort(),
      'note': _noteController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      final writer = widget.onSaveEntry;
      if (writer != null) {
        await writer(data);
      } else {
        await _entries.add(data);
      }
      if (!mounted) return;
      setState(() {
        _selectedMood = null;
        _selectedFeelings.clear();
        _noteController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre point bien-être a été enregistré.'),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (error.code) {
              'permission-denied' =>
                'Accès refusé par la sécurité Firebase. Réessayez après la mise à jour.',
              'unavailable' =>
                'Connexion indisponible. Vérifiez votre accès à Internet.',
              _ => 'Impossible d’enregistrer pour le moment.',
            }),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEntry(MentalHealthEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette entrée ?'),
        content: const Text(
          'Ce point bien-être sera définitivement retiré de votre journal.',
        ),
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
      final deleter = widget.onDeleteEntry;
      if (deleter != null) {
        await deleter(entry.id);
      } else {
        await _entries.doc(entry.id).delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Entrée supprimée.')));
      }
    } on FirebaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suppression impossible.')),
        );
      }
    }
  }

  Future<void> _openCrisisSupport() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CrisisSupportSheet(
      emergencyContactName: _emergencyContactName,
      emergencyContactPhone: _emergencyContactPhone,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text('Soutien psychologique'),
      actions: [
        IconButton(
          tooltip: 'Aide urgente',
          onPressed: _openCrisisSupport,
          icon: const Icon(Icons.sos_rounded, color: _rose),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: _SectionSwitcher(
                  selected: _section,
                  onSelected: (section) => setState(() => _section = section),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _section.index,
                  children: [
                    _SectionScroll(
                      key: const PageStorageKey('mental-health-overview'),
                      children: [
                        _WelcomeCard(
                          onFindProfessional: () => setState(
                            () => _section = _MentalHealthSection.support,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _CrisisBanner(onTap: _openCrisisSupport),
                        const SizedBox(height: 28),
                        const _SectionTitle(
                          eyebrow: 'VOS ESPACES',
                          title: 'Que souhaitez-vous faire ?',
                          subtitle:
                              'Chaque fonctionnalité est maintenant regroupée dans un espace dédié.',
                        ),
                        const SizedBox(height: 14),
                        _DashboardActions(
                          onSelected: (section) =>
                              setState(() => _section = section),
                        ),
                        const SizedBox(height: 24),
                        const _ClinicalNotice(),
                      ],
                    ),
                    _SectionScroll(
                      key: const PageStorageKey('mental-health-journal'),
                      children: [
                        const _SectionTitle(
                          eyebrow: 'POINT BIEN-ÊTRE',
                          title: 'Comment vous sentez-vous ?',
                          subtitle:
                              'Prenez un instant pour reconnaître ce que vous vivez.',
                        ),
                        const SizedBox(height: 14),
                        _CheckInCard(
                          selectedMood: _selectedMood,
                          selectedFeelings: _selectedFeelings,
                          noteController: _noteController,
                          saving: _saving,
                          onMoodSelected: (mood) =>
                              setState(() => _selectedMood = mood),
                          onFeelingSelected: (feeling, selected) =>
                              setState(() {
                                if (selected) {
                                  _selectedFeelings.add(feeling);
                                } else {
                                  _selectedFeelings.remove(feeling);
                                }
                              }),
                          onSave: _saveCheckIn,
                        ),
                        const SizedBox(height: 30),
                        const _SectionTitle(
                          eyebrow: 'VOTRE ESPACE PRIVÉ',
                          title: 'Journal récent',
                          subtitle:
                              'Vos entrées restent associées à votre compte personnel.',
                        ),
                        const SizedBox(height: 14),
                        _EntryHistory(
                          stream: _entriesStream,
                          onDelete: _deleteEntry,
                        ),
                      ],
                    ),
                    _SectionScroll(
                      key: const PageStorageKey('mental-health-tools'),
                      children: [
                        const _SectionTitle(
                          eyebrow: 'OUTILS IMMÉDIATS',
                          title: 'Retrouvez un peu de calme',
                          subtitle:
                              'Des exercices courts pour traverser un moment difficile.',
                        ),
                        const SizedBox(height: 14),
                        _WellbeingTools(onCrisisTap: _openCrisisSupport),
                        const SizedBox(height: 20),
                        _CrisisBanner(onTap: _openCrisisSupport),
                      ],
                    ),
                    _SectionScroll(
                      key: const PageStorageKey('mental-health-support'),
                      children: [
                        _CrisisBanner(onTap: _openCrisisSupport),
                        const SizedBox(height: 26),
                        const _SectionTitle(
                          eyebrow: 'ACCOMPAGNEMENT HUMAIN',
                          title: 'Parler à un professionnel',
                          subtitle:
                              'Contactez directement une ressource spécialisée en santé mentale.',
                        ),
                        const SizedBox(height: 14),
                        _ProfessionalDirectory(stream: _professionalsStream),
                        const SizedBox(height: 24),
                        const _ClinicalNotice(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SectionScroll extends StatelessWidget {
  final List<Widget> children;

  const _SectionScroll({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: key,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _SectionSwitcher extends StatelessWidget {
  final _MentalHealthSection selected;
  final ValueChanged<_MentalHealthSection> onSelected;

  const _SectionSwitcher({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x10102A56),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        for (final section in _MentalHealthSection.values)
          Expanded(
            child: _SectionSwitchItem(
              section: section,
              selected: section == selected,
              onTap: () => onSelected(section),
            ),
          ),
      ],
    ),
  );
}

class _SectionSwitchItem extends StatelessWidget {
  final _MentalHealthSection section;
  final bool selected;
  final VoidCallback onTap;

  const _SectionSwitchItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: Key('mental-health-section-${section.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              section.icon,
              size: 19,
              color: selected ? Colors.white : _muted,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                section.label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : _ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardActions extends StatelessWidget {
  final ValueChanged<_MentalHealthSection> onSelected;

  const _DashboardActions({required this.onSelected});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 3 : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final actions = [
        _DashboardActionCard(
          key: const Key('mental-health-dashboard-journal'),
          icon: Icons.edit_note_rounded,
          color: _primary,
          background: _primarySoft,
          title: 'Mon journal',
          description: 'Notez votre humeur et retrouvez votre historique.',
          onTap: () => onSelected(_MentalHealthSection.journal),
        ),
        _DashboardActionCard(
          key: const Key('mental-health-dashboard-tools'),
          icon: Icons.self_improvement_rounded,
          color: _teal,
          background: _tealSoft,
          title: 'Mes outils',
          description: 'Respirez, recentrez-vous et traversez le moment.',
          onTap: () => onSelected(_MentalHealthSection.tools),
        ),
        _DashboardActionCard(
          key: const Key('mental-health-dashboard-support'),
          icon: Icons.people_alt_outlined,
          color: _rose,
          background: _roseSoft,
          title: 'Trouver du soutien',
          description: 'Accédez aux contacts et aux professionnels.',
          onTap: () => onSelected(_MentalHealthSection.support),
        ),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final action in actions) SizedBox(width: width, child: action),
        ],
      );
    },
  );
}

class _DashboardActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DashboardActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: background,
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: color, size: 19),
          ],
        ),
      ),
    ),
  );
}

class _WelcomeCard extends StatelessWidget {
  final VoidCallback onFindProfessional;

  const _WelcomeCard({required this.onFindProfessional});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_primaryDark, Color(0xFF8265DF), Color(0xFFB36BA8)],
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x337656D8),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x24FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x35FFFFFF)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Confidentiel et sans jugement',
                      maxLines: 2,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Vous n’avez pas à tout porter seul·e.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                height: 1.12,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Évaluez votre état, utilisez un outil d’apaisement ou trouvez une personne qualifiée à qui parler.',
              style: TextStyle(
                color: Color(0xFFEDE8FF),
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onFindProfessional,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _primaryDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
              ),
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('Trouver du soutien'),
            ),
          ],
        );
        if (!wide) return content;
        return Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 30),
            Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                color: Color(0x1FFFFFFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                color: Colors.white,
                size: 84,
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _CrisisBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CrisisBanner({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: _roseSoft,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: const Key('mental-health-crisis-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sos_rounded, color: _rose),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Besoin d’aide maintenant ?',
                    style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Accédez aux contacts d’urgence et à votre personne de confiance.',
                    style: TextStyle(color: _ink, fontSize: 12.5, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: _rose),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: _primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        title,
        style: const TextStyle(
          color: _navy,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -.25,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.4),
      ),
    ],
  );
}

class _CheckInCard extends StatelessWidget {
  final MentalHealthMood? selectedMood;
  final Set<String> selectedFeelings;
  final TextEditingController noteController;
  final bool saving;
  final ValueChanged<MentalHealthMood> onMoodSelected;
  final void Function(String feeling, bool selected) onFeelingSelected;
  final VoidCallback onSave;

  const _CheckInCard({
    required this.selectedMood,
    required this.selectedFeelings,
    required this.noteController,
    required this.saving,
    required this.onMoodSelected,
    required this.onFeelingSelected,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 7.0;
            final itemWidth = (constraints.maxWidth - gap * 4) / 5;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var index = 0;
                  index < MentalHealthMood.values.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: gap),
                  SizedBox(
                    width: itemWidth,
                    child: _MoodButton(
                      mood: MentalHealthMood.values[index],
                      selected: selectedMood == MentalHealthMood.values[index],
                      onTap: () =>
                          onMoodSelected(MentalHealthMood.values[index]),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text(
          'Qu’est-ce qui est le plus présent ?',
          style: TextStyle(color: _navy, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            for (final feeling in _feelingLabels.entries)
              FilterChip(
                key: Key('mental-health-feeling-${feeling.key}'),
                label: Text(feeling.value),
                selected: selectedFeelings.contains(feeling.key),
                onSelected: (selected) =>
                    onFeelingSelected(feeling.key, selected),
                selectedColor: _primarySoft,
                checkmarkColor: _primary,
                side: BorderSide(
                  color: selectedFeelings.contains(feeling.key)
                      ? _primary
                      : _border,
                ),
                labelStyle: TextStyle(
                  color: selectedFeelings.contains(feeling.key)
                      ? _primaryDark
                      : _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('mental-health-note-field'),
          controller: noteController,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Une note pour vous (facultatif)',
            hintText: 'Écrivez librement ce que vous ressentez…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('mental-health-save-check-in'),
            onPressed: selectedMood == null || saving ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_outline_rounded, size: 19),
            label: Text(saving ? 'Enregistrement…' : 'Enregistrer mon état'),
          ),
        ),
      ],
    ),
  );
}

class _MoodButton extends StatelessWidget {
  final MentalHealthMood mood;
  final bool selected;
  final VoidCallback onTap;

  const _MoodButton({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? mood.color.withValues(alpha: .12)
        : const Color(0xFFF8F9FC),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      key: Key('mental-health-mood-${mood.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? mood.color : _border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(mood.icon, color: mood.color, size: 29),
            const SizedBox(height: 6),
            Text(
              mood.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? mood.color : _ink,
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WellbeingTools extends StatelessWidget {
  final VoidCallback onCrisisTap;

  const _WellbeingTools({required this.onCrisisTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 3 : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final tools = [
        _ToolCard(
          key: const Key('mental-health-breathing-tool'),
          icon: Icons.air_rounded,
          color: _teal,
          background: _tealSoft,
          title: 'Respiration guidée',
          description: 'Une minute pour ralentir et retrouver votre souffle.',
          duration: '1 min',
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _BreathingExerciseSheet(),
          ),
        ),
        _ToolCard(
          key: const Key('mental-health-grounding-tool'),
          icon: Icons.spa_outlined,
          color: _primary,
          background: _primarySoft,
          title: 'Ancrage 5-4-3-2-1',
          description: 'Revenez au présent en mobilisant vos cinq sens.',
          duration: '3 min',
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _GroundingExerciseSheet(),
          ),
        ),
        _ToolCard(
          key: const Key('mental-health-safety-tool'),
          icon: Icons.health_and_safety_outlined,
          color: _rose,
          background: _roseSoft,
          title: 'Je ne me sens pas en sécurité',
          description: 'Contactez immédiatement une personne ou un service.',
          duration: 'Aide',
          onTap: onCrisisTap,
        ),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final tool in tools) SizedBox(width: width, child: tool),
        ],
      );
    },
  );
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String description;
  final String duration;
  final VoidCallback onTap;

  const _ToolCard({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.description,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Text(
                  duration,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Icon(Icons.arrow_forward_rounded, color: color, size: 18),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _EntryHistory extends StatelessWidget {
  final Stream<List<MentalHealthEntry>> stream;
  final ValueChanged<MentalHealthEntry> onDelete;

  const _EntryHistory({required this.stream, required this.onDelete});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MentalHealthEntry>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _FeedbackCard(
          icon: Icons.lock_outline_rounded,
          title: 'Journal indisponible',
          message: 'Vos entrées ne peuvent pas être chargées pour le moment.',
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 110,
          child: Center(child: CircularProgressIndicator(color: _primary)),
        );
      }
      final entries = snapshot.data!;
      if (entries.isEmpty) {
        return const _FeedbackCard(
          icon: Icons.auto_stories_outlined,
          title: 'Votre journal commence ici',
          message:
              'Enregistrez un premier point bien-être pour suivre votre ressenti.',
        );
      }
      return Container(
        decoration: _cardDecoration,
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              _EntryTile(entry: entries[index], onDelete: onDelete),
              if (index < entries.length - 1)
                const Divider(height: 1, indent: 76, color: _border),
            ],
          ],
        ),
      );
    },
  );
}

class _EntryTile extends StatelessWidget {
  final MentalHealthEntry entry;
  final ValueChanged<MentalHealthEntry> onDelete;

  const _EntryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: entry.mood.color.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(entry.mood.icon, color: entry.mood.color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.mood.label,
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _formatDate(entry.createdAt),
                    style: const TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
              if (entry.feelings.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.feelings
                      .map((feeling) => _feelingLabels[feeling] ?? feeling)
                      .join(' · '),
                  style: const TextStyle(
                    color: _primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (entry.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.note,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Options de l’entrée',
          onSelected: (value) {
            if (value == 'delete') onDelete(entry);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: 9),
                  Text('Supprimer'),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProfessionalDirectory extends StatelessWidget {
  final Stream<List<MentalHealthProfessional>> stream;

  const _ProfessionalDirectory({required this.stream});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _PsycrephCard(),
      const SizedBox(height: 12),
      StreamBuilder<List<MentalHealthProfessional>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _FeedbackCard(
              icon: Icons.person_search_outlined,
              title: 'Annuaire momentanément indisponible',
              message:
                  'La ressource spécialisée ci-dessus reste accessible directement.',
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(color: _primary)),
            );
          }
          final professionals = snapshot.data!;
          if (professionals.isEmpty) {
            return const _FeedbackCard(
              icon: Icons.people_outline_rounded,
              title: 'D’autres professionnels seront ajoutés',
              message:
                  'L’annuaire affichera ici les psychologues, psychiatres et intervenants psychosociaux disponibles.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final professional in professionals)
                    SizedBox(
                      width: width,
                      child: _ProfessionalCard(professional: professional),
                    ),
                ],
              );
            },
          );
        },
      ),
    ],
  );
}

class _PsycrephCard extends StatelessWidget {
  const _PsycrephCard();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _primarySoft,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD8CCFF)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('mental-health-call-psycreph'),
              onPressed: () => _launchPhone(context, _psycrephPhone),
              style: FilledButton.styleFrom(backgroundColor: _primary),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Appeler'),
            ),
            OutlinedButton.icon(
              onPressed: () => _launchExternal(context, _psycrephWebsite),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryDark,
                side: const BorderSide(color: _primary),
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text('Voir les services'),
            ),
          ],
        );
        final information = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: _primary, size: 18),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Ressource locale',
                    style: TextStyle(
                      color: _primaryDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 7),
            Text(
              'PSYCREPH',
              style: TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Appui psychologique et psychosocial pour enfants, jeunes, adultes et familles en Haïti.',
              style: TextStyle(color: _ink, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 7),
            Text(
              '+509 3111 2640 · Port-au-Prince',
              style: TextStyle(
                color: _primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 650) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [information, const SizedBox(height: 15), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: information),
            const SizedBox(width: 20),
            actions,
          ],
        );
      },
    ),
  );
}

class _ProfessionalCard extends StatelessWidget {
  final MentalHealthProfessional professional;

  const _ProfessionalCard({required this.professional});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: _cardDecoration,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _tealSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.psychology_outlined, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    professional.name,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    professional.specialty.isEmpty
                        ? 'Santé mentale'
                        : professional.specialty,
                    style: const TextStyle(
                      color: _teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (professional.available)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Disponible',
                  style: TextStyle(
                    color: _teal,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        if (professional.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            professional.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
          ),
        ],
        if (professional.address.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: _muted, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  professional.address,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        if (professional.phone.isNotEmpty || professional.email.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              if (professional.phone.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launchPhone(context, professional.phone),
                    style: FilledButton.styleFrom(backgroundColor: _primary),
                    icon: const Icon(Icons.phone_outlined, size: 17),
                    label: const Text('Appeler'),
                  ),
                ),
              if (professional.phone.isNotEmpty &&
                  professional.email.isNotEmpty)
                const SizedBox(width: 8),
              if (professional.email.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launchEmail(context, professional.email),
                    style: OutlinedButton.styleFrom(foregroundColor: _primary),
                    icon: const Icon(Icons.email_outlined, size: 17),
                    label: const Text('Écrire'),
                  ),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _ClinicalNotice extends StatelessWidget {
  const _ClinicalNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F3F8),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: _muted, size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'I-ENTIER propose des outils de soutien et d’orientation. Ce service ne pose pas de diagnostic et ne remplace pas une consultation avec un professionnel qualifié.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
          ),
        ),
      ],
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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: _cardDecoration,
    child: Column(
      children: [
        Icon(icon, color: _primary, size: 34),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    ),
  );
}

class _CrisisSupportSheet extends StatelessWidget {
  final String emergencyContactName;
  final String emergencyContactPhone;

  const _CrisisSupportSheet({
    required this.emergencyContactName,
    required this.emergencyContactPhone,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetIcon(icon: Icons.favorite_rounded, color: _rose),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vous méritez une aide immédiate',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Si vous risquez de vous faire du mal ou de faire du mal à quelqu’un, ne restez pas seul·e. Éloignez-vous de tout objet dangereux et contactez une personne ou un service maintenant.',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _CrisisAction(
            key: const Key('mental-health-call-can'),
            icon: Icons.local_hospital_rounded,
            color: _rose,
            title: 'Urgence médicale — CAN',
            subtitle: 'Composer gratuitement le 116',
            onTap: () => _launchPhone(context, _canEmergencyNumber),
          ),
          if (emergencyContactPhone.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CrisisAction(
              key: const Key('mental-health-call-trusted-contact'),
              icon: Icons.person_rounded,
              color: _primary,
              title: emergencyContactName.isEmpty
                  ? 'Ma personne de confiance'
                  : emergencyContactName,
              subtitle: 'Appeler mon contact d’urgence',
              onTap: () => _launchPhone(context, emergencyContactPhone),
            ),
          ],
          const SizedBox(height: 10),
          _CrisisAction(
            icon: Icons.support_agent_rounded,
            color: _teal,
            title: 'Soutien psychosocial — PSYCREPH',
            subtitle: 'Appeler le +509 3111 2640',
            onTap: () => _launchPhone(context, _psycrephPhone),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              'La disponibilité des secours peut varier selon la zone et la situation sécuritaire. Si personne ne répond, demandez à un proche de vous accompagner vers le service d’urgence le plus proche.',
              style: TextStyle(color: _muted, fontSize: 11.5, height: 1.45),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CrisisAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CrisisAction({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .09),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _SheetIcon(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.phone_forwarded_rounded, color: color),
          ],
        ),
      ),
    ),
  );
}

class _SheetIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SheetIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, color: color),
  );
}

class _BreathingExerciseSheet extends StatefulWidget {
  const _BreathingExerciseSheet();

  @override
  State<_BreathingExerciseSheet> createState() =>
      _BreathingExerciseSheetState();
}

class _BreathingExerciseSheetState extends State<_BreathingExerciseSheet> {
  Timer? _timer;
  int _elapsed = 0;
  bool _running = false;

  static const _totalSeconds = 60;

  String get _phase {
    if (!_running && _elapsed == 0) return 'Prêt·e ?';
    if (_elapsed >= _totalSeconds) return 'Bravo';
    final cycle = _elapsed % 14;
    if (cycle < 4) return 'Inspirez';
    if (cycle < 8) return 'Gardez l’air';
    return 'Expirez doucement';
  }

  double get _scale {
    if (!_running) return 1;
    final cycle = _elapsed % 14;
    if (cycle < 4) return .78 + (cycle / 4) * .22;
    if (cycle < 8) return 1;
    return 1 - ((cycle - 8) / 6) * .22;
  }

  void _toggle() {
    if (_elapsed >= _totalSeconds) _elapsed = 0;
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
        if (_elapsed >= _totalSeconds) {
          _running = false;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ExerciseSheetFrame(
    title: 'Respiration guidée',
    subtitle: 'Inspirez 4 secondes, gardez 4 secondes, expirez 6 secondes.',
    child: Column(
      children: [
        const SizedBox(height: 22),
        SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: _scale),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: Container(
                    width: 205,
                    height: 205,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFFB5EEE5), Color(0xFF7BD5CB)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33078C83),
                          blurRadius: 35,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _phase,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${(_totalSeconds - _elapsed).clamp(0, _totalSeconds)} s',
                    style: const TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _toggle,
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: Icon(
              _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              _elapsed >= _totalSeconds
                  ? 'Recommencer'
                  : _running
                  ? 'Mettre en pause'
                  : 'Commencer',
            ),
          ),
        ),
      ],
    ),
  );
}

class _GroundingExerciseSheet extends StatefulWidget {
  const _GroundingExerciseSheet();

  @override
  State<_GroundingExerciseSheet> createState() =>
      _GroundingExerciseSheetState();
}

class _GroundingExerciseSheetState extends State<_GroundingExerciseSheet> {
  final Set<int> _completed = <int>{};
  static const _steps = [
    ('5', 'choses que vous pouvez voir', Icons.visibility_outlined),
    ('4', 'choses que vous pouvez toucher', Icons.touch_app_outlined),
    ('3', 'sons que vous pouvez entendre', Icons.hearing_outlined),
    ('2', 'odeurs que vous pouvez sentir', Icons.air_rounded),
    ('1', 'chose que vous pouvez goûter', Icons.restaurant_outlined),
  ];

  @override
  Widget build(BuildContext context) => _ExerciseSheetFrame(
    title: 'Ancrage 5-4-3-2-1',
    subtitle:
        'Prenez votre temps. Observez votre environnement sans vous presser.',
    child: Column(
      children: [
        const SizedBox(height: 18),
        for (var index = 0; index < _steps.length; index++) ...[
          Material(
            color: _completed.contains(index) ? _tealSoft : Colors.white,
            borderRadius: BorderRadius.circular(17),
            child: InkWell(
              onTap: () => setState(() {
                if (!_completed.add(index)) _completed.remove(index);
              }),
              borderRadius: BorderRadius.circular(17),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _completed.contains(index) ? _teal : _border,
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _completed.contains(index)
                          ? _teal
                          : _primarySoft,
                      foregroundColor: _completed.contains(index)
                          ? Colors.white
                          : _primary,
                      child: Text(
                        _steps[index].$1,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(_steps[index].$3, color: _primary, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _steps[index].$2,
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      _completed.contains(index)
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _completed.contains(index) ? _teal : _border,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (index < _steps.length - 1) const SizedBox(height: 9),
        ],
        if (_completed.length == _steps.length) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: _tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Vous êtes ici, dans le présent. Respirez encore lentement et remarquez ce qui a changé.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _teal,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ExerciseSheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ExerciseSheetFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    decoration: const BoxDecoration(
      color: _canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
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
          child,
        ],
      ),
    ),
  );
}

BoxDecoration get _cardDecoration => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(color: _border),
  boxShadow: const [
    BoxShadow(color: Color(0x0D102A56), blurRadius: 22, offset: Offset(0, 8)),
  ],
);

String _firstText(Map data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

String _formatDate(DateTime value) {
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
  final now = DateTime.now();
  final local = value.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (sameDay) {
    return 'Aujourd’hui · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

Future<void> _launchPhone(BuildContext context, String number) async {
  final normalized = number.replaceAll(RegExp(r'[^0-9+]'), '');
  final launched = await launchUrl(Uri(scheme: 'tel', path: normalized));
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir le téléphone.')),
    );
  }
}

Future<void> _launchEmail(BuildContext context, String email) async {
  final launched = await launchUrl(
    Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Demande de soutien'},
    ),
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir la messagerie.')),
    );
  }
}

Future<void> _launchExternal(BuildContext context, String url) async {
  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d’ouvrir cette ressource.')),
    );
  }
}

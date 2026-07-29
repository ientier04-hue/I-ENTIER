import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'supabase_config.dart';
import 'supabase_data.dart';

const _bloodRed = Color(0xFFD92D3A);
const _bloodRedDark = Color(0xFFA71927);
const _bloodSoft = Color(0xFFFFEDEF);
const _bloodBorder = Color(0xFFF4C7CC);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);

const _redCrossBloodUrl = 'https://www.croixrouge.ht/donnez-votre-sang';
const _redCrossInformationUrl = 'https://www.croixrouge.ht/2-check-up/';
const _whoBloodDonationUrl =
    'https://www.who.int/news-room/questions-and-answers/item/'
    'blood-products-why-should-i-donate-blood';
const _redCrossPhone = '+50928110010';

typedef BloodUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchBloodUri(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

enum BloodRequestUrgency { standard, urgent, critical }

extension BloodRequestUrgencyDetails on BloodRequestUrgency {
  String get label => switch (this) {
    BloodRequestUrgency.standard => 'Besoin actuel',
    BloodRequestUrgency.urgent => 'Urgent',
    BloodRequestUrgency.critical => 'Très urgent',
  };

  Color get color => switch (this) {
    BloodRequestUrgency.standard => const Color(0xFF176BFF),
    BloodRequestUrgency.urgent => const Color(0xFFE77817),
    BloodRequestUrgency.critical => _bloodRed,
  };

  static BloodRequestUrgency fromValue(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'critical' => BloodRequestUrgency.critical,
        'urgent' => BloodRequestUrgency.urgent,
        _ => BloodRequestUrgency.standard,
      };
}

class BloodRequest {
  final String id;
  final String personName;
  final int? personAge;
  final String bloodGroup;
  final int unitsNeeded;
  final String facilityName;
  final String commune;
  final String department;
  final String reason;
  final String contactName;
  final String contactPhone;
  final DateTime neededBy;
  final DateTime expiresAt;
  final BloodRequestUrgency urgency;
  final bool verified;
  final String status;

  const BloodRequest({
    required this.id,
    required this.personName,
    required this.bloodGroup,
    required this.facilityName,
    required this.commune,
    required this.contactName,
    required this.contactPhone,
    required this.neededBy,
    required this.expiresAt,
    this.personAge,
    this.unitsNeeded = 1,
    this.department = '',
    this.reason = '',
    this.urgency = BloodRequestUrgency.standard,
    this.verified = true,
    this.status = 'active',
  });

  static BloodRequest? fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final neededBy = _bloodDate(data['neededBy']);
    final expiresAt = _bloodDate(data['expiresAt']);
    final personName = data['personName']?.toString().trim() ?? '';
    final bloodGroup =
        data['bloodGroup']?.toString().trim().toUpperCase() ?? '';
    final facility = data['facilityName']?.toString().trim() ?? '';
    final contactPhone = data['contactPhone']?.toString().trim() ?? '';
    if (neededBy == null ||
        expiresAt == null ||
        personName.isEmpty ||
        bloodGroup.isEmpty ||
        facility.isEmpty ||
        contactPhone.isEmpty) {
      return null;
    }
    final ageValue = data['personAge'];
    final unitValue = data['unitsNeeded'];
    return BloodRequest(
      id: snapshot.id,
      personName: personName,
      personAge: ageValue is num ? ageValue.toInt() : int.tryParse('$ageValue'),
      bloodGroup: bloodGroup,
      unitsNeeded: unitValue is num
          ? unitValue.toInt()
          : int.tryParse('$unitValue') ?? 1,
      facilityName: facility,
      commune: data['commune']?.toString().trim() ?? '',
      department: data['department']?.toString().trim() ?? '',
      reason: data['reason']?.toString().trim() ?? '',
      contactName: data['contactName']?.toString().trim() ?? '',
      contactPhone: contactPhone,
      neededBy: neededBy,
      expiresAt: expiresAt,
      urgency: BloodRequestUrgencyDetails.fromValue(data['urgency']),
      verified: data['verificationStatus']?.toString() == 'approved',
      status: data['status']?.toString() ?? '',
    );
  }

  bool isCurrent(DateTime now) =>
      verified && status == 'active' && expiresAt.isAfter(now);

  String get location =>
      [commune, department].where((part) => part.isNotEmpty).join(', ');
}

enum _BloodSection {
  requests,
  process,
  eligibility,
  compatibility,
  centers,
  questions,
}

extension on _BloodSection {
  String get label => switch (this) {
    _BloodSection.requests => 'Besoins actuels',
    _BloodSection.process => 'Comment donner',
    _BloodSection.eligibility => 'Puis-je donner ?',
    _BloodSection.compatibility => 'Compatibilité',
    _BloodSection.centers => 'Où donner',
    _BloodSection.questions => 'Questions',
  };

  IconData get icon => switch (this) {
    _BloodSection.requests => Icons.campaign_outlined,
    _BloodSection.process => Icons.volunteer_activism_outlined,
    _BloodSection.eligibility => Icons.health_and_safety_outlined,
    _BloodSection.compatibility => Icons.bloodtype_outlined,
    _BloodSection.centers => Icons.location_on_outlined,
    _BloodSection.questions => Icons.help_outline_rounded,
  };

  String get keyName => switch (this) {
    _BloodSection.requests => 'requests',
    _BloodSection.process => 'process',
    _BloodSection.eligibility => 'eligibility',
    _BloodSection.compatibility => 'compatibility',
    _BloodSection.centers => 'centers',
    _BloodSection.questions => 'questions',
  };
}

class BloodDonationPage extends StatefulWidget {
  final Map<String, dynamic> patientProfile;
  final Stream<List<BloodRequest>>? requestStream;
  final DateTime? now;
  final BloodUriLauncher uriLauncher;

  const BloodDonationPage({
    super.key,
    this.patientProfile = const {},
    this.requestStream,
    this.now,
    this.uriLauncher = _launchBloodUri,
  });

  @override
  State<BloodDonationPage> createState() => _BloodDonationPageState();
}

class _BloodDonationPageState extends State<BloodDonationPage> {
  _BloodSection _section = _BloodSection.requests;
  String _bloodGroupFilter = 'Tous';
  late Stream<List<BloodRequest>> _requestStream = _resolveRequestStream();

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didUpdateWidget(covariant BloodDonationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestStream != widget.requestStream) {
      _requestStream = _resolveRequestStream();
    }
  }

  Stream<List<BloodRequest>> _resolveRequestStream() {
    final provided = widget.requestStream;
    if (provided != null) return provided;
    if (!SupabaseConfig.isInitialized) {
      return Stream.value(const <BloodRequest>[]);
    }
    return SupabaseDatabase.instance
        .collection('bloodDonationRequests')
        .where('status', isEqualTo: 'active')
        .orderBy('neededBy')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map(BloodRequest.fromSnapshot)
              .whereType<BloodRequest>()
              .where((request) => request.isCurrent(_now))
              .toList();
          requests.sort((a, b) {
            final urgency = b.urgency.index.compareTo(a.urgency.index);
            return urgency != 0 ? urgency : a.neededBy.compareTo(b.neededBy);
          });
          return requests;
        });
  }

  Future<void> _openUri(Uri uri, {required String failureMessage}) async {
    final launched = await widget.uriLauncher(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _selectSection(_BloodSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    appBar: AppBar(
      title: const Text('Don de sang'),
      centerTitle: false,
      actions: [
        IconButton(
          tooltip: 'Site de la Croix-Rouge Haïtienne',
          onPressed: () => _openUri(
            Uri.parse(_redCrossBloodUrl),
            failureMessage: 'Impossible d’ouvrir le site de la Croix-Rouge.',
          ),
          icon: const Icon(Icons.open_in_new_rounded),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const _BloodHero(),
          _BloodSectionNavigation(
            selected: _section,
            onSelected: _selectSection,
          ),
          Expanded(
            child: IndexedStack(
              index: _section.index,
              children: [
                for (final section in _BloodSection.values)
                  KeyedSubtree(
                    key: ValueKey(section),
                    child: _buildSection(section),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSection(_BloodSection section) => switch (section) {
    _BloodSection.requests => _RequestsSection(
      stream: _requestStream,
      now: _now,
      selectedGroup: _bloodGroupFilter,
      onGroupChanged: (value) => setState(() => _bloodGroupFilter = value),
      onHelp: _showRequestContact,
    ),
    _BloodSection.process => _DonationProcessSection(
      onOpenRedCross: () => _openUri(
        Uri.parse(_redCrossInformationUrl),
        failureMessage: 'Impossible d’ouvrir les informations demandées.',
      ),
      onOpenWho: () => _openUri(
        Uri.parse(_whoBloodDonationUrl),
        failureMessage: 'Impossible d’ouvrir les informations demandées.',
      ),
    ),
    _BloodSection.eligibility => const _EligibilitySection(),
    _BloodSection.compatibility => const _CompatibilitySection(),
    _BloodSection.centers => _CentersSection(
      onCall: () => _openUri(
        Uri(scheme: 'tel', path: _redCrossPhone),
        failureMessage: 'Impossible de lancer l’appel.',
      ),
      onWebsite: () => _openUri(
        Uri.parse('https://www.croixrouge.ht/'),
        failureMessage: 'Impossible d’ouvrir le site de la Croix-Rouge.',
      ),
    ),
    _BloodSection.questions => const _QuestionsSection(),
  };

  Future<void> _showRequestContact(BloodRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _RequestContactSheet(
        request: request,
        onCall: () {
          Navigator.of(sheetContext).pop();
          _openUri(
            Uri(scheme: 'tel', path: request.contactPhone),
            failureMessage: 'Impossible de lancer l’appel.',
          );
        },
      ),
    );
  }
}

class _BloodHero extends StatelessWidget {
  const _BloodHero();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [_bloodRedDark, _bloodRed],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Votre don peut changer une histoire',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Consultez les besoins vérifiés et préparez votre don en toute confiance.',
                      style: TextStyle(
                        color: Color(0xFFFFE8EA),
                        fontSize: 13,
                        height: 1.35,
                      ),
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

class _BloodSectionNavigation extends StatelessWidget {
  final _BloodSection selected;
  final ValueChanged<_BloodSection> onSelected;

  const _BloodSectionNavigation({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 0,
    child: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                for (final section in _BloodSection.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      key: Key('blood-section-${section.keyName}'),
                      selected: selected == section,
                      onSelected: (_) => onSelected(section),
                      avatar: Icon(
                        section.icon,
                        size: 18,
                        color: selected == section ? _bloodRed : _muted,
                      ),
                      label: Text(section.label),
                      labelStyle: TextStyle(
                        color: selected == section
                            ? _bloodRedDark
                            : AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                      selectedColor: _bloodSoft,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: selected == section ? _bloodBorder : _border,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 7,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionScrollView extends StatelessWidget {
  final Widget child;

  const _SectionScrollView({required this.child});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('blood-section-scroll'),
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 36),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: child,
      ),
    ),
  );
}

class _RequestsSection extends StatelessWidget {
  final Stream<List<BloodRequest>> stream;
  final DateTime now;
  final String selectedGroup;
  final ValueChanged<String> onGroupChanged;
  final ValueChanged<BloodRequest> onHelp;

  const _RequestsSection({
    required this.stream,
    required this.now,
    required this.selectedGroup,
    required this.onGroupChanged,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<List<BloodRequest>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const _SectionScrollView(child: _LoadingRequests());
      }
      if (snapshot.hasError) {
        return const _SectionScrollView(child: _RequestsUnavailable());
      }
      final current = (snapshot.data ?? const <BloodRequest>[])
          .where((request) => request.isCurrent(now))
          .toList();
      final groups = current.map((request) => request.bloodGroup).toSet();
      final visible = selectedGroup == 'Tous'
          ? current
          : current
                .where((request) => request.bloodGroup == selectedGroup)
                .toList();
      return _SectionScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionIntro(
              eyebrow: 'SOLIDARITÉ EN TEMPS RÉEL',
              title: 'Demandes de sang actuelles',
              description:
                  'Seules les demandes actives et vérifiées par i-ENTIER sont publiées ici. Appelez toujours le contact avant de vous déplacer.',
              trailing: _CountPill(
                count: current.length,
                singular: 'demande',
                plural: 'demandes',
              ),
            ),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in ['Tous', ...groups.toList()..sort()])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('blood-filter-$group'),
                          label: Text(group),
                          selected: selectedGroup == group,
                          onSelected: (_) => onGroupChanged(group),
                          showCheckmark: false,
                          selectedColor: _bloodSoft,
                          side: BorderSide(
                            color: selectedGroup == group
                                ? _bloodBorder
                                : _border,
                          ),
                          labelStyle: TextStyle(
                            color: selectedGroup == group
                                ? _bloodRedDark
                                : _ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (current.isEmpty)
              const _EmptyRequests()
            else if (visible.isEmpty)
              _NoGroupRequests(group: selectedGroup)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 760;
                  final cardWidth = twoColumns
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final request in visible)
                        SizedBox(
                          width: cardWidth,
                          child: _BloodRequestCard(
                            request: request,
                            now: now,
                            onHelp: () => onHelp(request),
                          ),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 18),
            const _PrivacyNotice(),
          ],
        ),
      );
    },
  );
}

class _LoadingRequests extends StatelessWidget {
  const _LoadingRequests();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chargement des demandes de sang',
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator(color: _bloodRed)),
    ),
  );
}

class _RequestsUnavailable extends StatelessWidget {
  const _RequestsUnavailable();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _SectionIntro(
        eyebrow: 'BESOINS ACTUELS',
        title: 'Demandes momentanément indisponibles',
        description:
            'La synchronisation n’a pas abouti. Les autres informations de cette page restent accessibles depuis le menu supérieur.',
      ),
      const SizedBox(height: 22),
      _StateCard(
        icon: Icons.cloud_off_outlined,
        title: 'Impossible d’actualiser les demandes',
        message:
            'Vérifiez votre connexion puis revenez sur cette section. Pour un besoin urgent, contactez directement le centre de transfusion.',
        color: const Color(0xFFE77817),
      ),
    ],
  );
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) => const _StateCard(
    key: Key('blood-requests-empty'),
    icon: Icons.favorite_outline_rounded,
    title: 'Aucune demande vérifiée pour le moment',
    message:
        'C’est une bonne nouvelle. Revenez plus tard ou consultez « Où donner » pour faire un don volontaire.',
    color: Color(0xFF079A7B),
  );
}

class _NoGroupRequests extends StatelessWidget {
  final String group;
  const _NoGroupRequests({required this.group});

  @override
  Widget build(BuildContext context) => _StateCard(
    icon: Icons.filter_alt_off_outlined,
    title: 'Aucune demande pour le groupe $group',
    message: 'Choisissez « Tous » pour voir les autres besoins actuels.',
    color: _bloodRed,
  );
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _StateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.45),
        ),
      ],
    ),
  );
}

class _BloodRequestCard extends StatelessWidget {
  final BloodRequest request;
  final DateTime now;
  final VoidCallback onHelp;

  const _BloodRequestCard({
    required this.request,
    required this.now,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    final urgentColor = request.urgency.color;
    return Container(
      key: Key('blood-request-${request.id}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: request.urgency == BloodRequestUrgency.critical
              ? _bloodBorder
              : _border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A102A56),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _bloodSoft,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  request.bloodGroup,
                  style: const TextStyle(
                    color: _bloodRedDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.personName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (request.personAge != null)
                      Text(
                        '${request.personAge} ans',
                        style: const TextStyle(color: _muted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              _StatusPill(label: request.urgency.label, color: urgentColor),
            ],
          ),
          const SizedBox(height: 16),
          _RequestInfoRow(
            icon: Icons.local_hospital_outlined,
            label: request.facilityName,
          ),
          if (request.location.isNotEmpty)
            _RequestInfoRow(
              icon: Icons.location_on_outlined,
              label: request.location,
            ),
          _RequestInfoRow(
            icon: Icons.water_drop_outlined,
            label:
                '${request.unitsNeeded} ${request.unitsNeeded == 1 ? 'pochette recherchée' : 'pochettes recherchées'}',
          ),
          _RequestInfoRow(
            icon: Icons.event_outlined,
            label: 'Besoin avant le ${_bloodShortDate(request.neededBy)}',
          ),
          if (request.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                request.reason,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onHelp,
              style: FilledButton.styleFrom(backgroundColor: _bloodRed),
              icon: const Icon(Icons.volunteer_activism_outlined),
              label: const Text('Je peux aider'),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF079A7B),
                size: 15,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Demande vérifiée · expire ${_relativeExpiry(request.expiresAt, now)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RequestInfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _bloodRed, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
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
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4FF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFC7DDF8)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Color(0xFF176BFF), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Les coordonnées sont publiées avec consentement et uniquement pendant la durée du besoin. Ne les partagez pas hors du contexte du don.',
            style: TextStyle(color: _ink, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _RequestContactSheet extends StatelessWidget {
  final BloodRequest request;
  final VoidCallback onCall;

  const _RequestContactSheet({required this.request, required this.onCall});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _bloodSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                request.bloodGroup,
                style: const TextStyle(
                  color: _bloodRedDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirmer avant de partir',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${request.personName} · ${request.facilityName}',
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SheetAdvice(
          icon: Icons.phone_in_talk_outlined,
          text:
              'Appelez le contact pour confirmer que le besoin est toujours actif, l’horaire et le point de collecte.',
        ),
        const _SheetAdvice(
          icon: Icons.badge_outlined,
          text:
              'Demandez quels documents apporter et donnez la référence de la personne.',
        ),
        const _SheetAdvice(
          icon: Icons.health_and_safety_outlined,
          text:
              'L’équipe du centre décidera sur place si le don est sûr pour vous et le receveur.',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: _bloodRed),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.contactName.isEmpty
                          ? 'Contact de la demande'
                          : request.contactName,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      request.contactPhone,
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copier le numéro',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: request.contactPhone),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Numéro copié.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('blood-request-call'),
            onPressed: onCall,
            style: FilledButton.styleFrom(backgroundColor: _bloodRed),
            icon: const Icon(Icons.call_outlined),
            label: const Text('Appeler le contact'),
          ),
        ),
      ],
    ),
  );
}

class _SheetAdvice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SheetAdvice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _bloodRed, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _ink, height: 1.4, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

class _DonationProcessSection extends StatelessWidget {
  final VoidCallback onOpenRedCross;
  final VoidCallback onOpenWho;

  const _DonationProcessSection({
    required this.onOpenRedCross,
    required this.onOpenWho,
  });

  @override
  Widget build(BuildContext context) => _SectionScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'UN PARCOURS SIMPLE ET ENCADRÉ',
          title: 'Comment se passe un don de sang ?',
          description:
              'Du premier accueil au temps de repos, une équipe formée vous accompagne et protège votre confidentialité.',
        ),
        const SizedBox(height: 22),
        const _ProcessTimeline(),
        const SizedBox(height: 20),
        _OfficialSourceCard(
          title: 'Croix-Rouge Haïtienne',
          description:
              'Consultez les étapes et les informations locales avant votre déplacement.',
          icon: Icons.add_box_outlined,
          actionLabel: 'Voir les informations',
          color: _bloodRed,
          onPressed: onOpenRedCross,
        ),
        const SizedBox(height: 12),
        _OfficialSourceCard(
          title: 'Organisation mondiale de la Santé',
          description:
              'Comprendre le déroulement, la sécurité et les précautions générales.',
          icon: Icons.public_rounded,
          actionLabel: 'Consulter la source',
          color: const Color(0xFF176BFF),
          onPressed: onOpenWho,
        ),
      ],
    ),
  );
}

class _ProcessTimeline extends StatelessWidget {
  const _ProcessTimeline();

  static const _steps = [
    (
      '1',
      'Avant de partir',
      'Mangez normalement, buvez de l’eau et prévoyez du temps. Appelez le centre pour confirmer les horaires et les documents utiles.',
      Icons.water_drop_outlined,
    ),
    (
      '2',
      'Accueil confidentiel',
      'Vous répondez à des questions sur votre santé, vos médicaments et certains risques récents. Répondez avec précision.',
      Icons.assignment_ind_outlined,
    ),
    (
      '3',
      'Vérification médicale',
      'L’équipe peut contrôler votre tension, votre pouls, votre poids et votre taux d’hémoglobine avant de confirmer votre éligibilité.',
      Icons.monitor_heart_outlined,
    ),
    (
      '4',
      'Prélèvement',
      'Le prélèvement lui-même dure généralement autour de 10 minutes, avec du matériel stérile à usage unique.',
      Icons.bloodtype_outlined,
    ),
    (
      '5',
      'Repos et hydratation',
      'Reposez-vous 10 à 15 minutes, prenez une collation, buvez davantage et évitez les efforts intenses le reste de la journée.',
      Icons.chair_alt_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        for (var index = 0; index < _steps.length; index++)
          _TimelineStep(
            number: _steps[index].$1,
            title: _steps[index].$2,
            description: _steps[index].$3,
            icon: _steps[index].$4,
            isLast: index == _steps.length - 1,
          ),
      ],
    ),
  );
}

class _TimelineStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  final bool isLast;

  const _TimelineStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 42,
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _bloodSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: _bloodRedDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: _bloodBorder,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _bloodRed, size: 22),
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
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _OfficialSourceCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String actionLabel;
  final Color color;
  final VoidCallback onPressed;

  const _OfficialSourceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.actionLabel,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sourceIcon = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      );
      final sourceText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
        ],
      );
      final action = TextButton(
        onPressed: onPressed,
        child: Text(actionLabel, textAlign: TextAlign.center),
      );
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: constraints.maxWidth < 480
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sourceIcon,
                      const SizedBox(width: 13),
                      Expanded(child: sourceText),
                    ],
                  ),
                  const SizedBox(height: 10),
                  action,
                ],
              )
            : Row(
                children: [
                  sourceIcon,
                  const SizedBox(width: 13),
                  Expanded(child: sourceText),
                  const SizedBox(width: 8),
                  action,
                ],
              ),
      );
    },
  );
}

class _EligibilitySection extends StatelessWidget {
  const _EligibilitySection();

  @override
  Widget build(BuildContext context) => const _SectionScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionIntro(
          eyebrow: 'VOTRE SÉCURITÉ D’ABORD',
          title: 'Puis-je donner mon sang ?',
          description:
              'Ces repères vous aident à préparer l’échange. Seule l’équipe du centre peut confirmer votre éligibilité le jour du don.',
        ),
        SizedBox(height: 22),
        _EligibilitySummary(),
        SizedBox(height: 16),
        _EligibilityGrid(),
        SizedBox(height: 16),
        _MedicalDecisionNotice(),
      ],
    ),
  );
}

class _EligibilitySummary extends StatelessWidget {
  const _EligibilitySummary();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFFFF5F6), Colors.white]),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _bloodBorder),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fact_check_outlined, color: _bloodRed),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Repères publiés par la Croix-Rouge Haïtienne',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CriterionPill(icon: Icons.cake_outlined, label: '17 à 70 ans'),
            _CriterionPill(
              icon: Icons.monitor_weight_outlined,
              label: 'Plus de 50 kg',
            ),
            _CriterionPill(
              icon: Icons.favorite_border_rounded,
              label: 'Tension adaptée',
            ),
            _CriterionPill(
              icon: Icons.science_outlined,
              label: 'Hémoglobine vérifiée',
            ),
          ],
        ),
      ],
    ),
  );
}

class _CriterionPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CriterionPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _bloodBorder),
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      children: [
        Icon(icon, color: _bloodRed, size: 17),
        Text(
          label,
          style: const TextStyle(
            color: _ink,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _EligibilityGrid extends StatelessWidget {
  const _EligibilityGrid();

  static const _items = [
    (
      Icons.sentiment_satisfied_alt_outlined,
      'Vous vous sentez bien',
      'Pas de fièvre, infection, grande fatigue ou malaise aujourd’hui.',
      Color(0xFF079A7B),
    ),
    (
      Icons.medication_outlined,
      'Médicaments et soins récents',
      'Signalez tout traitement, vaccination, chirurgie, tatouage ou perçage récent.',
      Color(0xFF176BFF),
    ),
    (
      Icons.pregnant_woman_outlined,
      'Grossesse ou allaitement',
      'Prévenez le centre : une période d’attente peut être nécessaire pour votre sécurité.',
      Color(0xFF8B5CF6),
    ),
    (
      Icons.coronavirus_outlined,
      'Risque d’infection',
      'Répondez franchement au questionnaire confidentiel, même si vous vous sentez bien.',
      Color(0xFFE77817),
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 680;
      final width = twoColumns
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in _items)
            SizedBox(
              width: width,
              child: _EligibilityCard(
                icon: item.$1,
                title: item.$2,
                description: item.$3,
                color: item.$4,
              ),
            ),
        ],
      );
    },
  );
}

class _EligibilityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _EligibilityCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: _border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
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
              const SizedBox(height: 5),
              Text(
                description,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MedicalDecisionNotice extends StatelessWidget {
  const _MedicalDecisionNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8E8),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF0D89A)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF9A6B00)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Ne vous excluez pas seul sur la base d’un doute. Appelez le centre : certaines situations entraînent seulement un report temporaire.',
            style: TextStyle(
              color: Color(0xFF6E5216),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CompatibilitySection extends StatelessWidget {
  const _CompatibilitySection();

  static const _compatibility = [
    ('O−', 'Tous les groupes', true),
    ('O+', 'O+, A+, B+, AB+', false),
    ('A−', 'A−, A+, AB−, AB+', false),
    ('A+', 'A+, AB+', false),
    ('B−', 'B−, B+, AB−, AB+', false),
    ('B+', 'B+, AB+', false),
    ('AB−', 'AB−, AB+', false),
    ('AB+', 'AB+ uniquement', false),
  ];

  @override
  Widget build(BuildContext context) => _SectionScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'GLOBULES ROUGES',
          title: 'Comprendre la compatibilité',
          description:
              'Ce tableau indique à quels groupes vos globules rouges peuvent généralement être transfusés. Le laboratoire vérifie toujours la compatibilité finale.',
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              const _CompatibilityHeader(),
              const Divider(height: 22, color: _border),
              for (var index = 0; index < _compatibility.length; index++) ...[
                _CompatibilityRow(
                  donor: _compatibility[index].$1,
                  recipients: _compatibility[index].$2,
                  universal: _compatibility[index].$3,
                ),
                if (index < _compatibility.length - 1)
                  const Divider(height: 18, color: _border),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _ComponentNotice(),
      ],
    ),
  );
}

class _CompatibilityHeader extends StatelessWidget {
  const _CompatibilityHeader();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      SizedBox(
        width: 76,
        child: Text(
          'DONNEUR',
          style: TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
      ),
      Expanded(
        child: Text(
          'PEUT AIDER',
          style: TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
      ),
    ],
  );
}

class _CompatibilityRow extends StatelessWidget {
  final String donor;
  final String recipients;
  final bool universal;

  const _CompatibilityRow({
    required this.donor,
    required this.recipients,
    required this.universal,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 52,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _bloodSoft,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          donor,
          style: const TextStyle(
            color: _bloodRedDark,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 24),
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              recipients,
              style: const TextStyle(
                color: _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (universal)
              const _StatusPill(label: 'Donneur universel', color: _bloodRed),
          ],
        ),
      ),
    ],
  );
}

class _ComponentNotice extends StatelessWidget {
  const _ComponentNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF4FF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFC7DDF8)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.science_outlined, color: Color(0xFF176BFF)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'La compatibilité du plasma et des plaquettes suit d’autres règles. Votre groupe n’est jamais la seule décision : le service de transfusion réalise les contrôles nécessaires.',
            style: TextStyle(color: _ink, fontSize: 12.5, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _CentersSection extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onWebsite;

  const _CentersSection({required this.onCall, required this.onWebsite});

  @override
  Widget build(BuildContext context) => _SectionScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'AVANT DE VOUS DÉPLACER',
          title: 'Trouver où donner',
          description:
              'Les lieux et horaires de collecte peuvent changer. Confirmez toujours par téléphone avant votre départ.',
        ),
        const SizedBox(height: 22),
        Container(
          key: const Key('blood-center-red-cross'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _bloodSoft,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: const Icon(
                      Icons.add_box_rounded,
                      color: _bloodRed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Croix-Rouge Haïtienne',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Information et orientation pour le don de sang',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(
                  label: 'Source officielle',
                  color: Color(0xFF079A7B),
                ),
              ),
              const SizedBox(height: 18),
              const _RequestInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Avenue Maïs Gaté, en face de Avis, Port-au-Prince',
              ),
              const _RequestInfoRow(
                icon: Icons.phone_outlined,
                label: '+509 28 11 00 10',
              ),
              const SizedBox(height: 8),
              const Text(
                'Appelez pour connaître le point de collecte adapté, ses horaires et les besoins du jour.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 460;
                  final callButton = FilledButton.icon(
                    key: const Key('blood-center-call'),
                    onPressed: onCall,
                    style: FilledButton.styleFrom(backgroundColor: _bloodRed),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Appeler'),
                  );
                  final webButton = OutlinedButton.icon(
                    onPressed: onWebsite,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Site officiel'),
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        callButton,
                        const SizedBox(height: 10),
                        webButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: callButton),
                      const SizedBox(width: 10),
                      Expanded(child: webButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _StateCard(
          icon: Icons.local_hospital_outlined,
          title: 'Une demande précise ?',
          message:
              'Utilisez le bouton « Je peux aider » dans la demande : le contact vous indiquera l’établissement et le point de collecte à utiliser.',
          color: Color(0xFF176BFF),
        ),
      ],
    ),
  );
}

class _QuestionsSection extends StatelessWidget {
  const _QuestionsSection();

  static const _questions = [
    (
      'Dois-je connaître mon groupe sanguin ?',
      'Non. Le centre réalise les vérifications nécessaires. Si vous le connaissez, vous pouvez néanmoins le communiquer.',
    ),
    (
      'Combien de temps faut-il prévoir ?',
      'Le prélèvement dure généralement autour de 10 minutes. Prévoyez davantage de temps pour l’accueil, le questionnaire, les contrôles et le repos.',
    ),
    (
      'Le matériel est-il réutilisé ?',
      'Non. L’aiguille et la poche de prélèvement proviennent d’un emballage stérile et ne sont pas réutilisées.',
    ),
    (
      'Puis-je reprendre mes activités après ?',
      'Après 10 à 15 minutes de repos et une collation, les activités ordinaires sont généralement possibles. Buvez davantage et évitez les efforts intenses le reste de la journée.',
    ),
    (
      'Une demande affichée est-elle toujours active ?',
      'La page retire automatiquement les demandes expirées, mais la situation peut changer rapidement. Appelez toujours avant de vous déplacer.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _SectionScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionIntro(
          eyebrow: 'AVANT VOTRE DON',
          title: 'Questions fréquentes',
          description:
              'Des réponses courtes pour vous préparer. Pour votre situation personnelle, contactez le centre de collecte.',
        ),
        const SizedBox(height: 22),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < _questions.length; index++) ...[
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 3,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    iconColor: _bloodRed,
                    collapsedIconColor: _muted,
                    title: Text(
                      _questions[index].$1,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _questions[index].$2,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < _questions.length - 1)
                  const Divider(height: 1, color: _border),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionIntro extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final Widget? trailing;

  const _SectionIntro({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: _bloodRed,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 12), trailing!],
    ],
  );
}

class _CountPill extends StatelessWidget {
  final int count;
  final String singular;
  final String plural;

  const _CountPill({
    required this.count,
    required this.singular,
    required this.plural,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: _bloodSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _bloodBorder),
    ),
    child: Text(
      '$count ${count == 1 ? singular : plural}',
      style: const TextStyle(
        color: _bloodRedDark,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

DateTime? _bloodDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

String _bloodShortDate(DateTime date) {
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

String _relativeExpiry(DateTime expiry, DateTime now) {
  final difference = expiry.difference(now);
  if (difference.inHours < 24) return 'aujourd’hui';
  if (difference.inHours < 48) return 'demain';
  return 'dans ${difference.inDays} jours';
}

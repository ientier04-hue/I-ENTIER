import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _primary = Color(0xFF176BFF);
const _teal = Color(0xFF009B88);
const _tealSoft = Color(0xFFE5F7F3);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF5F8FC);

class LaboratoryPage extends StatefulWidget {
  final String patientId;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? institutionStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? resultStream;
  final List<Laboratory>? laboratories;
  final List<LaboratoryExam>? examinations;
  final List<LaboratoryResult>? results;

  const LaboratoryPage({
    super.key,
    this.patientId = '',
    this.institutionStream,
    this.resultStream,
    this.laboratories,
    this.examinations,
    this.results,
  });

  @override
  State<LaboratoryPage> createState() => _LaboratoryPageState();
}

class _LaboratoryPageState extends State<LaboratoryPage> {
  final _searchController = TextEditingController();
  _LaboratorySection _section = _LaboratorySection.laboratories;
  _LaboratoryFilter _filter = _LaboratoryFilter.all;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _institutions =>
      widget.institutionStream ??
      FirebaseFirestore.instance
          .collection('institution')
          .limit(100)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _results =>
      widget.resultStream ??
      FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patientId)
          .collection('laboratoryResults')
          .orderBy('publishedAt', descending: true)
          .limit(100)
          .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Laboratoire',
        style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _LaboratorySectionSwitch(
              selected: _section,
              onSelected: (section) => setState(() => _section = section),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _section.index,
              children: [
                _buildLaboratorySource(),
                _ExaminationsPage(
                  examinations: widget.examinations ?? laboratoryExaminations,
                ),
                _buildResultSource(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildLaboratorySource() {
    if (widget.laboratories != null) {
      return _buildDirectory(widget.laboratories!);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _institutions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _PageFeedback(
            icon: Icons.lock_outline_rounded,
            title: 'Laboratoires indisponibles',
            message:
                'Vérifiez l’accès à la collection Firestore « institution ».',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _teal),
          );
        }
        final laboratories = snapshot.data!.docs
            .map(Laboratory.fromFirestore)
            .whereType<Laboratory>()
            .toList();
        return _buildDirectory(laboratories);
      },
    );
  }

  Widget _buildResultSource() {
    if (widget.results != null) {
      return _PatientResultsPage(results: widget.results!);
    }
    if (widget.patientId.isEmpty) {
      return const _PatientResultsPage(results: []);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _results,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _PageFeedback(
            icon: Icons.shield_outlined,
            title: 'Résultats indisponibles',
            message:
                'Vos résultats n’ont pas pu être chargés pour le moment.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _teal),
          );
        }
        final results = snapshot.data!.docs
            .map(LaboratoryResult.fromFirestore)
            .toList();
        return _PatientResultsPage(results: results);
      },
    );
  }

  Widget _buildDirectory(List<Laboratory> laboratories) {
    final query = _searchController.text.trim().toLowerCase();
    final visibleLaboratories = laboratories.where((laboratory) {
      final matchesQuery =
          query.isEmpty || laboratory.searchableText.contains(query);
      final matchesFilter = switch (_filter) {
        _LaboratoryFilter.all => true,
        _LaboratoryFilter.open => laboratory.available,
        _LaboratoryFilter.home => laboratory.homeSampling,
        _LaboratoryFilter.online => laboratory.onlineResults,
      };
      return matchesQuery && matchesFilter;
    }).toList()..sort((a, b) {
      if (a.available != b.available) return a.available ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              sliver: SliverList.list(
                children: [
                  _LaboratoryHero(laboratoryCount: laboratories.length),
                  const SizedBox(height: 22),
                  _LaboratorySearchField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    onClear: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 14),
                  _FilterBar(
                    selected: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 26),
                  _ResultHeader(count: visibleLaboratories.length),
                  const SizedBox(height: 14),
                  if (visibleLaboratories.isEmpty)
                    _EmptyResult(
                      hasLaboratories: laboratories.isNotEmpty,
                      onReset: () {
                        _searchController.clear();
                        setState(() => _filter = _LaboratoryFilter.all);
                      },
                    )
                  else
                    _LaboratoryGrid(laboratories: visibleLaboratories),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LaboratorySection { laboratories, examinations, results }

extension on _LaboratorySection {
  String get label => switch (this) {
    _LaboratorySection.laboratories => 'Laboratoires',
    _LaboratorySection.examinations => 'Examens',
    _LaboratorySection.results => 'Résultats',
  };

  IconData get icon => switch (this) {
    _LaboratorySection.laboratories => Icons.apartment_outlined,
    _LaboratorySection.examinations => Icons.biotech_outlined,
    _LaboratorySection.results => Icons.assignment_turned_in_outlined,
  };

  String get keyName => switch (this) {
    _LaboratorySection.laboratories => 'laboratories',
    _LaboratorySection.examinations => 'examinations',
    _LaboratorySection.results => 'results',
  };
}

class _LaboratorySectionSwitch extends StatelessWidget {
  final _LaboratorySection selected;
  final ValueChanged<_LaboratorySection> onSelected;

  const _LaboratorySectionSwitch({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFFE9EEF6),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        for (final section in _LaboratorySection.values)
          Expanded(
            child: Semantics(
              selected: selected == section,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: Key('laboratory-section-${section.keyName}'),
                  onTap: () => onSelected(section),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: selected == section
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: selected == section
                          ? const [
                              BoxShadow(
                                color: Color(0x12102A56),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          section.icon,
                          size: 18,
                          color: selected == section ? _teal : _muted,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            section.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected == section ? _navy : _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class LaboratoryExam {
  final String id;
  final String name;
  final String category;
  final String description;
  final String sampleType;
  final String preparation;
  final String turnaround;
  final bool fasting;

  const LaboratoryExam({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.sampleType,
    required this.preparation,
    required this.turnaround,
    this.fasting = false,
  });
}

const laboratoryExaminations = <LaboratoryExam>[
  LaboratoryExam(
    id: 'cbc',
    name: 'Hémogramme complet',
    category: 'Hématologie',
    description:
        'Évalue les globules rouges, les globules blancs et les plaquettes.',
    sampleType: 'Prélèvement sanguin',
    preparation: 'Aucune préparation particulière',
    turnaround: 'Généralement sous 24 h',
  ),
  LaboratoryExam(
    id: 'fasting-glucose',
    name: 'Glycémie à jeun',
    category: 'Biochimie',
    description: 'Mesure le taux de glucose dans le sang à jeun.',
    sampleType: 'Prélèvement sanguin',
    preparation: 'Ne pas manger pendant 8 à 12 heures',
    turnaround: 'Le jour même',
    fasting: true,
  ),
  LaboratoryExam(
    id: 'lipid-panel',
    name: 'Bilan lipidique',
    category: 'Biochimie',
    description: 'Mesure notamment le cholestérol et les triglycérides.',
    sampleType: 'Prélèvement sanguin',
    preparation: 'Suivre les instructions du laboratoire concernant le jeûne',
    turnaround: 'Sous 24 à 48 h',
  ),
  LaboratoryExam(
    id: 'urinalysis',
    name: 'Analyse d’urines',
    category: 'Analyses courantes',
    description: 'Recherche plusieurs marqueurs urinaires utiles au médecin.',
    sampleType: 'Échantillon d’urine',
    preparation: 'Utiliser le contenant stérile fourni',
    turnaround: 'Le jour même',
  ),
  LaboratoryExam(
    id: 'pregnancy-test',
    name: 'Test de grossesse β-hCG',
    category: 'Hormones',
    description: 'Détecte ou mesure l’hormone β-hCG selon la prescription.',
    sampleType: 'Sang ou urine',
    preparation: 'Selon le type de prélèvement demandé',
    turnaround: 'Le jour même',
  ),
  LaboratoryExam(
    id: 'hiv-screening',
    name: 'Dépistage du VIH',
    category: 'Dépistage',
    description:
        'Test de dépistage confidentiel avec accompagnement selon le centre.',
    sampleType: 'Prélèvement sanguin',
    preparation: 'Aucune préparation particulière',
    turnaround: 'Selon la méthode utilisée',
  ),
];

class _ExaminationsPage extends StatefulWidget {
  final List<LaboratoryExam> examinations;

  const _ExaminationsPage({required this.examinations});

  @override
  State<_ExaminationsPage> createState() => _ExaminationsPageState();
}

class _ExaminationsPageState extends State<_ExaminationsPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final visible = widget.examinations.where((exam) {
      final searchable = [
        exam.name,
        exam.category,
        exam.description,
        exam.sampleType,
      ].join(' ').toLowerCase();
      return query.isEmpty || searchable.contains(query);
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              sliver: SliverList.list(
                children: [
                  const _LaboratoryPageHeading(
                    icon: Icons.biotech_outlined,
                    eyebrow: 'CATALOGUE',
                    title: 'Examens courants',
                    subtitle:
                        'Préparez votre visite et vérifiez toujours les consignes auprès du laboratoire.',
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('laboratory-exam-search'),
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un examen…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${visible.length} examen${visible.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    const _PageFeedback(
                      icon: Icons.search_off_rounded,
                      title: 'Aucun examen trouvé',
                      message: 'Essayez un autre nom ou une autre catégorie.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 12.0;
                        final columns = constraints.maxWidth >= 760 ? 2 : 1;
                        final width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final exam in visible)
                              SizedBox(
                                width: width,
                                child: _LaboratoryExamCard(exam: exam),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaboratoryExamCard extends StatelessWidget {
  final LaboratoryExam exam;

  const _LaboratoryExamCard({required this.exam});

  @override
  Widget build(BuildContext context) => Container(
    key: Key('laboratory-exam-${exam.id}'),
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _tealSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.science_outlined, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.name,
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exam.category,
                    style: const TextStyle(
                      color: _teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (exam.fasting)
              const _FeaturePill(
                icon: Icons.no_food_outlined,
                label: 'À jeun',
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          exam.description,
          style: const TextStyle(color: _ink, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        _InfoLine(icon: Icons.water_drop_outlined, text: exam.sampleType),
        const SizedBox(height: 8),
        _InfoLine(icon: Icons.checklist_rounded, text: exam.preparation),
        const SizedBox(height: 8),
        _InfoLine(icon: Icons.schedule_outlined, text: exam.turnaround),
      ],
    ),
  );
}

class LaboratoryResult {
  final String id;
  final String examName;
  final String laboratoryName;
  final String status;
  final String summary;
  final String resultUrl;
  final DateTime publishedAt;

  const LaboratoryResult({
    required this.id,
    required this.examName,
    required this.laboratoryName,
    required this.status,
    required this.publishedAt,
    this.summary = '',
    this.resultUrl = '',
  });

  factory LaboratoryResult.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final published = data['publishedAt'];
    return LaboratoryResult(
      id: document.id,
      examName: _readText(data, const ['examName', 'examen', 'title', 'name']),
      laboratoryName: _readText(data, const [
        'laboratoryName',
        'laboratoire',
        'institutionName',
      ]),
      status: _readText(data, const ['status', 'statut']),
      summary: _readText(data, const ['summary', 'resume', 'résumé']),
      resultUrl: _readText(data, const ['resultUrl', 'downloadUrl', 'url']),
      publishedAt: published is Timestamp
          ? published.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _PatientResultsPage extends StatelessWidget {
  final List<LaboratoryResult> results;

  const _PatientResultsPage({required this.results});

  Future<void> _openResult(BuildContext context, String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce résultat.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          const _LaboratoryPageHeading(
            icon: Icons.assignment_turned_in_outlined,
            eyebrow: 'DOSSIER PRIVÉ',
            title: 'Mes résultats',
            subtitle:
                'Consultez les documents publiés par vos laboratoires partenaires.',
          ),
          const SizedBox(height: 18),
          if (results.isEmpty)
            const _PageFeedback(
              icon: Icons.inbox_outlined,
              title: 'Aucun résultat disponible',
              message:
                  'Vos prochains résultats apparaîtront ici lorsqu’un laboratoire les publiera.',
            )
          else
            for (var index = 0; index < results.length; index++) ...[
              _LaboratoryResultCard(
                result: results[index],
                onOpen: results[index].resultUrl.isEmpty
                    ? null
                    : () => _openResult(context, results[index].resultUrl),
              ),
              if (index < results.length - 1) const SizedBox(height: 11),
            ],
        ],
      ),
    ),
  );
}

class _LaboratoryResultCard extends StatelessWidget {
  final LaboratoryResult result;
  final VoidCallback? onOpen;

  const _LaboratoryResultCard({required this.result, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final available = result.status.toLowerCase() != 'pending';
    return Container(
      key: Key('laboratory-result-${result.id}'),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: available ? _tealSoft : const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              available ? Icons.description_outlined : Icons.hourglass_top,
              color: available ? _teal : _muted,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.examName.isEmpty ? 'Résultat de laboratoire' : result.examName,
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (result.laboratoryName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.laboratoryName,
                    style: const TextStyle(color: _teal, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  _formatLaboratoryDate(result.publishedAt),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (result.summary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    result.summary,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onOpen != null)
            IconButton(
              tooltip: 'Ouvrir le résultat',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, color: _primary),
            ),
        ],
      ),
    );
  }
}

class _LaboratoryPageHeading extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;

  const _LaboratoryPageHeading({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: _tealSoft,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(icon, color: _teal),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: _teal,
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: _navy,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    ],
  );
}

enum _LaboratoryFilter { all, open, home, online }

extension on _LaboratoryFilter {
  String get label => switch (this) {
    _LaboratoryFilter.all => 'Tous',
    _LaboratoryFilter.open => 'Ouverts',
    _LaboratoryFilter.home => 'À domicile',
    _LaboratoryFilter.online => 'Résultats en ligne',
  };

  IconData get icon => switch (this) {
    _LaboratoryFilter.all => Icons.grid_view_rounded,
    _LaboratoryFilter.open => Icons.schedule_rounded,
    _LaboratoryFilter.home => Icons.home_outlined,
    _LaboratoryFilter.online => Icons.language_rounded,
  };

  String get keyName => switch (this) {
    _LaboratoryFilter.all => 'all',
    _LaboratoryFilter.open => 'open',
    _LaboratoryFilter.home => 'home',
    _LaboratoryFilter.online => 'online',
  };
}

class _LaboratoryHero extends StatelessWidget {
  final int laboratoryCount;

  const _LaboratoryHero({required this.laboratoryCount});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFE2FAF6), Color(0xFFDDEEFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x123474B9),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  laboratoryCount == 0
                      ? 'RÉSEAU DE SOINS'
                      : '$laboratoryCount LABORATOIRE${laboratoryCount > 1 ? 'S' : ''}',
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Vos analyses,\nprès de chez vous.',
                style: TextStyle(
                  color: _navy,
                  fontSize: 27,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Comparez les services et trouvez le laboratoire adapté à votre examen.',
                style: TextStyle(color: _ink, height: 1.4, fontSize: 13.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 88,
          height: 112,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(25),
          ),
          child: const Icon(
            Icons.science_rounded,
            color: _teal,
            size: 58,
          ),
        ),
      ],
    ),
  );
}

class _LaboratorySearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _LaboratorySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('laboratory-search-field'),
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: 'Nom, analyse, service ou quartier...',
      prefixIcon: const Icon(Icons.search_rounded, color: _muted),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Effacer la recherche',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _teal, width: 1.6),
      ),
    ),
  );
}

class _FilterBar extends StatelessWidget {
  final _LaboratoryFilter selected;
  final ValueChanged<_LaboratoryFilter> onSelected;

  const _FilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: _LaboratoryFilter.values.length,
      separatorBuilder: (context, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final filter = _LaboratoryFilter.values[index];
        final isSelected = filter == selected;
        return ChoiceChip(
          key: Key('laboratory-filter-${filter.keyName}'),
          selected: isSelected,
          onSelected: (_) => onSelected(filter),
          avatar: Icon(
            filter.icon,
            size: 17,
            color: isSelected ? _teal : _muted,
          ),
          label: Text(filter.label),
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFF08776A) : _ink,
            fontWeight: FontWeight.w700,
          ),
          selectedColor: _tealSoft,
          backgroundColor: Colors.white,
          side: BorderSide(color: isSelected ? _teal : _border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          showCheckmark: false,
        );
      },
    ),
  );
}

class _ResultHeader extends StatelessWidget {
  final int count;

  const _ResultHeader({required this.count});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'Laboratoires disponibles',
          style: TextStyle(
            color: _navy,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _tealSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$count résultat${count > 1 ? 's' : ''}',
          style: const TextStyle(
            color: Color(0xFF08776A),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _LaboratoryGrid extends StatelessWidget {
  final List<Laboratory> laboratories;

  const _LaboratoryGrid({required this.laboratories});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 14.0;
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final cardWidth =
          (constraints.maxWidth - ((columns - 1) * gap)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final laboratory in laboratories)
            SizedBox(
              width: cardWidth,
              child: _LaboratoryCard(laboratory: laboratory),
            ),
        ],
      );
    },
  );
}

class _LaboratoryCard extends StatelessWidget {
  final Laboratory laboratory;

  const _LaboratoryCard({required this.laboratory});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('laboratory-card-${laboratory.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LaboratoryDetailPage(laboratory: laboratory),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D173B66),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: _tealSoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.biotech_rounded,
                    color: _teal,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        laboratory.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 17,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _AvailabilityBadge(available: laboratory.available),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5FB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _primary,
                    size: 14,
                  ),
                ),
              ],
            ),
            if (laboratory.services.isNotEmpty) ...[
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _InfoLine(
                  icon: Icons.science_outlined,
                  text: laboratory.services,
                  color: _navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (laboratory.address.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoLine(
                icon: Icons.location_on_outlined,
                text: laboratory.address,
              ),
            ],
            if (laboratory.schedule.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoLine(
                icon: Icons.schedule_outlined,
                text: laboratory.schedule,
              ),
            ],
            if (laboratory.distance.isNotEmpty ||
                laboratory.homeSampling ||
                laboratory.onlineResults) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (laboratory.distance.isNotEmpty)
                    _FeaturePill(
                      icon: Icons.near_me_outlined,
                      label: laboratory.distance,
                    ),
                  if (laboratory.homeSampling)
                    const _FeaturePill(
                      icon: Icons.home_outlined,
                      label: 'À domicile',
                    ),
                  if (laboratory.onlineResults)
                    const _FeaturePill(
                      icon: Icons.language_rounded,
                      label: 'En ligne',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _AvailabilityBadge extends StatelessWidget {
  final bool available;

  const _AvailabilityBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final foreground = available ? const Color(0xFF13795B) : _muted;
    final background = available ? const Color(0xFFE7F7F0) : Color(0xFFF0F2F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            available ? 'Ouvert' : 'Fermé',
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final FontWeight fontWeight;

  const _InfoLine({
    required this.icon,
    required this.text,
    this.color = _muted,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, height: 1.3, fontWeight: fontWeight),
        ),
      ),
    ],
  );
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _teal, size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: _navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EmptyResult extends StatelessWidget {
  final bool hasLaboratories;
  final VoidCallback onReset;

  const _EmptyResult({required this.hasLaboratories, required this.onReset});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        const Icon(Icons.science_outlined, color: _teal, size: 42),
        const SizedBox(height: 12),
        Text(
          hasLaboratories
              ? 'Aucun laboratoire trouvé'
              : 'Aucun laboratoire enregistré',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          hasLaboratories
              ? 'Modifiez votre recherche ou réinitialisez les filtres.'
              : 'Ajoutez des institutions de type « Laboratoire » dans Firestore.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        if (hasLaboratories) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réinitialiser'),
          ),
        ],
      ],
    ),
  );
}

class _PageFeedback extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PageFeedback({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _teal, size: 42),
          const SizedBox(height: 12),
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
            style: const TextStyle(color: _muted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _ExaminationsPage extends StatefulWidget {
  final List<LaboratoryExam> examinations;

  const _ExaminationsPage({required this.examinations});

  @override
  State<_ExaminationsPage> createState() => _ExaminationsPageState();
}

class _ExaminationsPageState extends State<_ExaminationsPage> {
  final _controller = TextEditingController();
  String _category = 'Tous';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final examinations = widget.examinations.where((examination) {
      final matchesCategory =
          _category == 'Tous' || examination.category == _category;
      final matchesQuery =
          query.isEmpty || examination.searchableText.contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: CustomScrollView(
          key: const PageStorageKey<String>('laboratory-examinations'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              sliver: SliverList.list(
                children: [
                  const _ExaminationHero(),
                  const SizedBox(height: 22),
                  TextField(
                    key: const Key('examination-search-field'),
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un examen ou un prélèvement...',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _muted,
                      ),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _controller.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ExaminationCategoryBar(
                    selected: _category,
                    onSelected: (category) =>
                        setState(() => _category = category),
                  ),
                  const SizedBox(height: 26),
                  _DirectoryTitle(
                    title: 'Catalogue des examens',
                    count: examinations.length,
                  ),
                  const SizedBox(height: 14),
                  if (examinations.isEmpty)
                    _SimpleEmptyState(
                      icon: Icons.biotech_outlined,
                      title: 'Aucun examen trouvé',
                      message:
                          'Modifiez votre recherche ou choisissez une autre catégorie.',
                      actionLabel: 'Tout afficher',
                      onAction: () {
                        _controller.clear();
                        setState(() => _category = 'Tous');
                      },
                    )
                  else
                    _ExaminationGrid(examinations: examinations),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExaminationHero extends StatelessWidget {
  const _ExaminationHero();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFEAF1FF), Color(0xFFE2FAF6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
    ),
    child: const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comprendre vos examens',
                style: TextStyle(
                  color: _navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Découvrez le prélèvement, la préparation et le délai indicatif avant de choisir un laboratoire.',
                style: TextStyle(color: _ink, height: 1.4, fontSize: 13.5),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Icon(Icons.biotech_rounded, color: _primary, size: 62),
      ],
    ),
  );
}

const _examinationCategories = [
  'Tous',
  'Sang',
  'Dépistage',
  'Hormones',
  'Urines',
  'Prévention',
];

class _ExaminationCategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _ExaminationCategoryBar({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _examinationCategories.length,
      separatorBuilder: (context, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = _examinationCategories[index];
        return ChoiceChip(
          key: Key('examination-category-${category.toLowerCase()}'),
          selected: category == selected,
          onSelected: (_) => onSelected(category),
          label: Text(category),
          showCheckmark: false,
          selectedColor: _tealSoft,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: category == selected ? _teal : _border,
          ),
          labelStyle: TextStyle(
            color: category == selected ? const Color(0xFF08776A) : _ink,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        );
      },
    ),
  );
}

class _DirectoryTitle extends StatelessWidget {
  final String title;
  final int count;

  const _DirectoryTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _tealSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Color(0xFF08776A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _ExaminationGrid extends StatelessWidget {
  final List<LaboratoryExam> examinations;

  const _ExaminationGrid({required this.examinations});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 14.0;
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final examination in examinations)
            SizedBox(
              width: width,
              child: _ExaminationCard(examination: examination),
            ),
        ],
      );
    },
  );
}

class _ExaminationCard extends StatelessWidget {
  final LaboratoryExam examination;

  const _ExaminationCard({required this.examination});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('examination-card-${examination.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LaboratoryExamDetailPage(examination: examination),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: examination.color,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(examination.icon, color: _teal, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        examination.name,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        examination.category,
                        style: const TextStyle(
                          color: _teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: _primary,
                  size: 15,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              examination.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, height: 1.35),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FeaturePill(
                  icon: Icons.water_drop_outlined,
                  label: examination.sample,
                ),
                _FeaturePill(
                  icon: Icons.schedule_outlined,
                  label: examination.turnaround,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class LaboratoryExamDetailPage extends StatelessWidget {
  final LaboratoryExam examination;

  const LaboratoryExamDetailPage({
    super.key,
    required this.examination,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text('Détails de l’examen'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.white, Color(0xFFE8F8F4)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: examination.color,
                          borderRadius: BorderRadius.circular(21),
                        ),
                        child: Icon(
                          examination.icon,
                          color: _teal,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              examination.name,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              examination.category,
                              style: const TextStyle(
                                color: _teal,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _DetailSection(
                  title: 'Informations',
                  children: [
                    _DetailEntry(
                      icon: Icons.info_outline_rounded,
                      label: 'À quoi sert cet examen ?',
                      value: examination.description,
                    ),
                    _DetailEntry(
                      icon: Icons.water_drop_outlined,
                      label: 'Type de prélèvement',
                      value: examination.sample,
                    ),
                    _DetailEntry(
                      icon: Icons.schedule_outlined,
                      label: 'Délai indicatif',
                      value: examination.turnaround,
                    ),
                    _DetailEntry(
                      icon: Icons.fact_check_outlined,
                      label: 'Préparation',
                      value: examination.preparation,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _MedicalNotice(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MedicalNotice extends StatelessWidget {
  const _MedicalNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFF4D9A6)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFFB54708)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Ces informations sont générales. Suivez toujours les consignes de votre professionnel de santé et du laboratoire.',
            style: TextStyle(color: Color(0xFF7A4A08), height: 1.4),
          ),
        ),
      ],
    ),
  );
}

enum _ResultFilter { all, available, pending }

class _PatientResultsPage extends StatefulWidget {
  final List<LaboratoryResult> results;

  const _PatientResultsPage({required this.results});

  @override
  State<_PatientResultsPage> createState() => _PatientResultsPageState();
}

class _PatientResultsPageState extends State<_PatientResultsPage> {
  final _controller = TextEditingController();
  _ResultFilter _filter = _ResultFilter.all;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final results = widget.results.where((result) {
      final matchesQuery = query.isEmpty || result.searchableText.contains(query);
      final matchesStatus = switch (_filter) {
        _ResultFilter.all => true,
        _ResultFilter.available => result.isAvailable,
        _ResultFilter.pending => !result.isAvailable,
      };
      return matchesQuery && matchesStatus;
    }).toList()..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    final availableCount = widget.results
        .where((result) => result.isAvailable)
        .length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: CustomScrollView(
          key: const PageStorageKey<String>('laboratory-results'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              sliver: SliverList.list(
                children: [
                  _ResultsHero(availableCount: availableCount),
                  const SizedBox(height: 22),
                  TextField(
                    key: const Key('laboratory-result-search-field'),
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un résultat ou un laboratoire...',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: _muted,
                      ),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _controller.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ResultFilterBar(
                    selected: _filter,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 26),
                  _DirectoryTitle(title: 'Historique', count: results.length),
                  const SizedBox(height: 14),
                  if (results.isEmpty)
                    _SimpleEmptyState(
                      icon: Icons.assignment_outlined,
                      title: widget.results.isEmpty
                          ? 'Aucun résultat disponible'
                          : 'Aucun résultat trouvé',
                      message: widget.results.isEmpty
                          ? 'Les résultats publiés par vos laboratoires apparaîtront ici.'
                          : 'Modifiez votre recherche ou affichez tout l’historique.',
                      actionLabel: widget.results.isEmpty
                          ? null
                          : 'Tout afficher',
                      onAction: widget.results.isEmpty
                          ? null
                          : () {
                              _controller.clear();
                              setState(() => _filter = _ResultFilter.all);
                            },
                    )
                  else
                    _ResultList(results: results),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsHero extends StatelessWidget {
  final int availableCount;

  const _ResultsHero({required this.availableCount});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFE8F8F4), Color(0xFFEAF1FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mes résultats',
                style: TextStyle(
                  color: _navy,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                availableCount == 0
                    ? 'Vos comptes rendus sont regroupés dans un espace privé.'
                    : '$availableCount compte${availableCount > 1 ? 's' : ''} rendu${availableCount > 1 ? 's' : ''} disponible${availableCount > 1 ? 's' : ''}.',
                style: const TextStyle(color: _ink, height: 1.4),
              ),
              const SizedBox(height: 11),
              const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: _teal, size: 17),
                  SizedBox(width: 6),
                  Text(
                    'Visible uniquement par vous',
                    style: TextStyle(
                      color: _teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        const Icon(
          Icons.assignment_turned_in_rounded,
          color: _primary,
          size: 60,
        ),
      ],
    ),
  );
}

class _ResultFilterBar extends StatelessWidget {
  final _ResultFilter selected;
  final ValueChanged<_ResultFilter> onSelected;

  const _ResultFilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const filters = [
      (_ResultFilter.all, 'Tous'),
      (_ResultFilter.available, 'Disponibles'),
      (_ResultFilter.pending, 'En attente'),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (filter, label) = filters[index];
          return ChoiceChip(
            key: Key('laboratory-result-filter-${filter.name}'),
            selected: selected == filter,
            onSelected: (_) => onSelected(filter),
            label: Text(label),
            showCheckmark: false,
            selectedColor: _tealSoft,
            backgroundColor: Colors.white,
            side: BorderSide(color: selected == filter ? _teal : _border),
            labelStyle: TextStyle(
              color: selected == filter ? const Color(0xFF08776A) : _ink,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          );
        },
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  final List<LaboratoryResult> results;

  const _ResultList({required this.results});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < results.length; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        _ResultCard(result: results[index]),
      ],
    ],
  );
}

class _ResultCard extends StatelessWidget {
  final LaboratoryResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: Key('laboratory-result-${result.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LaboratoryResultDetailPage(result: result),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: result.isAvailable
                    ? _tealSoft
                    : const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                result.isAvailable
                    ? Icons.description_outlined
                    : Icons.hourglass_top_rounded,
                color: result.isAvailable
                    ? _teal
                    : const Color(0xFFB54708),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.examName,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (result.laboratoryName.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      result.laboratoryName,
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ResultStatusBadge(result: result),
                      if (result.dateLabel.isNotEmpty)
                        _FeaturePill(
                          icon: Icons.calendar_today_outlined,
                          label: result.dateLabel,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: _primary,
              size: 15,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResultStatusBadge extends StatelessWidget {
  final LaboratoryResult result;

  const _ResultStatusBadge({required this.result});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: result.isAvailable ? _tealSoft : const Color(0xFFFFF3E8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      result.statusLabel,
      style: TextStyle(
        color: result.isAvailable
            ? const Color(0xFF08776A)
            : const Color(0xFFB54708),
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class LaboratoryResultDetailPage extends StatelessWidget {
  final LaboratoryResult result;

  const LaboratoryResultDetailPage({super.key, required this.result});

  Future<void> _openDocument(BuildContext context) async {
    final uri = Uri.tryParse(result.fileUrl);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text('Compte rendu'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.white, Color(0xFFE8F8F4)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResultStatusBadge(result: result),
                      const SizedBox(height: 13),
                      Text(
                        result.examName,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (result.laboratoryName.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          result.laboratoryName,
                          style: const TextStyle(
                            color: _teal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _DetailSection(
                  title: 'Informations',
                  children: [
                    if (result.collectedAt != null)
                      _DetailEntry(
                        icon: Icons.event_outlined,
                        label: 'Prélèvement',
                        value: _formatLaboratoryDate(result.collectedAt!),
                      ),
                    if (result.publishedAt != null)
                      _DetailEntry(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Publication',
                        value: _formatLaboratoryDate(result.publishedAt!),
                      ),
                    if (result.summary.isNotEmpty)
                      _DetailEntry(
                        icon: Icons.summarize_outlined,
                        label: 'Résumé',
                        value: result.summary,
                      ),
                    if (result.referenceRange.isNotEmpty)
                      _DetailEntry(
                        icon: Icons.straighten_outlined,
                        label: 'Valeurs de référence',
                        value: result.referenceRange,
                      ),
                    if (result.note.isNotEmpty)
                      _DetailEntry(
                        icon: Icons.notes_rounded,
                        label: 'Note du laboratoire',
                        value: result.note,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const _MedicalNotice(),
                if (result.isAvailable && result.fileUrl.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('open-laboratory-result-document'),
                    onPressed: () => _openDocument(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Ouvrir le compte rendu'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SimpleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SimpleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Icon(icon, color: _teal, size: 42),
        const SizedBox(height: 12),
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
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class LaboratoryDetailPage extends StatelessWidget {
  final Laboratory laboratory;

  const LaboratoryDetailPage({super.key, required this.laboratory});

  Future<void> _copyPhone(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: laboratory.phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Numéro de téléphone copié.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _canvas,
    appBar: AppBar(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      title: const Text('Détails du laboratoire'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LaboratoryDetailHero(laboratory: laboratory),
                if (laboratory.description.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _DetailSection(
                    title: 'À propos',
                    children: [
                      _DetailEntry(
                        icon: Icons.info_outline_rounded,
                        label: 'Présentation',
                        value: laboratory.description,
                      ),
                    ],
                  ),
                ],
                if (laboratory.services.isNotEmpty ||
                    laboratory.homeSampling ||
                    laboratory.onlineResults ||
                    laboratory.accredited) ...[
                  const SizedBox(height: 18),
                  _DetailSection(
                    title: 'Services',
                    children: [
                      if (laboratory.services.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.science_outlined,
                          label: 'Analyses et examens',
                          value: laboratory.services,
                        ),
                      if (laboratory.homeSampling)
                        const _DetailEntry(
                          icon: Icons.home_outlined,
                          label: 'Prélèvement',
                          value: 'Prélèvement à domicile disponible',
                        ),
                      if (laboratory.onlineResults)
                        const _DetailEntry(
                          icon: Icons.language_rounded,
                          label: 'Résultats',
                          value: 'Consultation des résultats en ligne',
                        ),
                      if (laboratory.accredited)
                        const _DetailEntry(
                          icon: Icons.verified_outlined,
                          label: 'Qualité',
                          value: 'Laboratoire accrédité',
                        ),
                    ],
                  ),
                ],
                if (laboratory.address.isNotEmpty ||
                    laboratory.distance.isNotEmpty ||
                    laboratory.schedule.isNotEmpty ||
                    laboratory.phone.isNotEmpty ||
                    laboratory.email.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _DetailSection(
                    title: 'Localisation et contact',
                    children: [
                      if (laboratory.address.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.location_on_outlined,
                          label: 'Adresse',
                          value: laboratory.address,
                        ),
                      if (laboratory.distance.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.near_me_outlined,
                          label: 'Distance',
                          value: laboratory.distance,
                        ),
                      if (laboratory.schedule.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.schedule_outlined,
                          label: 'Horaires',
                          value: laboratory.schedule,
                        ),
                      if (laboratory.phone.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.phone_outlined,
                          label: 'Téléphone',
                          value: laboratory.phone,
                        ),
                      if (laboratory.email.isNotEmpty)
                        _DetailEntry(
                          icon: Icons.email_outlined,
                          label: 'E-mail',
                          value: laboratory.email,
                        ),
                    ],
                  ),
                ],
                if (laboratory.phone.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _copyPhone(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text('Copier le numéro du laboratoire'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LaboratoryDetailHero extends StatelessWidget {
  final Laboratory laboratory;

  const _LaboratoryDetailHero({required this.laboratory});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Colors.white, Color(0xFFE8F8F4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: _border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _tealSoft,
            borderRadius: BorderRadius.circular(23),
          ),
          child: const Icon(Icons.biotech_rounded, color: _teal, size: 40),
        ),
        const SizedBox(width: 17),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                laboratory.name,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 23,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _AvailabilityBadge(available: laboratory.available),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, color: _border),
          children[index],
        ],
      ],
    ),
  );
}

class _DetailEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailEntry({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5FB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _teal, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              SelectableText(
                value,
                style: const TextStyle(
                  color: _navy,
                  fontSize: 14.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class Laboratory {
  final String id;
  final String name;
  final String description;
  final String services;
  final String address;
  final String distance;
  final String schedule;
  final String phone;
  final String email;
  final bool available;
  final bool homeSampling;
  final bool onlineResults;
  final bool accredited;

  const Laboratory({
    required this.id,
    required this.name,
    this.description = '',
    this.services = '',
    this.address = '',
    this.distance = '',
    this.schedule = '',
    this.phone = '',
    this.email = '',
    this.available = true,
    this.homeSampling = false,
    this.onlineResults = false,
    this.accredited = false,
  });

  static Laboratory? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final type = _readText(data, const [
      'type',
      'categorie',
      'catégorie',
      'category',
    ]);
    final name = _readText(data, const [
      'nom',
      'name',
      'nomInstitution',
      'displayName',
    ]);
    final identity = '$type $name'.toLowerCase();
    if (!identity.contains('labo') && !identity.contains('laboratory')) {
      return null;
    }

    return Laboratory(
      id: document.id,
      name: name.isEmpty ? 'Laboratoire' : name,
      description: _readText(data, const [
        'description',
        'aPropos',
        'about',
        'presentation',
        'présentation',
      ]),
      services: _readText(data, const [
        'services',
        'analyses',
        'examens',
        'prestations',
        'specialites',
        'spécialités',
      ]),
      address: _readText(data, const [
        'adresse',
        'address',
        'localisation',
        'location',
      ]),
      distance: _readText(data, const [
        'distance',
        'distanceLabel',
        'distance_label',
      ]),
      schedule: _readText(data, const [
        'horaires',
        'horaire',
        'openingHours',
        'opening_hours',
        'schedule',
      ]),
      phone: _readText(data, const [
        'telephone',
        'téléphone',
        'phone',
        'phoneNumber',
        'contact',
      ]),
      email: _readText(data, const ['email', 'e-mail', 'courriel', 'mail']),
      available: _readBool(data, const [
        'ouvert',
        'open',
        'isOpen',
        'disponible',
        'available',
        'isAvailable',
      ], fallback: true),
      homeSampling: _readBool(data, const [
        'prelevementDomicile',
        'prélèvementDomicile',
        'homeSampling',
        'homeCollection',
      ]),
      onlineResults: _readBool(data, const [
        'resultatsEnLigne',
        'résultatsEnLigne',
        'onlineResults',
        'digitalResults',
      ]),
      accredited: _readBool(data, const [
        'accredite',
        'accrédité',
        'accredited',
        'certified',
      ]),
    );
  }

  String get searchableText => [
    name,
    description,
    services,
    address,
  ].join(' ').toLowerCase();
}

String _readText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is Map) {
      for (final nestedKey in const [
        'label',
        'formatted',
        'fullAddress',
        'name',
        'value',
      ]) {
        final nestedValue = value[nestedKey];
        if (nestedValue != null && nestedValue.toString().trim().isNotEmpty) {
          return nestedValue.toString().trim();
        }
      }
      continue;
    }
    if (value is Iterable) {
      final result = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
      if (result.isNotEmpty) return result;
      continue;
    }
    if (value.toString().trim().isNotEmpty) return value.toString().trim();
  }
  return '';
}

bool _readBool(
  Map<String, dynamic> data,
  List<String> keys, {
  bool fallback = false,
}) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (const ['true', 'oui', 'yes', '1', 'ouvert'].contains(normalized)) {
        return true;
      }
      if (const ['false', 'non', 'no', '0', 'fermé', 'ferme'].contains(normalized)) {
        return false;
      }
    }
  }
  return fallback;
}

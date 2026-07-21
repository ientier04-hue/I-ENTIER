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

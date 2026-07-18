import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

const _primary = Color(0xFF176BFF);
const _primarySoft = Color(0xFFEAF1FF);
const _green = Color(0xFF009B88);
const _greenSoft = Color(0xFFE5F7F3);
const _navy = Color(0xFF102A56);
const _ink = Color(0xFF344054);
const _muted = Color(0xFF667085);
const _border = Color(0xFFE4EAF2);
const _canvas = Color(0xFFF5F8FC);

class PharmacyPage extends StatefulWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>>? institutionStream;

  const PharmacyPage({super.key, this.institutionStream});

  @override
  State<PharmacyPage> createState() => _PharmacyPageState();
}

class _PharmacyPageState extends State<PharmacyPage> {
  final _searchController = TextEditingController();
  String _category = 'Tous';
  bool _prescriptionOnly = false;
  bool _availableOnly = true;
  XFile? _prescription;
  Uint8List? _prescriptionBytes;
  Position? _position;
  bool _locating = false;
  String? _locationMessage;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _institutions =>
      widget.institutionStream ??
      FirebaseFirestore.instance
          .collection('institution')
          .limit(100)
          .snapshots();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_Medication> get _visibleMedications {
    final query = _searchController.text.trim().toLowerCase();
    return _medications.where((medication) {
      final matchesQuery =
          query.isEmpty ||
          medication.name.toLowerCase().contains(query) ||
          medication.activeIngredient.toLowerCase().contains(query) ||
          medication.category.toLowerCase().contains(query);
      final matchesCategory =
          _category == 'Tous' || medication.category == _category;
      final matchesPrescription =
          !_prescriptionOnly || medication.requiresPrescription;
      final matchesAvailability = !_availableOnly || medication.available;
      return matchesQuery &&
          matchesCategory &&
          matchesPrescription &&
          matchesAvailability;
    }).toList();
  }

  int get _activeFilterCount =>
      (_category == 'Tous' ? 0 : 1) +
      (_prescriptionOnly ? 1 : 0) +
      (_availableOnly ? 1 : 0);

  Future<void> _pickPrescription() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _PrescriptionSourceSheet(),
    );
    if (source == null || !mounted) return;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _prescription = file;
        _prescriptionBytes = bytes;
      });
      await showDialog<void>(
        context: context,
        builder: (context) =>
            _PrescriptionPreview(bytes: bytes, fileName: file.name),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code.contains('permission')
            ? 'Autorisez l’accès à la caméra ou aux photos pour continuer.'
            : 'Impossible d’ouvrir l’image. Réessayez dans un instant.',
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Impossible de lire cette ordonnance.');
      }
    }
  }

  Future<void> _findNearbyPharmacies() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationFailure(
          'Activez la localisation de votre appareil pour calculer les distances.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationFailure(
          'La permission de localisation a été refusée.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'La localisation est bloquée. Autorisez-la dans les réglages.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _locationMessage = 'Position mise à jour';
      });
    } on _LocationFailure catch (error) {
      if (mounted) setState(() => _locationMessage = error.message);
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(
          () => _locationMessage =
              'La localisation prend trop de temps. Réessayez.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationMessage = 'Votre position n’a pas pu être récupérée.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_PharmacyFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterSheet(
        initial: _PharmacyFilters(
          category: _category,
          prescriptionOnly: _prescriptionOnly,
          availableOnly: _availableOnly,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _category = result.category;
      _prescriptionOnly = result.prescriptionOnly;
      _availableOnly = result.availableOnly;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final medications = _visibleMedications;
    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: _canvas,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Pharmacie',
          style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
        ),
        actions: [
          IconButton(
            tooltip: 'Mon panier',
            onPressed: () => _showMessage('Votre panier est vide.'),
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  sliver: SliverList.list(
                    children: [
                      _PharmacyHero(onScan: _pickPrescription),
                      if (_prescription != null) ...[
                        const SizedBox(height: 14),
                        _PrescriptionStatus(
                          fileName: _prescription!.name,
                          bytes: _prescriptionBytes,
                          onReplace: _pickPrescription,
                          onRemove: () => setState(() {
                            _prescription = null;
                            _prescriptionBytes = null;
                          }),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _SearchAndFilter(
                        controller: _searchController,
                        filterCount: _activeFilterCount,
                        onChanged: (_) => setState(() {}),
                        onFilter: _openFilters,
                      ),
                      const SizedBox(height: 18),
                      _CategoryBar(
                        selected: _category,
                        onSelected: (category) =>
                            setState(() => _category = category),
                      ),
                      const SizedBox(height: 26),
                      _SectionTitle(
                        title: 'Médicaments populaires',
                        subtitle: medications.isEmpty
                            ? 'Aucun résultat'
                            : '${medications.length} produit${medications.length > 1 ? 's' : ''}',
                      ),
                      const SizedBox(height: 14),
                      if (medications.isEmpty)
                        _EmptyMedicationResult(
                          onReset: () {
                            _searchController.clear();
                            setState(() {
                              _category = 'Tous';
                              _prescriptionOnly = false;
                              _availableOnly = true;
                            });
                          },
                        )
                      else
                        _MedicationGrid(
                          medications: medications,
                          onAdd: (medication) => _showMessage(
                            '${medication.name} a été ajouté au panier.',
                          ),
                        ),
                      const SizedBox(height: 34),
                      _NearbyHeader(
                        locating: _locating,
                        hasPosition: _position != null,
                        onLocate: _findNearbyPharmacies,
                      ),
                      if (_locationMessage != null) ...[
                        const SizedBox(height: 10),
                        _LocationNotice(
                          message: _locationMessage!,
                          success: _position != null,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _NearbyPharmacies(
                        stream: _institutions,
                        position: _position,
                        onMessage: _showMessage,
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
}

class _PharmacyHero extends StatelessWidget {
  final VoidCallback onScan;

  const _PharmacyHero({required this.onScan});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFDDF8F2), Color(0xFFE9F4FF)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .82),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'VOTRE PHARMACIE SANTÉ',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: _green,
                ),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              compact
                  ? 'Trouvez vos médicaments simplement'
                  : 'Vos médicaments, sans perdre de temps',
              style: TextStyle(
                fontSize: compact ? 27 : 32,
                height: 1.08,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Recherchez un produit ou envoyez votre ordonnance à une pharmacie proche.',
              style: TextStyle(fontSize: 14.5, height: 1.45, color: _ink),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scanner une ordonnance'),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        );
        if (compact) return content;
        return Row(
          children: [
            Expanded(flex: 3, child: content),
            const SizedBox(width: 32),
            const _HeroIllustration(),
          ],
        );
      },
    ),
  );
}

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    height: 190,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .72),
      shape: BoxShape.circle,
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.local_pharmacy_rounded, size: 94, color: _green),
        Positioned(
          right: 22,
          top: 28,
          child: Transform.rotate(
            angle: -.3,
            child: Container(
              width: 47,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD7A8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 23.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFFF8F70),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(20),
                      ),
                    ),
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

class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  final int filterCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilter;

  const _SearchAndFilter({
    required this.controller,
    required this.filterCount,
    required this.onChanged,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const Key('pharmacy-search-field'),
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Médicament ou principe actif...',
            prefixIcon: const Icon(Icons.search_rounded, color: _muted),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: const BorderSide(color: _border),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Badge(
        isLabelVisible: filterCount > 0,
        label: Text('$filterCount'),
        backgroundColor: _green,
        child: IconButton.filledTonal(
          key: const Key('pharmacy-filter-button'),
          tooltip: 'Filtrer les médicaments',
          onPressed: onFilter,
          style: IconButton.styleFrom(
            minimumSize: const Size(56, 56),
            backgroundColor: _primarySoft,
            foregroundColor: _primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ),
    ],
  );
}

class _CategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;

  const _CategoryBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final category in _categories) ...[
          ChoiceChip(
            label: Text(category),
            selected: selected == category,
            onSelected: (_) => onSelected(category),
            showCheckmark: false,
            selectedColor: _green,
            backgroundColor: Colors.white,
            side: BorderSide(color: selected == category ? _green : _border),
            labelStyle: TextStyle(
              color: selected == category ? Colors.white : _navy,
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _navy,
          ),
        ),
      ),
      if (subtitle != null)
        Text(
          subtitle!,
          style: const TextStyle(
            color: _muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
    ],
  );
}

class _MedicationGrid extends StatelessWidget {
  final List<_Medication> medications;
  final ValueChanged<_Medication> onAdd;

  const _MedicationGrid({required this.medications, required this.onAdd});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final columns = constraints.maxWidth >= 880
          ? 3
          : constraints.maxWidth >= 540
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final medication in medications)
            SizedBox(
              width: width,
              child: _MedicationCard(
                medication: medication,
                onAdd: () => onAdd(medication),
              ),
            ),
        ],
      );
    },
  );
}

class _MedicationCard extends StatelessWidget {
  final _Medication medication;
  final VoidCallback onAdd;

  const _MedicationCard({required this.medication, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A173B66),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 78,
          height: 92,
          decoration: BoxDecoration(
            color: medication.color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(medication.icon, color: medication.accent, size: 39),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      medication.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                  ),
                  if (!medication.available)
                    const _TinyBadge(
                      label: 'Épuisé',
                      color: Color(0xFFB42318),
                      background: Color(0xFFFFEDEC),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                medication.activeIngredient,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: _muted),
              ),
              if (medication.requiresPrescription) ...[
                const SizedBox(height: 7),
                const _TinyBadge(
                  label: 'Ordonnance requise',
                  color: Color(0xFF175CD3),
                  background: _primarySoft,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      medication.price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _green,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Ajouter ${medication.name}',
                    onPressed: medication.available ? onAdd : null,
                    style: IconButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE9EDF3),
                      minimumSize: const Size(40, 40),
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _TinyBadge({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class _EmptyMedicationResult extends StatelessWidget {
  final VoidCallback onReset;

  const _EmptyMedicationResult({required this.onReset});

  @override
  Widget build(BuildContext context) => _FeedbackCard(
    icon: Icons.medication_outlined,
    title: 'Aucun médicament trouvé',
    message: 'Modifiez votre recherche ou réinitialisez les filtres.',
    actionLabel: 'Réinitialiser',
    onAction: onReset,
  );
}

class _NearbyHeader extends StatelessWidget {
  final bool locating;
  final bool hasPosition;
  final VoidCallback onLocate;

  const _NearbyHeader({
    required this.locating,
    required this.hasPosition,
    required this.onLocate,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pharmacies proches',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Distance calculée depuis votre position',
              style: TextStyle(fontSize: 12.5, color: _muted),
            ),
          ],
        ),
      ),
      TextButton.icon(
        key: const Key('pharmacy-location-button'),
        onPressed: locating ? null : onLocate,
        icon: locating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                hasPosition
                    ? Icons.my_location_rounded
                    : Icons.near_me_outlined,
                size: 18,
              ),
        label: Text(hasPosition ? 'Actualiser' : 'Me localiser'),
      ),
    ],
  );
}

class _LocationNotice extends StatelessWidget {
  final String message;
  final bool success;

  const _LocationNotice({required this.message, required this.success});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: success ? _greenSoft : const Color(0xFFFFF3E8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.info_outline_rounded,
          color: success ? _green : const Color(0xFFB54708),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12.5,
              color: success
                  ? const Color(0xFF13795B)
                  : const Color(0xFF93370D),
            ),
          ),
        ),
      ],
    ),
  );
}

class _NearbyPharmacies extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final Position? position;
  final ValueChanged<String> onMessage;

  const _NearbyPharmacies({
    required this.stream,
    required this.position,
    required this.onMessage,
  });

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const _FeedbackCard(
          icon: Icons.lock_outline_rounded,
          title: 'Pharmacies indisponibles',
          message:
              'Vérifiez l’accès à la collection Firestore « institution ».',
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 38),
          child: Center(child: CircularProgressIndicator(color: _green)),
        );
      }

      final pharmacies = snapshot.data!.docs
          .map(_NearbyPharmacy.fromFirestore)
          .whereType<_NearbyPharmacy>()
          .toList();
      if (position != null) {
        for (final pharmacy in pharmacies) {
          pharmacy.calculateDistance(position!);
        }
        pharmacies.sort((a, b) {
          if (a.distanceMeters == null) return 1;
          if (b.distanceMeters == null) return -1;
          return a.distanceMeters!.compareTo(b.distanceMeters!);
        });
      }

      if (pharmacies.isEmpty) {
        return const _FeedbackCard(
          icon: Icons.local_pharmacy_outlined,
          title: 'Aucune pharmacie enregistrée',
          message:
              'Ajoutez des institutions de type « Pharmacie » dans Firestore avec leur adresse et leurs coordonnées.',
        );
      }

      return SizedBox(
        height: 218,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: pharmacies.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) => SizedBox(
            width: 310,
            child: _NearbyPharmacyCard(
              pharmacy: pharmacies[index],
              onMessage: onMessage,
            ),
          ),
        ),
      );
    },
  );
}

class _NearbyPharmacyCard extends StatelessWidget {
  final _NearbyPharmacy pharmacy;
  final ValueChanged<String> onMessage;

  const _NearbyPharmacyCard({required this.pharmacy, required this.onMessage});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _greenSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.local_pharmacy_rounded, color: _green),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pharmacy.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _OpenBadge(open: pharmacy.open),
                ],
              ),
            ),
            if (pharmacy.distanceLabel.isNotEmpty)
              Text(
                pharmacy.distanceLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _PharmacyDetail(
          icon: Icons.location_on_outlined,
          text: pharmacy.address.isEmpty
              ? 'Adresse non renseignée'
              : pharmacy.address,
        ),
        const SizedBox(height: 8),
        _PharmacyDetail(
          icon: Icons.schedule_outlined,
          text: pharmacy.schedule.isEmpty
              ? 'Horaires non renseignés'
              : pharmacy.schedule,
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pharmacy.phone.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: pharmacy.phone),
                        );
                        onMessage('Numéro copié : ${pharmacy.phone}');
                      },
                    icon: const Icon(Icons.content_copy_rounded, size: 17),
                    label: const Text('Copier'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    onMessage('Sélection de ${pharmacy.name} enregistrée.'),
                style: FilledButton.styleFrom(backgroundColor: _green),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Choisir'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _OpenBadge extends StatelessWidget {
  final bool open;

  const _OpenBadge({required this.open});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: open ? _green : _muted,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        open ? 'Ouverte' : 'Fermée',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: open ? _green : _muted,
        ),
      ),
    ],
  );
}

class _PharmacyDetail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PharmacyDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: _muted),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: _muted),
        ),
      ),
    ],
  );
}

class _FeedbackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FeedbackCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        Icon(icon, color: _green, size: 34),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, color: _navy),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.35),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class _PrescriptionSourceSheet extends StatelessWidget {
  const _PrescriptionSourceSheet();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _SheetHandle()),
          const SizedBox(height: 18),
          const Text(
            'Ajouter une ordonnance',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Photographiez un document bien éclairé et entièrement visible.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 18),
          _SourceTile(
            icon: Icons.camera_alt_outlined,
            title: 'Prendre une photo',
            subtitle: 'Ouvrir la caméra',
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Choisir dans la galerie',
            subtitle: 'Importer une image existante',
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    tileColor: const Color(0xFFF7F9FC),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    leading: Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: _green),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class _PrescriptionPreview extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;

  const _PrescriptionPreview({required this.bytes, required this.fileName});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ordonnance ajoutée'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              height: 230,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.description_outlined)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
                'Le document reste sur cet appareil et n’est pas encore envoyé.',
            style: TextStyle(fontSize: 12.5, color: _muted),
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(backgroundColor: _green),
        child: const Text('Continuer'),
      ),
    ],
  );
}

class _PrescriptionStatus extends StatelessWidget {
  final String fileName;
  final Uint8List? bytes;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  const _PrescriptionStatus({
    required this.fileName,
    required this.bytes,
    required this.onReplace,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _green.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: bytes == null
              ? const SizedBox(
                  width: 46,
                  height: 46,
                  child: ColoredBox(
                    color: _greenSoft,
                    child: Icon(Icons.description_outlined, color: _green),
                  ),
                )
              : Image.memory(bytes!, width: 46, height: 46, fit: BoxFit.cover),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ordonnance prête',
                style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
              ),
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onReplace, child: const Text('Remplacer')),
        IconButton(
          tooltip: 'Supprimer l’ordonnance',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  final _PharmacyFilters initial;

  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _category = widget.initial.category;
  late bool _prescriptionOnly = widget.initial.prescriptionOnly;
  late bool _availableOnly = widget.initial.availableOnly;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: _SheetHandle()),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filtrer les médicaments',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _category = 'Tous';
                  _prescriptionOnly = false;
                  _availableOnly = true;
                }),
                child: const Text('Réinitialiser'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Catégorie',
            style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in _categories)
                ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 13),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Uniquement sur ordonnance'),
            value: _prescriptionOnly,
            activeTrackColor: _green,
            onChanged: (value) => setState(() => _prescriptionOnly = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Produits disponibles'),
            value: _availableOnly,
            activeTrackColor: _green,
            onChanged: (value) => setState(() => _availableOnly = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _PharmacyFilters(
                  category: _category,
                  prescriptionOnly: _prescriptionOnly,
                  availableOnly: _availableOnly,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Afficher les résultats'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 4,
    decoration: BoxDecoration(
      color: const Color(0xFFD0D5DD),
      borderRadius: BorderRadius.circular(20),
    ),
  );
}

class _PharmacyFilters {
  final String category;
  final bool prescriptionOnly;
  final bool availableOnly;

  const _PharmacyFilters({
    required this.category,
    required this.prescriptionOnly,
    required this.availableOnly,
  });
}

class _Medication {
  final String name;
  final String activeIngredient;
  final String category;
  final String price;
  final bool requiresPrescription;
  final bool available;
  final IconData icon;
  final Color color;
  final Color accent;

  const _Medication({
    required this.name,
    required this.activeIngredient,
    required this.category,
    required this.price,
    required this.requiresPrescription,
    required this.available,
    required this.icon,
    required this.color,
    required this.accent,
  });
}

class _NearbyPharmacy {
  final String name;
  final String address;
  final String schedule;
  final String phone;
  final String storedDistance;
  final bool open;
  final double? latitude;
  final double? longitude;
  double? distanceMeters;

  _NearbyPharmacy({
    required this.name,
    required this.address,
    required this.schedule,
    required this.phone,
    required this.storedDistance,
    required this.open,
    required this.latitude,
    required this.longitude,
  });

  static _NearbyPharmacy? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final type = _readText(data, [
      'type',
      'categorie',
      'catégorie',
      'category',
    ]);
    final name = _readText(data, ['nom', 'name', 'displayName']);
    if (!'$type $name'.toLowerCase().contains('pharm')) return null;

    double? latitude;
    double? longitude;
    for (final key in const [
      'coordinates',
      'coordonnees',
      'coordonnées',
      'position',
      'geoPoint',
      'location',
    ]) {
      final value = data[key];
      if (value is GeoPoint) {
        latitude = value.latitude;
        longitude = value.longitude;
        break;
      }
      if (value is Map) {
        latitude = _readNumber(value, ['latitude', 'lat']);
        longitude = _readNumber(value, ['longitude', 'lng', 'lon']);
        if (latitude != null && longitude != null) break;
      }
    }
    latitude ??= _readNumber(data, ['latitude', 'lat']);
    longitude ??= _readNumber(data, ['longitude', 'lng', 'lon']);

    return _NearbyPharmacy(
      name: name.isEmpty ? 'Pharmacie' : name,
      address: _readText(data, ['adresse', 'address', 'localisation']),
      schedule: _readText(data, [
        'horaires',
        'horaire',
        'openingHours',
        'opening_hours',
        'schedule',
      ]),
      phone: _readText(data, [
        'telephone',
        'téléphone',
        'phone',
        'phoneNumber',
        'contact',
      ]),
      storedDistance: _readText(data, [
        'distance',
        'distanceLabel',
        'distance_label',
      ]),
      open: _readBool(data, ['ouvert', 'open', 'isOpen', 'available']),
      latitude: latitude,
      longitude: longitude,
    );
  }

  void calculateDistance(Position position) {
    if (latitude == null || longitude == null) return;
    distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude!,
      longitude!,
    );
  }

  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return storedDistance;
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class _LocationFailure implements Exception {
  final String message;

  const _LocationFailure(this.message);
}

String _readText(Map<dynamic, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is Map) {
      final nested = _readText(value, const [
        'label',
        'formatted',
        'fullAddress',
        'name',
        'value',
      ]);
      if (nested.isNotEmpty) return nested;
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

double? _readNumber(Map<dynamic, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value.toDouble();
    if (value != null) {
      final parsed = double.tryParse(value.toString().replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool _readBool(Map<dynamic, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is bool) return value;
    if (value is String) {
      return const [
        'true',
        'oui',
        'open',
        'ouvert',
      ].contains(value.toLowerCase());
    }
  }
  return true;
}

const _categories = ['Tous', 'Douleur', 'Rhume', 'Digestif', 'Vitamines'];

const _medications = <_Medication>[
  _Medication(
    name: 'Paracétamol 500 mg',
    activeIngredient: 'Paracétamol · 20 comprimés',
    category: 'Douleur',
    price: '175 HTG',
    requiresPrescription: false,
    available: true,
    icon: Icons.medication_rounded,
    color: Color(0xFFFFF2E8),
    accent: Color(0xFFF79009),
  ),
  _Medication(
    name: 'Ibuprofène 400 mg',
    activeIngredient: 'Ibuprofène · 20 comprimés',
    category: 'Douleur',
    price: '250 HTG',
    requiresPrescription: false,
    available: true,
    icon: Icons.medication_liquid_rounded,
    color: Color(0xFFEAF1FF),
    accent: _primary,
  ),
  _Medication(
    name: 'Amoxicilline 500 mg',
    activeIngredient: 'Amoxicilline · 12 gélules',
    category: 'Rhume',
    price: '650 HTG',
    requiresPrescription: true,
    available: true,
    icon: Icons.vaccines_outlined,
    color: Color(0xFFE8F8F4),
    accent: _green,
  ),
  _Medication(
    name: 'Sirop expectorant',
    activeIngredient: 'Guaïfénésine · 120 ml',
    category: 'Rhume',
    price: '425 HTG',
    requiresPrescription: false,
    available: false,
    icon: Icons.local_drink_outlined,
    color: Color(0xFFF2ECFF),
    accent: Color(0xFF7A5AF8),
  ),
  _Medication(
    name: 'Solution de réhydratation',
    activeIngredient: 'Sels minéraux · 10 sachets',
    category: 'Digestif',
    price: '300 HTG',
    requiresPrescription: false,
    available: true,
    icon: Icons.water_drop_outlined,
    color: Color(0xFFE8F7FF),
    accent: Color(0xFF0BA5EC),
  ),
  _Medication(
    name: 'Vitamine C 1000 mg',
    activeIngredient: 'Acide ascorbique · 20 comprimés',
    category: 'Vitamines',
    price: '375 HTG',
    requiresPrescription: false,
    available: true,
    icon: Icons.spa_outlined,
    color: Color(0xFFFFF4D9),
    accent: Color(0xFFEAAA08),
  ),
];

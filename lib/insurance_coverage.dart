import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'supabase_config.dart';

const insuranceCardBucket = 'insurance-cards';

class MedicalInsuranceCoverage {
  final String id;
  final String insurerCode;
  final String memberNumber;
  final String status;
  final String reviewNote;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime submittedAt;

  const MedicalInsuranceCoverage({
    required this.id,
    required this.insurerCode,
    required this.memberNumber,
    required this.status,
    required this.reviewNote,
    required this.validFrom,
    required this.validUntil,
    required this.submittedAt,
  });

  factory MedicalInsuranceCoverage.fromRow(Map<String, dynamic> row) =>
      MedicalInsuranceCoverage(
        id: row['coverage_id']?.toString() ?? '',
        insurerCode: row['insurer_code']?.toString() ?? 'OFATMA',
        memberNumber: row['member_number']?.toString() ?? '',
        status: row['status']?.toString() ?? 'pending',
        reviewNote: row['review_note']?.toString() ?? '',
        validFrom: _coverageDate(row['valid_from']),
        validUntil: _coverageDate(row['valid_until']),
        submittedAt:
            _coverageDate(row['submitted_at']) ?? DateTime.now().toLocal(),
      );

  bool get isCurrentlyValid {
    if (status != 'verified' || validUntil == null) return false;
    final today = DateUtils.dateOnly(DateTime.now());
    return !DateUtils.dateOnly(validUntil!).isBefore(today);
  }
}

DateTime? _coverageDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal();

class InsuranceCardImage {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  const InsuranceCardImage({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });
}

abstract class MedicalInsuranceRepository {
  Future<List<MedicalInsuranceCoverage>> loadCoverages(String patientId);

  Future<String> submitOfatmaCoverage({
    required String patientName,
    required String memberNumber,
    required InsuranceCardImage front,
    required InsuranceCardImage back,
  });
}

class SupabaseMedicalInsuranceRepository implements MedicalInsuranceRepository {
  final SupabaseClient client;

  SupabaseMedicalInsuranceRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Future<List<MedicalInsuranceCoverage>> loadCoverages(String patientId) async {
    final rows = await client
        .schema('ientier')
        .from('medical_insurance_coverages')
        .select()
        .eq('patient_id', patientId)
        .order('submitted_at', ascending: false);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(MedicalInsuranceCoverage.fromRow).toList(growable: false);
  }

  @override
  Future<String> submitOfatmaCoverage({
    required String patientName,
    required String memberNumber,
    required InsuranceCardImage front,
    required InsuranceCardImage back,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Session patient requise.');
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final frontPath = '$userId/$nonce-front.${_extension(front.mimeType)}';
    final backPath = '$userId/$nonce-back.${_extension(back.mimeType)}';
    final uploaded = <String>[];
    try {
      await _upload(frontPath, front);
      uploaded.add(frontPath);
      await _upload(backPath, back);
      uploaded.add(backPath);
      final value = await client
          .schema('ientier')
          .rpc(
            'submit_medical_insurance_coverage',
            params: {
              'p_patient_name': patientName,
              'p_member_number': memberNumber,
              'p_card_front_path': frontPath,
              'p_card_back_path': backPath,
              'p_card_front_mime_type': front.mimeType,
              'p_card_back_mime_type': back.mimeType,
            },
          );
      return value.toString();
    } catch (_) {
      if (uploaded.isNotEmpty) {
        try {
          await client.storage.from(insuranceCardBucket).remove(uploaded);
        } catch (_) {
          // La soumission initiale reste l'erreur utile à remonter au patient.
        }
      }
      rethrow;
    }
  }

  Future<void> _upload(String path, InsuranceCardImage image) => client.storage
      .from(insuranceCardBucket)
      .uploadBinary(
        path,
        image.bytes,
        fileOptions: FileOptions(contentType: image.mimeType, upsert: false),
      );

  String _extension(String mimeType) => switch (mimeType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
}

class MedicalInsurancePage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final MedicalInsuranceRepository? repository;

  const MedicalInsurancePage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.repository,
  });

  @override
  State<MedicalInsurancePage> createState() => _MedicalInsurancePageState();
}

class _MedicalInsurancePageState extends State<MedicalInsurancePage> {
  late final MedicalInsuranceRepository _repository =
      widget.repository ?? SupabaseMedicalInsuranceRepository();
  late Future<List<MedicalInsuranceCoverage>> _coverages = _load();

  Future<List<MedicalInsuranceCoverage>> _load() =>
      _repository.loadCoverages(widget.patientId);

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _coverages = next);
    await next;
  }

  Future<void> _addCoverage() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OfatmaCardSubmissionScreen(
          patientName: widget.patientName,
          repository: _repository,
        ),
      ),
    );
    if (submitted == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Assurance et couverture'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<MedicalInsuranceCoverage>>(
      future: _coverages,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _InsuranceError(onRetry: _refresh);
        }
        final coverages = snapshot.data ?? const [];
        final latest = coverages.firstOrNull;
        final blocksSubmission =
            latest != null &&
            (latest.status == 'pending' || latest.isCurrentlyValid);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 42),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _InsuranceIntro(),
                      const SizedBox(height: 18),
                      if (latest == null)
                        const _InsuranceEmpty()
                      else
                        _CoverageStatusCard(coverage: latest),
                      const SizedBox(height: 18),
                      if (!blocksSubmission)
                        FilledButton.icon(
                          key: const ValueKey('add-ofatma-coverage'),
                          onPressed: _addCoverage,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            latest?.status == 'rejected'
                                ? 'Soumettre à nouveau ma carte'
                                : 'Ajouter ma carte OFATMA',
                          ),
                        ),
                      if (coverages.length > 1) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Historique',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final coverage in coverages.skip(1))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CoverageHistoryTile(coverage: coverage),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class OfatmaCardSubmissionScreen extends StatefulWidget {
  final String patientName;
  final MedicalInsuranceRepository repository;

  const OfatmaCardSubmissionScreen({
    super.key,
    required this.patientName,
    required this.repository,
  });

  @override
  State<OfatmaCardSubmissionScreen> createState() =>
      _OfatmaCardSubmissionScreenState();
}

class _OfatmaCardSubmissionScreenState
    extends State<OfatmaCardSubmissionScreen> {
  final _memberNumber = TextEditingController();
  final _picker = ImagePicker();
  InsuranceCardImage? _front;
  InsuranceCardImage? _back;
  bool _saving = false;

  @override
  void dispose() {
    _memberNumber.dispose();
    super.dispose();
  }

  Future<ImageSource?> _chooseSource() => showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter l’image',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scanner avec la caméra'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pick(bool front) async {
    final source = await _chooseSource();
    if (source == null) return;
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 8 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chaque image doit faire moins de 8 Mo.')),
      );
      return;
    }
    final mimeType = _imageMimeType(file);
    final image = InsuranceCardImage(
      fileName: file.name,
      mimeType: mimeType,
      bytes: bytes,
    );
    setState(() {
      if (front) {
        _front = image;
      } else {
        _back = image;
      }
    });
  }

  Future<void> _submit() async {
    if (_front == null || _back == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scannez le recto et le verso de votre carte.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.submitOfatmaCoverage(
        patientName: widget.patientName,
        memberNumber: _memberNumber.text.trim(),
        front: _front!,
        back: _back!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La carte n’a pas pu être envoyée. Vérifiez votre connexion et réessayez.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ajouter OFATMA')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 42),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Vos images seront examinées dans I-ENTIER Professionnel. Une fois OFATMA validée et non expirée, vous pourrez demander le Crédit Santé.',
                          style: TextStyle(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _memberNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Numéro d’assuré (facultatif)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                _CardSidePicker(
                  side: 'Recto',
                  instruction: 'Photo nette avec le nom et le numéro lisibles',
                  image: _front,
                  onTap: _saving ? null : () => _pick(true),
                ),
                const SizedBox(height: 14),
                _CardSidePicker(
                  side: 'Verso',
                  instruction: 'Photographiez toute la face arrière',
                  image: _back,
                  onTap: _saving ? null : () => _pick(false),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('submit-ofatma-card'),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                    _saving ? 'Envoi en cours…' : 'Envoyer pour validation',
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

String _imageMimeType(XFile file) {
  final declared = file.mimeType?.toLowerCase();
  if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(declared)) {
    return declared!;
  }
  final name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class _InsuranceIntro extends StatelessWidget {
  const _InsuranceIntro();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.navy, AppColors.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 38),
        SizedBox(height: 14),
        Text(
          'Votre couverture médicale',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'OFATMA est la première assurance prise en charge. La validation de la carte ouvre l’éligibilité au Crédit Santé.',
          style: TextStyle(color: Color(0xFFDDE8FF), height: 1.45),
        ),
      ],
    ),
  );
}

class _InsuranceEmpty extends StatelessWidget {
  const _InsuranceEmpty();

  @override
  Widget build(BuildContext context) => const _InsurancePanel(
    child: Row(
      children: [
        Icon(Icons.credit_card_off_outlined, color: AppColors.muted, size: 34),
        SizedBox(width: 15),
        Expanded(
          child: Text(
            'Aucune couverture vérifiée. Ajoutez votre carte OFATMA pour commencer.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _CoverageStatusCard extends StatelessWidget {
  final MedicalInsuranceCoverage coverage;
  const _CoverageStatusCard({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final expired = coverage.status == 'verified' && !coverage.isCurrentlyValid;
    final (color, icon, title) = expired
        ? (AppColors.warning, Icons.event_busy_outlined, 'Couverture expirée')
        : switch (coverage.status) {
            'verified' => (
              AppColors.success,
              Icons.verified_rounded,
              'Couverture valide',
            ),
            'rejected' => (
              Theme.of(context).colorScheme.error,
              Icons.error_outline_rounded,
              'Validation refusée',
            ),
            _ => (
              AppColors.warning,
              Icons.hourglass_top_rounded,
              'Validation en cours',
            ),
          };
    return _InsurancePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coverage.insurerCode,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (coverage.memberNumber.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Numéro d’assuré : ${coverage.memberNumber}'),
          ],
          if (coverage.validUntil != null) ...[
            const SizedBox(height: 8),
            Text('Valide jusqu’au ${_date(coverage.validUntil!)}'),
          ],
          if (coverage.reviewNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              coverage.reviewNote,
              style: TextStyle(color: color, height: 1.4),
            ),
          ],
          if (coverage.isCurrentlyValid) ...[
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(
                  Icons.lock_open_rounded,
                  color: AppColors.success,
                  size: 19,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vous êtes éligible au service Crédit Santé.',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CoverageHistoryTile extends StatelessWidget {
  final MedicalInsuranceCoverage coverage;
  const _CoverageHistoryTile({required this.coverage});

  @override
  Widget build(BuildContext context) => _InsurancePanel(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history_rounded),
      title: Text('${coverage.insurerCode} • ${_date(coverage.submittedAt)}'),
      subtitle: Text(switch (coverage.status) {
        'verified' => 'Validée',
        'rejected' => 'Refusée',
        _ => 'En attente',
      }),
    ),
  );
}

class _CardSidePicker extends StatelessWidget {
  final String side;
  final String instruction;
  final InsuranceCardImage? image;
  final VoidCallback? onTap;

  const _CardSidePicker({
    required this.side,
    required this.instruction,
    required this.image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: image == null ? Colors.white : const Color(0xFFEAF8F2),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: image == null ? AppColors.border : AppColors.success,
          ),
        ),
        child: Row(
          children: [
            Icon(
              image == null ? Icons.add_a_photo_outlined : Icons.check_circle,
              color: image == null ? AppColors.primary : AppColors.success,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Carte — $side',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    image?.fileName ?? instruction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InsurancePanel extends StatelessWidget {
  final Widget child;
  const _InsurancePanel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _InsuranceError extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _InsuranceError({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: AppColors.muted,
          ),
          const SizedBox(height: 12),
          const Text('Impossible de charger vos couvertures.'),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

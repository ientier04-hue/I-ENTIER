import 'privacy/vault_table.dart';
import 'supabase_config.dart';

enum CycleLifeStage {
  unspecified,
  menstruating,
  pregnant,
  postpartum,
  perimenopause,
  menopause,
}

enum CycleContraception { unspecified, none, nonHormonal, hormonal }

class CyclePersonalContext {
  final CycleLifeStage lifeStage;
  final CycleContraception contraception;
  final bool breastfeeding;
  final bool hasPcos;
  final DateTime? historyStart;

  const CyclePersonalContext({
    this.lifeStage = CycleLifeStage.unspecified,
    this.contraception = CycleContraception.unspecified,
    this.breastfeeding = false,
    this.hasPcos = false,
    this.historyStart,
  });

  String? get suspensionReason {
    if (lifeStage == CycleLifeStage.pregnant) return 'Grossesse';
    if (lifeStage == CycleLifeStage.postpartum) return 'Post-partum';
    if (lifeStage == CycleLifeStage.menopause) return 'Ménopause';
    if (contraception == CycleContraception.hormonal) {
      return 'Contraception hormonale';
    }
    if (breastfeeding) return 'Allaitement';
    return null;
  }

  bool get needsMoreHistory =>
      hasPcos || lifeStage == CycleLifeStage.perimenopause;
  int get minimumCycles => needsMoreHistory ? 6 : 3;
  bool get canUseSymptomTiming =>
      lifeStage == CycleLifeStage.menstruating &&
      (contraception == CycleContraception.none ||
          contraception == CycleContraception.nonHormonal) &&
      !breastfeeding &&
      !hasPcos;

  bool hasSamePhysiology(CyclePersonalContext other) =>
      lifeStage == other.lifeStage &&
      contraception == other.contraception &&
      breastfeeding == other.breastfeeding &&
      hasPcos == other.hasPcos;

  factory CyclePersonalContext.fromPatientProfile(
    Map<String, dynamic> profile,
  ) => CyclePersonalContext(
    lifeStage:
        profile['pregnancy_status']?.toString().trim().toLowerCase() == 'oui'
        ? CycleLifeStage.pregnant
        : CycleLifeStage.unspecified,
  );

  factory CyclePersonalContext.fromRow(Map<String, dynamic> row) {
    T decode<T extends Enum>(List<T> values, Object? value, T fallback) =>
        values.where((item) => item.name == value).firstOrNull ?? fallback;
    final rawDate = row['history_start']?.toString();
    final parsedDate = rawDate == null ? null : DateTime.tryParse(rawDate);
    // Unknown persisted values must not silently enable a natural-cycle model.
    if (!CycleLifeStage.values.any(
          (value) => value.name == row['life_stage'],
        ) ||
        !CycleContraception.values.any(
          (value) => value.name == row['contraception'],
        ) ||
        row['breastfeeding'] is! bool ||
        row['has_pcos'] is! bool ||
        (rawDate != null && parsedDate == null)) {
      throw const FormatException('Invalid cycle context');
    }
    return CyclePersonalContext(
      lifeStage: decode(
        CycleLifeStage.values,
        row['life_stage'],
        CycleLifeStage.unspecified,
      ),
      contraception: decode(
        CycleContraception.values,
        row['contraception'],
        CycleContraception.unspecified,
      ),
      breastfeeding: row['breastfeeding'] as bool,
      hasPcos: row['has_pcos'] as bool,
      historyStart: parsedDate,
    );
  }

  Map<String, dynamic> toRow() => {
    'life_stage': lifeStage.name,
    'contraception': contraception.name,
    'breastfeeding': breastfeeding,
    'has_pcos': hasPcos,
    'history_start': historyStart == null
        ? null
        : '${historyStart!.year.toString().padLeft(4, '0')}-${historyStart!.month.toString().padLeft(2, '0')}-${historyStart!.day.toString().padLeft(2, '0')}',
  };
}

abstract class CycleContextRepository {
  Future<CyclePersonalContext> load(String patientId);
  Future<void> save(String patientId, CyclePersonalContext context);
}

class SupabaseCycleContextRepository implements CycleContextRepository {
  @override
  Future<CyclePersonalContext> load(String patientId) async {
    final row = await VaultTable(
      SupabaseConfig.client,
      'cycle_personal_contexts',
    ).select().eq('patient_id', patientId).maybeSingle();
    if (row != null) return CyclePersonalContext.fromRow(row);
    // Reuse an explicitly recorded pregnancy when setting up cycle tracking.
    // A subsequently saved cycle context remains the user's current choice.
    final profile = await VaultTable(
      SupabaseConfig.client,
      'patient_profiles',
    ).select('pregnancy_status').eq('patient_id', patientId).maybeSingle();
    return CyclePersonalContext.fromPatientProfile(profile ?? const {});
  }

  @override
  Future<void> save(String patientId, CyclePersonalContext context) async {
    await VaultTable(SupabaseConfig.client, 'cycle_personal_contexts').upsert({
      'patient_id': patientId,
      ...context.toRow(),
    }, onConflict: 'patient_id');
  }
}

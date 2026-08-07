import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/20260807043705_add_traditional_medicine.sql',
    ).readAsStringSync();
  });

  test('active RLS sur toutes les données de médecine traditionnelle', () {
    const protectedTables = [
      'traditional_practitioner_profiles',
      'traditional_practitioner_documents',
      'natural_health_journal_entries',
      'natural_health_sharing_grants',
      'traditional_prevention_recommendations',
      'traditional_care_orientations',
      'traditional_practitioner_ratings',
      'traditional_safety_reports',
      'traditional_prevention_content',
    ];

    for (final table in protectedTables) {
      expect(
        migration,
        contains('ALTER TABLE $table ENABLE ROW LEVEL SECURITY;'),
        reason: '$table doit être protégé par RLS.',
      );
    }
  });

  test('garde le carnet privé et le partage sous contrôle du patient', () {
    expect(migration, contains('patient_id = (SELECT current_actor_id())'));
    expect(migration, contains('natural_health_sharing_grants g'));
    expect(migration, contains('g.revoked_at IS NULL'));
    expect(
      migration,
      contains('g.expires_at IS NULL OR g.expires_at > CURRENT_TIMESTAMP'),
    );
  });

  test('n’affiche que les praticiens approuvés et non suspendus', () {
    expect(migration, contains("validation_status = 'approved'"));
    expect(migration, contains('suspended_at IS NULL'));
    expect(migration, contains("p.verification_status = 'approved'"));
    expect(migration, contains('p.is_visible = TRUE'));
  });

  test('empêche l’auto-modification d’un dossier déjà vérifié', () {
    expect(migration, contains("OLD.validation_status = 'approved'"));
    expect(
      migration,
      contains(
        'Une modification du dossier vérifié doit être examinée par I-Entier.',
      ),
    );
  });

  test('calcule les cinq composantes du score de confiance', () {
    expect(migration, contains('profile_verification_score'));
    expect(migration, contains('patient_satisfaction_score'));
    expect(migration, contains('compliance_score'));
    expect(migration, contains('seniority_score'));
    expect(migration, contains('follow_up_quality_score'));
    expect(migration, contains('trust_score'));
  });

  test('isole les fonctions privilégiées et suspend un rapport crédible', () {
    expect(migration, contains('CREATE SCHEMA IF NOT EXISTS ientier_private'));
    expect(
      migration,
      contains('REVOKE ALL ON SCHEMA ientier_private FROM PUBLIC'),
    );
    expect(migration, contains("NEW.credibility_status = 'credible'"));
    expect(migration, contains("validation_status = 'suspended'"));
    expect(migration, contains('online_available = FALSE'));
  });

  test('protège les justificatifs dans un bucket privé', () {
    expect(migration, contains("'traditional-practitioner-documents'"));
    expect(migration, contains('FALSE,\n  10485760'));
    expect(
      migration,
      contains('(storage.foldername(name))[1] = (SELECT auth.uid())::TEXT'),
    );
  });
}

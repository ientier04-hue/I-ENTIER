import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/insurance_coverage.dart';

void main() {
  testWidgets('présente OFATMA et le parcours de scan recto verso', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeInsuranceRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MedicalInsurancePage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'OFATMA est la première assurance prise en charge. La validation de la carte ouvre l’éligibilité au Crédit Santé.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-ofatma-coverage')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-ofatma-coverage')));
    await tester.pumpAndSettle();

    expect(find.text('Carte — Recto'), findsOneWidget);
    expect(find.text('Carte — Verso'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit-ofatma-card')), findsOneWidget);
  });

  test(
    'considère seulement une couverture vérifiée non expirée comme valide',
    () {
      final coverage = MedicalInsuranceCoverage(
        id: 'coverage-1',
        insurerCode: 'OFATMA',
        memberNumber: '',
        status: 'verified',
        reviewNote: '',
        validFrom: DateTime(2026),
        validUntil: DateTime(2099, 12, 31),
        submittedAt: DateTime(2026),
      );
      expect(coverage.isCurrentlyValid, isTrue);
    },
  );
}

class _FakeInsuranceRepository implements MedicalInsuranceRepository {
  @override
  Future<List<MedicalInsuranceCoverage>> loadCoverages(
    String patientId,
  ) async => const [];

  @override
  Future<String> submitOfatmaCoverage({
    required String patientName,
    required String memberNumber,
    required InsuranceCardImage front,
    required InsuranceCardImage back,
  }) async => 'coverage-1';
}

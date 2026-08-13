import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/health_credit_models.dart';
import 'package:i_entier/health_credit_page.dart';
import 'package:i_entier/health_credit_repository.dart';
import 'package:i_entier/insurance_coverage.dart';

void main() {
  test('classe le risque à partir du Score Santé Financier', () {
    expect(HealthCreditRiskDetails.fromScore(105), HealthCreditRisk.excellent);
    expect(HealthCreditRiskDetails.fromScore(90), HealthCreditRisk.good);
    expect(HealthCreditRiskDetails.fromScore(75), HealthCreditRisk.medium);
    expect(HealthCreditRiskDetails.fromScore(55), HealthCreditRisk.high);
  });

  testWidgets('affiche le score, le risque et l’échéancier du patient', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeHealthCreditRepository(_dashboardWithCredit);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HealthCreditPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Score Santé Financier'), findsOneWidget);
    expect(find.text('Risque Bon'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('Solde restant  60 000 HTG'), findsOneWidget);

    await tester.tap(find.text('Paiements'));
    await tester.pumpAndSettle();

    expect(find.text('Calendrier des échéances'), findsOneWidget);
    expect(find.textContaining('Échéance 1'), findsOneWidget);
    expect(find.text('Paiement partiel ou total'), findsOneWidget);
  });

  testWidgets('ouvre une demande avec trois références obligatoires', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeHealthCreditRepository(_emptyDashboard);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HealthCreditPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('health-credit-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Nouvelle demande'), findsOneWidget);
    expect(find.text('Références (3/5)'), findsOneWidget);
    expect(find.text('Référence 1'), findsOneWidget);
    expect(find.text('Référence 2'), findsOneWidget);
    expect(find.text('Référence 3'), findsOneWidget);
  });

  testWidgets('verrouille la demande sans couverture OFATMA valide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HealthCreditPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: _FakeHealthCreditRepository(_ineligibleDashboard),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couverture OFATMA requise'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-credit-apply')), findsNothing);

    await tester.tap(find.text('Demande'));
    await tester.pumpAndSettle();
    expect(find.text('Demande verrouillée'), findsOneWidget);
  });
}

final _dashboardWithCredit = HealthCreditDashboardData(
  applications: const [],
  credit: const HealthCredit(
    id: 'credit-1',
    principal: 100000,
    balance: 60000,
    installmentCount: 5,
    score: 88,
    status: 'active',
  ),
  installments: [
    HealthCreditInstallment(
      id: 'installment-1',
      number: 1,
      dueDate: DateTime(2026, 9, 3),
      due: 20000,
      paid: 0,
      status: 'upcoming',
    ),
  ],
  payments: const [],
  scoreEvents: [
    HealthScoreEvent(
      score: 88,
      variation: -12,
      reason: 'Paiement reçu en retard',
      createdAt: DateTime(2026, 8, 3),
    ),
  ],
  assessment: null,
  partnerCenters: const [],
  solidarityRequests: const [],
);

final _emptyDashboard = HealthCreditDashboardData(
  applications: [],
  credit: null,
  installments: [],
  payments: [],
  scoreEvents: [],
  assessment: null,
  partnerCenters: [],
  solidarityRequests: [],
  insuranceCoverage: MedicalInsuranceCoverage(
    id: 'coverage-1',
    insurerCode: 'OFATMA',
    memberNumber: 'OF-123',
    status: 'verified',
    reviewNote: '',
    validFrom: DateTime(2026, 1, 1),
    validUntil: DateTime(2099, 12, 31),
    submittedAt: DateTime(2026, 1, 1),
  ),
);

const _ineligibleDashboard = HealthCreditDashboardData(
  applications: [],
  credit: null,
  installments: [],
  payments: [],
  scoreEvents: [],
  assessment: null,
  partnerCenters: [],
  solidarityRequests: [],
);

class _FakeHealthCreditRepository implements HealthCreditRepository {
  final HealthCreditDashboardData data;
  _FakeHealthCreditRepository(this.data);

  @override
  Future<HealthCreditDashboardData> loadDashboard(String patientId) async =>
      data;

  @override
  Future<String> submitApplication(HealthCreditApplicationDraft draft) async =>
      'application-1';

  @override
  Future<String> submitPayment({
    required String creditId,
    required double amount,
    required String method,
    required String reference,
  }) async => 'payment-1';

  @override
  Future<String> submitSocialAssessment({
    required double householdIncome,
    required int householdSize,
    required String housingStatus,
    required String incomeStability,
    required bool foodInsecurity,
    required bool catastrophicHealthExpense,
    required bool disabilityOrDependency,
    required bool singleParent,
    required String notes,
  }) async => 'assessment-1';

  @override
  Future<String> submitSolidarityRequest({
    required String assessmentId,
    required double amount,
    required String medicalNeed,
  }) async => 'solidarity-1';
}

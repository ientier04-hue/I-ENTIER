enum HealthCreditRisk { excellent, good, medium, high }

extension HealthCreditRiskDetails on HealthCreditRisk {
  String get label => switch (this) {
    HealthCreditRisk.excellent => 'Excellent',
    HealthCreditRisk.good => 'Bon',
    HealthCreditRisk.medium => 'Moyen',
    HealthCreditRisk.high => 'Élevé',
  };

  static HealthCreditRisk fromScore(int score) {
    if (score >= 100) return HealthCreditRisk.excellent;
    if (score >= 85) return HealthCreditRisk.good;
    if (score >= 70) return HealthCreditRisk.medium;
    return HealthCreditRisk.high;
  }
}

double creditAmount(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

DateTime? creditDate(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal();

class HealthCreditApplication {
  final String id;
  final double requestedAmount;
  final String medicalReason;
  final double monthlyIncome;
  final double monthlyExpenses;
  final double disposableIncome;
  final int recommendedInstallments;
  final double estimatedInstallment;
  final int preliminaryScore;
  final int validatedReferences;
  final String status;
  final String decisionReason;
  final DateTime createdAt;

  const HealthCreditApplication({
    required this.id,
    required this.requestedAmount,
    required this.medicalReason,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.disposableIncome,
    required this.recommendedInstallments,
    required this.estimatedInstallment,
    required this.preliminaryScore,
    required this.validatedReferences,
    required this.status,
    required this.decisionReason,
    required this.createdAt,
  });

  factory HealthCreditApplication.fromRow(Map<String, dynamic> row) =>
      HealthCreditApplication(
        id: row['application_id']?.toString() ?? '',
        requestedAmount: creditAmount(row['requested_amount']),
        medicalReason: row['medical_reason']?.toString() ?? '',
        monthlyIncome: creditAmount(row['monthly_income']),
        monthlyExpenses: creditAmount(row['monthly_expenses']),
        disposableIncome: creditAmount(row['disposable_income']),
        recommendedInstallments:
            (row['recommended_installments'] as num?)?.toInt() ?? 0,
        estimatedInstallment: creditAmount(row['estimated_installment']),
        preliminaryScore: (row['preliminary_score'] as num?)?.toInt() ?? 0,
        validatedReferences:
            (row['validated_reference_count'] as num?)?.toInt() ?? 0,
        status: row['status']?.toString() ?? '',
        decisionReason: row['decision_reason']?.toString() ?? '',
        createdAt: creditDate(row['created_at']) ?? DateTime.now(),
      );
}

class HealthCredit {
  final String id;
  final double principal;
  final double balance;
  final int installmentCount;
  final int score;
  final String status;
  final DateTime? suspendedUntil;

  const HealthCredit({
    required this.id,
    required this.principal,
    required this.balance,
    required this.installmentCount,
    required this.score,
    required this.status,
    this.suspendedUntil,
  });

  factory HealthCredit.fromRow(Map<String, dynamic> row) => HealthCredit(
    id: row['credit_id']?.toString() ?? '',
    principal: creditAmount(row['principal_amount']),
    balance: creditAmount(row['outstanding_balance']),
    installmentCount: (row['installment_count'] as num?)?.toInt() ?? 0,
    score: (row['financial_health_score'] as num?)?.toInt() ?? 100,
    status: row['status']?.toString() ?? '',
    suspendedUntil: creditDate(row['access_suspended_until']),
  );

  HealthCreditRisk get risk => HealthCreditRiskDetails.fromScore(score);
  double get progress => principal <= 0
      ? 0
      : ((principal - balance) / principal).clamp(0, 1).toDouble();
}

class HealthCreditInstallment {
  final String id;
  final int number;
  final DateTime dueDate;
  final double due;
  final double paid;
  final String status;

  const HealthCreditInstallment({
    required this.id,
    required this.number,
    required this.dueDate,
    required this.due,
    required this.paid,
    required this.status,
  });

  factory HealthCreditInstallment.fromRow(Map<String, dynamic> row) =>
      HealthCreditInstallment(
        id: row['installment_id']?.toString() ?? '',
        number: (row['installment_number'] as num?)?.toInt() ?? 0,
        dueDate: creditDate(row['due_date']) ?? DateTime.now(),
        due: creditAmount(row['amount_due']),
        paid: creditAmount(row['amount_paid']),
        status: row['status']?.toString() ?? '',
      );

  double get remaining => (due - paid).clamp(0, double.infinity);
}

class HealthCreditPayment {
  final String id;
  final double amount;
  final String method;
  final String status;
  final String rejectionReason;
  final DateTime createdAt;

  const HealthCreditPayment({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.rejectionReason,
    required this.createdAt,
  });

  factory HealthCreditPayment.fromRow(Map<String, dynamic> row) =>
      HealthCreditPayment(
        id: row['payment_id']?.toString() ?? '',
        amount: creditAmount(row['amount']),
        method: row['payment_method']?.toString() ?? '',
        status: row['payment_status']?.toString() ?? '',
        rejectionReason: row['rejection_reason']?.toString() ?? '',
        createdAt: creditDate(row['created_at']) ?? DateTime.now(),
      );
}

class HealthScoreEvent {
  final int score;
  final int variation;
  final String reason;
  final DateTime createdAt;

  const HealthScoreEvent({
    required this.score,
    required this.variation,
    required this.reason,
    required this.createdAt,
  });

  factory HealthScoreEvent.fromRow(Map<String, dynamic> row) =>
      HealthScoreEvent(
        score: (row['new_score'] as num?)?.toInt() ?? 100,
        variation: (row['variation'] as num?)?.toInt() ?? 0,
        reason: row['reason']?.toString() ?? '',
        createdAt: creditDate(row['created_at']) ?? DateTime.now(),
      );
}

class HealthSocialAssessment {
  final String id;
  final int score;
  final String level;
  final bool vulnerable;
  final DateTime assessedAt;

  const HealthSocialAssessment({
    required this.id,
    required this.score,
    required this.level,
    required this.vulnerable,
    required this.assessedAt,
  });

  factory HealthSocialAssessment.fromRow(Map<String, dynamic> row) =>
      HealthSocialAssessment(
        id: row['assessment_id']?.toString() ?? '',
        score: (row['vulnerability_score'] as num?)?.toInt() ?? 0,
        level: row['vulnerability_level']?.toString() ?? 'low',
        vulnerable: row['recognized_vulnerable'] == true,
        assessedAt: creditDate(row['assessed_at']) ?? DateTime.now(),
      );
}

class HealthPartnerCenter {
  final String id;
  final String name;
  final String address;
  final String commune;
  final String phone;
  final String services;

  const HealthPartnerCenter({
    required this.id,
    required this.name,
    required this.address,
    required this.commune,
    required this.phone,
    required this.services,
  });

  factory HealthPartnerCenter.fromRow(Map<String, dynamic> row) =>
      HealthPartnerCenter(
        id: row['center_id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        address: row['address']?.toString() ?? '',
        commune: row['commune']?.toString() ?? '',
        phone: row['phone']?.toString() ?? '',
        services: row['services_summary']?.toString() ?? '',
      );
}

class HealthSolidarityRequest {
  final String id;
  final double requestedAmount;
  final double fundedAmount;
  final String medicalNeed;
  final String status;
  final String socialWorker;
  final String medicalCoordinator;
  final String followUpNote;

  const HealthSolidarityRequest({
    required this.id,
    required this.requestedAmount,
    required this.fundedAmount,
    required this.medicalNeed,
    required this.status,
    required this.socialWorker,
    required this.medicalCoordinator,
    required this.followUpNote,
  });

  factory HealthSolidarityRequest.fromRow(Map<String, dynamic> row) =>
      HealthSolidarityRequest(
        id: row['solidarity_request_id']?.toString() ?? '',
        requestedAmount: creditAmount(row['requested_amount']),
        fundedAmount: creditAmount(row['funded_amount']),
        medicalNeed: row['medical_need']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        socialWorker: row['social_worker']?.toString() ?? '',
        medicalCoordinator: row['medical_coordinator']?.toString() ?? '',
        followUpNote: row['follow_up_note']?.toString() ?? '',
      );
}

class HealthCreditDashboardData {
  final List<HealthCreditApplication> applications;
  final HealthCredit? credit;
  final List<HealthCreditInstallment> installments;
  final List<HealthCreditPayment> payments;
  final List<HealthScoreEvent> scoreEvents;
  final HealthSocialAssessment? assessment;
  final List<HealthPartnerCenter> partnerCenters;
  final List<HealthSolidarityRequest> solidarityRequests;

  const HealthCreditDashboardData({
    required this.applications,
    required this.credit,
    required this.installments,
    required this.payments,
    required this.scoreEvents,
    required this.assessment,
    required this.partnerCenters,
    required this.solidarityRequests,
  });
}

class HealthCreditReferenceDraft {
  final String fullName;
  final String phone;
  final String relationship;
  final String type;

  const HealthCreditReferenceDraft({
    required this.fullName,
    required this.phone,
    required this.relationship,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'phone': phone,
    'relationship': relationship,
    'reference_type': type,
  };
}

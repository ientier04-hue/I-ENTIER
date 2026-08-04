import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'health_credit_models.dart';
import 'supabase_config.dart';

class HealthCreditDocumentDraft {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  const HealthCreditDocumentDraft({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });
}

class HealthCreditApplicationDraft {
  final String patientName;
  final double requestedAmount;
  final String medicalReason;
  final double monthlyIncome;
  final double monthlyExpenses;
  final String employer;
  final List<HealthCreditReferenceDraft> references;
  final List<HealthCreditDocumentDraft> documents;

  const HealthCreditApplicationDraft({
    required this.patientName,
    required this.requestedAmount,
    required this.medicalReason,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.employer,
    required this.references,
    required this.documents,
  });
}

abstract class HealthCreditRepository {
  Future<HealthCreditDashboardData> loadDashboard(String patientId);
  Future<String> submitApplication(HealthCreditApplicationDraft draft);
  Future<String> submitPayment({
    required String creditId,
    required double amount,
    required String method,
    required String reference,
  });
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
  });
  Future<String> submitSolidarityRequest({
    required String assessmentId,
    required double amount,
    required String medicalNeed,
  });
}

class SupabaseHealthCreditRepository implements HealthCreditRepository {
  final SupabaseClient client;

  SupabaseHealthCreditRepository({SupabaseClient? client})
    : client = client ?? SupabaseConfig.client;

  @override
  Future<HealthCreditDashboardData> loadDashboard(String patientId) async {
    final results = await Future.wait<dynamic>([
      client
          .schema('ientier')
          .from('health_credit_applications')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
      client
          .schema('ientier')
          .from('health_credits')
          .select()
          .eq('patient_id', patientId)
          .order('activated_at', ascending: false),
      client
          .schema('ientier')
          .from('health_credit_installments')
          .select()
          .order('installment_number'),
      client
          .schema('ientier')
          .from('health_credit_payments')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
      client
          .schema('ientier')
          .from('health_financial_score_events')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
      client
          .schema('ientier')
          .from('health_social_assessments')
          .select()
          .eq('patient_id', patientId)
          .order('assessed_at', ascending: false),
      client
          .schema('ientier')
          .from('health_partner_centers')
          .select()
          .eq('active', true)
          .order('name'),
      client
          .schema('ientier')
          .from('health_solidarity_requests')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
    ]);
    List<Map<String, dynamic>> rows(int index) =>
        List<Map<String, dynamic>>.from(results[index] as List);
    final credits = rows(1).map(HealthCredit.fromRow).toList();
    final credit = credits.isEmpty ? null : credits.first;
    return HealthCreditDashboardData(
      applications: rows(0).map(HealthCreditApplication.fromRow).toList(),
      credit: credit,
      installments: rows(2)
          .where(
            (row) =>
                credit != null && row['credit_id']?.toString() == credit.id,
          )
          .map(HealthCreditInstallment.fromRow)
          .toList(),
      payments: rows(3)
          .where(
            (row) =>
                credit == null || row['credit_id']?.toString() == credit.id,
          )
          .map(HealthCreditPayment.fromRow)
          .toList(),
      scoreEvents: rows(4).map(HealthScoreEvent.fromRow).toList(),
      assessment: rows(5).isEmpty
          ? null
          : HealthSocialAssessment.fromRow(rows(5).first),
      partnerCenters: rows(6).map(HealthPartnerCenter.fromRow).toList(),
      solidarityRequests: rows(7).map(HealthSolidarityRequest.fromRow).toList(),
    );
  }

  @override
  Future<String> submitApplication(HealthCreditApplicationDraft draft) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Session patient requise.');
    final uploaded = <Map<String, dynamic>>[];
    for (var index = 0; index < draft.documents.length; index++) {
      final document = draft.documents[index];
      final safeName = document.fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final path =
          '$userId/${DateTime.now().microsecondsSinceEpoch}-$index-$safeName';
      await client.storage
          .from('health-credit-documents')
          .uploadBinary(
            path,
            document.bytes,
            fileOptions: FileOptions(
              contentType: document.mimeType,
              upsert: false,
            ),
          );
      uploaded.add({
        'storage_path': path,
        'file_name': document.fileName,
        'mime_type': document.mimeType,
        'file_size_bytes': document.bytes.length,
      });
    }
    final value = await client
        .schema('ientier')
        .rpc(
          'submit_health_credit_application',
          params: {
            'p_patient_name': draft.patientName,
            'p_requested_amount': draft.requestedAmount,
            'p_medical_reason': draft.medicalReason,
            'p_monthly_income': draft.monthlyIncome,
            'p_monthly_expenses': draft.monthlyExpenses,
            'p_employer': draft.employer,
            'p_references': draft.references
                .map((item) => item.toJson())
                .toList(),
            'p_documents': uploaded,
          },
        );
    return value.toString();
  }

  @override
  Future<String> submitPayment({
    required String creditId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    final value = await client
        .schema('ientier')
        .rpc(
          'submit_health_credit_payment',
          params: {
            'p_credit_id': creditId,
            'p_amount': amount,
            'p_payment_method': method,
            'p_patient_reference': reference,
          },
        );
    return value.toString();
  }

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
  }) async {
    final value = await client
        .schema('ientier')
        .rpc(
          'submit_health_social_assessment',
          params: {
            'p_household_income': householdIncome,
            'p_household_size': householdSize,
            'p_housing_status': housingStatus,
            'p_income_stability': incomeStability,
            'p_food_insecurity': foodInsecurity,
            'p_catastrophic_health_expense': catastrophicHealthExpense,
            'p_disability_or_dependency': disabilityOrDependency,
            'p_single_parent': singleParent,
            'p_notes': notes,
          },
        );
    return value.toString();
  }

  @override
  Future<String> submitSolidarityRequest({
    required String assessmentId,
    required double amount,
    required String medicalNeed,
  }) async {
    final value = await client
        .schema('ientier')
        .rpc(
          'submit_health_solidarity_request',
          params: {
            'p_assessment_id': assessmentId,
            'p_requested_amount': amount,
            'p_medical_need': medicalNeed,
          },
        );
    return value.toString();
  }
}

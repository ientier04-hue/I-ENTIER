import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

enum ConsultationKind { diagnosis, prescription, exams, followup }

extension ConsultationKindText on ConsultationKind {
  String get label => switch (this) {
    ConsultationKind.diagnosis => 'Diagnostic',
    ConsultationKind.prescription => 'Ordonnance',
    ConsultationKind.exams => 'Examens',
    ConsultationKind.followup => 'Rendez-vous',
  };
  String get title => switch (this) {
    ConsultationKind.diagnosis => 'Fiche de diagnostic',
    ConsultationKind.prescription => 'Nouvelle ordonnance',
    ConsultationKind.exams => 'Examens à réaliser',
    ConsultationKind.followup => 'Prochain rendez-vous',
  };
}

class ConsultationDocument {
  final String id, patientName, providerName;
  final ConsultationKind kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  ConsultationDocument.fromJson(Map<String, dynamic> row)
    : id = row['document_id'] as String,
      patientName = row['patient_name'] as String,
      providerName = row['provider_name'] as String,
      kind = ConsultationKind.values.byName(row['kind'] as String),
      payload = Map<String, dynamic>.from(row['payload'] as Map),
      createdAt = DateTime.parse(row['created_at'] as String).toLocal();
}

class ConsultationExam {
  final String id, name, category;
  const ConsultationExam({
    required this.id,
    required this.name,
    required this.category,
  });
}

abstract class ConsultationRepository {
  Future<List<ConsultationDocument>> documents(String appointmentId);
  Future<List<ConsultationExam>> examCatalog(String appointmentId);
  Future<ConsultationDocument> publish({
    required String appointmentId,
    required String requestId,
    required ConsultationKind kind,
    required Map<String, dynamic> payload,
  });
}

class SupabaseConsultationRepository implements ConsultationRepository {
  final SupabaseClient client;
  final String userId;
  const SupabaseConsultationRepository({
    required this.client,
    required this.userId,
  });

  void _checkUser() {
    if (client.auth.currentUser?.id != userId) {
      throw const ConsultationException('Reconnectez-vous pour continuer.');
    }
  }

  @override
  Future<List<ConsultationDocument>> documents(String appointmentId) async {
    _checkUser();
    final rows = await client
        .schema('ientier')
        .from('consultation_documents')
        .select(
          'document_id,patient_name,provider_name,kind,payload,created_at',
        )
        .eq('appointment_id', appointmentId)
        .eq('provider_id', userId)
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(const Duration(seconds: 20));
    _checkUser();
    return rows.map(ConsultationDocument.fromJson).toList();
  }

  @override
  Future<List<ConsultationExam>> examCatalog(String appointmentId) async {
    _checkUser();
    final rows = await client
        .schema('ientier')
        .rpc(
          'video_consultation_catalog',
          params: {'p_appointment_id': appointmentId},
        )
        .timeout(const Duration(seconds: 20));
    _checkUser();
    return (rows as List)
        .map(
          (row) => ConsultationExam(
            id: row['id'] as String,
            name: row['name'] as String,
            category: row['category'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<ConsultationDocument> publish({
    required String appointmentId,
    required String requestId,
    required ConsultationKind kind,
    required Map<String, dynamic> payload,
  }) async {
    _checkUser();
    try {
      final row = await client
          .schema('ientier')
          .rpc(
            'publish_video_consultation',
            params: {
              'p_appointment_id': appointmentId,
              'p_request_id': requestId,
              'p_kind': kind.name,
              'p_payload': payload,
            },
          )
          .timeout(const Duration(seconds: 30));
      _checkUser();
      return ConsultationDocument.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
    } on PostgrestException catch (error) {
      throw ConsultationException(switch (error.message) {
        'not_allowed' => 'Cette consultation ne vous est plus accessible.',
        'provider_not_approved' =>
          'Votre profil professionnel doit être validé.',
        'slot_unavailable' =>
          'Ce créneau est déjà occupé. Choisissez un autre horaire.',
        'exam_unavailable' => 'Un examen sélectionné n’est plus disponible.',
        'invalid_followup' =>
          'Choisissez un rendez-vous entre 30 minutes et un an à partir de maintenant.',
        'request_conflict' =>
          'Cet envoi a déjà été traité avec un autre contenu.',
        _ =>
          error.code == '22023'
              ? 'Vérifiez les champs saisis.'
              : 'Envoi impossible. Réessayez.',
      });
    }
  }
}

class ConsultationException implements Exception {
  final String message;
  const ConsultationException(this.message);
}

/// Kept for the entire submission attempt, including network retries.
String newConsultationRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum VideoCallRole { patient, provider }

class VideoCall {
  final int revision;
  final String id, appointmentId, patientId, providerId, callerId;
  final String patientName, providerName, status;
  final DateTime createdAt, expiresAt;
  final DateTime? acceptedAt, endedAt;

  VideoCall.fromJson(Map<String, dynamic> row)
    : revision = (row['revision'] as num?)?.toInt() ?? 0,
      id = row['id'] as String,
      appointmentId = row['appointment_id'] as String,
      patientId = row['patient_id'] as String,
      providerId = row['provider_id'] as String,
      callerId = row['caller_id'] as String,
      patientName = row['patient_name'] as String,
      providerName = row['provider_name'] as String,
      status = row['status'] as String,
      createdAt = DateTime.parse(row['created_at'] as String),
      expiresAt = DateTime.parse(row['expires_at'] as String),
      acceptedAt = DateTime.tryParse(row['accepted_at']?.toString() ?? ''),
      endedAt = DateTime.tryParse(row['ended_at']?.toString() ?? '');

  bool get isActive => status == 'ringing' || status == 'accepted';
  bool isIncoming(String userId) =>
      status == 'ringing' &&
      callerId != userId &&
      expiresAt.isAfter(DateTime.now());
  String otherName(String userId) =>
      userId == patientId ? providerName : patientName;
  String get label => switch (status) {
    'ringing' =>
      expiresAt.isAfter(DateTime.now()) ? 'Appel en cours…' : 'Sans réponse',
    'accepted' => 'En cours',
    'declined' => 'Refusé',
    'missed' => 'Sans réponse',
    'cancelled' => 'Annulé',
    'failed' => 'Échec de connexion',
    _ => 'Terminé',
  };
}

class VideoAppointment {
  final String id, name, service;
  final DateTime scheduledAt;
  VideoAppointment.fromJson(Map<String, dynamic> row, VideoCallRole role)
    : id = row['appointment_id'] as String,
      name =
          row[role == VideoCallRole.patient
                  ? 'provider_name_snapshot'
                  : 'patient_name_snapshot']
              as String,
      service = row['service_name_snapshot'] as String? ?? '',
      scheduledAt = DateTime.parse(row['scheduled_at'] as String);

  bool canCallAt(DateTime now) =>
      !now.isBefore(scheduledAt.subtract(const Duration(minutes: 30))) &&
      !now.isAfter(scheduledAt.add(const Duration(hours: 4)));
}

class VideoCallException implements Exception {
  final String code;
  const VideoCallException(this.code);
  String get message => switch (code) {
    'not_configured' => 'Les appels vidéo ne sont pas encore disponibles.',
    'unauthorized' => 'Reconnectez-vous pour appeler.',
    'not_allowed' => 'Cet appel ne vous est pas accessible.',
    'outside_call_window' =>
      'L’appel est disponible 30 minutes avant le rendez-vous et jusqu’à 4 heures après.',
    'appointment_unavailable' => 'Ce rendez-vous vidéo n’est plus disponible.',
    'participant_busy' => 'Votre interlocuteur est déjà en appel.',
    'rate_limited' => 'Patientez un instant avant de rappeler.',
    'call_finished' => 'Cet appel est terminé.',
    _ => 'Connexion impossible. Réessayez.',
  };
}

abstract class VideoCallRepository {
  Stream<void> get changes;
  Future<Map<String, dynamic>> command(
    String action, {
    String? appointmentId,
    String? callId,
  });
  Future<List<VideoAppointment>> appointments();
  void dispose();
}

class SupabaseVideoCallRepository implements VideoCallRepository {
  final SupabaseClient client;
  final String userId;
  final VideoCallRole role;
  final _changes = StreamController<void>.broadcast();
  late final RealtimeChannel _channel;

  SupabaseVideoCallRepository({
    required this.client,
    required this.userId,
    required this.role,
  }) {
    _channel = client.channel('video-calls-$userId-${role.name}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'ientier',
        table: 'video_calls',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: '${role.name}_id',
          value: userId,
        ),
        callback: (_) {
          if (!_changes.isClosed) _changes.add(null);
        },
      )
      ..subscribe();
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Map<String, dynamic>> command(
    String action, {
    String? appointmentId,
    String? callId,
  }) async {
    // Reject a stale screen after sign-out/account switching.
    if (client.auth.currentUser?.id != userId) {
      throw const VideoCallException('unauthorized');
    }
    try {
      final response = await client.functions
          .invoke(
            'video-call',
            body: {
              'action': action,
              'appointmentId': ?appointmentId,
              'callId': ?callId,
            },
          )
          .timeout(const Duration(seconds: 20));
      final body = Map<String, dynamic>.from(response.data as Map);
      if (body['error'] != null) {
        throw VideoCallException(body['error'] as String);
      }
      return body;
    } on FunctionException catch (error) {
      final details = error.details;
      throw VideoCallException(
        details is Map
            ? details['error']?.toString() ?? 'unavailable'
            : 'unavailable',
      );
    }
  }

  @override
  Future<List<VideoAppointment>> appointments() async {
    final rows = await client
        .schema('ientier')
        .from('appointments')
        .select(
          'appointment_id,patient_name_snapshot,provider_name_snapshot,service_name_snapshot,scheduled_at',
        )
        .eq('${role.name}_id', userId)
        .eq('mode', 'video')
        .eq('status', 'confirmed')
        .gte(
          'scheduled_at',
          DateTime.now()
              .subtract(const Duration(hours: 4))
              .toUtc()
              .toIso8601String(),
        )
        .order('scheduled_at')
        .limit(100);
    return rows.map((row) => VideoAppointment.fromJson(row, role)).toList();
  }

  @override
  void dispose() {
    unawaited(client.removeChannel(_channel));
    unawaited(_changes.close());
  }
}

class VideoCallController extends ChangeNotifier {
  final VideoCallRepository repository;
  final String userId;
  List<VideoCall> calls = [];
  bool loading = true, configured = false;
  String? error;
  bool _disposed = false, _refreshing = false, _refreshAgain = false;
  late final StreamSubscription<void> _subscription;
  Timer? _poll;

  VideoCallController({required this.repository, required this.userId}) {
    _subscription = repository.changes.listen((_) => unawaited(refresh()));
    // Polling recovers from Realtime outages and expired unanswered calls.
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final result = await repository.command('sync');
      if (_disposed) return;
      final incoming = (result['calls'] as List)
          .map(
            (row) => VideoCall.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      _merge(incoming);
      configured = result['configured'] == true;
      error = null;
    } catch (_) {
      if (!_disposed) error = 'Impossible de charger les appels.';
    } finally {
      _refreshing = false;
      if (!_disposed) {
        loading = false;
        notifyListeners();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  VideoCall? find(String id) {
    for (final call in calls) {
      if (call.id == id) return call;
    }
    return null;
  }

  Future<VideoCall> act(
    String action, {
    String? appointmentId,
    String? callId,
  }) async {
    final response = await repository.command(
      action,
      appointmentId: appointmentId,
      callId: callId,
    );
    final call = VideoCall.fromJson(
      Map<String, dynamic>.from(response['call'] as Map),
    );
    if (!_disposed) {
      _merge([call]);
      notifyListeners();
    }
    return call;
  }

  void _merge(List<VideoCall> incoming) {
    final byId = {for (final call in calls) call.id: call};
    for (final call in incoming) {
      if (call.revision >= (byId[call.id]?.revision ?? -1)) {
        byId[call.id] = call;
      }
    }
    calls = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (calls.length > 100) calls = calls.take(100).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_subscription.cancel());
    repository.dispose();
    super.dispose();
  }
}

String videoCallError(Object error) => error is VideoCallException
    ? error.message
    : 'Connexion impossible. Réessayez.';

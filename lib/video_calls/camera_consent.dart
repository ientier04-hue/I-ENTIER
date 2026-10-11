import 'dart:convert';

/// A request only offers a camera button; it never starts capture.
class CameraConsent {
  static const topic = 'ientier.camera-request.v1';
  final String callId, patientId, providerId, userId;
  DateTime? _requestedUntil;
  DateTime? _lastSentAt;

  CameraConsent({
    required this.callId,
    required this.patientId,
    required this.providerId,
    required this.userId,
  });

  bool get isProvider => userId == providerId;
  bool hasRequest(DateTime now) =>
      userId == patientId && (_requestedUntil?.isAfter(now) ?? false);
  bool canEnableCamera(DateTime now) => isProvider || hasRequest(now);
  bool canRequest(DateTime now) =>
      isProvider &&
      (_lastSentAt == null || now.difference(_lastSentAt!).inSeconds >= 15);

  List<int> request(DateTime now) {
    if (!canRequest(now)) throw StateError('Camera request unavailable');
    _lastSentAt = now;
    return utf8.encode(
      jsonEncode({
        'callId': callId,
        'expiresAt': now
            .add(const Duration(seconds: 60))
            .toUtc()
            .toIso8601String(),
      }),
    );
  }

  bool receive({
    required String? senderId,
    required String? messageTopic,
    required List<int> data,
    required DateTime now,
  }) {
    if (userId != patientId ||
        senderId != providerId ||
        messageTopic != topic ||
        data.length > 1024) {
      return false;
    }
    try {
      final payload = jsonDecode(utf8.decode(data));
      if (payload is! Map || payload['callId'] != callId) return false;
      final expires = DateTime.tryParse(payload['expiresAt']?.toString() ?? '');
      if (expires == null ||
          !expires.isAfter(now) ||
          expires.difference(now) > const Duration(seconds: 65)) {
        return false;
      }
      _requestedUntil = expires;
      return true;
    } on FormatException {
      return false;
    }
  }

  void dismiss() => _requestedUntil = null;
  void reset() {
    dismiss();
    _lastSentAt = null;
  }
}

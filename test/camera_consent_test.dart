import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/video_calls/camera_consent.dart';

void main() {
  final now = DateTime.utc(2026, 10, 10, 12);
  CameraConsent consent(String user) => CameraConsent(
    callId: 'call',
    patientId: 'patient',
    providerId: 'provider',
    userId: user,
  );
  bool deliver(
    CameraConsent target,
    List<int> data, {
    String? sender = 'provider',
    String topic = CameraConsent.topic,
    DateTime? at,
  }) => target.receive(
    senderId: sender,
    messageTopic: topic,
    data: data,
    now: at ?? now,
  );

  test('patient camera requires a request; provider controls own camera', () {
    expect(consent('patient').canEnableCamera(now), isFalse);
    expect(consent('provider').canEnableCamera(now), isTrue);
    expect(consent('stranger').canEnableCamera(now), isFalse);
    expect(() => consent('patient').request(now), throwsStateError);
  });

  test('valid request offers consent and expires after one minute', () {
    final patient = consent('patient');
    expect(deliver(patient, consent('provider').request(now)), isTrue);
    expect(patient.hasRequest(now), isTrue);
    expect(patient.canEnableCamera(now), isTrue);
    expect(
      patient.canEnableCamera(now.add(const Duration(seconds: 60))),
      isFalse,
    );
  });

  test('refusal or consumption requires a fresh request', () {
    final patient = consent('patient');
    deliver(patient, consent('provider').request(now));
    patient.dismiss();
    expect(patient.canEnableCamera(now), isFalse);
  });

  test('reconnection clears consent and request cooldown', () {
    final patient = consent('patient');
    final provider = consent('provider');
    deliver(patient, provider.request(now));
    expect(provider.canRequest(now), isFalse);
    patient.reset();
    provider.reset();
    expect(patient.hasRequest(now), isFalse);
    expect(provider.canRequest(now), isTrue);
  });

  test('requests are throttled without preventing a later retry', () {
    final provider = consent('provider');
    provider.request(now);
    expect(() => provider.request(now), throwsStateError);
    expect(provider.canRequest(now.add(const Duration(seconds: 15))), isTrue);
  });

  test(
    'ignores other senders, topics, calls, expired or malformed messages',
    () {
      final patient = consent('patient');
      final message = consent('provider').request(now);
      expect(deliver(patient, message, sender: 'patient'), isFalse);
      expect(deliver(patient, message, sender: null), isFalse);
      expect(deliver(patient, message, topic: 'other'), isFalse);
      expect(deliver(consent('provider'), message), isFalse);
      expect(
        deliver(patient, message, at: now.add(const Duration(minutes: 1))),
        isFalse,
      );
      expect(
        deliver(patient, message, at: now.subtract(const Duration(minutes: 1))),
        isFalse,
      );
      expect(deliver(patient, utf8.encode('{"callId":"other"}')), isFalse);
      expect(deliver(patient, utf8.encode('not json')), isFalse);
      expect(deliver(patient, [255]), isFalse);
      expect(deliver(patient, List.filled(1025, 0)), isFalse);
      expect(patient.hasRequest(now), isFalse);
    },
  );
}

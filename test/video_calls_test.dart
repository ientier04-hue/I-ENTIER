import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/video_calls/video_call_repository.dart';
import 'package:i_entier/video_calls/video_calls_page.dart';
import 'package:i_entier/video_calls/video_room_page.dart';

Map<String, dynamic> callRow({String status = 'ringing', int revision = 0}) => {
  'id': 'call-one',
  'appointment_id': 'appointment-one',
  'patient_id': 'patient',
  'provider_id': 'doctor',
  'caller_id': 'patient',
  'patient_name': 'Marie Jean',
  'provider_name': 'Dr Anne Pierre',
  'status': status,
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'expires_at': DateTime.now()
      .add(const Duration(minutes: 1))
      .toUtc()
      .toIso8601String(),
  'revision': revision,
};

class FakeCalls implements VideoCallRepository {
  final events = StreamController<void>.broadcast();
  final actions = <String>[];
  List<Map<String, dynamic>> rows = [];
  bool configured = true;
  Completer<Map<String, dynamic>>? nextSync;
  Completer<Map<String, dynamic>>? nextStart;
  List<VideoAppointment> targets = [
    VideoAppointment.fromJson({
      'appointment_id': 'appointment-one',
      'provider_name_snapshot': 'Dr Anne Pierre',
      'service_name_snapshot': 'Consultation',
      'scheduled_at': DateTime.now().toUtc().toIso8601String(),
    }, VideoCallRole.patient),
  ];
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<List<VideoAppointment>> appointments() async => targets;
  @override
  Future<Map<String, dynamic>> command(
    String action, {
    String? appointmentId,
    String? callId,
  }) async {
    actions.add(action);
    if (action == 'sync') {
      final pending = nextSync;
      nextSync = null;
      return pending == null
          ? {'calls': rows, 'configured': configured}
          : pending.future;
    }
    if (action == 'start' && nextStart != null) return nextStart!.future;
    final row = callRow(
      status: action == 'end'
          ? 'ended'
          : action == 'decline'
          ? 'declined'
          : 'ringing',
      revision: action == 'end' || action == 'decline' ? 2 : 0,
    );
    rows = [row];
    return {'call': row};
  }

  @override
  void dispose() {
    unawaited(events.close());
  }
}

void main() {
  testWidgets('incoming call appears over another page and can be declined', (
    tester,
  ) async {
    final repo = FakeCalls();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoCallHost(
          userId: 'patient',
          role: VideoCallRole.patient,
          repository: repo,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Dossier')),
                  ),
                ),
                child: const Text('Ouvrir le dossier'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouvrir le dossier'));
    await tester.pumpAndSettle();
    repo.rows = [callRow()..['caller_id'] = 'doctor'];
    repo.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Appel vidéo entrant'), findsOneWidget);
    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();
    expect(repo.actions, contains('decline'));
    expect(find.text('Dossier'), findsOneWidget);
    expect(find.text('Appel vidéo entrant'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('caller cancellation dismisses only the incoming dialog', (
    tester,
  ) async {
    final repo = FakeCalls()..rows = [callRow()..['caller_id'] = 'doctor'];
    await tester.pumpWidget(
      MaterialApp(
        home: VideoCallHost(
          userId: 'patient',
          role: VideoCallRole.patient,
          repository: repo,
          child: const Scaffold(body: Text('Accueil')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appel vidéo entrant'), findsOneWidget);
    repo.rows = [
      callRow(status: 'cancelled', revision: 1)..['caller_id'] = 'doctor',
    ];
    repo.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Appel vidéo entrant'), findsNothing);
    expect(find.text('Accueil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('call window boundaries match server policy', () {
    final appointment = FakeCalls().targets.first;
    expect(
      appointment.canCallAt(
        appointment.scheduledAt.subtract(const Duration(minutes: 31)),
      ),
      false,
    );
    expect(
      appointment.canCallAt(
        appointment.scheduledAt.subtract(const Duration(minutes: 30)),
      ),
      true,
    );
    expect(
      appointment.canCallAt(
        appointment.scheduledAt.add(const Duration(hours: 4)),
      ),
      true,
    );
    expect(
      appointment.canCallAt(
        appointment.scheduledAt.add(const Duration(hours: 4, seconds: 1)),
      ),
      false,
    );
  });

  test('an outdated sync cannot revive an ended call', () async {
    final repo = FakeCalls();
    final controller = VideoCallController(repository: repo, userId: 'patient');
    await Future<void>.delayed(Duration.zero);
    final pending = Completer<Map<String, dynamic>>();
    repo.nextSync = pending;
    final refresh = controller.refresh();
    await controller.act('end', callId: 'call-one');
    pending.complete({
      'calls': [callRow()],
      'configured': true,
    });
    await refresh;
    expect(controller.find('call-one')!.status, 'ended');
    controller.dispose();
  });

  test('expired invitations do not ring', () {
    final row = callRow()
      ..['expires_at'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
    expect(VideoCall.fromJson(row).isIncoming('doctor'), false);
  });

  testWidgets('dedicated page renders on a narrow phone and starts only once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeCalls();
    final pending = Completer<Map<String, dynamic>>();
    repo.nextStart = pending;
    final controller = VideoCallController(repository: repo, userId: 'patient');
    VideoCall? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoCallsPage(
          controller: controller,
          onOpenCall: (call) async {
            opened = call;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appels vidéo'), findsOneWidget);
    expect(find.text('Dr Anne Pierre'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Appeler'));
    await tester.pump();
    await tester.tap(find.text('Appeler'));
    await tester.pump();
    expect(repo.actions.where((a) => a == 'start').length, 1);
    pending.complete({'call': callRow()});
    await tester.pumpAndSettle();
    expect(opened?.id, 'call-one');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('unconfigured service disables placing calls', (tester) async {
    final repo = FakeCalls()..configured = false;
    final controller = VideoCallController(repository: repo, userId: 'patient');
    await tester.pumpWidget(
      MaterialApp(
        home: VideoCallsPage(controller: controller, onOpenCall: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appels vidéo indisponibles'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'hanging up while ringing never requests camera or media tokens',
    (tester) async {
      final repo = FakeCalls()..rows = [callRow()];
      final controller = VideoCallController(
        repository: repo,
        userId: 'patient',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VideoRoomPage(
            controller: controller,
            initialCall: VideoCall.fromJson(callRow()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Raccrocher'));
      await tester.pumpAndSettle();
      expect(repo.actions, contains('end'));
      expect(repo.actions, isNot(contains('join')));
      expect(find.text('Fermer'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

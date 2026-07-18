import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/mental_health_page.dart';

void main() {
  Widget buildPage({
    Future<void> Function(Map<String, dynamic>)? onSaveEntry,
  }) => MaterialApp(
    home: MentalHealthPage(
      patientId: 'patient-test',
      patientProfile: const {
        'emergencyContact': {'name': 'Marie', 'phone': '+509 3700 0000'},
      },
      entryStream: Stream.value(const <MentalHealthEntry>[]),
      professionalStream: Stream.value(const <MentalHealthProfessional>[]),
      onSaveEntry: onSaveEntry ?? (_) async {},
    ),
  );

  testWidgets('affiche le parcours complet de soutien psychologique', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.text('Soutien psychologique'), findsOneWidget);
    expect(find.text('Comment vous sentez-vous ?'), findsOneWidget);
    expect(find.text('Respiration guidée'), findsOneWidget);
    expect(find.text('Ancrage 5-4-3-2-1'), findsOneWidget);
    expect(find.text('PSYCREPH'), findsOneWidget);
    expect(find.text('Votre journal commence ici'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enregistre un point bien-être privé', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      buildPage(onSaveEntry: (data) async => saved = data),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('mental-health-mood-low')));
    await tester.tap(find.byKey(const Key('mental-health-feeling-anxious')));
    await tester.enterText(
      find.byKey(const Key('mental-health-note-field')),
      'Journée difficile, mais je demande de l’aide.',
    );
    await tester.tap(find.byKey(const Key('mental-health-save-check-in')));
    await tester.pump();

    expect(saved?['mood'], 'low');
    expect(saved?['moodScore'], 2);
    expect(saved?['feelings'], contains('anxious'));
    expect(saved?['note'], 'Journée difficile, mais je demande de l’aide.');
    expect(
      find.text('Votre point bien-être a été enregistré.'),
      findsOneWidget,
    );
  });

  testWidgets('présente les aides immédiates et le contact de confiance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('mental-health-crisis-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Vous méritez une aide immédiate'), findsOneWidget);
    expect(find.text('Urgence médicale — CAN'), findsOneWidget);
    expect(find.text('Marie'), findsOneWidget);
    expect(find.text('Soutien psychosocial — PSYCREPH'), findsOneWidget);
  });

  testWidgets('ouvre les deux exercices guidés', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('mental-health-breathing-tool')));
    await tester.pumpAndSettle();
    expect(
      find.text('Inspirez 4 secondes, gardez 4 secondes, expirez 6 secondes.'),
      findsOneWidget,
    );
    expect(find.text('Commencer'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('mental-health-grounding-tool')),
    );
    await tester.tap(find.byKey(const Key('mental-health-grounding-tool')));
    await tester.pumpAndSettle();
    expect(find.text('choses que vous pouvez voir'), findsOneWidget);
    expect(find.text('chose que vous pouvez goûter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

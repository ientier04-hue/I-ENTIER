import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/blood_donation_page.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final now = DateTime(2026, 7, 29, 10);
  final requests = [
    BloodRequest(
      id: 'request-o-negative',
      personName: 'Nadia Pierre',
      personAge: 32,
      bloodGroup: 'O-',
      unitsNeeded: 2,
      facilityName: 'Hôpital Saint-Louis',
      commune: 'Port-au-Prince',
      department: 'Ouest',
      reason: 'Intervention chirurgicale programmée',
      contactName: 'Marc Pierre',
      contactPhone: '+509 3700 0000',
      neededBy: DateTime(2026, 7, 30),
      expiresAt: DateTime(2026, 8, 1),
      urgency: BloodRequestUrgency.critical,
    ),
    BloodRequest(
      id: 'request-a-positive',
      personName: 'Samuel Jean',
      personAge: 48,
      bloodGroup: 'A+',
      facilityName: 'Centre hospitalier',
      commune: 'Delmas',
      contactName: 'Anne Jean',
      contactPhone: '+509 3800 0000',
      neededBy: DateTime(2026, 8, 2),
      expiresAt: DateTime(2026, 8, 3),
    ),
    BloodRequest(
      id: 'request-expired',
      personName: 'Demande expirée',
      bloodGroup: 'B+',
      facilityName: 'Centre hospitalier',
      commune: 'Delmas',
      contactName: 'Contact',
      contactPhone: '+509 3900 0000',
      neededBy: DateTime(2026, 7, 27),
      expiresAt: DateTime(2026, 7, 28),
    ),
  ];

  Widget buildPage({
    Stream<List<BloodRequest>>? stream,
    BloodUriLauncher? launcher,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: BloodDonationPage(
      now: now,
      requestStream: stream ?? Stream.value(requests),
      uriLauncher: launcher ?? (uri) async => true,
    ),
  );

  testWidgets('ouvre un espace interne avec six sections en haut', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.text('Don de sang'), findsOneWidget);
    expect(find.text('Besoins actuels'), findsOneWidget);
    expect(find.text('Comment donner'), findsOneWidget);
    expect(find.text('Puis-je donner ?'), findsOneWidget);
    expect(find.text('Compatibilité'), findsOneWidget);
    expect(find.text('Où donner'), findsOneWidget);
    expect(find.text('Questions'), findsOneWidget);
    expect(find.text('Nadia Pierre'), findsOneWidget);
    expect(find.text('Demande expirée'), findsNothing);
  });

  testWidgets('la carte de l’accueil ouvre la page interne', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const user = User(
      id: 'blood-page-patient',
      appMetadata: {},
      userMetadata: {'full_name': 'Patient Test'},
      aud: 'authenticated',
      email: 'patient@example.com',
      createdAt: '2026-07-29T00:00:00.000Z',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          user: user,
          account: const {'displayName': 'Patient Test'},
          patientProfile: const {'profileComplete': true},
          notificationStream: Stream.value(const <AppNotification>[]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Don de sang'));
    await tester.pumpAndSettle();

    expect(find.byType(BloodDonationPage), findsOneWidget);
    expect(find.text('Demandes de sang actuelles'), findsOneWidget);
  });

  testWidgets('filtre les demandes actuelles par groupe sanguin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.tap(find.byKey(const Key('blood-filter-O-')));
    await tester.pump();

    expect(find.text('Nadia Pierre'), findsOneWidget);
    expect(find.text('Samuel Jean'), findsNothing);
    expect(find.text('2 demandes'), findsOneWidget);
  });

  testWidgets('ouvre les coordonnées d’une demande vérifiée et lance l’appel', (
    tester,
  ) async {
    Uri? launchedUri;
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildPage(
        launcher: (uri) async {
          launchedUri = uri;
          return true;
        },
      ),
    );
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('blood-request-request-o-negative')),
        matching: find.text('Je peux aider'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmer avant de partir'), findsOneWidget);
    expect(find.text('Marc Pierre'), findsOneWidget);
    expect(find.text('+509 3700 0000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('blood-request-call')));
    await tester.pumpAndSettle();
    expect(launchedUri, Uri(scheme: 'tel', path: '+509 3700 0000'));
  });

  testWidgets('affiche un véritable état vide sans créer de fausse demande', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(stream: Stream.value(const <BloodRequest>[])),
    );
    await tester.pump();

    expect(find.byKey(const Key('blood-requests-empty')), findsOneWidget);
    expect(find.text('Aucune demande vérifiée pour le moment'), findsOneWidget);
  });

  testWidgets('navigue vers le guide et ouvre le lien Croix-Rouge', (
    tester,
  ) async {
    Uri? launchedUri;
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildPage(
        launcher: (uri) async {
          launchedUri = uri;
          return true;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('blood-section-process')));
    await tester.pumpAndSettle();

    expect(find.text('Comment se passe un don de sang ?'), findsOneWidget);
    expect(find.text('Croix-Rouge Haïtienne'), findsOneWidget);
    await tester.tap(find.text('Voir les informations'));
    await tester.pump();

    expect(launchedUri, Uri.parse('https://www.croixrouge.ht/2-check-up/'));
  });

  testWidgets('reste navigable sur un petit écran', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());
    await tester.pump();

    for (final key in const [
      'blood-section-process',
      'blood-section-eligibility',
      'blood-section-compatibility',
      'blood-section-centers',
      'blood-section-questions',
      'blood-section-requests',
    ]) {
      final target = find.byKey(Key(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: key);
    }
  });
}

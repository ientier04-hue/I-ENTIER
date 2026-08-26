import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/blood_donation_page.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBloodDonationRepository implements BloodDonationRepository {
  BloodDonationRequestDraft? lastRequest;

  @override
  Future<String> publishRequest(BloodDonationRequestDraft request) async {
    lastRequest = request;
    return 'blood-request-new';
  }
}

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
    BloodDonationRepository? repository,
  }) => MaterialApp(
    theme: AppTheme.light,
    home: BloodDonationPage(
      patientId: 'patient-1',
      patientName: 'Marie Jean',
      now: now,
      requestStream: stream ?? Stream.value(requests),
      repository: repository,
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
        matching: find.text('Je veux donner'),
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
    expect(find.text('Aucune demande pour le moment'), findsOneWidget);
  });

  testWidgets('navigue vers le guide et ouvre la source OMS', (tester) async {
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
    expect(find.text('Organisation mondiale de la Santé'), findsOneWidget);
    await tester.tap(find.text('Consulter la source'));
    await tester.pump();

    expect(
      launchedUri,
      Uri.parse(
        'https://www.who.int/news-room/questions-and-answers/item/'
        'blood-products-why-should-i-donate-blood',
      ),
    );
  });

  testWidgets('publie une demande avec tous les champs demandés', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeBloodDonationRepository();
    await tester.pumpWidget(buildPage(repository: repository));
    await tester.pump();

    await tester.tap(find.byKey(const Key('blood-publish-request')));
    await tester.pumpAndSettle();

    expect(find.text('Publier une demande'), findsOneWidget);
    expect(find.text('Marie Jean'), findsOneWidget);

    await tester.tap(find.byKey(const Key('blood-request-blood-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('O-').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('blood-request-donor-count')),
      '3',
    );
    await tester.enterText(
      find.byKey(const Key('blood-request-facility')),
      'Hôpital Saint-Louis',
    );
    await tester.tap(find.byKey(const Key('blood-request-urgency')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Très urgent').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('blood-request-contact-phone')),
      '+509 3700 0000',
    );

    final submit = find.byKey(const Key('blood-request-submit'));
    final formScroll = find
        .descendant(
          of: find.byKey(const Key('blood-request-form-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(submit, 300, scrollable: formScroll);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.lastRequest, isNotNull);
    expect(repository.lastRequest!.personName, 'Marie Jean');
    expect(repository.lastRequest!.bloodGroup, 'O-');
    expect(repository.lastRequest!.donorCount, 3);
    expect(repository.lastRequest!.facilityName, 'Hôpital Saint-Louis');
    expect(repository.lastRequest!.neededBy, DateTime(2026, 7, 30));
    expect(repository.lastRequest!.urgency, BloodRequestUrgency.critical);
    expect(repository.lastRequest!.contactPhone, '+509 3700 0000');
    expect(find.text('Votre demande de sang est publiée.'), findsOneWidget);
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:i_entier/onboarding_page.dart';

class _FakeUser implements User {
  @override
  String get uid => 'test-patient';

  @override
  String? get displayName => 'Patient Test';

  @override
  String? get email => 'patient@example.com';

  @override
  String? get photoURL => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('présente les quatre étapes avant la connexion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onFinished: () => finished = true)),
    );

    expect(find.text('Votre santé.\nEnfin réunie.'), findsOneWidget);
    expect(find.text('Passer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Les bons soins,\nau bon moment.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Un suivi qui vous\nressemble vraiment.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Vous gardez le\ncontrôle.'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    final skipGuard = find.byKey(const ValueKey('skip-onboarding-guard'));
    expect(tester.widget<IgnorePointer>(skipGuard).ignoring, isTrue);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('affiche le portail de connexion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Bienvenue sur I-ENTIER'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
  });

  testWidgets('regroupe le profil en catégories et propose la déconnexion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PatientProfileScreen(
          user: _FakeUser(),
          accountProfile: const {'displayName': 'Patient Test'},
          initialProfile: const {
            'sex': 'Femme',
            'birthDate': '1990-02-10',
            'phone': '509 3700 0000',
            'emergencyContact': {
              'name': 'Contact Test',
              'relationship': 'Parent',
              'phone': '509 3800 0000',
            },
          },
        ),
      ),
    );

    expect(find.text('Identité'), findsOneWidget);
    expect(find.text('Coordonnées et mesures'), findsOneWidget);
    expect(find.text('Contact d’urgence'), findsOneWidget);
    expect(find.text('Dossier médical'), findsOneWidget);
    expect(find.text('Suivi et couverture'), findsOneWidget);
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche le header Material 3 compact sur mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          user: _FakeUser(),
          account: const {'name': 'Patient Test'},
          patientProfile: const {},
          notificationStream: Stream.value(defaultAppNotifications()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
    expect(find.text('I-ENTIER'), findsOneWidget);
    expect(find.text('Votre espace santé'), findsOneWidget);
    expect(find.text('LL'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.text('Rechercher un service, un professionnel...'),
      findsOneWidget,
    );
    expect(find.byTooltip('Filtrer'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-header')),
        matching: find.textContaining('Bonjour'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Annuaire'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-header')), findsNothing);

    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
  });

  testWidgets(
    'fusionne personnel et institutions dans un annuaire avec sélecteur',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            user: _FakeUser(),
            account: const {'name': 'Patient Test'},
            patientProfile: const {},
            notificationStream: Stream.value(defaultAppNotifications()),
          ),
        ),
      );

      await tester.tap(find.text('Annuaire'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('directory-type-switch')),
        findsOneWidget,
      );
      expect(find.text('Personnel médical'), findsOneWidget);
      expect(find.text('Institution'), findsNothing);
      expect(find.text('Institutions'), findsOneWidget);

      await tester.tap(find.text('Institutions'));
      await tester.pumpAndSettle();

      expect(find.text('Personnel médical'), findsNothing);
      expect(
        find.text('Des soins de qualité, partout où vous êtes.'),
        findsOneWidget,
      );
      expect(find.text('Annuaire'), findsOneWidget);
    },
  );

  testWidgets('la croix ferme toute la feuille AI avec le clavier ouvert', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          user: _FakeUser(),
          account: const {'name': 'Patient Test'},
          patientProfile: const {},
          notificationStream: Stream.value(defaultAppNotifications()),
        ),
      ),
    );

    final prompt = find.text('Écrivez votre message...');
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final composer = find.widgetWithText(
      TextField,
      'Demandez quelque chose...',
    );
    expect(composer, findsOneWidget);
    await tester.showKeyboard(composer);
    await tester.pump();

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Fermer'), findsNothing);
    expect(prompt, findsOneWidget);
  });

  testWidgets('la poignée ferme toute la feuille AI en glissant vers le bas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          user: _FakeUser(),
          account: const {'name': 'Patient Test'},
          patientProfile: const {},
          notificationStream: Stream.value(defaultAppNotifications()),
        ),
      ),
    );

    final prompt = find.text('Écrivez votre message...');
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    final handle = find.byKey(const ValueKey('ai-sheet-drag-handle'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Fermer'), findsNothing);
    expect(prompt, findsOneWidget);
  });
}

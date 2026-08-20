import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:i_entier/onboarding_page.dart';
import 'package:i_entier/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User fakeUser() => const User(
  id: 'test-patient',
  appMetadata: {},
  userMetadata: {'full_name': 'Patient Test'},
  aud: 'authenticated',
  email: 'patient@example.com',
  createdAt: '2026-07-20T00:00:00.000Z',
);

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

  testWidgets(
    'rend les contrôles d’onboarding accessibles sans agrandir les points',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onFinished: () {})),
      );
      await tester.pump();

      for (var index = 0; index < 4; index++) {
        final target = find.byKey(ValueKey('onboarding-dot-$index'));
        final targetSize = tester.getSize(target);
        expect(targetSize.width, greaterThanOrEqualTo(48));
        expect(targetSize.height, greaterThanOrEqualTo(48));
        expect(tester.getSemantics(target).label, 'Étape ${index + 1} sur 4');

        final visual = find.descendant(
          of: target,
          matching: find.byType(AnimatedContainer),
        );
        expect(visual, findsOneWidget);
        expect(tester.getSize(visual).height, 8);
      }

      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('onboarding-next')))
            .label,
        'Continuer vers l’étape 2 sur 4',
      );
      semantics.dispose();
    },
  );

  testWidgets('réduit les animations de l’onboarding sur demande', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OnboardingScreen(onFinished: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 9));
    expect(tester.binding.transientCallbackCount, 0);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pump();
    expect(find.text('Les bons soins,\nau bon moment.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-dot-3')));
    await tester.pump();
    expect(find.text('Vous gardez le\ncontrôle.'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('onboarding-next'))).label,
      'Se connecter',
    );
    semantics.dispose();
  });

  testWidgets('affiche le portail de connexion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Bienvenue sur I-ENTIER'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer en mode invité'), findsOneWidget);
    expect(find.byKey(const ValueKey('anonymous-sign-in')), findsOneWidget);
  });

  testWidgets('démarre une connexion anonyme depuis le portail', (
    tester,
  ) async {
    var anonymousSignInCalls = 0;
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          anonymousSignIn: () {
            anonymousSignInCalls++;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('anonymous-sign-in')));
    await tester.pump();

    expect(anonymousSignInCalls, 1);
    expect(find.text('Connexion invitée en cours...'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Continuer en mode invité'), findsOneWidget);
  });

  testWidgets('explique quand le mode anonyme est désactivé côté Supabase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          anonymousSignIn: () => throw const AuthException(
            'Anonymous sign-ins are disabled',
            statusCode: '422',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('anonymous-sign-in')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Le mode invité n’est pas encore activé sur ce projet Supabase.',
      ),
      findsOneWidget,
    );
  });

  test('identifie le fournisseur d’un compte anonyme', () {
    const anonymousUser = User(
      id: 'anonymous-patient',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-08-20T00:00:00.000Z',
      isAnonymous: true,
    );

    expect(anonymousUser.authProvider, 'anonymous');
  });

  testWidgets('regroupe le profil en catégories et propose la déconnexion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PatientProfileScreen(
          user: fakeUser(),
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
          user: fakeUser(),
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
    expect(find.text('PT'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.text('Institution, personnel, malaise, médicament, examen...'),
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
            user: fakeUser(),
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
          user: fakeUser(),
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
          user: fakeUser(),
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

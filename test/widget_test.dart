import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';

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
  testWidgets('affiche le portail de connexion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Bienvenue sur I-ENTIER'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
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

    await tester.tap(find.text('Personnel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-header')), findsNothing);

    await tester.tap(find.text('Accueil'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
  });

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

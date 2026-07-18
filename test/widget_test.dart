import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:i_entier/main.dart';

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
}

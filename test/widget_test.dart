import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:i_entier/main.dart';

void main() {
  testWidgets('affiche le portail de connexion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Bienvenue sur I-ENTIER'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
  });
}

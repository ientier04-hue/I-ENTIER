import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/pharmacy_page.dart';

void main() {
  Widget buildPage() => MaterialApp(
    home: PharmacyPage(
      institutionStream:
          const Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
    ),
  );

  testWidgets('recherche un médicament dans le catalogue', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    expect(find.text('Pharmacie'), findsOneWidget);
    expect(find.text('Scanner une ordonnance'), findsOneWidget);
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('pharmacy-search-field')),
      'vitamine',
    );
    await tester.pump();

    expect(find.text('Vitamine C 1000 mg'), findsOneWidget);
    expect(find.text('Paracétamol 500 mg'), findsNothing);
    expect(find.text('1 produit'), findsOneWidget);
  });

  testWidgets('ouvre les choix pour scanner une ordonnance', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.text('Scanner une ordonnance'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ajouter une ordonnance'), findsOneWidget);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);
  });
}

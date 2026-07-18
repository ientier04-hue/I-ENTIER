import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/pharmacy_page.dart';

void main() {
  Widget buildPage() => MaterialApp(
    home: PharmacyPage(
      patientId: 'patient-test',
      institutionStream:
          const Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
      prescriptionStream:
          const Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
    ),
  );

  testWidgets('recherche un médicament dans le catalogue', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    expect(find.text('Pharmacie'), findsWidgets);
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

  testWidgets('navigue entre les trois sections de pharmacie', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('pharmacy-section-pharmacies')));
    await tester.pump();
    expect(find.text('Une pharmacie près de vous'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pharmacy-section-prescriptions')));
    await tester.pump();
    expect(find.text('Mes ordonnances'), findsOneWidget);
    expect(find.byKey(const Key('prescription-scan-button')), findsOneWidget);
  });

  testWidgets('les trois sections restent utilisables sur mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    for (final key in const [
      'pharmacy-section-medications',
      'pharmacy-section-pharmacies',
      'pharmacy-section-prescriptions',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}

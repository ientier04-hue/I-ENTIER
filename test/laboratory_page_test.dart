import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/laboratory_page.dart';

void main() {
  const laboratories = [
    Laboratory(
      id: 'bio-plus',
      name: 'Laboratoire Bio Plus',
      description: 'Laboratoire de proximité',
      services: 'Hématologie, glycémie, bilan sanguin',
      address: 'Pétion-Ville',
      schedule: 'Lun - Sam · 7h00 - 17h00',
      phone: '+509 2812 0000',
      available: true,
      homeSampling: true,
      onlineResults: true,
      accredited: true,
    ),
    Laboratory(
      id: 'central',
      name: 'Laboratoire Central',
      services: 'PCR et dépistage',
      address: 'Delmas',
      available: false,
    ),
  ];

  final results = [
    LaboratoryResult(
      id: 'result-nfs',
      examName: 'Numération formule sanguine',
      laboratoryName: 'Laboratoire Bio Plus',
      status: 'available',
      summary: 'Compte rendu complet disponible',
      referenceRange: 'Voir le document du laboratoire',
      collectedAt: DateTime(2026, 7, 17),
      publishedAt: DateTime(2026, 7, 18),
    ),
    LaboratoryResult(
      id: 'result-tsh',
      examName: 'TSH',
      laboratoryName: 'Laboratoire Central',
      status: 'pending',
      collectedAt: DateTime(2026, 7, 20),
    ),
  ];

  Widget buildPage() => MaterialApp(
    home: LaboratoryPage(laboratories: laboratories, results: results),
  );

  testWidgets('regroupe les fonctionnalités dans trois menus en haut', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    expect(find.text('Laboratoires'), findsOneWidget);
    expect(find.text('Examens'), findsOneWidget);
    expect(find.text('Résultats'), findsOneWidget);
    expect(
      find.byKey(const Key('laboratory-section-laboratories')),
      findsOneWidget,
    );
  });

  testWidgets('affiche les laboratoires et recherche dans leurs services', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    expect(find.text('Laboratoires disponibles'), findsOneWidget);
    expect(find.text('Laboratoire Bio Plus'), findsOneWidget);
    expect(find.text('Laboratoire Central'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('laboratory-search-field')),
      'glycémie',
    );
    await tester.pump();

    expect(find.text('Laboratoire Bio Plus'), findsOneWidget);
    expect(find.text('Laboratoire Central'), findsNothing);
    expect(find.text('1 résultat'), findsOneWidget);
  });

  testWidgets('filtre les laboratoires ouverts et à domicile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('laboratory-filter-open')));
    await tester.pump();
    expect(find.text('Laboratoire Bio Plus'), findsOneWidget);
    expect(find.text('Laboratoire Central'), findsNothing);

    await tester.tap(find.byKey(const Key('laboratory-filter-home')));
    await tester.pump();
    expect(find.text('Laboratoire Bio Plus'), findsOneWidget);
    expect(find.text('1 résultat'), findsOneWidget);
  });

  testWidgets('ouvre la fiche détaillée d’un laboratoire', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('laboratory-card-bio-plus')));
    await tester.pumpAndSettle();

    expect(find.text('Détails du laboratoire'), findsOneWidget);
    expect(find.text('Analyses et examens'), findsOneWidget);
    expect(find.text('Prélèvement à domicile disponible'), findsOneWidget);
    expect(find.text('Copier le numéro du laboratoire'), findsOneWidget);
  });

  testWidgets('navigue et recherche dans le catalogue des examens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('laboratory-section-examinations')));
    await tester.pump();

    expect(find.text('Comprendre vos examens'), findsOneWidget);
    expect(find.text('Numération formule sanguine'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('examination-search-field')),
      'glycémie',
    );
    await tester.pump();

    expect(find.text('Glycémie'), findsOneWidget);
    expect(find.text('Numération formule sanguine'), findsNothing);
  });

  testWidgets('affiche les résultats privés du patient et leur détail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    await tester.tap(find.byKey(const Key('laboratory-section-results')));
    await tester.pump();

    expect(find.text('Mes résultats'), findsOneWidget);
    expect(find.text('Visible uniquement par vous'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('laboratory-result-result-tsh')),
        matching: find.text('En attente'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('laboratory-result-result-nfs')));
    await tester.pumpAndSettle();

    expect(find.text('Compte rendu'), findsOneWidget);
    expect(find.text('Compte rendu complet disponible'), findsOneWidget);
    expect(find.text('18 juil. 2026'), findsOneWidget);
  });

  testWidgets('la page reste utilisable sur mobile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    for (final key in const [
      'laboratory-section-examinations',
      'laboratory-section-results',
      'laboratory-section-laboratories',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: key);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('laboratory-card-central')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}

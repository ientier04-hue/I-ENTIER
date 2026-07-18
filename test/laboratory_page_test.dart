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

  Widget buildPage() =>
      const MaterialApp(home: LaboratoryPage(laboratories: laboratories));

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

  testWidgets('la page reste utilisable sur mobile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildPage());

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('laboratory-card-central')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}

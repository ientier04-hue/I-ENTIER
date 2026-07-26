import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/main.dart';

void main() {
  Future<void> pumpProfile(
    WidgetTester tester,
    DirectoryProfilePreviewType type, {
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: buildDirectoryProfilePreview(type),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('présente le personnel comme un profil social lisible', (
    tester,
  ) async {
    await pumpProfile(tester, DirectoryProfilePreviewType.professional);

    expect(
      find.byKey(const ValueKey('directory-profile-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('directory-profile-submenu')),
      findsOneWidget,
    );
    expect(find.text('Dr Nadège Pierre'), findsOneWidget);
    expect(find.text('12 ans'), findsOneWidget);
    expect(find.text('Prendre rendez-vous'), findsOneWidget);
    expect(find.text('Appeler'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Itinéraire'), findsOneWidget);
    expect(find.text('Informations professionnelles'), findsNothing);

    final informationTab = find.byKey(
      const ValueKey('directory-profile-tab-information'),
    );
    await tester.ensureVisible(informationTab);
    await tester.pumpAndSettle();
    await tester.tap(informationTab);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('directory-profile-hero')), findsNothing);
    expect(find.text('Informations professionnelles'), findsOneWidget);
    expect(find.text('+509 3700 0000'), findsNothing);

    final contactTab = find.byKey(
      const ValueKey('directory-profile-tab-contact'),
    );
    await tester.ensureVisible(contactTab);
    await tester.pumpAndSettle();
    await tester.tap(contactTab);
    await tester.pumpAndSettle();

    expect(find.text('+509 3700 0000'), findsOneWidget);
    expect(find.text('Informations professionnelles'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('garde le profil institution utilisable sur écran étroit', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      DirectoryProfilePreviewType.institution,
      size: const Size(320, 740),
    );

    expect(find.text('Clinique Horizon Santé'), findsOneWidget);
    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('Prendre rendez-vous'), findsOneWidget);
    expect(find.text('Tarifs indicatifs'), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('directory-profile-hero')))
          .width,
      lessThanOrEqualTo(288),
    );
    expect(tester.takeException(), isNull);

    final pricesTab = find.byKey(
      const ValueKey('directory-profile-tab-prices'),
    );
    await tester.ensureVisible(pricesTab);
    await tester.pumpAndSettle();
    await tester.tap(pricesTab);
    await tester.pumpAndSettle();

    expect(find.text('Tarifs indicatifs'), findsOneWidget);
    expect(find.text('Localisation et contact'), findsNothing);

    final contactTab = find.byKey(
      const ValueKey('directory-profile-tab-contact'),
    );
    await tester.ensureVisible(contactTab);
    await tester.pumpAndSettle();
    await tester.tap(contactTab);
    await tester.pumpAndSettle();

    expect(find.text('Localisation et contact'), findsOneWidget);
    expect(find.text('Tarifs indicatifs'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

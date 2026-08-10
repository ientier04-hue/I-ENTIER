import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:i_entier/service_personalization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User themeTestUser() => const User(
  id: 'theme-test-patient',
  appMetadata: {},
  userMetadata: {'full_name': 'Patient Test'},
  aud: 'authenticated',
  email: 'patient@example.com',
  createdAt: '2026-07-20T00:00:00.000Z',
);

Widget _buildHome({
  TextScaler textScaler = TextScaler.noScaling,
  ServicePreferencesRepository? servicePreferencesRepository,
}) => MaterialApp(
  theme: AppTheme.light,
  scrollBehavior: const AppScrollBehavior(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: HomeScreen(
    user: themeTestUser(),
    account: const {'displayName': 'Patient Test'},
    patientProfile: const {},
    notificationStream: Stream.value(defaultAppNotifications()),
    servicePreferencesRepository: servicePreferencesRepository,
  ),
);

Future<void> _revealCatalogTarget(
  WidgetTester tester,
  Finder target, {
  bool towardStart = false,
}) async {
  final catalog = find.byKey(const ValueKey('services-catalog-scroll'));
  for (var attempt = 0; attempt < 20; attempt++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      if (rect.top >= 60 && rect.bottom <= 830) return;
    }
    await tester.drag(
      catalog,
      Offset(0, towardStart ? 260 : -260),
      warnIfMissed: false,
    );
    await tester.pump();
  }
  expect(target, findsWidgets);
}

void main() {
  test('le thème de production couvre les composants essentiels', () {
    final theme = AppTheme.light;

    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Arial'));
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    expect(theme.dialogTheme.shape, isA<RoundedRectangleBorder>());
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
  });

  testWidgets('la recherche universelle et le catalogue sont fonctionnels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    final homeCardSize = tester.getSize(
      find.byKey(const ValueKey('service-card-diagnostic-assiste')),
    );

    await tester.tap(find.byKey(const ValueKey('home-search-bar')));
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    expect(find.text('Tout'), findsOneWidget);
    expect(find.text('Institutions'), findsOneWidget);
    expect(find.text('Personnel médical'), findsOneWidget);
    expect(find.text('Malaises'), findsOneWidget);
    expect(find.text('Médicaments'), findsOneWidget);
    expect(find.text('Examens'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    await tester.enterText(searchField, 'prévention');
    await tester.pump();
    expect(find.text('Prévention'), findsOneWidget);
    expect(find.text('Pharmacie'), findsNothing);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();

    expect(find.text('Tous les services'), findsOneWidget);
    expect(find.text('14 services'), findsOneWidget);
    expect(find.text('Diagnostic assisté'), findsOneWidget);
    expect(find.text('Pharmacie'), findsOneWidget);
    expect(find.text('Mobilité Santé'), findsOneWidget);
    final catalogCard = find.byKey(
      const ValueKey('service-card-diagnostic-assiste'),
    );
    final catalogCardSize = tester.getSize(catalogCard);
    expect(
      catalogCardSize.height / catalogCardSize.width,
      closeTo(homeCardSize.height / homeCardSize.width, .01),
    );
    expect(catalogCardSize.height, lessThan(260));
    final catalogImage = tester.widget<Image>(
      find.descendant(of: catalogCard, matching: find.byType(Image)).first,
    );
    expect(catalogImage.image, isA<ResizeImage>());
    await _revealCatalogTarget(tester, find.text('Financement solidaire'));
    expect(find.text('Financement solidaire'), findsOneWidget);
    await _revealCatalogTarget(tester, find.text('Clinique Mobile'));
    expect(find.text('Clinique Mobile'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('service-card-clinique-mobile')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    await _revealCatalogTarget(tester, find.text('Maternité & Petite Enfance'));
    expect(find.text('Maternité & Petite Enfance'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('service-card-maman-bebe')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'filtre les médicaments puis ouvre la pharmacie sur le résultat choisi',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_buildHome());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('home-search-bar')));
      await tester.pumpAndSettle();

      final medicationFilter = find.byKey(
        const ValueKey('universal-search-filter-medications'),
      );
      await tester.ensureVisible(medicationFilter);
      await tester.tap(medicationFilter);
      await tester.pump();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'amoxicilline');
      await tester.pump();

      expect(find.text('Amoxicilline 500 mg'), findsOneWidget);
      expect(find.text('Paracétamol 500 mg'), findsNothing);

      final result = find.byKey(
        const ValueKey(
          'universal-search-result-medications-Amoxicilline 500 mg',
        ),
      );
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pumpAndSettle();

      expect(find.text('Pharmacie'), findsWidgets);
      expect(find.text('Amoxicilline 500 mg'), findsWidgets);
      final pharmacySearch = tester.widget<TextField>(
        find.byKey(const Key('pharmacy-search-field')),
      );
      expect(pharmacySearch.controller?.text, 'Amoxicilline 500 mg');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retrouve les malaises et les examens sans accents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-search-bar')));
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'vertiges');
    await tester.pump();
    expect(find.text('Vertiges et malaise'), findsOneWidget);

    await tester.enterText(searchField, 'glycemie');
    await tester.pump();
    expect(find.text('Glycémie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('épingle au plus trois services et permet de les réordonner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryServicePreferencesRepository();
    await tester.pumpWidget(
      _buildHome(servicePreferencesRepository: repository),
    );
    await tester.pump();

    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();
    expect(find.text('Mes services épinglés'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);

    Future<void> pin(String serviceId) async {
      final button = find.byKey(ValueKey('service-pin-$serviceId'));
      await _revealCatalogTarget(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await pin('diagnostic-assiste');
    await pin('pharmacie');
    await pin('don-de-sang');
    await pin('mobilite-sante');
    expect(
      find.text(
        'Vous pouvez épingler jusqu’à 3 services. Retirez-en un pour continuer.',
      ),
      findsOneWidget,
    );

    await _revealCatalogTarget(
      tester,
      find.text('Mes services épinglés'),
      towardStart: true,
    );
    expect(find.text('3/3'), findsOneWidget);

    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('pinned-service-diagnostic-assiste')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('pinned-service-don-de-sang')),
            )
            .dy,
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('pinned-drag-diagnostic-assiste')),
      const Offset(0, 130),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('pinned-service-diagnostic-assiste')),
          )
          .dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('pinned-service-pharmacie')))
            .dy,
      ),
    );
    final saved = await repository.load(themeTestUser().id);
    expect(saved.pinnedServiceIds, [
      'pharmacie',
      'diagnostic-assiste',
      'don-de-sang',
    ]);
  });

  testWidgets(
    'invite à compléter le profil sous la recherche sans bloquer l’accueil',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_buildHome());
      await tester.pump();

      final search = find.byKey(const ValueKey('home-search-bar'));
      final invitation = find.byKey(const ValueKey('profile-completion-card'));
      expect(invitation, findsOneWidget);
      expect(find.text('Complétez votre profil'), findsOneWidget);
      expect(
        find.text(
          'Quelques informations suffisent pour personnaliser votre expérience.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(invitation).dy,
        greaterThan(tester.getBottomLeft(search).dy),
      );

      await tester.tap(invitation);
      await tester.pumpAndSettle();
      expect(find.text('Profil patient'), findsOneWidget);
    },
  );

  testWidgets('la carte Mobilité Santé ouvre le transport accompagné', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();
    await _revealCatalogTarget(tester, find.text('Mobilité Santé'));
    await tester.tap(find.text('Mobilité Santé'));
    await tester.pumpAndSettle();

    expect(
      find.text('Danger immédiat ? N’attendez pas un conducteur.'),
      findsOneWidget,
    );
    expect(find.text('Devenir partenaire'), findsOneWidget);
  });

  testWidgets('Maternité & Petite Enfance reste un service autonome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();
    await _revealCatalogTarget(tester, find.text('Maternité & Petite Enfance'));
    await tester.tap(find.text('Maternité & Petite Enfance'));
    await tester.pumpAndSettle();

    expect(
      find.text('Votre parcours Maternité & Petite Enfance'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('maternal-create-pregnancy')), findsOneWidget);
  });

  testWidgets('masque l’invitation quand le profil est complet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          user: themeTestUser(),
          account: const {'displayName': 'Patient Test'},
          patientProfile: const {'profileComplete': true},
          notificationStream: Stream.value(defaultAppNotifications()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-completion-card')), findsNothing);
  });

  testWidgets('un onglet visité conserve ses filtres', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    await tester.tap(find.text('Annuaire'));
    await tester.pump();
    final nursesFinder = find.widgetWithText(ChoiceChip, 'Infirmiers');
    await tester.ensureVisible(nursesFinder);
    await tester.pump();
    await tester.tap(nursesFinder);
    await tester.pump();

    ChoiceChip nursesChip() => tester.widget<ChoiceChip>(nursesFinder);
    expect(nursesChip().selected, isTrue);
    final directoryState = tester.state(
      find.byKey(const ValueKey('personnel-directory')),
    );

    await tester.tap(find.text('Accueil'));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
    await tester.tap(find.text('Annuaire'));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-header')), findsNothing);

    expect(
      tester.state(find.byKey(const ValueKey('personnel-directory'))),
      same(directoryState),
    );
    expect(nursesChip().selected, isTrue);
  });

  testWidgets('la navigation devient latérale sur grand écran', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(HomeScreen))).width,
      1280,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('desktop-navigation')), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
  });

  testWidgets('l’accueil reste utilisable avec un texte agrandi à 200 %', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    await tester.pumpWidget(_buildHome(textScaler: const TextScaler.linear(2)));
    await tester.pump();

    expect(find.byKey(const ValueKey('home-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-search-bar')), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le header reste fixe et occupe toute la largeur', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    final header = find.byKey(const ValueKey('home-header'));
    final initialTop = tester.getTopLeft(header).dy;
    expect(tester.getTopLeft(header).dx, 0);
    expect(tester.getSize(header).width, 390);
    final decoration = tester.widget<Container>(header).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration! as BoxDecoration).borderRadius, isNull);

    await tester.drag(
      find.byKey(const PageStorageKey('home-tab-0')),
      const Offset(0, -500),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getTopLeft(header).dy, initialTop);
  });

  testWidgets('la barre d’onglets mobile a des proportions compactes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    final shell = find.byKey(const ValueKey('home-tab-bar-shell'));
    expect(tester.getSize(shell).height, 49);
    expect(tester.getSize(shell).width, lessThanOrEqualTo(366));
    final surface = find.byKey(const ValueKey('home-tab-bar-surface'));
    final surfaceDecoration = tester
        .widget<DecoratedBox>(
          find
              .descendant(of: surface, matching: find.byType(DecoratedBox))
              .first,
        )
        .decoration;
    expect(
      (surfaceDecoration as BoxDecoration).borderRadius,
      BorderRadius.circular(24.5),
    );
    final emergencyButton = find.byKey(
      const ValueKey('emergency-bottom-button'),
    );
    expect(emergencyButton, findsOneWidget);
    expect(tester.getSize(emergencyButton), const Size.square(49));
  });
}

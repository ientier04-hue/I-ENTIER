import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User themeTestUser() => const User(
  id: 'theme-test-patient',
  appMetadata: {},
  userMetadata: {'full_name': 'Patient Test'},
  aud: 'authenticated',
  email: 'patient@example.com',
  createdAt: '2026-07-20T00:00:00.000Z',
);

Widget _buildHome({TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
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
      ),
    );

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

  testWidgets('la recherche et le catalogue de services sont fonctionnels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_buildHome());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('home-search-bar')));
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'prévention');
    await tester.pump();
    expect(find.text('Prévention'), findsOneWidget);
    expect(find.text('Pharmacie'), findsNothing);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();

    expect(find.text('Tous les services'), findsOneWidget);
    expect(find.text('12 services'), findsOneWidget);
    expect(find.text('Diagnostic assisté'), findsOneWidget);
    expect(find.text('Pharmacie'), findsOneWidget);
    expect(find.text('Mobilité Santé'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Financement solidaire'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Financement solidaire'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Clinique Mobile'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Clinique Mobile'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/services/mobile_clinic_3d.png')),
      findsOneWidget,
    );
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
    await tester.tap(find.text('Mobilité Santé'));
    await tester.pumpAndSettle();

    expect(
      find.text('Danger immédiat ? N’attendez pas un conducteur.'),
      findsOneWidget,
    );
    expect(find.text('Devenir partenaire'), findsOneWidget);
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
    expect(tester.getSize(shell).height, 70);
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
      BorderRadius.circular(35),
    );
    expect(
      find.byKey(const ValueKey('emergency-bottom-button')),
      findsOneWidget,
    );
  });
}

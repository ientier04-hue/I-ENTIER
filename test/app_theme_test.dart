import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/main.dart';
import 'package:i_entier/notification_service.dart';

class _ThemeTestUser implements User {
  @override
  String get uid => 'theme-test-patient';

  @override
  String? get displayName => 'Patient Test';

  @override
  String? get email => 'patient@example.com';

  @override
  String? get photoURL => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildHome({TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: HomeScreen(
        user: _ThemeTestUser(),
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
    expect(find.text('6 services'), findsOneWidget);
    expect(find.text('Pharmacie'), findsOneWidget);
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

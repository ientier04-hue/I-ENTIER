import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/community_transport_page.dart';

class _FakeTransportRepository implements CommunityTransportRepository {
  CommunityTransportRequestDraft? lastRequest;
  CommunityTransportPartnerApplication? lastApplication;

  @override
  Future<String> createRequest(CommunityTransportRequestDraft request) async {
    lastRequest = request;
    return 'transport-request-12345678';
  }

  @override
  Future<String> applyAsPartner(
    CommunityTransportPartnerApplication application,
  ) async {
    lastApplication = application;
    return 'partner-application-12345678';
  }
}

Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void main() {
  testWidgets('distingue le transport communautaire de l’urgence vitale', (
    tester,
  ) async {
    Uri? launchedUri;
    await tester.pumpWidget(
      _app(
        CommunityTransportPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: _FakeTransportRepository(),
          uriLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mobilité Santé'), findsOneWidget);
    expect(
      find.text('Danger immédiat ? N’attendez pas un conducteur.'),
      findsOneWidget,
    );
    expect(find.text('Appeler le CAN au 116'), findsOneWidget);
    expect(find.text('Demander un transport'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transport-call-116')));
    await tester.pump();
    expect(launchedUri, Uri(scheme: 'tel', path: '116'));
  });

  testWidgets('présente la candidature ouverte avec vérification obligatoire', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CommunityTransportPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: _FakeTransportRepository(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('transport-tab-partner')));
    await tester.pumpAndSettle();

    expect(
      find.text('Votre véhicule peut rapprocher un malade des soins'),
      findsOneWidget,
    );
    expect(find.text('Accompagnateur santé obligatoire'), findsOneWidget);
    expect(find.text('Validation avant activation'), findsOneWidget);
    expect(find.text('Déposer ma candidature'), findsOneWidget);
  });

  testWidgets('reste lisible sur petit écran avec texte agrandi', (
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CommunityTransportPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: _FakeTransportRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mobilité Santé'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transport-emergency-boundary')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('enregistre une demande avec repère et accompagnateur imposé', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(430, 932)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final repository = _FakeTransportRepository();
    await tester.pumpWidget(
      _app(
        CommunityTransportRequestFormPage(
          patientId: 'patient-1',
          patientName: 'Marie Jean',
          repository: repository,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('transport-contact-phone')),
      '+509 3700 0000',
    );

    final department = find.byKey(
      const ValueKey('transport-pickup-department'),
    );
    final formScroll = find
        .descendant(
          of: find.byKey(const ValueKey('transport-request-form-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(department, 500, scrollable: formScroll);
    await tester.tap(department);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ouest').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('transport-pickup-commune')),
      'Pétion-Ville',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-pickup-landmark')),
      'Après l’église, maison bleue près du marché',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-destination-name')),
      'Hôpital de Fermathe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transport-destination-commune')),
      'Kenscoff',
    );

    final boundary = find.byKey(const ValueKey('transport-medical-boundary'));
    await tester.ensureVisible(boundary);
    await tester.tap(boundary);
    await tester.pump();

    final submit = find.byKey(const ValueKey('transport-submit-request'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Recherche du duo lancée'), findsOneWidget);
    expect(repository.lastRequest, isNotNull);
    expect(repository.lastRequest!.pickupDepartment, 'Ouest');
    expect(repository.lastRequest!.pickupCommune, 'Pétion-Ville');
    expect(repository.lastRequest!.pickupLandmark, contains('maison bleue'));
    expect(repository.lastRequest!.destinationName, 'Hôpital de Fermathe');
    expect(repository.lastRequest!.departureNow, isTrue);
  });
}

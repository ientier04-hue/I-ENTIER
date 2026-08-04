import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:i_entier/app_theme.dart';
import 'package:i_entier/rescue_page.dart';

void main() {
  testWidgets('présente le réseau et ouvre l’inscription des volontaires', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRescueRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('I-Entier Rescue'), findsOneWidget);
    expect(find.text('Réseau National de Volontaires'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('rescue-tab-overview')), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/services/i_entier_rescue_3d.png')),
      findsNWidgets(2),
    );
    expect(find.text('Devenir volontaire'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Push, SMS et e-mail'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rescue-primary-action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rescue-registration-form')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rescue-full-name')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('rescue-registration-form')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('rescue-identity-document')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rescue-license-document')),
      findsOneWidget,
    );
  });

  testWidgets('un volontaire vérifié accepte puis fait progresser sa mission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRescueRepository(
      profile: _profile(RescueVerificationStatus.verified),
      missions: [
        RescueMission(
          assignmentId: 'assignment-1',
          title: 'Renfort médical immédiat',
          eventType: 'earthquake',
          severity: 'critical',
          zone: 'Delmas 33',
          instructions: 'Rejoindre le poste de triage.',
          status: RescueMissionStatus.sent,
          createdAt: DateTime(2026, 8, 3),
        ),
      ],
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missions').last);
    await tester.pumpAndSettle();

    expect(find.text('Renfort médical immédiat'), findsOneWidget);
    expect(find.text('Accepter'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accepter'));
    await tester.pump();

    expect(repository.statusUpdates, [
      ('assignment-1', RescueMissionStatus.accepted),
    ]);
  });

  testWidgets('bloque les missions tant que le dossier est en attente', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRescueRepository(
      profile: _profile(RescueVerificationStatus.pending),
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missions').last);
    await tester.pumpAndSettle();

    expect(find.text('Vérification requise'), findsOneWidget);
    expect(find.textContaining('validation de votre identité'), findsOneWidget);
  });

  testWidgets('charge la carte opérationnelle et ses filtres professionnels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRescueRepository(
      profile: _profile(RescueVerificationStatus.verified),
      mapPoints: const [
        RescueMapPoint(
          id: 'site-1',
          type: 'partner_hospital',
          label: 'Hôpital partenaire',
          latitude: 18.54,
          longitude: -72.31,
          detail: 'Ouvert',
        ),
      ],
    );

    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carte').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rescue-operational-map')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('rescue-map-profession-filter')),
      findsOneWidget,
    );
    expect(find.byTooltip('Hôpital partenaire\nOuvert'), findsOneWidget);
  });
}

Widget _app(_FakeRescueRepository repository) => MaterialApp(
  theme: AppTheme.light,
  home: RescuePage(
    userId: 'user-1',
    userDisplayName: 'Marie Jean',
    repository: repository,
  ),
);

RescueVolunteerProfile _profile(RescueVerificationStatus status) =>
    RescueVolunteerProfile(
      id: 'volunteer-1',
      fullName: 'Marie Jean',
      phone: '+509 3700 0000',
      profession: RescueVolunteerProfession.nurse,
      specialty: 'Urgences',
      organization: 'Hôpital communautaire',
      skills: const ['Triage', 'Premiers soins'],
      verificationStatus: status,
      availability: RescueAvailability.available,
      interventionRadiusKm: 30,
      locationConsent: false,
    );

class _FakeRescueRepository implements RescueRepository {
  final RescueVolunteerProfile? profile;
  final List<RescueMission> missions;
  final List<RescueMapPoint> mapPoints;
  final List<(String, RescueMissionStatus)> statusUpdates = [];
  RescueVolunteerApplication? application;

  _FakeRescueRepository({
    this.profile,
    this.missions = const [],
    this.mapPoints = const [],
  });

  @override
  Stream<RescueVolunteerProfile?> watchProfile(String userId) =>
      Stream.value(profile);

  @override
  Stream<List<RescueMission>> watchMissions(String userId) =>
      Stream.value(missions);

  @override
  Future<void> submitApplication(RescueVolunteerApplication application) async {
    this.application = application;
  }

  @override
  Future<void> setAvailability(
    String volunteerId,
    RescueAvailability status,
  ) async {}

  @override
  Future<void> setLocationConsent(String volunteerId, bool consent) async {}

  @override
  Future<void> updateLocation(String volunteerId, Position position) async {}

  @override
  Future<void> updateMissionStatus(
    String assignmentId,
    RescueMissionStatus status,
  ) async {
    statusUpdates.add((assignmentId, status));
  }

  @override
  Future<List<RescueMapPoint>> loadMapPoints({
    RescueVolunteerProfession? profession,
    String specialty = '',
  }) async => mapPoints;
}

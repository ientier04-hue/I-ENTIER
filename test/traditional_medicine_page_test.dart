import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/traditional_medicine_page.dart';

class _FakeRepository implements TraditionalMedicineRepository {
  final practitioner = const TraditionalPractitioner(
    id: 'traditional-1',
    name: 'Man Rose Pierre',
    description: 'Accompagnement préventif et bien-être.',
    phone: '+509 0000 0000',
    address: 'Delmas',
    schedule: 'Lundi au vendredi',
    experienceYears: 18,
    practiceDomains: ['Plantes traditionnelles', 'Bien-être'],
    languages: ['Créole haïtien', 'Français'],
    interventionZones: ['Delmas', 'Pétion-Ville'],
    trustScore: 88,
    onlineAvailable: true,
  );

  bool? sharingEnabled;
  String? bookedPractitioner;
  String? journalTitle;
  String? acceptedOrientation;

  @override
  Stream<List<TraditionalPractitioner>> watchPractitioners() =>
      Stream.value([practitioner]);

  @override
  Stream<List<NaturalHealthJournalEntry>> watchJournal(String patientId) =>
      Stream.value(const []);

  @override
  Stream<List<NaturalHealthSharingGrant>> watchSharingGrants(
    String patientId,
  ) => Stream.value(const []);

  @override
  Stream<List<TraditionalPreventionContent>> watchPreventionContent(
    String regionCode,
  ) => Stream.value(const [
    TraditionalPreventionContent(
      id: 'content-1',
      title: 'Hygiène des mains',
      summary: 'Utilisez de l’eau propre et du savon.',
      category: 'hygiene',
      priority: 80,
    ),
  ]);

  @override
  Stream<List<TraditionalPatientRecommendation>> watchRecommendations(
    String patientId,
  ) => Stream.value([
    TraditionalPatientRecommendation(
      id: 'recommendation-1',
      type: 'prevention',
      title: 'Hydratation quotidienne',
      content: 'Boire régulièrement de l’eau potable.',
      reminderAt: null,
      createdAt: DateTime(2026, 8, 7),
    ),
  ]);

  @override
  Stream<List<TraditionalCareOrientation>> watchOrientations(
    String patientId,
  ) => Stream.value([
    TraditionalCareOrientation(
      id: 'orientation-1',
      targetType: 'doctor',
      targetName: 'Dr Jean Louis',
      reason: 'Évaluation médicale complémentaire.',
      urgency: 'priority',
      status: 'proposed',
      createdAt: DateTime(2026, 8, 7),
    ),
  ]);

  @override
  Future<void> addJournalEntry(
    String patientId,
    NaturalJournalEntryType type,
    String title,
    String details,
    String productName,
    int? wellnessRating,
  ) async => journalTitle = title;

  @override
  Future<void> bookConsultation({
    required String patientId,
    required String patientName,
    required TraditionalPractitioner practitioner,
    required bool video,
    required DateTime scheduledAt,
    required String note,
  }) async => bookedPractitioner = practitioner.id;

  @override
  Future<void> setJournalSharing({
    required String patientId,
    required String practitionerId,
    required bool enabled,
  }) async => sharingEnabled = enabled;

  @override
  Future<void> reportPractitioner({
    required String reporterId,
    required String practitionerId,
    required String category,
    required String details,
  }) async {}

  @override
  Future<void> acceptOrientation(
    String orientationId, {
    bool booked = false,
  }) async => acceptedOrientation = orientationId;
}

void main() {
  testWidgets('affiche uniquement un praticien vérifié et ses garanties', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: TraditionalMedicinePage(
          patientId: 'patient-1',
          patientName: 'Marie Patient',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Médecine Traditionnelle'), findsOneWidget);
    expect(find.text('Man Rose Pierre'), findsOneWidget);
    expect(find.text('Vérifié'), findsOneWidget);
    expect(find.text('88/100'), findsOneWidget);
    expect(find.text('18 ans'), findsOneWidget);
    expect(find.text('Disponible'), findsOneWidget);

    await tester.tap(find.text('Man Rose Pierre'));
    await tester.pumpAndSettle();
    expect(find.text('Score de confiance'), findsOneWidget);
    expect(find.text('Aucun diagnostic médical'), findsNothing);
    expect(
      find.textContaining('ne pose pas de diagnostic médical'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('traditional-share-journal')));
    await tester.pumpAndSettle();
    expect(repository.sharingEnabled, isTrue);

    await tester.tap(find.byKey(const Key('traditional-book-practitioner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('traditional-confirm-booking')));
    await tester.pumpAndSettle();
    expect(repository.bookedPractitioner, 'traditional-1');
  });

  testWidgets('enregistre le carnet privé et traite une orientation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeRepository();
    var directoryOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TraditionalMedicinePage(
          patientId: 'patient-1',
          patientName: 'Marie Patient',
          repository: repository,
          onOpenCareDirectory: () => directoryOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mon carnet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Privé par défaut'), findsOneWidget);
    await tester.tap(find.byKey(const Key('traditional-add-journal-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('traditional-journal-title')),
      'Observation du jour',
    );
    await tester.tap(find.byKey(const Key('traditional-save-journal')));
    await tester.pumpAndSettle();
    expect(repository.journalTitle, 'Observation du jour');

    await tester.tap(find.text('Orientations'));
    await tester.pumpAndSettle();
    expect(find.text('Dr Jean Louis'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-orientation-orientation-1')));
    await tester.pumpAndSettle();
    expect(repository.acceptedOrientation, 'orientation-1');
    expect(directoryOpened, isTrue);
  });

  testWidgets('affiche l’alerte d’urgence avant toute consultation', (
    tester,
  ) async {
    final repository = _FakeRepository();
    var emergencyOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TraditionalMedicinePage(
          patientId: 'patient-1',
          patientName: 'Marie Patient',
          repository: repository,
          onEmergency: () => emergencyOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('traditional-emergency-banner')));
    await tester.pumpAndSettle();
    expect(find.text('Une urgence ne peut pas attendre'), findsOneWidget);
    await tester.tap(find.byKey(const Key('traditional-open-emergency')));
    await tester.pumpAndSettle();
    expect(emergencyOpened, isTrue);
  });
}

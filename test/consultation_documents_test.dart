import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/consultations/consultation_documents_page.dart';
import 'package:i_entier/consultations/consultation_repository.dart';
import 'package:i_entier/notifications_page.dart';

ConsultationDocument document(
  ConsultationKind kind,
  Map<String, dynamic> payload,
) => ConsultationDocument.fromJson({
  'document_id': '00000000-0000-0000-0000-000000000001',
  'patient_name': 'Marie Jean',
  'provider_name': 'Dr Louis',
  'created_at': '2026-10-10T14:00:00Z',
  'kind': kind.name,
  'payload': payload,
});

void main() {
  testWidgets('patient reads a diagnostic with its author and plan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultationDocumentsPage(
          patientId: 'patient',
          loader: () async => [
            document(ConsultationKind.diagnosis, {
              'diagnosis': 'Diagnostic de test',
              'plan': 'Plan de suivi',
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diagnostic de test'), findsOneWidget);
    expect(find.text('Plan de suivi'), findsOneWidget);
    expect(find.textContaining('Dr Louis'), findsOneWidget);
    expect(find.text('Envoyer au patient'), findsNothing);
  });
  testWidgets('patient sees prescription and exam details on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultationDocumentsPage(
          patientId: 'patient',
          kind: ConsultationKind.exams,
          loader: () async => [
            document(ConsultationKind.exams, {
              'priority': 'urgent',
              'indication': 'Indication clinique',
              'items': [
                {
                  'name': 'Hémogramme',
                  'instructions': 'Consigne de préparation',
                },
              ],
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Examens prescrits'), findsOneWidget);
    expect(find.text('Hémogramme'), findsOneWidget);
    expect(find.text('Consigne de préparation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultationDocumentsPage(
          key: const ValueKey('rx'),
          patientId: 'patient',
          loader: () async => [
            document(ConsultationKind.prescription, {
              'items': [
                {
                  'medication_name': 'Médicament de test',
                  'dosage': 'Dosage de test',
                  'frequency': 'Fréquence de test',
                  'duration_days': 3,
                },
              ],
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Médicament de test'), findsOneWidget);
    expect(find.textContaining('3 jours'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('document load failure offers a working retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultationDocumentsPage(
          patientId: 'patient',
          loader: () async {
            if (attempts++ == 0) throw StateError('offline');
            return [
              document(ConsultationKind.diagnosis, {'diagnosis': 'Disponible'}),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documents indisponibles'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Disponible'), findsOneWidget);
    expect(attempts, 2);
  });
  for (final source in ['app', 'prescription']) {
    testWidgets('notification $source opens the correct patient document', (
      tester,
    ) async {
      final notification = AppNotification(
        id: 'notice',
        title: 'Nouveau document',
        message: 'Un document est disponible.',
        createdAt: DateTime(2026, 1, 1),
        type: AppNotificationType.result,
        isRead: true,
        source: source,
        sourceId: source == 'app'
            ? 'consultation:00000000-0000-0000-0000-000000000001'
            : 'rx-test',
        actionLabel: 'Consulter',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(
            patientId: 'patient',
            notificationStream: Stream.value([notification]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouveau document'));
      await tester.pumpAndSettle();
      final page = tester.widget<ConsultationDocumentsPage>(
        find.byType(ConsultationDocumentsPage),
      );
      expect(page.patientId, 'patient');
      if (source == 'app') {
        expect(page.documentId, '00000000-0000-0000-0000-000000000001');
      } else {
        expect(page.prescriptionId, 'rx-test');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

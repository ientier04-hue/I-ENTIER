import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/notifications_page.dart';

void main() {
  testWidgets('affiche les notifications et leur compteur non lu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('3 nouvelles notifications'), findsOneWidget);
    expect(find.text('Vos résultats sont disponibles'), findsOneWidget);
    expect(find.text('Non lues (3)'), findsOneWidget);
  });

  testWidgets(
    'annonce l’état de lecture et masque les actions sans destination',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final notification = AppNotification(
        id: 'result-without-destination',
        title: 'Résultat disponible',
        message: 'Votre résultat est prêt.',
        createdAt: DateTime(2026, 7, 23),
        type: AppNotificationType.result,
        actionLabel: 'Voir le résultat',
      );

      await tester.pumpWidget(
        MaterialApp(home: NotificationsPage(notifications: [notification])),
      );

      final semanticsFinder = find.byKey(
        const Key('notification-semantics-result-without-destination'),
      );
      expect(
        tester.getSemantics(semanticsFinder).getSemanticsData().label,
        contains('Notification non lue'),
      );
      expect(find.text('Voir le résultat'), findsNothing);

      await tester.tap(find.text('Résultat disponible'));
      await tester.pump();

      expect(
        tester.getSemantics(semanticsFinder).getSemanticsData().label,
        contains('Notification lue'),
      );
      expect(find.textContaining('bientôt disponible'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('permet de tout marquer comme lu et affiche l’état vide', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));

    await tester.tap(find.byTooltip('Tout marquer comme lu'));
    await tester.pump();

    expect(find.text('Tout est à jour'), findsOneWidget);
    expect(find.text('Non lues (0)'), findsOneWidget);

    await tester.tap(find.text('Non lues (0)'));
    await tester.pumpAndSettle();

    expect(find.text('Aucune notification non lue'), findsOneWidget);
  });

  testWidgets('resynchronise le parent après un rollback de lecture', (
    tester,
  ) async {
    final notification = AppNotification(
      id: 'read-rollback',
      title: 'Notification à lire',
      message: 'Le stockage simulé échouera.',
      createdAt: DateTime(2026, 7, 23),
      type: AppNotificationType.reminder,
    );
    final changes = <List<AppNotification>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          patientId: 'patient-without-firebase',
          notificationStream: Stream.value([notification]),
          onNotificationsChanged: (items) => changes.add(items),
        ),
      ),
    );
    await tester.pumpAndSettle();
    changes.clear();

    await tester.tap(find.text('Notification à lire'));
    await tester.pumpAndSettle();

    expect(
      changes.map((items) => items.single.isRead),
      orderedEquals([true, false]),
    );
    expect(find.text('Non lues (1)'), findsOneWidget);
  });

  testWidgets('resynchronise le parent après un rollback de tout lire', (
    tester,
  ) async {
    final notification = AppNotification(
      id: 'all-read-rollback',
      title: 'Notification non lue',
      message: 'Le stockage simulé échouera.',
      createdAt: DateTime(2026, 7, 23),
      type: AppNotificationType.reminder,
    );
    final changes = <List<AppNotification>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          patientId: 'patient-without-firebase',
          notificationStream: Stream.value([notification]),
          onNotificationsChanged: (items) => changes.add(items),
        ),
      ),
    );
    await tester.pumpAndSettle();
    changes.clear();

    await tester.tap(find.byTooltip('Tout marquer comme lu'));
    await tester.pumpAndSettle();

    expect(
      changes.map((items) => items.single.isRead),
      orderedEquals([true, false]),
    );
    expect(find.text('Non lues (1)'), findsOneWidget);
  });

  testWidgets('resynchronise le parent après un rollback de suppression', (
    tester,
  ) async {
    final notification = AppNotification(
      id: 'delete-rollback',
      title: 'Notification à conserver',
      message: 'Le stockage simulé échouera.',
      createdAt: DateTime(2026, 7, 23),
      type: AppNotificationType.reminder,
    );
    final changes = <List<AppNotification>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          patientId: 'patient-without-firebase',
          notificationStream: Stream.value([notification]),
          onNotificationsChanged: (items) => changes.add(items),
        ),
      ),
    );
    await tester.pumpAndSettle();
    changes.clear();

    await tester.tap(find.byTooltip('Options de la notification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(changes.map((items) => items.length), orderedEquals([0, 1]));
    expect(find.text('Notification à conserver'), findsOneWidget);
  });

  testWidgets('n’affiche un rappel synchronisé qu’à son échéance', (
    tester,
  ) async {
    final now = DateTime.now();
    final notifications = [
      AppNotification(
        id: 'due',
        title: 'Rappel arrivé',
        message: 'Ce rappel doit être visible.',
        createdAt: now.subtract(const Duration(days: 1)),
        scheduledAt: now.subtract(const Duration(minutes: 1)),
        type: AppNotificationType.reminder,
      ),
      AppNotification(
        id: 'future',
        title: 'Rappel futur',
        message: 'Ce rappel ne doit pas encore être visible.',
        createdAt: now,
        scheduledAt: now.add(const Duration(days: 1)),
        type: AppNotificationType.reminder,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          notificationStream: Stream.value(notifications),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rappel arrivé'), findsOneWidget);
    expect(find.text('Rappel futur'), findsNothing);
    expect(find.text('1 nouvelle notification'), findsOneWidget);
  });

  testWidgets('ouvre la page Rendez-vous depuis une réponse professionnelle', (
    tester,
  ) async {
    var opened = false;
    final notification = AppNotification(
      id: 'appointment_request-1',
      title: 'Rendez-vous confirmé',
      message: 'Dre Marie Jean a confirmé votre demande de rendez-vous.',
      createdAt: DateTime.now(),
      type: AppNotificationType.appointment,
      actionLabel: 'Voir le rendez-vous',
      source: 'appointment',
      sourceId: 'request-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          notifications: [notification],
          onAppointmentTap: () => opened = true,
        ),
      ),
    );

    expect(find.text('Voir le rendez-vous'), findsOneWidget);
    await tester.tap(find.text('Rendez-vous confirmé'));
    await tester.pump();

    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}

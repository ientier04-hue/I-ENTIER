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
}

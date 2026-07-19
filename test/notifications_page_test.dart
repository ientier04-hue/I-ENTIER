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
}

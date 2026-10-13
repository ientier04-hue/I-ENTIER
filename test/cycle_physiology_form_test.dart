import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';
import 'package:i_entier/supabase_data.dart';

void main() {
  final today = DateTime(2026, 9, 12);
  final observation = CycleEntry(
    id: 'sample',
    date: today,
    basalTemperatureC: 36.65,
    temperatureDisturbed: true,
    lhTest: 'positive',
    cervicalMucus: 'stretchy',
  );

  Future<void> openForm(
    WidgetTester tester, {
    CycleEntry? entry,
    required ValueChanged<CycleEntry> save,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CycleTrackingPage(
          patientId: 'test',
          now: today,
          initialEntries: [?entry],
          onSaveEntry: (value) async => save(value),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('cycle-log-today')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-physiology-fields')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    if (!(entry?.hasPhysiologyDetails ?? false)) {
      await tester.tap(find.text('Observations du cycle'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('cycle-save-entry')));
    await tester.tap(find.byKey(const Key('cycle-save-entry')));
    await tester.pumpAndSettle();
  }

  test(
    'physiological-only entries survive round trip and period corrections',
    () {
      final loaded = CycleEntry.fromSupabase(
        QueryDocumentSnapshot('sample', observation.toData()),
      );
      expect(loaded.hasDetails, isTrue);
      final corrected = loaded.copyWith(isPeriod: true, flow: 'light');
      expect(corrected.basalTemperatureC, 36.65);
      expect(corrected.temperatureDisturbed, isTrue);
      expect(corrected.lhTest, 'positive');
      expect(corrected.cervicalMucus, 'stretchy');
    },
  );

  test(
    'legacy observations remain optional and malformed values are ignored',
    () {
      final legacy = CycleEntry.fromSupabase(
        QueryDocumentSnapshot('legacy', {
          'date': Timestamp.fromDate(today),
          'isPeriod': false,
          'basalTemperatureC': double.nan,
          'lhTest': 'unknown',
          'cervicalMucus': 'unknown',
        }),
      );
      expect(legacy.hasDetails, isFalse);
      expect(legacy.basalTemperatureC, isNull);
      expect(legacy.temperatureDisturbed, isFalse);
    },
  );

  testWidgets('saves optional observations on a small screen', (tester) async {
    CycleEntry? saved;
    await openForm(tester, save: (value) => saved = value);
    await tester.ensureVisible(
      find.byKey(const Key('cycle-basal-temperature')),
    );
    await tester.enterText(
      find.byKey(const Key('cycle-basal-temperature')),
      '36,65',
    );
    await tester.ensureVisible(
      find.byKey(const Key('cycle-temperature-disturbed')),
    );
    await tester.tap(find.byKey(const Key('cycle-temperature-disturbed')));
    await tester.ensureVisible(find.byKey(const Key('cycle-lh-test')));
    await tester.tap(find.byKey(const Key('cycle-lh-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Positif').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cycle-cervical-mucus')));
    await tester.tap(find.byKey(const Key('cycle-cervical-mucus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filante').last);
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(saved!.basalTemperatureC, 36.65);
    expect(saved!.temperatureDisturbed, isTrue);
    expect(saved!.lhTest, 'positive');
    expect(saved!.cervicalMucus, 'stretchy');
    expect(saved!.isPeriod, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('can clear all physiological observations when editing', (
    tester,
  ) async {
    CycleEntry? saved;
    await openForm(tester, entry: observation, save: (value) => saved = value);
    await tester.ensureVisible(
      find.byKey(const Key('cycle-basal-temperature')),
    );
    await tester.enterText(
      find.byKey(const Key('cycle-basal-temperature')),
      '',
    );
    for (final option in [
      ('cycle-lh-test', 'Non renseigné'),
      ('cycle-cervical-mucus', 'Non renseignée'),
    ]) {
      await tester.ensureVisible(find.byKey(Key(option.$1)));
      await tester.tap(find.byKey(Key(option.$1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option.$2).last);
      await tester.pumpAndSettle();
    }
    await saveForm(tester);
    expect(saved!.basalTemperatureC, isNull);
    expect(saved!.temperatureDisturbed, isFalse);
    expect(saved!.lhTest, isEmpty);
    expect(saved!.cervicalMucus, isEmpty);
  });

  testWidgets('rejects invalid temperature without losing the form', (
    tester,
  ) async {
    CycleEntry? saved;
    await openForm(tester, save: (value) => saved = value);
    for (final input in ['NaN', 'Infinity', '33', '42.1']) {
      await tester.ensureVisible(
        find.byKey(const Key('cycle-basal-temperature')),
      );
      await tester.enterText(
        find.byKey(const Key('cycle-basal-temperature')),
        input,
      );
      await saveForm(tester);
      expect(saved, isNull);
      await tester.ensureVisible(
        find.byKey(const Key('cycle-basal-temperature')),
      );
      expect(
        find.text('Saisissez une température entre 34 et 42 °C.'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

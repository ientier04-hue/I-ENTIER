import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/cycle_tracking_page.dart';

final _today = DateTime(2026, 9, 12);
final _observation = CycleEntry(
  id: 'same-day',
  date: _today,
  basalTemperatureC: 36.65,
  lhTest: 'positive',
  cervicalMucus: 'stretchy',
  note: 'Patient A',
);
final _otherObservation = CycleEntry(
  id: 'same-day',
  date: _today,
  basalTemperatureC: 37.2,
  note: 'Patient B',
);

void main() {
  Future<void Function()> mount(
    WidgetTester tester, {
    required Future<void> Function(String, CycleEntry) save,
    Future<void> Function(String, CycleEntry)? delete,
    List<CycleEntry>? initialEntries,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var patient = 'A';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            final id = patient;
            return CycleTrackingPage(
              patientId: id,
              now: _today,
              initialEntries: id == 'A'
                  ? initialEntries ?? [_observation]
                  : [_otherObservation],
              onSaveEntry: (entry) => save(id, entry),
              onDeleteEntry: (entry) async => delete?.call(id, entry),
            );
          },
        ),
      ),
    );
    return () => update(() => patient = 'B');
  }

  Future<void> openEntry(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('cycle-log-today')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-basal-temperature')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }

  Future<void> saveEntry(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-save-entry')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('cycle-save-entry')));
    await tester.pumpAndSettle();
  }

  Future<void> closeEntry(WidgetTester tester) async {
    await Navigator.of(
      tester.element(find.byKey(const Key('cycle-save-entry'))),
    ).maybePop();
    await tester.pumpAndSettle();
  }

  Future<void> expectOtherPatientUnchanged(WidgetTester tester) async {
    await closeEntry(tester);
    await openEntry(tester);
    final field = tester.widget<TextField>(
      find.byKey(const Key('cycle-basal-temperature')),
    );
    expect(field.controller!.text, '37.2');
    expect(tester.takeException(), isNull);
  }

  testWidgets('failed save retains observations and supports a retry', (
    tester,
  ) async {
    final attempts = <CycleEntry>[];
    await mount(
      tester,
      save: (patient, entry) async {
        attempts.add(entry);
        if (attempts.length == 1) throw Exception('network unavailable');
      },
    );
    await openEntry(tester);
    await tester.enterText(
      find.byKey(const Key('cycle-basal-temperature')),
      '36,72',
    );
    await saveEntry(tester);
    expect(find.text('Enregistrement impossible. Réessayez.'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('cycle-basal-temperature')),
    );
    expect(field.controller!.text, '36,72');
    await saveEntry(tester);
    expect(attempts, hasLength(2));
    expect(attempts.last.basalTemperatureC, 36.72);
    expect(attempts.last.lhTest, 'positive');
    expect(attempts.last.cervicalMucus, 'stretchy');
    expect(find.byKey(const Key('cycle-save-entry')), findsNothing);
    expect(find.text('Votre journée a été enregistrée.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocks duplicate submissions and dismissal while saving', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await mount(
      tester,
      save: (patient, entry) async {
        calls++;
        await pending.future;
      },
    );
    await openEntry(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('cycle-save-entry')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final submit = tester
        .widget<FilledButton>(find.byKey(const Key('cycle-save-entry')))
        .onPressed!;
    submit();
    submit();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cycle-save-entry')))
          .onPressed,
      isNull,
    );
    final formContext = tester.element(
      find.byKey(const Key('cycle-save-entry')),
    );
    expect(await Navigator.of(formContext).maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-save-entry')), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cycle-save-entry')), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open form cannot save into a newly selected patient', (
    tester,
  ) async {
    final calls = <String>[];
    final switchPatient = await mount(
      tester,
      save: (patient, entry) async => calls.add(patient),
    );
    await openEntry(tester);
    switchPatient();
    await tester.pumpAndSettle();
    await saveEntry(tester);
    expect(calls, isEmpty);
    expect(
      find.text('Le compte a changé. Fermez ce formulaire.'),
      findsOneWidget,
    );
    await expectOtherPatientUnchanged(tester);
  });

  testWidgets(
    'a save completing after patient change cannot mutate the new journal',
    (tester) async {
      final pending = Completer<void>();
      final calls = <String>[];
      final switchPatient = await mount(
        tester,
        save: (patient, entry) async {
          calls.add(patient);
          await pending.future;
        },
      );
      await openEntry(tester);
      await saveEntry(tester);
      expect(calls, ['A']);
      switchPatient();
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(calls, ['A']);
      expect(
        find.text('Le compte a changé. Fermez ce formulaire.'),
        findsOneWidget,
      );
      await expectOtherPatientUnchanged(tester);
    },
  );

  testWidgets(
    'a deletion completing after patient change cannot remove the new journal entry',
    (tester) async {
      final pending = Completer<void>();
      final calls = <String>[];
      final switchPatient = await mount(
        tester,
        save: (patient, entry) async {},
        delete: (patient, entry) async {
          calls.add(patient);
          await pending.future;
        },
      );
      await openEntry(tester);
      await tester.scrollUntilVisible(
        find.text('Supprimer cette journée'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Supprimer cette journée'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(calls, ['A']);
      switchPatient();
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Le compte a changé. Fermez ce formulaire.'),
        findsOneWidget,
      );
      await expectOtherPatientUnchanged(tester);
    },
  );

  testWidgets(
    'a period form opened for another patient cannot write its range',
    (tester) async {
      final calls = <String>[];
      final switchPatient = await mount(
        tester,
        initialEntries: const [],
        save: (patient, entry) async => calls.add(patient),
      );
      await tester.tap(find.byKey(const Key('cycle-add-period')));
      await tester.pumpAndSettle();
      switchPatient();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cycle-save-period')));
      await tester.tap(find.byKey(const Key('cycle-save-period')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await openEntry(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cycle-basal-temperature')))
            .controller!
            .text,
        '37.2',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'period range stops after an awaited write when patient changes',
    (tester) async {
      final pending = Completer<void>();
      final calls = <String>[];
      final switchPatient = await mount(
        tester,
        initialEntries: const [],
        save: (patient, entry) async {
          calls.add(patient);
          await pending.future;
        },
      );
      await tester.tap(find.byKey(const Key('cycle-add-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cycle-range-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.tap(find.text('Choisir'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cycle-save-period')));
      await tester.tap(find.byKey(const Key('cycle-save-period')));
      await tester.pumpAndSettle();
      expect(calls, ['A']);
      switchPatient();
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(calls, ['A']);
      await openEntry(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cycle-basal-temperature')))
            .controller!
            .text,
        '37.2',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

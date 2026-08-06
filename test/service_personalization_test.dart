import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/service_personalization.dart';

void main() {
  const ranker = ServiceRelevanceRanker();
  const serviceIds = [
    'diagnostic-assiste',
    'pharmacie',
    'don-de-sang',
    'mobilite-sante',
    'laboratoire',
    'medecine-preventive',
    'maman-bebe',
  ];

  test('les épingles gardent exactement l’ordre choisi', () {
    final preferences = ServicePreferences(
      pinnedServiceIds: const ['laboratoire', 'pharmacie'],
      usage: {
        'diagnostic-assiste': ServiceUsage(
          openCount: 20,
          lastOpenedAt: DateTime.utc(2026, 8, 6),
        ),
      },
    );

    final ranked = ranker.rank(
      services: serviceIds,
      idOf: (serviceId) => serviceId,
      preferences: preferences,
      now: DateTime.utc(2026, 8, 6),
    );

    expect(ranked.take(3), ['laboratoire', 'pharmacie', 'diagnostic-assiste']);
  });

  test('la fréquence et la récence remontent un service utilisé', () {
    final preferences = ServicePreferences(
      usage: {
        'laboratoire': ServiceUsage(
          openCount: 2,
          lastOpenedAt: DateTime.utc(2026, 8, 5),
        ),
      },
    );

    final ranked = ranker.rank(
      services: serviceIds,
      idOf: (serviceId) => serviceId,
      preferences: preferences,
      now: DateTime.utc(2026, 8, 6),
    );

    expect(ranked.first, 'laboratoire');
  });

  test('les signaux explicites du profil apportent un boost pertinent', () {
    final ranked = ranker.rank(
      services: serviceIds,
      idOf: (serviceId) => serviceId,
      preferences: ServicePreferences.empty,
      patientProfile: const {
        'pregnancyStatus': 'Oui',
        'specialNeeds': 'Fauteuil roulant',
      },
      now: DateTime.utc(2026, 8, 6),
    );

    expect(ranked.first, 'maman-bebe');
    expect(
      ranked.indexOf('mobilite-sante'),
      lessThan(ranked.indexOf('diagnostic-assiste')),
    );
  });

  test('on ne peut épingler que trois services et les réordonner', () {
    var preferences = ServicePreferences.empty
        .pin('diagnostic-assiste')
        .pin('pharmacie')
        .pin('laboratoire')
        .pin('don-de-sang');

    expect(preferences.pinnedServiceIds, [
      'diagnostic-assiste',
      'pharmacie',
      'laboratoire',
    ]);

    preferences = preferences.reorderPinned(0, 3);
    expect(preferences.pinnedServiceIds, [
      'pharmacie',
      'laboratoire',
      'diagnostic-assiste',
    ]);
  });

  test('l’historique est sérialisé et relu sans perdre les épingles', () {
    final original = ServicePreferences(
      pinnedServiceIds: const ['pharmacie'],
    ).recordOpen('laboratoire', DateTime.utc(2026, 8, 6, 12));

    final restored = ServicePreferences.fromRow(original.toRow('patient-1'));

    expect(restored.pinnedServiceIds, ['pharmacie']);
    expect(restored.usage['laboratoire']?.openCount, 1);
    expect(
      restored.usage['laboratoire']?.lastOpenedAt,
      DateTime.utc(2026, 8, 6, 12),
    );
  });
}

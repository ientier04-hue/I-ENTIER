import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

const int maximumPinnedServices = 3;

class ServiceUsage {
  const ServiceUsage({required this.openCount, this.lastOpenedAt});

  final int openCount;
  final DateTime? lastOpenedAt;

  factory ServiceUsage.fromJson(dynamic value) {
    if (value is! Map) return const ServiceUsage(openCount: 0);
    final count = int.tryParse(value['open_count']?.toString() ?? '') ?? 0;
    final openedAt = DateTime.tryParse(
      value['last_opened_at']?.toString() ?? '',
    );
    return ServiceUsage(
      openCount: math.max(0, count),
      lastOpenedAt: openedAt?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'open_count': openCount,
    if (lastOpenedAt != null)
      'last_opened_at': lastOpenedAt!.toUtc().toIso8601String(),
  };
}

class ServicePreferences {
  ServicePreferences({
    Iterable<String> pinnedServiceIds = const [],
    Map<String, ServiceUsage> usage = const {},
  }) : pinnedServiceIds = _sanitizePinnedIds(pinnedServiceIds),
       usage = Map.unmodifiable(usage);

  final List<String> pinnedServiceIds;
  final Map<String, ServiceUsage> usage;

  static ServicePreferences get empty => ServicePreferences();

  factory ServicePreferences.fromRow(Map<String, dynamic>? row) {
    final rawPins = row?['pinned_service_ids'];
    final pins = rawPins is Iterable
        ? rawPins.map((value) => value.toString())
        : const <String>[];
    final rawUsage = row?['usage'];
    final usage = <String, ServiceUsage>{};
    if (rawUsage is Map) {
      for (final entry in rawUsage.entries) {
        final id = entry.key.toString().trim();
        if (id.isNotEmpty) usage[id] = ServiceUsage.fromJson(entry.value);
      }
    }
    return ServicePreferences(pinnedServiceIds: pins, usage: usage);
  }

  Map<String, dynamic> toRow(String patientId) => {
    'patient_id': patientId,
    'pinned_service_ids': pinnedServiceIds,
    'usage': usage.map(
      (serviceId, serviceUsage) => MapEntry(serviceId, serviceUsage.toJson()),
    ),
  };

  bool isPinned(String serviceId) => pinnedServiceIds.contains(serviceId);

  ServicePreferences pin(String serviceId) {
    final normalizedId = serviceId.trim();
    if (normalizedId.isEmpty || isPinned(normalizedId)) return this;
    if (pinnedServiceIds.length >= maximumPinnedServices) return this;
    return ServicePreferences(
      pinnedServiceIds: [...pinnedServiceIds, normalizedId],
      usage: usage,
    );
  }

  ServicePreferences unpin(String serviceId) => ServicePreferences(
    pinnedServiceIds: pinnedServiceIds
        .where((candidate) => candidate != serviceId),
    usage: usage,
  );

  ServicePreferences reorderPinned(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= pinnedServiceIds.length) return this;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex--;
    targetIndex = targetIndex.clamp(0, pinnedServiceIds.length - 1);
    if (targetIndex == oldIndex) return this;
    final reordered = List<String>.of(pinnedServiceIds);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    return ServicePreferences(pinnedServiceIds: reordered, usage: usage);
  }

  ServicePreferences recordOpen(String serviceId, DateTime openedAt) {
    final normalizedId = serviceId.trim();
    if (normalizedId.isEmpty) return this;
    final previous = usage[normalizedId];
    return ServicePreferences(
      pinnedServiceIds: pinnedServiceIds,
      usage: {
        ...usage,
        normalizedId: ServiceUsage(
          openCount: (previous?.openCount ?? 0) + 1,
          lastOpenedAt: openedAt.toUtc(),
        ),
      },
    );
  }

  static List<String> _sanitizePinnedIds(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      final id = value.trim();
      if (id.isEmpty || result.contains(id)) continue;
      result.add(id);
      if (result.length == maximumPinnedServices) break;
    }
    return List.unmodifiable(result);
  }
}

abstract interface class ServicePreferencesRepository {
  Future<ServicePreferences> load(String patientId);

  Future<void> save(String patientId, ServicePreferences preferences);
}

class SupabaseServicePreferencesRepository
    implements ServicePreferencesRepository {
  SupabaseServicePreferencesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ServicePreferences> load(String patientId) async {
    final row = await _client
        .schema('ientier')
        .from('patient_service_preferences')
        .select('pinned_service_ids, usage')
        .eq('patient_id', patientId)
        .maybeSingle();
    return ServicePreferences.fromRow(row);
  }

  @override
  Future<void> save(
    String patientId,
    ServicePreferences preferences,
  ) async {
    await _client
        .schema('ientier')
        .from('patient_service_preferences')
        .upsert(preferences.toRow(patientId), onConflict: 'patient_id');
  }
}

class MemoryServicePreferencesRepository
    implements ServicePreferencesRepository {
  final Map<String, ServicePreferences> _preferencesByPatient = {};

  @override
  Future<ServicePreferences> load(String patientId) async =>
      _preferencesByPatient[patientId] ?? ServicePreferences.empty;

  @override
  Future<void> save(
    String patientId,
    ServicePreferences preferences,
  ) async {
    _preferencesByPatient[patientId] = preferences;
  }
}

class ServiceRelevanceRanker {
  const ServiceRelevanceRanker();

  List<T> rank<T>({
    required List<T> services,
    required String Function(T service) idOf,
    required ServicePreferences preferences,
    Map<String, dynamic> patientProfile = const {},
    DateTime? now,
  }) {
    final referenceTime = (now ?? DateTime.now()).toUtc();
    final originalIndex = <String, int>{
      for (var index = 0; index < services.length; index++)
        idOf(services[index]): index,
    };
    final byId = {for (final service in services) idOf(service): service};
    final ranked = <T>[];
    final alreadyAdded = <String>{};

    for (final serviceId in preferences.pinnedServiceIds) {
      final service = byId[serviceId];
      if (service != null) {
        ranked.add(service);
        alreadyAdded.add(serviceId);
      }
    }

    final profileBoosts = _profileBoosts(patientProfile);
    final remaining = services
        .where((service) => !alreadyAdded.contains(idOf(service)))
        .toList();
    remaining.sort((left, right) {
      final leftId = idOf(left);
      final rightId = idOf(right);
      final scoreComparison = _score(
        rightId,
        preferences,
        profileBoosts,
        referenceTime,
      ).compareTo(
        _score(leftId, preferences, profileBoosts, referenceTime),
      );
      if (scoreComparison != 0) return scoreComparison;
      return (originalIndex[leftId] ?? services.length).compareTo(
        originalIndex[rightId] ?? services.length,
      );
    });
    return [...ranked, ...remaining];
  }

  double _score(
    String serviceId,
    ServicePreferences preferences,
    Map<String, double> profileBoosts,
    DateTime now,
  ) {
    final usage = preferences.usage[serviceId];
    final frequencyScore = math.min(usage?.openCount ?? 0, 20) * 8.0;
    final recencyScore = _recencyScore(usage?.lastOpenedAt, now);
    return frequencyScore + recencyScore + (profileBoosts[serviceId] ?? 0);
  }

  double _recencyScore(DateTime? lastOpenedAt, DateTime now) {
    if (lastOpenedAt == null) return 0;
    final age = now.difference(lastOpenedAt.toUtc());
    if (age.isNegative || age.inHours <= 24) return 36;
    if (age.inDays <= 7) return 24;
    if (age.inDays <= 30) return 12;
    if (age.inDays <= 90) return 4;
    return 0;
  }

  Map<String, double> _profileBoosts(Map<String, dynamic> profile) {
    final boosts = <String, double>{};

    void add(String serviceId, double value) {
      boosts[serviceId] = (boosts[serviceId] ?? 0) + value;
    }

    final pregnancy = _profileText(profile, const [
      'pregnancyStatus',
      'statutGrossesse',
    ]).toLowerCase();
    if (pregnancy.isNotEmpty &&
        !const {'non', 'none', 'aucune', 'not pregnant'}.contains(pregnancy)) {
      add('maman-bebe', 70);
      add('laboratoire', 12);
      add('medecine-preventive', 8);
    }

    if (_profileText(profile, const [
      'specialNeeds',
      'besoinsParticuliers',
    ]).isNotEmpty) {
      add('mobilite-sante', 30);
    }
    if (_profileText(profile, const [
      'bloodType',
      'groupeSanguin',
    ]).isNotEmpty) {
      add('don-de-sang', 12);
    }
    if (_hasProfileValue(profile, const [
      'currentMedications',
      'medicaments',
      'allergies',
    ])) {
      add('pharmacie', 20);
    }
    if (_hasProfileValue(profile, const [
          'medicalConditions',
          'maladies',
          'primaryDoctor',
          'medecinTraitant',
        ])) {
      add('medecine-preventive', 22);
      add('laboratoire', 8);
    }
    return boosts;
  }

  bool _hasProfileValue(Map<String, dynamic> profile, List<String> keys) {
    for (final key in keys) {
      final value = profile[key];
      if (value is Iterable && value.isNotEmpty) return true;
      if (value is Map && value.isNotEmpty) return true;
      if (value != null && value.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  String _profileText(Map<String, dynamic> profile, List<String> keys) {
    for (final key in keys) {
      final value = profile[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}

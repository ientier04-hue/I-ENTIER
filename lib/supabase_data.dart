import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class Timestamp {
  final DateTime _value;

  const Timestamp._(this._value);

  factory Timestamp.fromDate(DateTime value) => Timestamp._(value);

  DateTime toDate() => _value;
}

class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);
}

class FieldValue {
  const FieldValue._();

  static const ServerTimestamp serverTimestampValue = ServerTimestamp();

  static ServerTimestamp serverTimestamp() => serverTimestampValue;
}

class ServerTimestamp {
  const ServerTimestamp();
}

class SetOptions {
  final bool merge;

  const SetOptions({this.merge = false});
}

class SupabaseDataException implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const SupabaseDataException(this.code, this.message, [this.cause]);

  @override
  String toString() => 'SupabaseDataException($code, $message)';
}

class DocumentSnapshot<T> {
  final String id;
  final T? _value;

  const DocumentSnapshot(this.id, this._value);

  bool get exists => _value != null;

  T? data() => _value;
}

class QueryDocumentSnapshot<T> extends DocumentSnapshot<T> {
  // ignore: use_super_parameters
  const QueryDocumentSnapshot(String id, T value) : super(id, value);

  @override
  T data() => super.data() as T;
}

class QuerySnapshot<T> {
  final List<QueryDocumentSnapshot<T>> docs;

  const QuerySnapshot(this.docs);
}

class SupabaseDatabase {
  SupabaseDatabase._();

  static final SupabaseDatabase instance = SupabaseDatabase._();

  SupabaseClient get _client => SupabaseConfig.client;

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      CollectionReference<Map<String, dynamic>>._(this, [name]);

  WriteBatch batch() => WriteBatch._();

  Future<List<Map<String, dynamic>>> _loadRows(
    _CollectionSpec spec, {
    String? documentId,
  }) async {
    try {
      dynamic query = _client.schema('ientier').from(spec.table).select();
      if (spec.parentId != null) {
        query = query.eq(spec.parentColumn!, spec.parentId!);
      }
      if (documentId != null) query = query.eq(spec.primaryKey, documentId);
      final response = await query;
      final rows = List<Map<String, dynamic>>.from(response as List);
      return Future.wait(rows.map((row) => _hydrate(spec, row)));
    } catch (error) {
      throw _translateError(error);
    }
  }

  Stream<List<Map<String, dynamic>>> _watchRows(
    _CollectionSpec spec, {
    String? documentId,
    List<_QueryFilter> filters = const [],
    String? orderField,
    bool descending = false,
    int? limit,
  }) {
    try {
      final filterBuilder = _client
          .schema('ientier')
          .from(spec.table)
          .stream(primaryKey: [spec.primaryKey]);
      late SupabaseStreamBuilder stream;

      if (spec.parentId != null) {
        stream = filterBuilder.eq(spec.parentColumn!, spec.parentId!);
      } else if (documentId != null) {
        stream = filterBuilder.eq(spec.primaryKey, documentId);
      } else if (spec.kind == _CollectionKind.publicProfessionals) {
        stream = filterBuilder.eq('account_type', 'professional');
      } else if (spec.kind == _CollectionKind.publicInstitutions) {
        stream = filterBuilder.eq('account_type', 'institution');
      } else if (filters.isNotEmpty) {
        final first = filters.first;
        stream = filterBuilder.eq(spec.column(first.field), first.value ?? '');
      } else {
        stream = filterBuilder;
      }

      if (orderField != null) {
        stream = stream.order(spec.column(orderField), ascending: !descending);
      }
      if (limit != null) stream = stream.limit(limit);

      return stream.asyncMap((rawRows) async {
        var rows = List<Map<String, dynamic>>.from(rawRows);
        if (spec.kind == _CollectionKind.publicProfessionals ||
            spec.kind == _CollectionKind.publicInstitutions) {
          rows = rows
              .where(
                (row) =>
                    row['verification_status'] == 'approved' &&
                    row['is_visible'] == true,
              )
              .toList();
        }
        if (documentId != null && spec.parentId != null) {
          rows = rows
              .where((row) => row[spec.primaryKey]?.toString() == documentId)
              .toList();
        }
        for (final filter in filters) {
          rows = rows
              .where((row) => row[spec.column(filter.field)] == filter.value)
              .toList();
        }
        return Future.wait(rows.map((row) => _hydrate(spec, row)));
      });
    } catch (error) {
      return Stream.error(_translateError(error));
    }
  }

  Future<Map<String, dynamic>> _hydrate(
    _CollectionSpec spec,
    Map<String, dynamic> row,
  ) async {
    final converted = spec.fromRow(row);
    try {
      if (spec.kind == _CollectionKind.patientProfiles) {
        final patientId = row['patient_id'].toString();
        final emergency = await _client
            .schema('ientier')
            .from('patient_emergency_contacts')
            .select()
            .eq('patient_id', patientId)
            .maybeSingle();
        if (emergency is Map<String, dynamic>) {
          converted['emergencyContact'] = {
            'name': emergency['contact_name'] ?? '',
            'relationship': emergency['relationship'] ?? '',
            'phone': emergency['phone'] ?? '',
          };
        }
        final itemResponse = await _client
            .schema('ientier')
            .from('patient_medical_items')
            .select('item_type,label')
            .eq('patient_id', patientId)
            .eq('active', true);
        final items = List<Map<String, dynamic>>.from(itemResponse);
        for (final entry in const {
          'condition': 'medicalConditions',
          'allergy': 'allergies',
          'medication': 'currentMedications',
          'surgery': 'previousSurgeries',
        }.entries) {
          converted[entry.value] = items
              .where((item) => item['item_type'] == entry.key)
              .map((item) => item['label'].toString())
              .toList(growable: false);
        }
      } else if (spec.kind == _CollectionKind.cycleEntries) {
        final symptoms = await _client
            .schema('ientier')
            .from('cycle_entry_symptoms')
            .select('symptom')
            .eq('cycle_entry_id', row['cycle_entry_id'].toString());
        converted['symptoms'] = List<Map<String, dynamic>>.from(
          symptoms,
        ).map((item) => item['symptom'].toString()).toList(growable: false);
      } else if (spec.kind == _CollectionKind.mentalHealthEntries) {
        final feelings = await _client
            .schema('ientier')
            .from('mental_health_entry_feelings')
            .select('feeling')
            .eq(
              'mental_health_entry_id',
              row['mental_health_entry_id'].toString(),
            );
        converted['feelings'] = List<Map<String, dynamic>>.from(
          feelings,
        ).map((item) => item['feeling'].toString()).toList(growable: false);
      }
    } catch (error) {
      throw _translateError(error);
    }
    return converted;
  }

  Future<void> _setDocument(
    _CollectionSpec spec,
    String id,
    Map<String, dynamic> data, {
    required bool merge,
  }) async {
    try {
      final row = spec.toRow(id, data);
      await _client
          .schema('ientier')
          .from(spec.table)
          .upsert(row, onConflict: spec.primaryKey);
      await _writeRelations(spec, id, data);
    } catch (error) {
      throw _translateError(error);
    }
  }

  Future<void> _updateDocument(
    _CollectionSpec spec,
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final row = spec.toRow(id, data)..remove(spec.primaryKey);
      if (row.isNotEmpty) {
        await _client
            .schema('ientier')
            .from(spec.table)
            .update(row)
            .eq(spec.primaryKey, id);
      }
      await _writeRelations(spec, id, data);
    } catch (error) {
      throw _translateError(error);
    }
  }

  Future<void> _writeRelations(
    _CollectionSpec spec,
    String id,
    Map<String, dynamic> data,
  ) async {
    if (spec.kind == _CollectionKind.patientProfiles) {
      final emergency = data['emergencyContact'];
      if (emergency is Map) {
        await _client
            .schema('ientier')
            .from('patient_emergency_contacts')
            .upsert({
              'patient_id': id,
              'contact_name': emergency['name']?.toString() ?? '',
              'relationship': emergency['relationship']?.toString() ?? '',
              'phone': emergency['phone']?.toString() ?? '',
            }, onConflict: 'patient_id');
      }
      for (final entry in const {
        'medicalConditions': 'condition',
        'allergies': 'allergy',
        'currentMedications': 'medication',
        'previousSurgeries': 'surgery',
      }.entries) {
        if (!data.containsKey(entry.key)) continue;
        await _client
            .schema('ientier')
            .from('patient_medical_items')
            .delete()
            .eq('patient_id', id)
            .eq('item_type', entry.value);
        final values = data[entry.key];
        if (values is Iterable) {
          final rows = values
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .map(
                (label) => {
                  'patient_id': id,
                  'item_type': entry.value,
                  'label': label,
                },
              )
              .toList();
          if (rows.isNotEmpty) {
            await _client
                .schema('ientier')
                .from('patient_medical_items')
                .insert(rows);
          }
        }
      }
    } else if (spec.kind == _CollectionKind.cycleEntries &&
        data.containsKey('symptoms')) {
      await _client
          .schema('ientier')
          .from('cycle_entry_symptoms')
          .delete()
          .eq('cycle_entry_id', id);
      final symptoms = data['symptoms'];
      if (symptoms is Iterable) {
        final rows = symptoms
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .map((symptom) => {'cycle_entry_id': id, 'symptom': symptom})
            .toList();
        if (rows.isNotEmpty) {
          await _client
              .schema('ientier')
              .from('cycle_entry_symptoms')
              .insert(rows);
        }
      }
    } else if (spec.kind == _CollectionKind.mentalHealthEntries &&
        data.containsKey('feelings')) {
      await _client
          .schema('ientier')
          .from('mental_health_entry_feelings')
          .delete()
          .eq('mental_health_entry_id', id);
      final feelings = data['feelings'];
      if (feelings is Iterable) {
        final rows = feelings
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .map(
              (feeling) => {'mental_health_entry_id': id, 'feeling': feeling},
            )
            .toList();
        if (rows.isNotEmpty) {
          await _client
              .schema('ientier')
              .from('mental_health_entry_feelings')
              .insert(rows);
        }
      }
    }
  }

  Future<void> _deleteDocument(_CollectionSpec spec, String id) async {
    try {
      await _client
          .schema('ientier')
          .from(spec.table)
          .delete()
          .eq(spec.primaryKey, id);
    } catch (error) {
      throw _translateError(error);
    }
  }
}

class Query<T extends Map<String, dynamic>> {
  final SupabaseDatabase _database;
  final List<String> _path;
  final List<_QueryFilter> _filters;
  final String? _orderField;
  final bool _descending;
  final int? _limit;

  const Query._(
    this._database,
    this._path, {
    List<_QueryFilter> filters = const [],
    String? orderField,
    bool descending = false,
    int? limit,
  }) : _filters = filters,
       _orderField = orderField,
       _descending = descending,
       _limit = limit;

  Query<T> where(String field, {required Object? isEqualTo}) => Query<T>._(
    _database,
    _path,
    filters: [..._filters, _QueryFilter(field, isEqualTo)],
    orderField: _orderField,
    descending: _descending,
    limit: _limit,
  );

  Query<T> orderBy(String field, {bool descending = false}) => Query<T>._(
    _database,
    _path,
    filters: _filters,
    orderField: field,
    descending: descending,
    limit: _limit,
  );

  Query<T> limit(int value) => Query<T>._(
    _database,
    _path,
    filters: _filters,
    orderField: _orderField,
    descending: _descending,
    limit: value,
  );

  Stream<QuerySnapshot<T>> snapshots() {
    final spec = _CollectionSpec.resolve(_path);
    return _database
        ._watchRows(
          spec,
          filters: _filters,
          orderField: _orderField,
          descending: _descending,
          limit: _limit,
        )
        .map(
          (rows) => QuerySnapshot<T>(
            rows
                .map(
                  (row) => QueryDocumentSnapshot<T>(
                    row.remove('_documentId').toString(),
                    row as T,
                  ),
                )
                .toList(growable: false),
          ),
        );
  }
}

class CollectionReference<T extends Map<String, dynamic>> extends Query<T> {
  // ignore: use_super_parameters
  CollectionReference._(SupabaseDatabase database, List<String> path)
    : super._(database, path);

  DocumentReference<T> doc([String? id]) =>
      DocumentReference<T>._(_database, [..._path, id ?? _newId()]);

  Future<DocumentReference<T>> add(T data) async {
    final reference = doc();
    await reference.set(data);
    return reference;
  }
}

class DocumentReference<T extends Map<String, dynamic>> {
  final SupabaseDatabase _database;
  final List<String> _path;

  const DocumentReference._(this._database, this._path);

  String get id => _path.last;

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      CollectionReference<Map<String, dynamic>>._(_database, [..._path, name]);

  Future<DocumentSnapshot<T>> get() async {
    final spec = _CollectionSpec.resolve(_path.sublist(0, _path.length - 1));
    final rows = await _database._loadRows(spec, documentId: id);
    if (rows.isEmpty) return DocumentSnapshot<T>(id, null);
    final row = rows.first;
    row.remove('_documentId');
    return DocumentSnapshot<T>(id, row as T);
  }

  Stream<DocumentSnapshot<T>> snapshots() {
    final spec = _CollectionSpec.resolve(_path.sublist(0, _path.length - 1));
    return _database._watchRows(spec, documentId: id).map((rows) {
      if (rows.isEmpty) return DocumentSnapshot<T>(id, null);
      final row = rows.first;
      row.remove('_documentId');
      return DocumentSnapshot<T>(id, row as T);
    });
  }

  Future<void> set(T data, [SetOptions options = const SetOptions()]) {
    final spec = _CollectionSpec.resolve(_path.sublist(0, _path.length - 1));
    return _database._setDocument(spec, id, data, merge: options.merge);
  }

  Future<void> update(Map<String, dynamic> data) {
    final spec = _CollectionSpec.resolve(_path.sublist(0, _path.length - 1));
    return _database._updateDocument(spec, id, data);
  }

  Future<void> delete() {
    final spec = _CollectionSpec.resolve(_path.sublist(0, _path.length - 1));
    return _database._deleteDocument(spec, id);
  }
}

class WriteBatch {
  final List<Future<void> Function()> _operations = [];

  WriteBatch._();

  void set<T extends Map<String, dynamic>>(
    DocumentReference<T> reference,
    T data, [
    SetOptions options = const SetOptions(),
  ]) {
    _operations.add(() => reference.set(data, options));
  }

  void update<T extends Map<String, dynamic>>(
    DocumentReference<T> reference,
    Map<String, dynamic> data,
  ) {
    _operations.add(() => reference.update(data));
  }

  void delete<T extends Map<String, dynamic>>(DocumentReference<T> reference) {
    _operations.add(reference.delete);
  }

  Future<void> commit() async {
    for (final operation in _operations) {
      await operation();
    }
  }
}

class SupabaseStorage {
  SupabaseStorage._();

  static final SupabaseStorage instance = SupabaseStorage._();

  StorageReference ref(String path) => StorageReference._(path);
}

class SettableMetadata {
  final String? contentType;
  final Map<String, String>? customMetadata;

  const SettableMetadata({this.contentType, this.customMetadata});
}

class StorageReference {
  final String fullPath;

  const StorageReference._(this.fullPath);

  String get _bucket => fullPath.split('/').first;
  String get _objectPath => fullPath.split('/').skip(1).join('/');

  Future<void> putData(Uint8List bytes, [SettableMetadata? metadata]) async {
    try {
      await SupabaseConfig.client.storage
          .from(_bucket)
          .uploadBinary(
            _objectPath,
            bytes,
            fileOptions: FileOptions(
              contentType: metadata?.contentType,
              metadata: metadata?.customMetadata,
              upsert: true,
            ),
          );
    } catch (error) {
      throw _translateError(error);
    }
  }

  Future<void> delete() async {
    try {
      await SupabaseConfig.client.storage.from(_bucket).remove([_objectPath]);
    } catch (error) {
      throw _translateError(error);
    }
  }

  Future<String> getDownloadURL() async {
    try {
      return await SupabaseConfig.client.storage
          .from(_bucket)
          .createSignedUrl(_objectPath, 3600);
    } catch (error) {
      throw _translateError(error);
    }
  }

  Future<Uint8List?> getData(int maxSize) async {
    try {
      final bytes = await SupabaseConfig.client.storage
          .from(_bucket)
          .download(_objectPath);
      if (bytes.length > maxSize) return null;
      return bytes;
    } catch (error) {
      throw _translateError(error);
    }
  }
}

enum _CollectionKind {
  appUsers,
  administrators,
  patientProfiles,
  providerProfiles,
  publicProfessionals,
  publicInstitutions,
  appointments,
  healthMeasurements,
  cycleEntries,
  mentalHealthEntries,
  laboratoryResults,
  preventiveRecords,
  preventiveReminders,
  prescriptions,
  notifications,
}

class _CollectionSpec {
  final _CollectionKind kind;
  final String table;
  final String primaryKey;
  final String? parentId;
  final String? parentColumn;

  const _CollectionSpec(
    this.kind,
    this.table,
    this.primaryKey, {
    this.parentId,
    this.parentColumn,
  });

  static _CollectionSpec resolve(List<String> path) {
    if (path.length == 1) {
      return switch (path.first) {
        'user' => const _CollectionSpec(
          _CollectionKind.appUsers,
          'app_users',
          'user_id',
        ),
        'administrators' => const _CollectionSpec(
          _CollectionKind.administrators,
          'administrators',
          'user_id',
        ),
        'patients' => const _CollectionSpec(
          _CollectionKind.patientProfiles,
          'patient_profiles',
          'patient_id',
        ),
        'providerProfiles' => const _CollectionSpec(
          _CollectionKind.providerProfiles,
          'provider_profiles',
          'provider_id',
        ),
        'personnelMedical' => const _CollectionSpec(
          _CollectionKind.publicProfessionals,
          'provider_profiles',
          'provider_id',
        ),
        'institution' => const _CollectionSpec(
          _CollectionKind.publicInstitutions,
          'provider_profiles',
          'provider_id',
        ),
        'appointments' => const _CollectionSpec(
          _CollectionKind.appointments,
          'appointments',
          'appointment_id',
        ),
        _ => throw StateError('Collection Supabase inconnue: ${path.first}'),
      };
    }
    if (path.length == 3 && path.first == 'patients') {
      final patientId = path[1];
      return switch (path[2]) {
        'healthMeasurements' => _CollectionSpec(
          _CollectionKind.healthMeasurements,
          'health_measurements',
          'measurement_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'cycleEntries' => _CollectionSpec(
          _CollectionKind.cycleEntries,
          'cycle_entries',
          'cycle_entry_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'mentalHealthEntries' => _CollectionSpec(
          _CollectionKind.mentalHealthEntries,
          'mental_health_entries',
          'mental_health_entry_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'laboratoryResults' => _CollectionSpec(
          _CollectionKind.laboratoryResults,
          'laboratory_results',
          'laboratory_result_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'preventiveCareRecords' => _CollectionSpec(
          _CollectionKind.preventiveRecords,
          'preventive_care_records',
          'preventive_record_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'preventiveCareReminders' => _CollectionSpec(
          _CollectionKind.preventiveReminders,
          'preventive_care_reminders',
          'preventive_reminder_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'prescriptions' => _CollectionSpec(
          _CollectionKind.prescriptions,
          'prescriptions',
          'prescription_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        'notifications' => _CollectionSpec(
          _CollectionKind.notifications,
          'notifications',
          'notification_id',
          parentId: patientId,
          parentColumn: 'patient_id',
        ),
        _ => throw StateError('Sous-collection Supabase inconnue: ${path[2]}'),
      };
    }
    throw StateError('Chemin Supabase invalide: ${path.join('/')}');
  }

  String column(String legacyField) =>
      _columnMappings[kind]?[legacyField] ?? _snakeCase(legacyField);

  Map<String, dynamic> fromRow(Map<String, dynamic> row) {
    final result = <String, dynamic>{'_documentId': row[primaryKey].toString()};
    final reverse = {
      for (final entry in (_columnMappings[kind] ?? const {}).entries)
        entry.value: entry.key,
    };
    for (final entry in row.entries) {
      final key = reverse[entry.key] ?? entry.key;
      result[key] = _readValue(entry.value);
    }
    if (kind == _CollectionKind.publicProfessionals) {
      final legacy = row['legacy_availability_config'] is Map
          ? Map<String, dynamic>.from(row['legacy_availability_config'] as Map)
          : const <String, dynamic>{};
      result.addAll({
        'ownerUid': row['provider_id'],
        'nomComplet': row['display_name'],
        'specialite': row['category'],
        'etablissement': row['workplace'],
        'institutionId': row['linked_institution_id'],
        'institutionName': row['linked_institution_name_snapshot'],
        'biographie': row['description'],
        'qualification': row['qualifications'],
        'services': row['services_summary'],
        'horaires': row['schedule_summary'],
        'adresse': row['address'],
        'telephone': row['phone'],
        'disponible': row['available'],
        'verificationStatus': 'approved',
        'isPublished': true,
        'horairesParMode': {
          'inPerson': legacy['atProviderSchedule'] ?? '',
          'homeVisit': legacy['homeVisitSchedule'] ?? '',
          'video': legacy['videoSchedule'] ?? '',
        },
        'modesDeRendezVous': {
          'inPerson': legacy['atProviderEnabled'] == true,
          'homeVisit': legacy['homeVisitEnabled'] == true,
          'video': legacy['videoEnabled'] == true,
        },
        'disponibilitesParMode':
            legacy['availabilityConfigurations'] ?? const {},
        'prixParDefaut': legacy['defaultPrice'] ?? '',
      });
    } else if (kind == _CollectionKind.publicInstitutions) {
      result.addAll({
        'ownerUid': row['provider_id'],
        'nom': row['display_name'],
        'type': row['category'],
        'services': row['services_summary'],
        'horaires': row['schedule_summary'],
        'adresse': row['address'],
        'telephone': row['phone'],
        'disponible': row['available'],
        'tarifsPublies': row['institution_prices_published'],
        'tarifsServices': row['service_prices_summary'],
        'tarifsChambres': row['room_prices_summary'],
        'verificationStatus': 'approved',
        'isPublished': true,
      });
    }
    return result;
  }

  Map<String, dynamic> toRow(String id, Map<String, dynamic> data) {
    final row = <String, dynamic>{primaryKey: id};
    if (parentId != null) row[parentColumn!] = parentId;
    for (final entry in data.entries) {
      if (_relationFields.contains(entry.key) ||
          entry.value is ServerTimestamp) {
        continue;
      }
      final target = column(entry.key);
      final value = _writeValue(entry.value, dateOnly: target == 'entry_date');
      row[target] =
          kind == _CollectionKind.cycleEntries &&
              (target == 'flow' || target == 'mood') &&
              value == ''
          ? null
          : value;
    }
    if (_firestoreIdKinds.contains(kind)) row['firestore_id'] = id;
    if (kind == _CollectionKind.notifications) {
      final source = data['source']?.toString() ?? 'app';
      final sourceId = data['sourceId']?.toString() ?? '';
      final relationColumn = switch (source) {
        'appointment' => 'appointment_id',
        'preventiveRecord' => 'preventive_record_id',
        'preventiveReminder' => 'preventive_reminder_id',
        'laboratoryResult' => 'laboratory_result_id',
        'prescription' => 'prescription_id',
        _ => null,
      };
      if (relationColumn != null && sourceId.isNotEmpty) {
        row[relationColumn] = sourceId;
      }
    }
    return row;
  }
}

const _columnMappings = <_CollectionKind, Map<String, String>>{
  _CollectionKind.appUsers: {
    'displayName': 'display_name',
    'photoUrl': 'photo_url',
    'provider': 'auth_provider',
    'emailVerified': 'email_verified',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.patientProfiles: {
    'birthDate': 'birth_date',
    'weightKg': 'weight_kg',
    'heightCm': 'height_cm',
    'bloodType': 'blood_type',
    'specialNeeds': 'special_needs',
    'pregnancyStatus': 'pregnancy_status',
    'primaryDoctor': 'primary_doctor',
    'profileComplete': 'profile_complete',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.providerProfiles: {
    'ownerUid': 'provider_id',
    'accountType': 'account_type',
    'displayName': 'display_name',
    'registrationNumber': 'registration_number',
    'contactPerson': 'contact_person',
    'linkedInstitutionId': 'linked_institution_id',
    'linkedInstitutionName': 'linked_institution_name_snapshot',
    'services': 'services_summary',
    'schedule': 'schedule_summary',
    'institutionPricesPublished': 'institution_prices_published',
    'servicePrices': 'service_prices_summary',
    'roomPrices': 'room_prices_summary',
    'availabilityConfigurations': 'legacy_availability_config',
    'isVisible': 'is_visible',
    'verificationStatus': 'verification_status',
    'rejectionReason': 'rejection_reason',
    'termsAccepted': 'terms_accepted',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.appointments: {
    'patientId': 'patient_id',
    'patientName': 'patient_name_snapshot',
    'providerId': 'provider_id',
    'providerType': 'provider_type_snapshot',
    'providerName': 'provider_name_snapshot',
    'service': 'service_name_snapshot',
    'appointmentMode': 'mode',
    'scheduledAt': 'scheduled_at',
    'scheduleLabel': 'schedule_label',
    'patientNote': 'patient_note',
    'responseNote': 'response_note',
    'respondedAt': 'responded_at',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.healthMeasurements: {
    'secondaryValue': 'secondary_value',
    'pulseBpm': 'pulse_bpm',
    'measuredAt': 'measured_at',
    'createdAt': 'created_at',
  },
  _CollectionKind.cycleEntries: {
    'date': 'entry_date',
    'isPeriod': 'is_period',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.mentalHealthEntries: {
    'moodScore': 'mood_score',
    'createdAt': 'created_at',
  },
  _CollectionKind.laboratoryResults: {
    'laboratoryId': 'laboratory_id',
    'examId': 'exam_id',
    'examName': 'exam_name_snapshot',
    'laboratoryName': 'laboratory_name_snapshot',
    'referenceRange': 'reference_range',
    'fileUrl': 'file_url',
    'collectedAt': 'collected_at',
    'publishedAt': 'published_at',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.preventiveRecords: {
    'planItemId': 'plan_item_id',
    'completedAt': 'completed_at',
    'nextDueAt': 'next_due_at',
    'provider': 'provider_name',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.preventiveReminders: {
    'planItemId': 'plan_item_id',
    'dueAt': 'due_at',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.prescriptions: {
    'doctorId': 'doctor_id',
    'doctorName': 'doctor_name_snapshot',
    'fileName': 'file_name',
    'storagePath': 'storage_path',
    'mimeType': 'mime_type',
    'fileSizeBytes': 'file_size_bytes',
    'issuedAt': 'issued_at',
    'expiresAt': 'expires_at',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
  _CollectionKind.notifications: {
    'isRead': 'is_read',
    'scheduledAt': 'scheduled_at',
    'actionLabel': 'action_label',
    'sourceId': 'source_id',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
};

const _relationFields = {
  'emergencyContact',
  'medicalConditions',
  'allergies',
  'currentMedications',
  'previousSurgeries',
  'symptoms',
  'feelings',
};

const _firestoreIdKinds = {
  _CollectionKind.healthMeasurements,
  _CollectionKind.cycleEntries,
  _CollectionKind.mentalHealthEntries,
  _CollectionKind.laboratoryResults,
  _CollectionKind.preventiveRecords,
  _CollectionKind.preventiveReminders,
  _CollectionKind.prescriptions,
  _CollectionKind.notifications,
};

class _QueryFilter {
  final String field;
  final Object? value;

  const _QueryFilter(this.field, this.value);
}

Object? _readValue(Object? value) {
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null &&
        (value.contains('T') ||
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))) {
      return Timestamp.fromDate(date.toLocal());
    }
  }
  return value;
}

Object? _writeValue(Object? value, {bool dateOnly = false}) {
  if (value is Timestamp) {
    final date = value.toDate().toUtc();
    if (dateOnly) {
      return '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }
    return date.toIso8601String();
  }
  if (value is DateTime) return value.toUtc().toIso8601String();
  return value;
}

String _snakeCase(String value) => value.replaceAllMapped(
  RegExp('[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);

String _newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(10, (_) => random.nextInt(256));
  final suffix = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}$suffix';
}

SupabaseDataException _translateError(Object error) {
  if (error is SupabaseDataException) return error;
  if (error is PostgrestException) {
    return SupabaseDataException(
      error.code ?? 'database-error',
      error.message,
      error,
    );
  }
  if (error is StorageException) {
    return SupabaseDataException(
      error.statusCode ?? 'storage-error',
      error.message,
      error,
    );
  }
  return SupabaseDataException('unknown', error.toString(), error);
}

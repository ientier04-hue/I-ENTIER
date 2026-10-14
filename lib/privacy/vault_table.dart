import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'patient_vault.dart';
import 'vault_crypto.dart';
import 'vault_schema.dart';

/// A deliberately small local query API. Filters run on authenticated plaintext
/// only after decryption; none of their values are sent to PostgREST.
class VaultTable {
  final PatientVault vault;
  final String table;
  VaultTable(SupabaseClient client, this.table) : vault = PatientVault(client) {
    if (!vaultPrimaryKeys.containsKey(table)) throw ArgumentError.value(table);
  }
  VaultQuery select([String columns = '*']) => VaultQuery(vault, table);
  VaultQuery insert(dynamic data) =>
      VaultQuery(vault, table, operation: 'insert', data: data);
  VaultQuery upsert(dynamic data, {String? onConflict}) =>
      VaultQuery(vault, table, operation: 'upsert', data: data);
  VaultQuery update(Map<String, dynamic> data) =>
      VaultQuery(vault, table, operation: 'update', data: data);
  VaultQuery delete() => VaultQuery(vault, table, operation: 'delete');
  VaultStream stream({required List<String> primaryKey}) =>
      VaultStream(select());
}

class VaultQuery implements Future<List<Map<String, dynamic>>> {
  final PatientVault vault;
  final String table, operation;
  final dynamic data;
  final _filters = <bool Function(Map<String, dynamic>)>[];
  final _orders = <(String, bool)>[];
  int? _limit;
  Future<List<Map<String, dynamic>>>? _result;
  VaultQuery(this.vault, this.table, {this.operation = 'select', this.data});
  VaultQuery select([String columns = '*']) => this;
  VaultQuery eq(String column, Object value) {
    _filters.add((r) => r[column] == value);
    return this;
  }

  VaultQuery neq(String column, Object value) {
    _filters.add((r) => r[column] != value);
    return this;
  }

  VaultQuery inFilter(String column, List<Object> values) {
    _filters.add((r) => values.contains(r[column]));
    return this;
  }

  VaultQuery gte(String column, Object value) {
    _filters.add((r) => _compare(r[column], value) >= 0);
    return this;
  }

  VaultQuery order(String column, {bool ascending = true}) {
    _orders.add((column, ascending));
    return this;
  }

  VaultQuery limit(int limit) {
    _limit = limit;
    return this;
  }

  bool _matches(Map<String, dynamic> row) => _filters.every((f) => f(row));
  static int _compare(dynamic a, dynamic b) {
    if (a == null) return b == null ? 0 : -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  Future<List<Map<String, dynamic>>> run() async {
    if ([
      'consultation_documents',
      'prescriptions',
      'notifications',
      'traditional_prevention_recommendations',
      'traditional_care_orientations',
    ].contains(table)) {
      await vault.importDocuments();
    }
    final operational = table == 'notifications'
        ? await vault.client
              .schema('ientier')
              .from('notifications')
              .select()
              .eq('patient_id', vault.userId)
              .order('created_at', ascending: false)
              .limit(100)
        : <Map<String, dynamic>>[];
    if (operation != 'select') {
      if (table == 'notifications' &&
          ['update', 'delete'].contains(operation)) {
        for (final row in operational.where(_matches)) {
          if (operation == 'delete') {
            await vault.client
                .schema('ientier')
                .from('notifications')
                .delete()
                .eq('notification_id', row['notification_id']);
          } else if ((data as Map).containsKey('is_read')) {
            await vault.client
                .schema('ientier')
                .from('notifications')
                .update({'is_read': data['is_read']})
                .eq('notification_id', row['notification_id']);
          }
        }
      }
      final deletedIds = <dynamic>{};
      await vault.mutate(table, (rows) {
        if (operation == 'delete') {
          deletedIds.addAll(
            rows.where(_matches).map((r) => r[vaultPrimaryKeys[table]]),
          );
          rows.removeWhere(_matches);
          return;
        }
        if (operation == 'update') {
          for (final row in rows.where(_matches)) {
            _checkOwner(data);
            row.addAll(Map<String, dynamic>.from(data));
          }
          return;
        }
        final incoming = data is List ? data as List : [data];
        final pk = vaultPrimaryKeys[table]!;
        for (final raw in incoming) {
          final row = Map<String, dynamic>.from(raw as Map);
          _checkOwner(row);
          final now = DateTime.now().toUtc().toIso8601String();
          row[pk] ??= VaultCrypto.newId();
          bool same(Map<String, dynamic> r) =>
              r[pk] == row[pk] &&
              (table != 'cycle_entry_symptoms' ||
                  r['symptom'] == row['symptom']) &&
              (table != 'mental_health_entry_feelings' ||
                  r['feeling'] == row['feeling']);
          final index = rows.indexWhere(same);
          if (index >= 0 && operation == 'insert') {
            throw StateError('Cet élément existe déjà.');
          }
          row['updated_at'] = now;
          if (index >= 0) {
            rows[index] = {...rows[index], ...row};
          } else {
            rows.add({
              'created_at': now,
              if (table == 'natural_health_journal_entries') 'occurred_at': now,
              if (table == 'patient_medical_items') 'active': true,
              if (table == 'prescriptions') 'status': 'available',
              ...row,
            });
          }
        }
      });
      if (deletedIds.isNotEmpty) {
        final relation = const {
          'cycle_entries': ('cycle_entry_symptoms', 'cycle_entry_id'),
          'mental_health_entries': (
            'mental_health_entry_feelings',
            'mental_health_entry_id',
          ),
          'laboratory_results': (
            'laboratory_result_items',
            'laboratory_result_id',
          ),
          'prescriptions': ('prescription_items', 'prescription_id'),
        }[table];
        if (relation != null) {
          await vault.mutate(
            relation.$1,
            (rows) =>
                rows.removeWhere((r) => deletedIds.contains(r[relation.$2])),
          );
        }
      }
      return [];
    }
    var rows = [
      ...(await vault.read(table)).rows,
      ...operational,
    ].where(_matches).toList();
    rows.sort((a, b) {
      for (final order in _orders) {
        final result = _compare(a[order.$1], b[order.$1]) * (order.$2 ? 1 : -1);
        if (result != 0) return result;
      }
      return 0;
    });
    if (_limit != null) rows = rows.take(_limit!).toList();
    return rows;
  }

  void _checkOwner(Map<dynamic, dynamic> row) {
    for (final field in ['patient_id', 'guardian_patient_id']) {
      if (row[field] != null && row[field] != vault.userId) {
        throw const VaultLocked();
      }
    }
  }

  Future<List<Map<String, dynamic>>> get _future => _result ??= run();
  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await _future;
    if (rows.length > 1) throw StateError('Résultat non unique');
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, dynamic>> single() async => (await _future).single;
  @override
  Stream<List<Map<String, dynamic>>> asStream() => _future.asStream();
  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object)? test,
  }) => _future.catchError(onError, test: test);
  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) => _future.timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<List<Map<String, dynamic>>> whenComplete(
    FutureOr<void> Function() action,
  ) => _future.whenComplete(action);
}

class VaultStream extends Stream<List<Map<String, dynamic>>> {
  final VaultQuery query;
  VaultStream(this.query);
  VaultStream eq(String column, Object value) {
    query.eq(column, value);
    return this;
  }

  VaultStream order(String column, {bool ascending = true}) {
    query.order(column, ascending: ascending);
    return this;
  }

  VaultStream limit(int count) {
    query.limit(count);
    return this;
  }

  @override
  StreamSubscription<List<Map<String, dynamic>>> listen(
    void Function(List<Map<String, dynamic>>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;
    StreamSubscription<void>? subscription;
    bool busy = false, cancelled = false;
    Future<void> refresh() async {
      if (busy || cancelled) return;
      busy = true;
      try {
        final rows = await query.run();
        if (!cancelled) controller.add(rows);
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
      } finally {
        busy = false;
      }
    }

    controller = StreamController(
      onListen: () {
        subscription = query.vault.changes.stream.listen((_) => refresh());
        timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
        unawaited(refresh());
      },
      onCancel: () async {
        cancelled = true;
        timer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

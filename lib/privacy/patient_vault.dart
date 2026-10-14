import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vault_crypto.dart';
import 'vault_schema.dart';

class VaultLocked implements Exception {
  const VaultLocked();
  @override
  String toString() => 'Déverrouillez votre coffre avec votre carte privée.';
}

class PatientVault {
  PatientVault._(this.client) {
    client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut ||
          event.session?.user.id != _recovery?.patientId) {
        lock();
      }
    });
  }
  static final _instances = Expando<PatientVault>();
  factory PatientVault(SupabaseClient client) =>
      _instances[client] ??= PatientVault._(client);
  final SupabaseClient client;
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  VaultRecovery? _recovery;
  final changes = StreamController<void>.broadcast();
  final _queues = <String, Future<void>>{};
  String get userId =>
      client.auth.currentUser?.id ?? (throw const VaultLocked());
  bool get unlocked =>
      _recovery != null && _recovery!.patientId == client.auth.currentUser?.id;
  VaultRecovery get recovery =>
      unlocked ? _recovery! : throw const VaultLocked();
  void lock() {
    _recovery?.destroy();
    _recovery = null;
    changes.add(null);
  }

  String _context(String collection, [VaultRecovery? r]) {
    final card = r ?? recovery;
    return '${card.patientId}:${card.vaultId}:$collection';
  }

  void _check(VaultRecovery r) {
    if (!identical(r, _recovery) ||
        client.auth.currentUser?.id != r.patientId) {
      throw const VaultLocked();
    }
  }

  Future<Map<String, dynamic>?> metadata() => client
      .schema('ientier')
      .from('patient_vaults')
      .select()
      .eq('patient_id', userId)
      .maybeSingle();

  Future<bool> restoreDevice() async {
    if (unlocked) return true;
    // A browser never persists the recovery secret (including localStorage).
    if (kIsWeb) return false;
    final id = userId;
    final code = await _storage.read(key: 'ientier.vault.v1.$id');
    if (code == null || userId != id) return false;
    await unlock(code);
    return true;
  }

  Future<void> unlock(String code) async {
    final card = VaultRecovery.parse(code);
    try {
      if (card.patientId != userId) throw const VaultLocked();
      final meta = await metadata();
      if (meta == null || meta['vault_id'] != card.vaultId) {
        throw const VaultLocked();
      }
      final check = await VaultCrypto.open(
        Map<String, dynamic>.from(meta['key_check']),
        card.key,
        _context('key-check', card),
      );
      if (check != 'ientier-vault-v1' || userId != card.patientId) {
        throw const VaultLocked();
      }
      lock();
      _recovery = card;
      if (!kIsWeb) {
        await _storage.write(
          key: 'ientier.vault.v1.${card.patientId}',
          value: card.code,
        );
      }
      _check(card);
      changes.add(null);
    } catch (_) {
      if (!identical(_recovery, card)) card.destroy();
      rethrow;
    }
  }

  /// Activation encrypts locally, then atomically replaces the exported legacy
  /// snapshot. A changed snapshot aborts the transaction, without deleting data.
  Future<void> activate(VaultRecovery card) async {
    if (card.patientId != userId) throw const VaultLocked();
    final exported = Map<String, dynamic>.from(
      await client.schema('ientier').rpc('vault_export_legacy'),
    );
    final tables = Map<String, dynamic>.from(exported['tables']);
    final sealed = <String, dynamic>{};
    for (final entry in tables.entries) {
      sealed[entry.key] = await VaultCrypto.seal(
        entry.value,
        card.key,
        _context(entry.key, card),
      );
      // Verify before any destructive server-side migration can run.
      final decoded = await VaultCrypto.open(
        sealed[entry.key],
        card.key,
        _context(entry.key, card),
      );
      if (jsonEncode(decoded) != jsonEncode(entry.value)) {
        throw const VaultLocked();
      }
    }
    // Attachments are embedded in their own encrypted dataset. Old objects are
    // removed only after the ciphertext has been stored and verified.
    final files = <Map<String, dynamic>>[];
    for (final row in (tables['prescriptions'] as List? ?? const [])) {
      final path = row['storage_path']?.toString() ?? '';
      if (path.isEmpty || files.any((f) => f['path'] == path)) continue;
      final parts = path.split('/');
      if (parts.first != 'prescriptions' ||
          parts.length < 3 ||
          parts[1] != card.patientId) {
        throw StateError('Pièce jointe à vérifier avant activation.');
      }
      final bytes = await client.storage
          .from(parts.first)
          .download(parts.skip(1).join('/'));
      files.add({'path': path, 'bytes': base64Encode(bytes)});
    }
    if (files.isNotEmpty) {
      sealed['files'] = await VaultCrypto.seal(
        files,
        card.key,
        _context('files', card),
      );
    }
    final check = await VaultCrypto.seal(
      'ientier-vault-v1',
      card.key,
      _context('key-check', card),
    );
    if (userId != card.patientId) throw const VaultLocked();
    await client
        .schema('ientier')
        .rpc(
          'vault_activate',
          params: {
            'p_vault_id': card.vaultId,
            'p_key_check': check,
            'p_fingerprint': exported['fingerprint'],
            'p_collections': sealed,
          },
        );
    await unlock(card.code);
    await removeLegacyFiles();
  }

  Future<void> removeLegacyFiles() async {
    final current = recovery;
    final data = await read('files');
    for (final file in data.rows) {
      _check(current);
      final path = file['path'] as String;
      final parts = path.split('/');
      if (parts.first != 'prescriptions' || parts[1] != current.patientId) {
        continue;
      }
      await client.storage.from(parts.first).remove([parts.skip(1).join('/')]);
    }
  }

  Future<VaultDataset> read(String collection) async {
    final current = recovery;
    final row = await client
        .schema('ientier')
        .from('vault_collections')
        .select()
        .eq('patient_id', current.patientId)
        .eq('collection', collection)
        .maybeSingle();
    _check(current);
    if (row == null) return VaultDataset([], 0);
    final value = await VaultCrypto.open(
      Map<String, dynamic>.from(row['payload']),
      current.key,
      _context(collection),
    );
    _check(current);
    return VaultDataset(
      (value as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
      (row['revision'] as num).toInt(),
    );
  }

  Future<void> mutate(
    String collection,
    void Function(List<Map<String, dynamic>>) change,
  ) {
    final current = recovery;
    final prior = _queues[collection] ?? Future<void>.value();
    final next = prior.catchError((Object _) {}).then((_) async {
      _check(current);
      final dataset = await read(collection);
      change(dataset.rows);
      final payload = await VaultCrypto.seal(
        dataset.rows,
        current.key,
        _context(collection),
      );
      _check(current);
      await client
          .schema('ientier')
          .rpc(
            'vault_write',
            params: {
              'p_collection': collection,
              'p_expected_revision': dataset.revision,
              'p_payload': payload,
            },
          );
      _check(current);
      changes.add(null);
    });
    _queues[collection] = next;
    return next;
  }

  Future<void> putFile(String path, Uint8List bytes) => mutate('files', (rows) {
    rows.removeWhere((r) => r['path'] == path);
    rows.add({'path': path, 'bytes': base64Encode(bytes)});
  });
  Future<Uint8List?> file(String path) async {
    final rows = (await read('files')).rows.where((r) => r['path'] == path);
    return rows.isEmpty ? null : base64Decode(rows.first['bytes'] as String);
  }

  Future<void> deleteFile(String path) =>
      mutate('files', (rows) => rows.removeWhere((r) => r['path'] == path));

  Future<String> authorize({
    required String providerId,
    required String appointmentId,
    required Set<String> groups,
    required int minutes,
  }) async {
    final current = recovery;
    await importDocuments();
    final id = VaultCrypto.newId();
    final key = VaultCrypto.randomBytes(32);
    try {
      final snapshot = <String, dynamic>{};
      for (final table
          in groups
              .expand((g) => vaultShareGroups[g] ?? const <String>[])
              .toSet()) {
        snapshot[table] = (await read(table)).rows;
      }
      if (groups.contains('Analyses et ordonnances')) {
        snapshot['files'] = (await read('files')).rows;
      }
      final ctx = 'grant:$id:${current.patientId}:$providerId:$appointmentId';
      final payload = await VaultCrypto.seal(snapshot, key, ctx);
      final ownerKey = await VaultCrypto.seal(
        base64Encode(key),
        current.key,
        _context('grant:$id'),
      );
      _check(current);
      await client
          .schema('ientier')
          .rpc(
            'vault_authorize',
            params: {
              'p_grant_id': id,
              'p_provider_id': providerId,
              'p_appointment_id': appointmentId,
              'p_minutes': minutes,
              'p_payload': payload,
              'p_owner_key': ownerKey,
            },
          );
      _check(current);
      return 'IEA1.$id.${base64UrlEncode(key)}';
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void>? _importing;
  Future<void> importDocuments() =>
      _importing ??= _importDocuments().whenComplete(() => _importing = null);

  Future<void> _importDocuments() async {
    final current = recovery;
    final rows = await client
        .schema('ientier')
        .from('vault_inbox')
        .select()
        .eq('patient_id', current.patientId)
        .eq('imported', false)
        .order('created_at')
        .limit(100);
    for (final item in rows) {
      _check(current);
      final grant = await client
          .schema('ientier')
          .from('vault_grants')
          .select()
          .eq('grant_id', item['grant_id'])
          .eq('patient_id', current.patientId)
          .single();
      final raw = await VaultCrypto.open(
        Map<String, dynamic>.from(grant['owner_key']),
        current.key,
        _context('grant:${grant['grant_id']}'),
      );
      final key = base64Decode(raw as String);
      try {
        final document = Map<String, dynamic>.from(
          await VaultCrypto.open(
            Map<String, dynamic>.from(item['payload']),
            key,
            'document:${item['document_id']}:${grant['grant_id']}:${current.patientId}:${grant['provider_id']}:${grant['appointment_id']}',
          ),
        );
        _check(current);
        document.addAll({
          'document_id': item['document_id'],
          'patient_id': current.patientId,
          'provider_id': grant['provider_id'],
          'appointment_id': grant['appointment_id'],
          'created_at': item['created_at'],
        });
        if (document['kind'] == 'record') {
          final payload = Map<String, dynamic>.from(document['payload'] as Map);
          final collection = payload['collection'] as String;
          if (![
            'traditional_prevention_recommendations',
            'traditional_care_orientations',
          ].contains(collection)) {
            throw const FormatException('Document invalide');
          }
          final pk = vaultPrimaryKeys[collection]!;
          final row = Map<String, dynamic>.from(payload['row'] as Map)
            ..addAll({
              pk: item['document_id'],
              'patient_id': current.patientId,
              'practitioner_id': grant['provider_id'],
              'created_at': item['created_at'],
              if (collection == 'traditional_care_orientations')
                'status': 'proposed',
            });
          await mutate(collection, (data) {
            if (!data.any((r) => r[pk] == item['document_id'])) data.add(row);
          });
        } else {
          if (![
            'diagnosis',
            'prescription',
            'exams',
            'followup',
          ].contains(document['kind'])) {
            throw const FormatException('Document invalide');
          }
          await mutate('consultation_documents', (data) {
            if (!data.any((r) => r['document_id'] == item['document_id'])) {
              data.add(document);
            }
          });
        }
        if (document['kind'] == 'prescription') {
          final prescriptionId = item['document_id'].toString();
          final payload = Map<String, dynamic>.from(document['payload'] as Map);
          final items = (payload['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          await mutate('prescriptions', (data) {
            data.removeWhere((r) => r['prescription_id'] == prescriptionId);
            data.add({
              'prescription_id': prescriptionId,
              'patient_id': current.patientId,
              'source': 'doctor',
              'status': 'available',
              'doctor_id': grant['provider_id'],
              'doctor_name_snapshot': document['provider_name'],
              'created_at': item['created_at'],
              'issued_at': item['created_at'],
              'transcription': items
                  .map(
                    (r) =>
                        '${r['medication_name']} — ${r['dosage']} — ${r['frequency']} — ${r['duration_days']} jours',
                  )
                  .join('\n'),
              'storage_path': '',
              'file_name': '',
            });
          });
          await mutate('prescription_items', (data) {
            data.removeWhere((r) => r['prescription_id'] == prescriptionId);
            for (var i = 0; i < items.length; i++) {
              data.add({
                ...items[i],
                'prescription_id': prescriptionId,
                'prescription_item_id': '$prescriptionId-$i',
                'sort_order': i,
              });
            }
          });
          await mutate('consultation_documents', (data) {
            data.firstWhere(
              (r) => r['document_id'] == item['document_id'],
            )['prescription_id'] = prescriptionId;
          });
        }
        if (document['kind'] == 'exams') {
          final payload = Map<String, dynamic>.from(document['payload'] as Map);
          final items = payload['items'] as List;
          await mutate('laboratory_exam_requests', (data) {
            for (var i = 0; i < items.length; i++) {
              final id = '${item['document_id']}-$i';
              if (data.any((r) => r['request_id'] == id)) continue;
              data.add({
                'request_id': id,
                'document_id': item['document_id'],
                'patient_id': current.patientId,
                'provider_id': grant['provider_id'],
                'exam_id': items[i]['exam_id'],
                'exam_name': items[i]['name'],
                'instructions': items[i]['instructions'],
                'priority': payload['priority'],
                'created_at': item['created_at'],
              });
            }
          });
        }
        if (document['kind'] == 'followup') {
          await mutate('appointment_notes', (data) {
            final id = 'followup-${item['document_id']}';
            if (!data.any((r) => r['appointment_id'] == id)) {
              data.add({
                'appointment_id': id,
                'response_note': document['payload']['note'] ?? '',
              });
            }
          });
        }
        await mutate('notifications', (data) {
          if (!data.any(
            (r) => r['notification_id'] == 'document-${item['document_id']}',
          )) {
            data.add({
              'notification_id': 'document-${item['document_id']}',
              'patient_id': current.patientId,
              'title': 'Document de consultation',
              'message': 'Un document est disponible dans votre coffre.',
              'source': 'app',
              'source_id': item['document_id'],
              'type': 'info',
              'is_read': false,
              'created_at': item['created_at'],
            });
          }
        });
        await client
            .schema('ientier')
            .rpc(
              'vault_acknowledge',
              params: {'p_document_id': item['document_id']},
            );
      } finally {
        key.fillRange(0, key.length, 0);
      }
    }
  }
}

class VaultDataset {
  final List<Map<String, dynamic>> rows;
  final int revision;
  const VaultDataset(this.rows, this.revision);
}

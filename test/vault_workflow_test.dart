import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:i_entier/privacy/patient_vault.dart';
import 'package:i_entier/privacy/vault_crypto.dart';
import 'package:i_entier/privacy/vault_table.dart';
import 'patient_vault_test.dart' show clientFor, patient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'activation, scoped sharing and encrypted prescription import after revocation',
    () async {
      const provider = '20000000-0000-4000-8000-000000000001';
      final card = VaultRecovery.create(patient);
      Map<String, dynamic>? metadata, grant;
      final datasets = <String, Map<String, dynamic>>{};
      final inbox = <Map<String, dynamic>>[];
      final writes = <http.Request>[];
      var failAcknowledgement = true;
      final client = await clientFor((r) async {
        http.Response json(Object? value) => http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
        final endpoint = r.url.path.split('/').last;
        final decoded = r.body.isEmpty ? null : jsonDecode(r.body);
        final body = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};
        if (r.method != 'GET') writes.add(r);
        switch (endpoint) {
          case 'patient_vaults':
            return json(metadata == null ? [] : [metadata]);
          case 'vault_export_legacy':
            return json({
              'fingerprint': 'snapshot-fingerprint',
              'tables': {
                'patient_profiles': [
                  {'patient_id': patient, 'blood_type': 'PRIVATE-PROFILE'},
                ],
                'mental_health_entries': [
                  {'patient_id': patient, 'note': 'NOT-SHARED'},
                ],
              },
            });
          case 'vault_activate':
            expect(body['p_fingerprint'], 'snapshot-fingerprint');
            metadata = {
              'patient_id': patient,
              'vault_id': body['p_vault_id'],
              'key_check': body['p_key_check'],
            };
            for (final entry
                in (body['p_collections'] as Map<String, dynamic>).entries) {
              // Activation must be recoverable with exactly the card already saved.
              await VaultCrypto.open(
                Map<String, dynamic>.from(entry.value),
                card.key,
                '$patient:${card.vaultId}:${entry.key}',
              );
              datasets[entry.key] = {'payload': entry.value, 'revision': 1};
            }
            return http.Response('', 204);
          case 'vault_collections':
            final table = r.url.queryParameters['collection']!.substring(3);
            return json(datasets.containsKey(table) ? [datasets[table]] : []);
          case 'vault_write':
            final table = body['p_collection'] as String;
            expect(
              body['p_expected_revision'],
              datasets[table]?['revision'] ?? 0,
            );
            datasets[table] = {
              'payload': body['p_payload'],
              'revision': (body['p_expected_revision'] as int) + 1,
            };
            return http.Response('', 204);
          case 'vault_authorize':
            grant = {
              'grant_id': body['p_grant_id'],
              'patient_id': patient,
              'provider_id': body['p_provider_id'],
              'appointment_id': body['p_appointment_id'],
              'payload': body['p_payload'],
              'owner_key': body['p_owner_key'],
            };
            expect(body['p_minutes'], 15);
            return http.Response('', 204);
          case 'vault_grants':
            return json(grant);
          case 'vault_inbox':
            return json(inbox.where((r) => r['imported'] == false).toList());
          case 'vault_acknowledge':
            if (failAcknowledgement) {
              failAcknowledgement = false;
              return http.Response('{"message":"network interruption"}', 503);
            }
            inbox.single['imported'] = true;
            return http.Response('', 204);
          default:
            throw StateError('Unexpected endpoint $endpoint');
        }
      });
      addTearDown(client.dispose);
      final vault = PatientVault(client);
      await vault.activate(card);
      expect(vault.unlocked, true);
      expect(
        (await vault.read('patient_profiles')).rows.single['blood_type'],
        'PRIVATE-PROFILE',
      );
      // Serial local edits must not silently overwrite each other.
      await Future.wait([
        VaultTable(
          client,
          'health_measurements',
        ).insert({'measurement_id': 'a', 'value': 1}),
        VaultTable(
          client,
          'health_measurements',
        ).insert({'measurement_id': 'b', 'value': 2}),
      ]);
      expect((await vault.read('health_measurements')).rows, hasLength(2));
      await VaultTable(
        client,
        'cycle_entries',
      ).insert({'cycle_entry_id': 'cycle'});
      await VaultTable(
        client,
        'cycle_entry_symptoms',
      ).insert({'cycle_entry_id': 'cycle', 'symptom': 'pain'});
      await VaultTable(
        client,
        'cycle_entries',
      ).delete().eq('cycle_entry_id', 'cycle');
      expect((await vault.read('cycle_entry_symptoms')).rows, isEmpty);
      final code = await vault.authorize(
        providerId: provider,
        appointmentId: 'visit',
        groups: {'Profil médical'},
        minutes: 15,
      );
      final grantKey = base64Url.decode(code.split('.').last);
      expect(grantKey, isNot(card.key));
      final shared =
          await VaultCrypto.open(
                Map<String, dynamic>.from(grant!['payload']),
                grantKey,
                'grant:${grant!['grant_id']}:$patient:$provider:visit',
              )
              as Map;
      expect(shared['patient_profiles'], isNotEmpty);
      expect(shared.containsKey('mental_health_entries'), false);
      expect(shared.containsKey('files'), false);
      final documentId = VaultCrypto.newId();
      final prescription = {
        'kind': 'prescription',
        'patient_name': 'Patient',
        'provider_name': 'Dr Test',
        'payload': {
          'items': [
            {
              'medication_name': 'PRIVATE-MEDICATION',
              'dosage': '1',
              'frequency': '2/jour',
              'duration_days': 5,
            },
          ],
          'notes': '',
        },
      };
      inbox.add({
        'document_id': documentId,
        'grant_id': grant!['grant_id'],
        'imported': false,
        'created_at': '2026-10-14T10:00:00Z',
        'payload': await VaultCrypto.seal(
          prescription,
          grantKey,
          'document:$documentId:${grant!['grant_id']}:$patient:$provider:visit',
        ),
      });
      grant!['revoked_at'] = '2026-10-14T11:00:00Z';
      await expectLater(vault.importDocuments(), throwsA(anything));
      await vault.importDocuments();
      expect(
        (await vault.read('prescriptions')).rows.single['prescription_id'],
        documentId,
      );
      expect(
        (await vault.read('prescription_items')).rows.single['medication_name'],
        'PRIVATE-MEDICATION',
      );
      expect(
        (await vault.read(
          'consultation_documents',
        )).rows.single['prescription_id'],
        documentId,
      );
      expect((await vault.read('notifications')).rows, hasLength(1));
      expect(inbox.single['imported'], true);
      for (final r in writes) {
        for (final secret in [
          'PRIVATE-PROFILE',
          'NOT-SHARED',
          'PRIVATE-MEDICATION',
          card.code,
          base64Encode(card.key),
          base64UrlEncode(grantKey),
        ]) {
          expect(r.body, isNot(contains(secret)));
        }
      }
    },
  );
}

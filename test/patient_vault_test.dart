import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:i_entier/privacy/patient_vault.dart';
import 'package:i_entier/privacy/vault_crypto.dart';
import 'package:i_entier/privacy/vault_table.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const patient = '10000000-0000-4000-8000-000000000001';
Future<SupabaseClient> clientFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'https://example.test',
    'public-test-key',
    httpClient: MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final jwt =
            '${base64UrlEncode(utf8.encode('{"alg":"HS256"}'))}.${base64UrlEncode(utf8.encode(jsonEncode({'sub': patient, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.fake';
        return http.Response(
          jsonEncode({
            'access_token': jwt,
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': patient,
              'aud': 'authenticated',
              'role': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final response = await handler(request);
      return http.Response(
        response.body,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.signInWithPassword(
    email: 'patient@example.test',
    password: 'test',
  );
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'unlock requires the matching card; only ciphertext crosses the write boundary',
    () async {
      final card = VaultRecovery.create(patient);
      final check = await VaultCrypto.seal(
        'ientier-vault-v1',
        card.key,
        '$patient:${card.vaultId}:key-check',
      );
      Map<String, dynamic>? stored;
      final requests = <http.Request>[];
      final client = await clientFor((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/patient_vaults')) {
          return http.Response(
            jsonEncode([
              {
                'patient_id': patient,
                'vault_id': card.vaultId,
                'key_check': check,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.endsWith('/vault_collections')) {
          return http.Response(
            jsonEncode(stored == null ? [] : [stored]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.endsWith('/vault_write')) {
          final body = jsonDecode(r.body) as Map;
          stored = {'payload': body['p_payload'], 'revision': 1};
          return http.Response('', 204);
        }
        throw StateError('Unexpected endpoint ${r.url.path}');
      });
      addTearDown(client.dispose);
      final vault = PatientVault(client);
      await expectLater(
        vault.unlock(VaultRecovery.create(patient).code),
        throwsA(anything),
      );
      expect(vault.unlocked, false);
      await vault.unlock(card.code);
      await VaultTable(client, 'patient_medical_items').insert({
        'patient_id': patient,
        'item_type': 'allergy',
        'label': 'CONFIDENTIAL-ALLERGY',
      });
      final rows = await VaultTable(
        client,
        'patient_medical_items',
      ).select().eq('item_type', 'allergy');
      expect(rows.single['label'], 'CONFIDENTIAL-ALLERGY');
      for (final r in requests) {
        expect(r.body, isNot(contains('CONFIDENTIAL-ALLERGY')));
        expect(r.body, isNot(contains(base64Encode(card.key))));
        expect(r.url.toString(), isNot(contains('allergy')));
      }
      vault.lock();
      await expectLater(
        vault.read('patient_medical_items'),
        throwsA(isA<VaultLocked>()),
      );
    },
  );
  test(
    'session/account mismatch rejects a card before opening or sending its key',
    () async {
      final client = await clientFor(
        (r) async => throw StateError('No request expected'),
      );
      addTearDown(client.dispose);
      await expectLater(
        PatientVault(
          client,
        ).unlock(VaultRecovery.create('different-patient').code),
        throwsA(isA<VaultLocked>()),
      );
    },
  );
}

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_entier/privacy/vault_crypto.dart';

void main() {
  test(
    'random authenticated encryption hides medical text and uses fresh nonces',
    () async {
      final key = VaultCrypto.randomBytes(32);
      const data = {
        'allergy': 'pénicilline',
        'measurements': [36.5, 37.1],
      };
      final a = await VaultCrypto.seal(data, key, 'patient:vault:profile');
      final b = await VaultCrypto.seal(data, key, 'patient:vault:profile');
      expect(a['n'], isNot(b['n']));
      expect(a['c'], isNot(b['c']));
      expect(jsonEncode(a), isNot(contains('pénicilline')));
      expect(await VaultCrypto.open(a, key, 'patient:vault:profile'), data);
    },
  );
  test(
    'different key, patient, vault or dataset fails authentication',
    () async {
      final key = VaultCrypto.randomBytes(32);
      final box = await VaultCrypto.seal(
        {'diagnosis': 'secret'},
        key,
        'p1:v1:profile',
      );
      for (final context in [
        'p2:v1:profile',
        'p1:v2:profile',
        'p1:v1:journal',
      ]) {
        await expectLater(
          VaultCrypto.open(box, key, context),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }
      await expectLater(
        VaultCrypto.open(box, VaultCrypto.randomBytes(32), 'p1:v1:profile'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    },
  );
  test(
    'ciphertext and tag tampering are rejected, never decoded as plaintext',
    () async {
      final key = VaultCrypto.randomBytes(32);
      final box = await VaultCrypto.seal('medical record', key, 'context');
      for (final field in ['c', 't']) {
        final bytes = base64Decode(box[field]);
        bytes[0] ^= 1;
        await expectLater(
          VaultCrypto.open(
            {...box, field: base64Encode(bytes)},
            key,
            'context',
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }
      await expectLater(
        VaultCrypto.open({...box, 'v': 2}, key, 'context'),
        throwsFormatException,
      );
    },
  );
  test('card round trip binds account and vault and rejects access codes', () {
    final card = VaultRecovery.create('10000000-0000-4000-8000-000000000001');
    final restored = VaultRecovery.parse(card.code);
    expect(restored.patientId, card.patientId);
    expect(restored.vaultId, card.vaultId);
    expect(restored.key, card.key);
    expect(() => VaultRecovery.parse('IEA1.some-code'), throwsFormatException);
    expect(
      () => VaultRecovery.parse('IEV1.ZGVtbw==.${card.vaultId}.AA=='),
      throwsFormatException,
    );
    restored.destroy();
    expect(restored.key.every((v) => v == 0), true);
    expect(card.key.any((v) => v != 0), true);
  });
}

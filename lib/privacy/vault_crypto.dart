import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Protocol v1. Only random 256-bit keys; never a password or an account token.
class VaultCrypto {
  static final _aes = AesGcm.with256bits();
  static Uint8List randomBytes(int size) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
  }

  static String newId() {
    final b = randomBytes(16);
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static Future<Map<String, dynamic>> seal(
    Object value,
    List<int> key,
    String context,
  ) async {
    if (key.length != 32) throw const FormatException('Clé invalide');
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: SecretKey(key),
      nonce: randomBytes(12),
      aad: utf8.encode('ientier:e2ee:v1:$context'),
    );
    return {
      'v': 1,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      't': base64Encode(box.mac.bytes),
    };
  }

  static Future<dynamic> open(
    Map<String, dynamic> envelope,
    List<int> key,
    String context,
  ) async {
    if (envelope['v'] != 1 || key.length != 32) {
      throw const FormatException('Format chiffré invalide');
    }
    final nonce = base64Decode(envelope['n'] as String);
    final tag = base64Decode(envelope['t'] as String);
    if (nonce.length != 12 || tag.length != 16) {
      throw const FormatException('Format chiffré invalide');
    }
    final plain = await _aes.decrypt(
      SecretBox(
        base64Decode(envelope['c'] as String),
        nonce: nonce,
        mac: Mac(tag),
      ),
      secretKey: SecretKey(key),
      aad: utf8.encode('ientier:e2ee:v1:$context'),
    );
    return jsonDecode(utf8.decode(plain));
  }
}

/// A recovery card and a consultation code intentionally have different prefixes.
/// Neither belongs in a URL, a server request, telemetry, or a clipboard by default.
class VaultRecovery {
  final String patientId, vaultId;
  final Uint8List key;
  VaultRecovery(this.patientId, this.vaultId, List<int> key)
    : key = Uint8List.fromList(key);
  factory VaultRecovery.create(String patientId) => VaultRecovery(
    patientId,
    VaultCrypto.newId(),
    VaultCrypto.randomBytes(32),
  );
  String get code =>
      'IEV1.${base64UrlEncode(utf8.encode(patientId))}.$vaultId.${base64UrlEncode(key)}';
  factory VaultRecovery.parse(String text) {
    final parts = text.replaceAll(RegExp(r'\s'), '').split('.');
    if (parts.length != 4 || parts[0] != 'IEV1') {
      throw const FormatException('Carte invalide');
    }
    final key = base64Url.decode(parts[3]);
    final patient = utf8.decode(base64Url.decode(parts[1]));
    if (key.length != 32 ||
        patient.isEmpty ||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(parts[2])) {
      throw const FormatException('Carte invalide');
    }
    return VaultRecovery(patient, parts[2], key);
  }
  void destroy() => key.fillRange(0, key.length, 0);
}

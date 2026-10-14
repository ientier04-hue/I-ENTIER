import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'vault_device_store.dart';

VaultDeviceStore createVaultDeviceStore() => const _WebVaultDeviceStore();

extension type _StoredCard._(JSObject _) implements JSObject {
  external factory _StoredCard({
    required web.CryptoKey key,
    required JSUint8Array iv,
    required JSArrayBuffer ciphertext,
  });
  external web.CryptoKey get key;
  external JSUint8Array get iv;
  external JSArrayBuffer get ciphertext;
}

/// Opt-in browser storage: ciphertext plus a non-exportable local wrapping key.
/// Same-origin scripts can still use the key; this does not protect against XSS
/// or a compromised browser/OS and is not a hardware-backed key store.
class _WebVaultDeviceStore implements VaultDeviceStore {
  const _WebVaultDeviceStore();
  static const _database = 'ientier-vault-device-v1';
  static const _store = 'cards';

  Future<web.IDBDatabase> _open() {
    final ready = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_database, 1);
    final timer = Timer(const Duration(seconds: 5), () {
      if (!ready.isCompleted) {
        ready.completeError(StateError('device_storage_timeout'));
      }
    });
    void fail() {
      timer.cancel();
      if (!ready.isCompleted) {
        ready.completeError(StateError('device_storage_unavailable'));
      }
    }

    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      timer.cancel();
      final db = request.result as web.IDBDatabase;
      if (ready.isCompleted) {
        db.close();
      } else {
        db.onversionchange = ((web.Event _) => db.close()).toJS;
        ready.complete(db);
      }
    }).toJS;
    request.onerror = ((web.Event _) => fail()).toJS;
    request.onblocked = ((web.Event _) => fail()).toJS;
    return ready.future;
  }

  Future<JSAny?> _record(
    String patientId, {
    _StoredCard? value,
    bool delete = false,
  }) async {
    final db = await _open();
    try {
      final transaction = db.transaction(
        _store.toJS,
        value != null || delete ? 'readwrite' : 'readonly',
      );
      final done = Completer<JSAny?>();
      JSAny? result;
      transaction.oncomplete = ((web.Event _) {
        if (!done.isCompleted) done.complete(result);
      }).toJS;
      transaction.onabort = ((web.Event _) {
        if (!done.isCompleted) {
          done.completeError(StateError('device_storage_failed'));
        }
      }).toJS;
      final store = transaction.objectStore(_store);
      final request = value != null
          ? store.put(value, patientId.toJS)
          : delete
          ? store.delete(patientId.toJS)
          : store.get(patientId.toJS);
      request.onsuccess = ((web.Event _) => result = request.result).toJS;
      return await done.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          transaction.abort();
          throw StateError('device_storage_timeout');
        },
      );
    } finally {
      db.close();
    }
  }

  JSObject _algorithm(String patientId, JSUint8Array iv) =>
      {
            'name': 'AES-GCM',
            'iv': iv,
            'additionalData': Uint8List.fromList(
              utf8.encode('ientier:device:v1:$patientId'),
            ).toJS,
            'tagLength': 128,
          }.jsify()
          as JSObject;

  @override
  Future<String?> read(String patientId) async {
    final value = await _record(patientId);
    if (value.isUndefinedOrNull) return null;
    final record = value as _StoredCard;
    if (record.key.extractable) throw StateError('invalid_device_key');
    final bytes =
        (await web.window.crypto.subtle
                    .decrypt(
                      _algorithm(patientId, record.iv),
                      record.key,
                      record.ciphertext,
                    )
                    .toDart
                as JSArrayBuffer)
            .toDart
            .asUint8List();
    try {
      return utf8.decode(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> write(String patientId, String code) async {
    final crypto = web.window.crypto;
    final key =
        await crypto.subtle
                .generateKey(
                  {'name': 'AES-GCM', 'length': 256}.jsify()!,
                  false,
                  ['encrypt'.toJS, 'decrypt'.toJS].toJS,
                )
                .toDart
            as web.CryptoKey;
    final iv = crypto.getRandomValues(Uint8List(12).toJS) as JSUint8Array;
    final bytes = Uint8List.fromList(utf8.encode(code));
    try {
      final ciphertext =
          await crypto.subtle
                  .encrypt(_algorithm(patientId, iv), key, bytes.toJS)
                  .toDart
              as JSArrayBuffer;
      await _record(
        patientId,
        value: _StoredCard(key: key, iv: iv, ciphertext: ciphertext),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> delete(String patientId) async {
    await _record(patientId, delete: true);
  }
}

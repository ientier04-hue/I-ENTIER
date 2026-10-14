@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:i_entier/privacy/vault_device_store.dart';

extension type _Record._(JSObject _) implements JSObject {
  external web.CryptoKey get key;
  external JSArrayBuffer get ciphertext;
}

Future<JSAny?> requestResult(web.IDBRequest request) {
  final result = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => result.completeError(
    StateError('idb'),
  )).toJS;
  return result.future;
}

void main() {
  test(
    'browser retains only encrypted cards and non-exportable account-bound keys',
    () async {
      final storage = VaultDeviceStore.create();
      const patient = 'device-storage-test-patient';
      const other = 'device-storage-test-other';
      const card = 'IEV1.fictitious-patient.fictitious-vault.fictitious-key';
      addTearDown(() async {
        await storage.delete(patient);
        await storage.delete(other);
      });
      await storage.write(patient, card);
      expect(await VaultDeviceStore.create().read(patient), card);
      expect(await storage.read(other), isNull);

      final db =
          await requestResult(
                web.window.indexedDB.open('ientier-vault-device-v1', 1),
              )
              as web.IDBDatabase;
      try {
        final record =
            await requestResult(
                  db
                      .transaction('cards'.toJS)
                      .objectStore('cards')
                      .get(patient.toJS),
                )
                as _Record;
        expect(record.key.extractable, false);
        await expectLater(
          web.window.crypto.subtle.exportKey('raw', record.key).toDart,
          throwsA(anything),
        );
        expect(
          utf8.decode(
            record.ciphertext.toDart.asUint8List(),
            allowMalformed: true,
          ),
          isNot(contains(card)),
        );
        expect(web.window.localStorage.getItem(patient), isNull);
        expect(web.window.sessionStorage.getItem(patient), isNull);

        // Moving a stored envelope to another account must fail authentication.
        await requestResult(
          db
              .transaction('cards'.toJS, 'readwrite')
              .objectStore('cards')
              .put(record, other.toJS),
        );
        await expectLater(storage.read(other), throwsA(anything));
      } finally {
        db.close();
      }
      await storage.delete(patient);
      expect(await VaultDeviceStore.create().read(patient), isNull);
    },
  );
}

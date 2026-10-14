import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'vault_device_store.dart';

VaultDeviceStore createVaultDeviceStore() => const _NativeVaultDeviceStore();

class _NativeVaultDeviceStore implements VaultDeviceStore {
  const _NativeVaultDeviceStore();
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  String _key(String id) => 'ientier.vault.v1.$id';
  @override
  Future<String?> read(String patientId) => _storage.read(key: _key(patientId));
  @override
  Future<void> write(String patientId, String code) =>
      _storage.write(key: _key(patientId), value: code);
  @override
  Future<void> delete(String patientId) =>
      _storage.delete(key: _key(patientId));
}

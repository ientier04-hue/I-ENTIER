import 'vault_device_store_native.dart'
    if (dart.library.js_interop) 'vault_device_store_web.dart'
    as platform;

/// A local, account-scoped copy. Never used as a server recovery mechanism.
abstract interface class VaultDeviceStore {
  static VaultDeviceStore create() => platform.createVaultDeviceStore();
  Future<String?> read(String patientId);
  Future<void> write(String patientId, String code);
  Future<void> delete(String patientId);
}

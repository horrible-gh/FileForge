import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/storage.dart';
import 'package:file_forge_app/screens/main/main_screen.dart';

/// CH0007 — TR0011 rev0 was rejected because the mail `[+]` and `[multi-select]`
/// shell-AppBar actions were NOT hidden on the mail screen. Root cause: the
/// AppBar resolved its action set from `StorageProvider.currentStorage`, which
/// lags the route (it is only set by the drawer flow / defaults to the first
/// file storage), while StorageDispatcher renders MailListScreen from the
/// route's storageUuid. On a Flutter Web URL reload the two diverged and the
/// guards (`storageType != 'mail'`) passed, leaving the two actions visible.
///
/// These assert [resolveStorageTypeForLocation] keys off the ROUTE so the
/// AppBar matches the body. They are load-bearing: reverting the fix (keying
/// off currentStorage) flips the divergent-route case back to 'file'.
void main() {
  final file = Storage(
    storageUuid: 'file-uuid',
    storageName: 'Files',
    storageType: 'file',
    isDefault: true,
  );
  final mail = Storage(
    storageUuid: 'mail-uuid',
    storageName: 'Mail',
    storageType: 'mail',
  );
  final vault = Storage(
    storageUuid: 'vault-uuid',
    storageName: 'Vault',
    storageType: 'password',
  );
  final storages = [file, mail, vault];

  group('resolveStorageTypeForLocation', () {
    test('mail route resolves to mail even when currentStorage is the default '
        'file storage (web-reload divergence — the rejected case)', () {
      // currentStorage = file (drawer flow never ran), route = mail storage.
      expect(resolveStorageTypeForLocation('/mail-uuid', storages, file), 'mail');
      // ...also with a node segment (/:storageUuid/:nodeUuid).
      expect(
        resolveStorageTypeForLocation('/mail-uuid/some-node', storages, file),
        'mail',
      );
      // Ablation: the OLD behavior read currentStorage.storageType == 'file',
      // which is exactly what let the [+]/[multi-select] actions render on mail.
      expect(file.storageType, 'file');
    });

    test('password (vault) route resolves to password regardless of currentStorage',
        () {
      expect(
        resolveStorageTypeForLocation('/vault-uuid', storages, file),
        'password',
      );
    });

    test('home and fixed shell routes fall back to currentStorage', () {
      // home '/' carries no storageUuid.
      expect(resolveStorageTypeForLocation('/', storages, file), 'file');
      // share-links / settings are not storage routes — first segment ignored.
      expect(
        resolveStorageTypeForLocation('/share-links', storages, mail),
        'mail', // falls through to currentStorage (actions are hidden there anyway)
      );
      expect(
        resolveStorageTypeForLocation('/settings', storages, file),
        'file',
      );
    });

    test('unknown / not-yet-loaded uuid falls back to currentStorage then file',
        () {
      expect(resolveStorageTypeForLocation('/ghost-uuid', storages, mail), 'mail');
      expect(resolveStorageTypeForLocation('/ghost-uuid', storages, null), 'file');
      expect(resolveStorageTypeForLocation('/', const [], null), 'file');
    });
  });
}

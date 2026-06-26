import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/storage.dart';
import '../services/storage_service.dart';

/// L001 § 3-2 — storage text text current selection state management
/// L002 ST-02:
///   - storages 0text text file text text prohibited (translated text currentStorage null text)
///   - storage text text text text translated text FileProvidertext initialize
class StorageProvider extends ChangeNotifier {
  // ── state ────────────────────────────────────────────────────────────────────
  List<Storage> _storages = [];
  Storage? _currentStorage;
  bool _isLoading = false;
  String? _error;

  // ── translated text ────────────────────────────────────────────────────────────────
  late final StorageService _storageService;

  StorageProvider(Dio dio) {
    _storageService = StorageService(dio);
  }

  // ── read-only ────────────────────────────────────────────────────────────
  List<Storage> get storages => _storages;
  Storage? get currentStorage => _currentStorage;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── translated text ────────────────────────────────────────────────────────────────

  /// GET /storages/get_user_storages
  /// success text text text storagetext text selectiontext (L002 ST-02 Row1).
  Future<void> loadStorages(String userUuid) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _storageService.getUserStorages(userUuid: userUuid);
      _storages = raw
          .cast<Map<String, dynamic>>()
          .map(Storage.fromJson)
          .toList();
      // text text file text storagetext text selection; 0translated text null keep
      _currentStorage = _storages.isNotEmpty
          ? (_storages.firstWhere((s) => s.isDefault, orElse: () => _storages.first))
          : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// account text/logout text storage state text initialize (T074).
  void reset() {
    _storages = [];
    _currentStorage = null;
    _error = null;
    notifyListeners();
  }

  /// storage text — text file translated text FileProvidertext text initializetext.
  void selectStorage(Storage storage) {
    if (_currentStorage?.storageUuid == storage.storageUuid) return;
    _currentStorage = storage;
    notifyListeners();
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/storage.dart';
import '../services/storage_service.dart';

/// L001 § 3-2 — 스토리지 목록 및 현재 선택 상태 관리
/// L002 ST-02:
///   - storages 0개일 때 파일 목록 호출 금지 (호출부에서 currentStorage null 확인)
///   - 스토리지 전환 시 이전 캐시 데이터는 FileProvider가 초기화
class StorageProvider extends ChangeNotifier {
  // ── 상태 ────────────────────────────────────────────────────────────────────
  List<Storage> _storages = [];
  Storage? _currentStorage;
  bool _isLoading = false;
  String? _error;

  // ── 서비스 ────────────────────────────────────────────────────────────────
  late final StorageService _storageService;

  StorageProvider(Dio dio) {
    _storageService = StorageService(dio);
  }

  // ── 읽기 전용 ────────────────────────────────────────────────────────────
  List<Storage> get storages => _storages;
  Storage? get currentStorage => _currentStorage;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── 메서드 ────────────────────────────────────────────────────────────────

  /// GET /storages/get_user_storages
  /// 성공 시 첫 번째 스토리지를 자동 선택한다 (L002 ST-02 Row1).
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
      // 첫 번째 file 타입 스토리지를 자동 선택; 0개이면 null 유지
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

  /// 계정 전환/로그아웃 시 스토리지 상태 전체 초기화 (T074).
  void reset() {
    _storages = [];
    _currentStorage = null;
    _error = null;
    notifyListeners();
  }

  /// 스토리지 전환 — 이전 파일 목록은 FileProvider가 별도 초기화한다.
  void selectStorage(Storage storage) {
    if (_currentStorage?.storageUuid == storage.storageUuid) return;
    _currentStorage = storage;
    notifyListeners();
  }
}

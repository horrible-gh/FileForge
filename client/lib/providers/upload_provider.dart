import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/upload_item.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

/// L003 — 업로드 큐/병렬 업로드/패널 상태 관리
class UploadProvider extends ChangeNotifier {
  static const int maxConcurrent = 2;
  static const String _tag = 'UploadProvider';

  final StorageService _storageService;

  final List<UploadItem> _items = [];
  bool _isPanelExpanded = false;

  /// 업로드 완료 시 호출할 콜백 (FileProvider.loadChildren 연결)
  VoidCallback? onUploadComplete;

  UploadProvider(Dio dio) : _storageService = StorageService(dio);

  // ── 읽기 전용 ─────────────────────────────────────────────────────────────
  List<UploadItem> get items => List.unmodifiable(_items);
  bool get isPanelExpanded => _isPanelExpanded;
  bool get hasItems => _items.isNotEmpty;

  int get uploadingCount =>
      _items.where((i) => i.status == UploadStatus.uploading).length;
  int get pendingCount =>
      _items.where((i) => i.status == UploadStatus.pending).length;
  int get completedCount =>
      _items.where((i) => i.status == UploadStatus.completed).length;
  int get errorCount =>
      _items.where((i) => i.status == UploadStatus.error).length;

  /// 모든 항목이 completed 또는 error → "전체 삭제" 활성
  bool get canClearAll =>
      _items.isNotEmpty &&
      _items.every(
          (i) => i.status == UploadStatus.completed || i.status == UploadStatus.error);

  // ── 큐 추가 (L003 ST-L3-01 #1) ──────────────────────────────────────────

  void addFiles({
    required List<MapEntry<String, List<int>>> files,
    required String storageUuid,
    required String parentUuid,
    required String userUuid,
    required String groupUuid,
    Map<String, String>? relativePathMap,
  }) {
    int added = 0;
    for (final entry in files) {
      final filename = entry.key;
      // uploading 중인 동일 파일명 재추가 금지
      final isDuplicate = _items.any(
        (i) => i.filename == filename && i.status == UploadStatus.uploading,
      );
      if (isDuplicate) {
        AppLogger.warn(_tag, '중복 파일 건너뜀: $filename');
        continue;
      }

      final item = UploadItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_$added',
        filename: filename,
        fileBytes: entry.value,
        storageUuid: storageUuid,
        parentUuid: parentUuid,
        userUuid: userUuid,
        groupUuid: groupUuid,
        relativePath: relativePathMap?[filename] ?? '',
      );
      _items.add(item);
      added++;
    }

    if (added > 0) {
      _isPanelExpanded = true;
      notifyListeners();
      _processQueue();
    }
  }

  // ── 큐 소비 루프 (L003 ST-L3-02) ────────────────────────────────────────

  void _processQueue() {
    while (uploadingCount < maxConcurrent) {
      final next = _items
          .where((i) => i.status == UploadStatus.pending)
          .firstOrNull;
      if (next == null) break;
      _startUpload(item: next);
    }
  }

  // ── 개별 업로드 시작 (L003 ST-L3-01 #2~#7) ──────────────────────────────

  Future<void> _startUpload({required UploadItem item}) async {
    item.status = UploadStatus.uploading;
    item.cancelToken = CancelToken();
    notifyListeners();

    try {
      await _storageService.upload(
        storageUuid: item.storageUuid,
        parentUuid: item.parentUuid,
        userUuid: item.userUuid,
        groupUuid: item.groupUuid,
        filename: item.filename,
        fileBytes: item.fileBytes,
        relativePath: item.relativePath,
        cancelToken: item.cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) {
            final newProgress = sent / total;
            if (newProgress >= item.progress) {
              item.progress = newProgress;
              notifyListeners();
            }
          }
        },
      );

      // 성공 (L003 ST-L3-01 #5)
      item.status = UploadStatus.completed;
      item.progress = 1.0;
      AppLogger.info(_tag, '업로드 완료: ${item.filename}');
      notifyListeners();
      if (pendingCount == 0 && uploadingCount == 0) {
        onUploadComplete?.call();
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // 취소 → 이미 removeItem에서 처리됨
        return;
      }
      final statusCode = e.response?.statusCode;
      if (statusCode == 413) {
        item.status = UploadStatus.error;
        item.errorMessage = 'Insufficient storage space';
        AppLogger.warn(_tag, 'HTTP 413: ${item.filename}');
      } else {
        item.status = UploadStatus.error;
        item.errorMessage = 'Upload failed';
        AppLogger.error(_tag, '업로드 실패: ${item.filename} ($statusCode)');
      }
      notifyListeners();
    } catch (e) {
      item.status = UploadStatus.error;
      item.errorMessage = 'Upload failed';
      AppLogger.error(_tag, '업로드 예외: ${item.filename} $e');
      notifyListeners();
    }

    // 큐 재개 (L003 ST-L3-01 #5~#7)
    _processQueue();
  }

  // ── 항목 제거 (L003 ST-L3-01 #8~#9) ─────────────────────────────────────

  void removeItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.status == UploadStatus.uploading) {
      item.cancelToken?.cancel('사용자 취소');
    }
    _items.removeAt(idx);
    notifyListeners();
    _processQueue();
  }

  // ── 완료/에러 항목 일괄 제거 (L003 ST-L3-01 #10) ────────────────────────

  void clearCompleted() {
    _items.removeWhere(
      (i) => i.status == UploadStatus.completed || i.status == UploadStatus.error,
    );
    if (_items.isEmpty) _isPanelExpanded = false;
    notifyListeners();
  }

  // ── 패널 토글 (L003 ST-L3-01 #11) ───────────────────────────────────────

  void togglePanel() {
    _isPanelExpanded = !_isPanelExpanded;
    notifyListeners();
  }
}

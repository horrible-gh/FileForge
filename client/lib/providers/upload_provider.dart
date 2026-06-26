import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/upload_item.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

/// L003 — upload text/text upload/text state management
class UploadProvider extends ChangeNotifier {
  static const int maxConcurrent = 2;
  static const String _tag = 'UploadProvider';

  final StorageService _storageService;

  final List<UploadItem> _items = [];
  bool _isPanelExpanded = false;

  /// upload complete text translated text text (FileProvider.loadChildren text)
  VoidCallback? onUploadComplete;

  UploadProvider(Dio dio) : _storageService = StorageService(dio);

  // ── read-only ─────────────────────────────────────────────────────────────
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

  /// all translated text completed text error → "text delete" text
  bool get canClearAll =>
      _items.isNotEmpty &&
      _items.every(
          (i) => i.status == UploadStatus.completed || i.status == UploadStatus.error);

  // ── text add (L003 ST-L3-01 #1) ──────────────────────────────────────────

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
      // uploading text text filetext textadd prohibited
      final isDuplicate = _items.any(
        (i) => i.filename == filename && i.status == UploadStatus.uploading,
      );
      if (isDuplicate) {
        AppLogger.warn(_tag, 'text file translated text: $filename');
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

  // ── text text text (L003 ST-L3-02) ────────────────────────────────────────

  void _processQueue() {
    while (uploadingCount < maxConcurrent) {
      final next = _items
          .where((i) => i.status == UploadStatus.pending)
          .firstOrNull;
      if (next == null) break;
      _startUpload(item: next);
    }
  }

  // ── text upload text (L003 ST-L3-01 #2~#7) ──────────────────────────────

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

      // success (L003 ST-L3-01 #5)
      item.status = UploadStatus.completed;
      item.progress = 1.0;
      AppLogger.info(_tag, 'upload complete: ${item.filename}');
      notifyListeners();
      if (pendingCount == 0 && uploadingCount == 0) {
        onUploadComplete?.call();
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // cancel → text removeItemtext translated text
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
        AppLogger.error(_tag, 'upload failed: ${item.filename} ($statusCode)');
      }
      notifyListeners();
    } catch (e) {
      item.status = UploadStatus.error;
      item.errorMessage = 'Upload failed';
      AppLogger.error(_tag, 'upload exampletext: ${item.filename} $e');
      notifyListeners();
    }

    // text text (L003 ST-L3-01 #5~#7)
    _processQueue();
  }

  // ── text text (L003 ST-L3-01 #8~#9) ─────────────────────────────────────

  void removeItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final item = _items[idx];
    if (item.status == UploadStatus.uploading) {
      item.cancelToken?.cancel('translated text cancel');
    }
    _items.removeAt(idx);
    notifyListeners();
    _processQueue();
  }

  // ── complete/error text text text (L003 ST-L3-01 #10) ────────────────────────

  void clearCompleted() {
    _items.removeWhere(
      (i) => i.status == UploadStatus.completed || i.status == UploadStatus.error,
    );
    if (_items.isEmpty) _isPanelExpanded = false;
    notifyListeners();
  }

  // ── text text (L003 ST-L3-01 #11) ───────────────────────────────────────

  void togglePanel() {
    _isPanelExpanded = !_isPanelExpanded;
    notifyListeners();
  }
}

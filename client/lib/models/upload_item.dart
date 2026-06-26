import 'package:dio/dio.dart';

/// upload text state
enum UploadStatus { pending, uploading, completed, error }

/// L003 ST-L3-01 — upload text text text
/// filetext upload translated text(storageUuid text)text text translated text preservedtext
/// text add text text pending translated text translated text translated text translated text text.
class UploadItem {
  final String id;
  final String filename;
  final List<int> fileBytes;

  // translated text upload translated text
  final String storageUuid;
  final String parentUuid;
  final String userUuid;
  final String groupUuid;
  final String relativePath;

  UploadStatus status;
  double progress;
  String? errorMessage;
  CancelToken? cancelToken;

  UploadItem({
    required this.id,
    required this.filename,
    required this.fileBytes,
    required this.storageUuid,
    required this.parentUuid,
    required this.userUuid,
    required this.groupUuid,
    this.relativePath = '',
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.cancelToken,
  });
}

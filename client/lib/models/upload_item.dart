import 'package:dio/dio.dart';

/// 업로드 항목 상태
enum UploadStatus { pending, uploading, completed, error }

/// L003 ST-L3-01 — 업로드 큐 항목 모델
/// 파일별 업로드 컨텍스트(storageUuid 등)를 항목 자체에 보존해
/// 배치 추가 시 기존 pending 항목의 컨텍스트가 덮어쓰이지 않도록 한다.
class UploadItem {
  final String id;
  final String filename;
  final List<int> fileBytes;

  // 항목별 업로드 컨텍스트
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

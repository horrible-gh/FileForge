import 'package:dio/dio.dart';

/// 스토리지/파일 API 래퍼 — P003/P004 프로토콜 기준
/// 인증 토큰은 ApiClient 인터셉터에 의존한다.
class StorageService {
  final Dio _dio;

  StorageService(this._dio);

  /// GET /storages/get_user_storages
  /// 반환: 스토리지 배열 (raw JSON List)
  Future<List<dynamic>> getUserStorages({
    required String userUuid,
    String? groupUuid,
  }) async {
    final response = await _dio.get(
      '/storages/get_user_storages',
      queryParameters: {
        'user_uuid': userUuid,
        'group_uuid': groupUuid,
      },
    );
    return response.data as List<dynamic>;
  }

  /// GET /storages/get_directory_trees
  /// 반환: { "storage_uuid": ..., "tree": [...] }
  Future<Map<String, dynamic>> getDirectoryTrees({
    required String storageUuid,
    required String userUuid,
  }) async {
    final response = await _dio.get(
      '/storages/get_directory_trees',
      queryParameters: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// GET /storages/get_node_children
  /// 반환: { "storage_uuid": ..., "current_node": ..., "breadcrumb_path": [...], "children": [...] }
  /// search가 빈 문자열이면 전송하지 않는다 (L002 ST-02 Row7).
  Future<Map<String, dynamic>> getNodeChildren({
    required String storageUuid,
    required String userUuid,
    String? nodeUuid,
    String? search,
  }) async {
    final response = await _dio.get(
      '/storages/get_node_children',
      queryParameters: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
        if (nodeUuid != null && nodeUuid.isNotEmpty) 'node_uuid': nodeUuid,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // ── Phase 4 파일 조작 API ─────────────────────────────────────────────────

  /// POST /storages/upload (multipart/form-data)
  /// [onSendProgress] dio의 진행률 콜백.
  /// [cancelToken] 업로드 취소용.
  Future<Map<String, dynamic>> upload({
    required String storageUuid,
    required String parentUuid,
    required String userUuid,
    required String groupUuid,
    required String filename,
    required List<int> fileBytes,
    String relativePath = '',
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'storage_uuid': storageUuid,
      'parent_uuid': parentUuid,
      'user_uuid': userUuid,
      'group_uuid': groupUuid,
      'relative_path': relativePath,
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final response = await _dio.post(
      '/storages/upload',
      data: formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return response.data as Map<String, dynamic>;
  }

  /// GET /storages/download — 단일 파일/폴더 다운로드 (바이너리)
  Future<Response<List<int>>> download({
    required String storageUuid,
    required String userUuid,
    required String groupUuid,
    required String nodeUuid,
  }) async {
    return _dio.get<List<int>>(
      '/storages/download',
      queryParameters: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
        'group_uuid': groupUuid,
        'node_uuid': nodeUuid,
      },
      options: Options(responseType: ResponseType.bytes),
    );
  }

  /// POST /storages/create_folder
  Future<Map<String, dynamic>> createFolder({
    required String storageUuid,
    required String userUuid,
    required String? nodeUuid,
    required String folderName,
  }) async {
    final response = await _dio.post(
      '/storages/create_folder',
      data: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
        'node_uuid': nodeUuid,
        'folder_name': folderName,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// PUT /storages/rename
  Future<Map<String, dynamic>> renameNode({
    required String storageUuid,
    required String userUuid,
    required String groupUuid,
    required String nodeUuid,
    required String newName,
  }) async {
    final response = await _dio.put(
      '/storages/rename',
      data: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
        'group_uuid': groupUuid,
        'node_uuid': nodeUuid,
        'new_name': newName,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// DELETE /storages/delete
  Future<Map<String, dynamic>> deleteNode({
    required String storageUuid,
    required String userUuid,
    required String groupUuid,
    required String nodeUuid,
  }) async {
    final response = await _dio.delete(
      '/storages/delete',
      queryParameters: {
        'storage_uuid': storageUuid,
        'user_uuid': userUuid,
        'group_uuid': groupUuid,
        'node_uuid': nodeUuid,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// POST /storages/bulk/download — 벌크 ZIP 다운로드
  Future<Response<List<int>>> bulkDownload({
    required List<String> nodeUuids,
  }) async {
    return _dio.post<List<int>>(
      '/storages/bulk/download',
      data: {'node_uuids': nodeUuids},
      options: Options(responseType: ResponseType.bytes),
    );
  }

  /// POST /storages/bulk/delete — 벌크 삭제
  Future<Map<String, dynamic>> bulkDelete({
    required List<String> nodeUuids,
  }) async {
    final response = await _dio.post(
      '/storages/bulk/delete',
      data: {'node_uuids': nodeUuids},
    );
    return response.data as Map<String, dynamic>;
  }
}

import 'package:dio/dio.dart';

/// storage/file API text — P003/P004 translated text text
/// authentication tokentext ApiClient translated text translated text.
class StorageService {
  final Dio _dio;

  StorageService(this._dio);

  /// GET /storages/get_user_storages
  /// return: storage text (raw JSON List)
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
  /// return: { "storage_uuid": ..., "tree": [...] }
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
  /// return: { "storage_uuid": ..., "current_node": ..., "breadcrumb_path": [...], "children": [...] }
  /// searchtext empty stringtext translated text translated text (L002 ST-02 Row7).
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

  // ── Phase 4 file text API ─────────────────────────────────────────────────

  /// POST /storages/upload (multipart/form-data)
  /// [onSendProgress] diotext translated text text.
  /// [cancelToken] upload canceltext.
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

  /// GET /storages/download — text file/folder download (translated text)
  ///
  /// [onReceiveProgress] surfaces transfer progress so callers can show an
  /// in-flight indicator (fileforge.ui.0002 "고스트 다운로드"). `count`/`total`
  /// follow Dio's convention; `total` is -1 when the server omits
  /// Content-Length.
  Future<Response<List<int>>> download({
    required String storageUuid,
    required String userUuid,
    required String groupUuid,
    required String nodeUuid,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
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
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
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

  /// POST /storages/bulk/download — text ZIP download
  Future<Response<List<int>>> bulkDownload({
    required List<String> nodeUuids,
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    return _dio.post<List<int>>(
      '/storages/bulk/download',
      data: {'node_uuids': nodeUuids},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  /// POST /storages/bulk/delete — text delete
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

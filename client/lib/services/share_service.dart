import 'package:dio/dio.dart';

/// D004 Phase 5 — text text API text
/// authentication tokentext ApiClient translated text translated text.
class ShareService {
  final Dio _dio;

  ShareService(this._dio);

  /// POST /share/create
  /// return: createtext text text text JSON (Map)
  Future<Map<String, dynamic>> createLink(
    String nodeUuid,
    String nodeType, [
    String? password,
  ]) async {
    final body = <String, dynamic>{
      'node_uuid': nodeUuid,
      'node_type': nodeType,
    };
    if (password != null) body['password'] = password;
    final response = await _dio.post('/share/create', data: body);
    return response.data as Map<String, dynamic>;
  }

  /// GET /share/list
  /// return: text text text (raw JSON List)
  Future<List<dynamic>> fetchList() async {
    final response = await _dio.get('/share/list');
    return response.data as List<dynamic>;
  }

  /// DELETE /share/{token}
  /// return: delete text JSON (Map)
  Future<Map<String, dynamic>> deleteLink(String token) async {
    final response = await _dio.delete('/share/$token');
    return response.data as Map<String, dynamic>;
  }
}

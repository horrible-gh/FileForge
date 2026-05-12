import 'package:dio/dio.dart';

/// D004 Phase 5 — 공유 링크 API 래퍼
/// 인증 토큰은 ApiClient 인터셉터에 의존한다.
class ShareService {
  final Dio _dio;

  ShareService(this._dio);

  /// POST /share/create
  /// 반환: 생성된 공유 링크 응답 JSON (Map)
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
  /// 반환: 공유 링크 배열 (raw JSON List)
  Future<List<dynamic>> fetchList() async {
    final response = await _dio.get('/share/list');
    return response.data as List<dynamic>;
  }

  /// DELETE /share/{token}
  /// 반환: 삭제 응답 JSON (Map)
  Future<Map<String, dynamic>> deleteLink(String token) async {
    final response = await _dio.delete('/share/$token');
    return response.data as Map<String, dynamic>;
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/share_link.dart';
import '../services/share_service.dart';

/// D004 Phase 5 — 공유 링크 목록/생성/삭제 상태 관리
class ShareLinkProvider extends ChangeNotifier {
  // ── 상태 ────────────────────────────────────────────────────────────────────
  List<ShareLink> _links = [];
  bool _isLoading = false;
  String? _error;

  // ── 서비스 ────────────────────────────────────────────────────────────────
  late final ShareService _shareService;

  ShareLinkProvider(Dio dio) {
    _shareService = ShareService(dio);
  }

  // ── 읽기 전용 ────────────────────────────────────────────────────────────
  List<ShareLink> get links => _links;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── 메서드 ────────────────────────────────────────────────────────────────

  /// GET /share/list
  /// 서버 목록 응답을 ShareLink 모델 리스트로 갱신한다.
  Future<void> fetchList() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _shareService.fetchList();
      _links = raw
          .cast<Map<String, dynamic>>()
          .map(ShareLink.fromJson)
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// POST /share/create
  /// P005 기준 응답: { "token": "...", "url": "..." }
  /// 생성 응답을 그대로 반환하고, 후속 UI가 즉시 사용할 수 있게 한다.
  /// 목록 갱신은 호출부에서 필요 시 fetchList()로 수행한다.
  Future<Map<String, dynamic>?> createLink(
    String nodeUuid,
    String nodeType, [
    String? password,
  ]) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await _shareService.createLink(nodeUuid, nodeType, password);
      return raw;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// DELETE /share/{token}
  /// 성공 시 links에서 해당 토큰 항목을 제거한다.
  Future<void> deleteLink(String token) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _shareService.deleteLink(token);
      _links = _links.where((l) => l.token != token).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

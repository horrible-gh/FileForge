import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/share_link.dart';
import '../services/share_service.dart';

/// D004 Phase 5 — text text text/create/delete state management
class ShareLinkProvider extends ChangeNotifier {
  // ── state ────────────────────────────────────────────────────────────────────
  List<ShareLink> _links = [];
  bool _isLoading = false;
  String? _error;

  // ── translated text ────────────────────────────────────────────────────────────────
  late final ShareService _shareService;

  ShareLinkProvider(Dio dio) {
    _shareService = ShareService(dio);
  }

  // ── read-only ────────────────────────────────────────────────────────────
  List<ShareLink> get links => _links;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── translated text ────────────────────────────────────────────────────────────────

  /// GET /share/list
  /// server text translated text ShareLink text translated text refreshtext.
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
  /// P005 text text: { "token": "...", "url": "..." }
  /// create translated text as-is returntext, text UItext text translated text text text text.
  /// text refreshtext translated text text text fetchList()text translated text.
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
  /// success text linkstext text token translated text translated text.
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

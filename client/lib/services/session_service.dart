import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/user_session.dart';

/// Header carrying the device name to the server at login.
///
/// The server prefers this over parsing the User-Agent, which on a native app
/// says nothing useful about the device (D0003 §3.1, server session_store.describe_request).
const String deviceNameHeader = 'X-Device-Name';

/// A device name for the session list, derived without adding a dependency.
///
/// `device_info_plus` is not in pubspec (NR0005 F14) and pulling it in for one
/// string is not worth it: `defaultTargetPlatform` already distinguishes the
/// platforms the session list needs to tell apart, and unlike `dart:io.Platform`
/// it also compiles for web. The label is intentionally ASCII — it travels as an
/// HTTP header value.
String currentDeviceLabel() {
  if (kIsWeb) return 'Web browser';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android device';
    case TargetPlatform.iOS:
      return 'iPhone / iPad';
    case TargetPlatform.windows:
      return 'Windows PC';
    case TargetPlatform.macOS:
      return 'Mac';
    case TargetPlatform.linux:
      return 'Linux PC';
    case TargetPlatform.fuchsia:
      return 'Fuchsia device';
  }
}

/// Session management API (server routers/login/sessions.py, T2).
///
/// Mirrors [TotpService]: constructed from `authProvider.dio` so it inherits the
/// Bearer token and the shared 401/refresh interceptor.
class SessionService {
  final Dio _dio;

  SessionService(this._dio);

  Future<SessionListResult> list() async {
    final response = await _dio.get('/auth/sessions');
    return SessionListResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// End one session. Returns true when it was the caller's own — the caller is
  /// then already signed out server-side and must go back to the login screen.
  Future<bool> revoke(String sid) async {
    final response = await _dio.delete('/auth/sessions/$sid');
    final data = response.data as Map<String, dynamic>;
    return data['was_current'] == true;
  }

  /// End every session but this one. Returns how many were ended.
  Future<int> revokeOthers() async {
    final response = await _dio.post('/auth/sessions/revoke-others');
    final data = response.data as Map<String, dynamic>;
    return (data['revoked'] as num?)?.toInt() ?? 0;
  }
}

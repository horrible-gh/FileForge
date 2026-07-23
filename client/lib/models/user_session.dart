/// One signed-in device, as returned by GET /auth/sessions
/// (server routers/login/sessions.py — fileforge.default.0004 T2).
class UserSession {
  /// Session id. Also the path segment for DELETE /auth/sessions/{sid}.
  final String sid;

  /// Device name the client sent at login (X-Device-Name), or the server's
  /// User-Agent guess when it did not.
  final String deviceLabel;

  /// Raw User-Agent of the login. Shown only as a secondary line.
  final String clientType;

  /// Address the login came from. Displayed as-is: turning it into a place name
  /// is deferred (D0003 [DEFERRED]).
  final String ipDisplay;

  final DateTime createdAt;
  final DateTime lastUsedAt;

  /// True for the session making the request — it gets a badge instead of a
  /// terminate button (D0003 §8).
  final bool isCurrent;

  const UserSession({
    required this.sid,
    required this.deviceLabel,
    required this.clientType,
    required this.ipDisplay,
    required this.createdAt,
    required this.lastUsedAt,
    required this.isCurrent,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    DateTime fromEpoch(Object? value) => DateTime.fromMillisecondsSinceEpoch(
          ((value as num?)?.toInt() ?? 0) * 1000,
        );

    return UserSession(
      sid: json['sid'] as String? ?? '',
      deviceLabel: json['device_label'] as String? ?? '',
      clientType: json['client_type'] as String? ?? '',
      ipDisplay: json['ip_display'] as String? ?? '',
      createdAt: fromEpoch(json['created_at']),
      lastUsedAt: fromEpoch(json['last_used_at']),
      isCurrent: json['is_current'] == true,
    );
  }
}

/// Result of GET /auth/sessions.
class SessionListResult {
  final List<UserSession> sessions;

  /// True when the caller's token predates multi-session support, so the server
  /// cannot say which session it belongs to. The screen shows the "sign in again
  /// to see your devices" notice instead of an empty list (D0003 §6/§8).
  final bool sessionUnavailable;

  const SessionListResult({
    required this.sessions,
    required this.sessionUnavailable,
  });

  factory SessionListResult.fromJson(Map<String, dynamic> json) {
    final raw = json['sessions'] as List<dynamic>? ?? const [];
    return SessionListResult(
      sessions: raw
          .map((e) => UserSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      sessionUnavailable: json['session_unavailable'] == true,
    );
  }
}

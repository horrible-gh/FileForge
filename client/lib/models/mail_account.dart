/// 메일 계정(M) 모델 — P0007 §3.6 Account 와이어 형태.
///
/// 흡수 아키텍처에서 메일 계정은 FileForge 사용자에 종속된 외부 메일함
/// 연결(OAuth/IMAP)이다. 식별자는 서버 발급 불투명 문자열, 시각은 ISO-8601.
library;

/// 서버가 허용하는 provider 화이트리스트(accounts.go `validProvider`와 일치).
/// 클라 provider 선택지를 이 목록과 동기화해 ValidationFailed(field=provider)를
/// 미연에 방지한다.
const List<String> kMailProviders = ['gmail', 'outlook', 'imap'];

/// OAuth 동의(브라우저) 흐름을 지원하는 provider — 서버 accounts.go
/// `oauthAuthProvider` 와 일치. imap 은 비밀번호 기반이라 동의 URL 이 없다.
/// 이 집합의 provider 는 "코드 붙여넣기" 대신 브라우저 로그인으로 연결한다.
const Set<String> kOAuthProviders = {'gmail', 'outlook'};

/// P0007 §3.6 — 연결된 메일 계정.
class MailAccount {
  final String accountId;
  final String email;
  final String provider;

  /// "connected" 등 서버 상태 문자열(P0007 §3.6).
  final String status;
  final String connectedAt;

  const MailAccount({
    required this.accountId,
    required this.email,
    required this.provider,
    this.status = 'connected',
    this.connectedAt = '',
  });

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      accountId: json['account_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      status: json['status'] as String? ?? '',
      connectedAt: json['connected_at'] as String? ?? '',
    );
  }

  bool get isConnected => status == 'connected';
}

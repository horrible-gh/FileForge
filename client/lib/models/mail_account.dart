/// text account(M) text — P0007 §3.6 Account translated text text.
///
/// merge translated text text accounttext FileForge translated text translated text text translated text
/// text(OAuth/IMAP)text. translated text server issue translated text string, translated text ISO-8601.
library;

/// servertext allowedtext provider translated text(accounts.go `validProvider`text text).
/// text provider choicestext text translated text synctext ValidationFailed(field=provider)text
/// translated text translated text.
const List<String> kMailProviders = ['gmail', 'outlook', 'imap'];

/// OAuth text(browser) translated text translated text provider — server accounts.go
/// `oauthAuthProvider` text text. imap text password translated text consent URL text text.
/// text translated text provider text "text translated text" text browser logintext translated text.
const Set<String> kOAuthProviders = {'gmail', 'outlook'};

/// P0007 §3.6 — translated text text account.
class MailAccount {
  final String accountId;
  final String email;
  final String provider;

  /// "connected" text server state string(P0007 §3.6).
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

  /// State the server assigns when OAuth credentials are lost (0018.0009-TR). This
  /// account must be re-connected (re-authenticated) via OAuth before sending/receiving mail.
  bool get needsReauth => status == 'reauth_required';
}

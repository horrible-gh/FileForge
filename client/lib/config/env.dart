import 'package:flutter/foundation.dart';

/// build Environment variables — --dart-define-from-file text translated text text translated text.
/// text text translated text app_config.dart text text.
class Env {
  /// translated text SERVER_URL(translated text text empty string). translated text as-is uses.
  static const String _serverUrlOverride = String.fromEnvironment('SERVER_URL');

  /// translated text MAIL_SERVER_URL(translated text text empty string).
  static const String _mailServerUrlOverride = String.fromEnvironment(
    'MAIL_SERVER_URL',
  );

  /// translated text default valuetext translated text.
  ///
  /// `10.0.2.2` text **translated text translated text text** text(translated text→translated text loopback)text
  /// text/translated text/iOS runtimetranslated text translated text translated text. text runtimetext text text translated text text
  /// `net::ERR_CONNECTION_TIMED_OUT` text all translated text translated text(R0001 textsymptomtext
  /// text translated text: text buildtext `10.0.2.2:8000/fileforge/mail/accounts` translated text).
  /// translated text translated text(text-text)text `10.0.2.2`, text text(text·translated text·iOS)text `localhost` text translated text.
  /// `--dart-define` text text translated text text text translated text.
  static String get _defaultHost {
    if (kIsWeb) return 'localhost';
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
  }

  /// file API base URL. build text --dart-define=SERVER_URL=https://... text
  /// --dart-define-from-file=config/dev.json text text.
  /// translated text path(/fileforge)text translated text API base URL translated text translated text (T077).
  static String get serverUrl => _serverUrlOverride.isNotEmpty
      ? _serverUrlOverride
      : 'http://$_defaultHost:8000/fileforge';

  /// Mail subsystem base URL (NR0003 / 0002 group).
  ///
  /// The legacy standalone MailAnchor (Go, `:8090/api/v1`) has been absorbed into
  /// the FileForge FastAPI server: the mail routes now live at
  /// `:8000/fileforge/mail/*` on the SAME origin as the file API. There is no
  /// separate `:8090` process anymore. The client's mail Dio uses this value as
  /// `baseUrl` and appends `/accounts`, `/sync`, `/mails`, `/drafts`, ... which
  /// resolve onto `:8000/fileforge/mail/...`.
  ///
  /// Override at build time with `--dart-define=MAIL_SERVER_URL=...` or
  /// `--dart-define-from-file=config/dev.json`; an empty override falls back to
  /// the default below.
  static String get mailServerUrl => _mailServerUrlOverride.isNotEmpty
      ? _mailServerUrlOverride
      : 'http://$_defaultHost:8000/fileforge/mail';

  /// text text text: debug | info | warn | error
  static const String logLevel = String.fromEnvironment(
    'LOG_LEVEL',
    defaultValue: 'debug',
  );

  /// text text base URL — /share/{token} firsttext text text.
  /// build text SHARE_BASE_URL text text. translated text text text default value text.
  static const String shareBaseUrl = String.fromEnvironment(
    'SHARE_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// text text text (release translated text false text text)
  static const bool logConsole = bool.fromEnvironment(
    'LOG_CONSOLE',
    defaultValue: true,
  );

  /// file text text
  static const bool logFile = bool.fromEnvironment(
    'LOG_FILE',
    defaultValue: true,
  );
}

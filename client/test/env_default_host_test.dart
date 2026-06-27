import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/config/env.dart';

/// R0001 textsymptom regressionguard: translated text text base URL text translated text runtimetext text translated text.
///
/// `10.0.2.2` text translated text translated text text translated text text/translated text/iOS text translated text text
/// (`net::ERR_CONNECTION_TIMED_OUT`). text translated text `MAIL_SERVER_URL`/`SERVER_URL` text
/// translated text text state(translated text text dart-define None)text host translated text verifytext.
///
/// VM translated text `kIsWeb` text textfiletext false text text branchtext text translated text text translated text,
/// text text-translated text translated text `localhost` text translated text "translated text 10.0.2.2, text text localhost"
/// text core invarianttext text text branchtext translated text.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Env translated text text host text', () {
    test('translated text(text-text): translated text text 10.0.2.2 keep', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // NR0003: mail subsystem absorbed into FileForge FastAPI (:8000/fileforge/mail);
      // no separate Go MailAnchor (:8090) anymore.
      expect(Env.mailServerUrl, 'http://10.0.2.2:8000/fileforge/mail');
      expect(Env.serverUrl, 'http://10.0.2.2:8000/fileforge');
    });

    test('iOS: translated text translated text 10.0.2.2 text localhost text text', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(Env.mailServerUrl, 'http://localhost:8000/fileforge/mail');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('translated text(example: macOS): localhost text text', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl, 'http://localhost:8000/fileforge/mail');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('text runtimetranslated text default valuetext translated text translated text translated text translated text text', () {
      // text-translated text runtimetext default valuetext 10.0.2.2 text translated text translated text text.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl.contains('10.0.2.2'), isFalse);
      expect(Env.serverUrl.contains('10.0.2.2'), isFalse);
    });

    test('NR0003 regressionguard: mail base is the absorbed :8000/fileforge/mail, never the dead :8090//api/v1', () {
      // After absorption the mail subsystem lives on the FileForge origin
      // (:8000/fileforge/mail). The legacy standalone Go server (:8090) and its
      // /api/v1 prefix no longer exist; pointing there yields connection
      // failures / 404 (the original D1 symptom).
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(Env.mailServerUrl.contains(':8090'), isFalse,
            reason: '$platform: the standalone :8090 server was absorbed');
        expect(Env.mailServerUrl.contains('/api/v1'), isFalse,
            reason: '$platform: the legacy /api/v1 prefix is gone (now /fileforge/mail)');
        expect(Env.mailServerUrl.endsWith(':8000/fileforge/mail'), isTrue);
      }
    });
  });
}

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
      // text translated text Go MailAnchor(:8090), file translated text Python FileForge(:8000).
      expect(Env.mailServerUrl, 'http://10.0.2.2:8090/api/v1');
      expect(Env.serverUrl, 'http://10.0.2.2:8000/fileforge');
    });

    test('iOS: translated text translated text 10.0.2.2 text localhost text text', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(Env.mailServerUrl, 'http://localhost:8090/api/v1');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('translated text(example: macOS): localhost text text', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl, 'http://localhost:8090/api/v1');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('text runtimetranslated text default valuetext translated text translated text translated text translated text text', () {
      // text-translated text runtimetext default valuetext 10.0.2.2 text translated text translated text text.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl.contains('10.0.2.2'), isFalse);
      expect(Env.serverUrl.contains('10.0.2.2'), isFalse);
    });

    test('T0008 regressionguard: text translated text translated text Python :8000(translated text 404) text translated text text', () {
      // R0001/T0008 symptom: text text text buildtext `:8000/api/v1/...` text 404.
      // text translated text text runtimetranslated text :8000 text translated text Go MailAnchor :8090 translated text text.
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(Env.mailServerUrl.contains(':8000'), isFalse,
            reason: '$platform: text translated text Python :8000 text translated text /api/v1 translated text 404');
        expect(Env.mailServerUrl.endsWith(':8090/api/v1'), isTrue);
      }
    });
  });
}

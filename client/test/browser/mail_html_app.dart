// Browser integration entry point. Uses the PRODUCTION detail screen, provider
// contract and MailHtmlBody, not a JavaScript imitation of the Dart bridge.
// No accounts, credentials, mail servers or personal messages are accessed.
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/screens/mail/mail_detail_screen.dart';

@JS('ffSetMailFixture')
external set _setFixture(JSFunction callback);

const fixtureHtml = '''<html><head><style>
.notice { border-collapse:collapse; width:960px; }
.notice td { vertical-align:top; padding:8px; border:1px solid #aaa; }
.step { width:280px; background:#fce9d9; }
</style></head><body style="color:black">
<p id="greeting">申 様 — HTML mail regression fixture</p>
<p>お世話になっております。面談のお時間をいただきありがとうございました。</p>
<p>【選考フロー】</p><p>ご応募</p><p>↓</p><p>書類選考</p><p>↓</p>
<p>オンライン面接（1～2回を予定）</p><p>↓</p><p>ご内定</p>
<table class="notice"><tr><td id="step" class="step" rowspan="2">STEP 1</td>
<td id="instructions"><p>下記リンクよりご応募ください</p>
<p><a id="application" href="https://example.com/apply">応募リンク</a></p>
<p>アカウント作成後、応募書類をご提出ください。</p></td></tr>
<tr><td id="last-cell">履歴書・職務経歴書のご提出が必要です。</td></tr></table>
<p id="end">End of message</p></body></html>''';

class FixtureMailProvider extends MailProvider {
  FixtureMailProvider() : super(Dio());
  String _html = fixtureHtml;

  @override
  Future<void> openMail(String mailId) async {}

  @override
  MailDetail get detail => MailDetail(
        mailId: 'fixture',
        subject: 'Browser regression mail',
        from: const MailAddress(address: 'sender@example.com'),
        receivedAt: '2026-01-01T00:00:00Z',
        body: MailBody(format: 'html', content: _html),
      );

  @override
  bool get detailLoading => false;
  @override
  String? get detailError => null;

  void replaceHtml(String html) {
    _html = html;
    notifyListeners();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = FixtureMailProvider();
  _setFixture = ((JSString html) => provider.replaceHtml(html.toDart)).toJS;
  runApp(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(),
    home: ChangeNotifierProvider<MailProvider>.value(
      value: provider,
      child: const MailDetailScreen(
        mailId: 'fixture',
        subject: 'Browser regression mail',
      ),
    ),
  ));
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/screens/mail/mail_detail_screen.dart';
import 'package:file_forge_app/utils/mail_link_launcher.dart';
import 'package:file_forge_app/utils/mail_text_linkify.dart';
import 'package:file_forge_app/widgets/mail_html_body.dart';

/// R0001 / 0031 (NR0003) — "메일로 온 링크가 단 하나도 눌러지지 않음 … 최소한 누를 수
/// 있게 옵션이라도 주던가". These tests pin the two newly-wired tap paths (HTML
/// `<a href>` via fwfh `onTapUrl`, plain-text URLs via [MailLinkedText]) and the
/// shared guarded launch flow (scheme allow-list + confirm dialog).
class _FixedDetailMailProvider extends MailProvider {
  _FixedDetailMailProvider(this._fixed) : super(Dio());
  final MailDetail _fixed;

  @override
  Future<void> openMail(String mailId) async {}
  @override
  MailDetail? get detail => _fixed;
  @override
  bool get detailLoading => false;
  @override
  String? get detailError => null;
}

void main() {
  // ── Pure unit: scheme allow-list ────────────────────────────────────────────
  group('isOpenableMailLink', () {
    test('allows http/https/mailto only', () {
      expect(isOpenableMailLink('http://example.com'), isTrue);
      expect(isOpenableMailLink('https://example.com/a?b=1'), isTrue);
      expect(isOpenableMailLink('mailto:a@b.com'), isTrue);
      expect(isOpenableMailLink('  https://example.com  '), isTrue);
    });

    test('refuses unsafe / unknown schemes and non-URLs', () {
      expect(isOpenableMailLink('javascript:alert(1)'), isFalse);
      expect(isOpenableMailLink('file:///etc/passwd'), isFalse);
      expect(isOpenableMailLink('data:text/html,<b>x'), isFalse);
      expect(isOpenableMailLink('ftp://host/f'), isFalse);
      expect(isOpenableMailLink('myapp://do'), isFalse);
      expect(isOpenableMailLink('not a url'), isFalse);
      expect(isOpenableMailLink(''), isFalse);
    });
  });

  // ── Pure unit: plain-text linkifier ─────────────────────────────────────────
  group('linkifyPlainText', () {
    test('text with no URL is a single plain run', () {
      final runs = linkifyPlainText('just some words');
      expect(runs.length, 1);
      expect(runs.single.isLink, isFalse);
      expect(runs.single.text, 'just some words');
    });

    test('splits surrounding text from the link and keeps order', () {
      final runs = linkifyPlainText('see https://x.test/p now');
      expect(runs.map((r) => r.isLink).toList(), [false, true, false]);
      expect(runs[0].text, 'see ');
      expect(runs[1].text, 'https://x.test/p');
      expect(runs[1].url, 'https://x.test/p');
      expect(runs[2].text, ' now');
    });

    test('trailing sentence punctuation is not part of the link', () {
      final runs = linkifyPlainText('go to https://x.test/p.');
      final link = runs.firstWhere((r) => r.isLink);
      expect(link.text, 'https://x.test/p');
      expect(runs.last.text, '.');
    });

    test('bare www host is promoted to https', () {
      final runs = linkifyPlainText('visit www.example.com today');
      final link = runs.firstWhere((r) => r.isLink);
      expect(link.text, 'www.example.com');
      expect(link.url, 'https://www.example.com');
    });
  });

  // ── Widget harness ──────────────────────────────────────────────────────────
  Widget l10nHost(Widget child) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  // ── Guarded launch flow (shared by both paths) ──────────────────────────────
  testWidgets('confirmAndOpenMailLink shows a confirm dialog with the URL',
      (tester) async {
    await tester.pumpWidget(l10nHost(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => confirmAndOpenMailLink(context, 'https://example.com/go'),
        child: const Text('tap'),
      ),
    )));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();

    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('https://example.com/go'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel dismisses without launching anything.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open link'), findsNothing);
  });

  testWidgets('confirmAndOpenMailLink refuses an unsafe scheme (toast, no dialog)',
      (tester) async {
    await tester.pumpWidget(l10nHost(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => confirmAndOpenMailLink(context, 'javascript:alert(1)'),
        child: const Text('tap'),
      ),
    )));
    await tester.tap(find.text('tap'));
    await tester.pump(); // toast inserts an overlay entry
    expect(find.text('Open link'), findsNothing);
    expect(find.text("Couldn't open the link"), findsOneWidget);

    // Let the toast's auto-dismiss timer fire so no timer outlives the tree.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // ── HTML path: fwfh onTapUrl wiring (load-bearing) ──────────────────────────
  testWidgets('tapping an HTML <a href> opens the confirm dialog', (tester) async {
    const html = '<body><p>Please <a href="https://example.com/link">click here</a>'
        ' to continue.</p></body>';
    await tester.pumpWidget(l10nHost(
      const SingleChildScrollView(child: MailHtmlBody(html)),
    ));
    await tester.pumpAndSettle();

    // The anchor text renders.
    expect(find.textContaining('click here', findRichText: true), findsOneWidget);

    // Tapping the anchor must reach our onTapUrl → guarded launcher. Without the
    // wiring this dialog never appears (fwfh-core's default is a no-op).
    await tester.tapOnText(find.textRange.ofSubstring('click here'));
    await tester.pumpAndSettle();
    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('https://example.com/link'), findsOneWidget);
  });

  // ── Plain-text path inside the real detail screen ───────────────────────────
  testWidgets('plain-text body URL is tappable and opens the confirm dialog',
      (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(address: 'a@b.com'),
      subject: 'Subj',
      body: const MailBody(
        format: 'text',
        content: 'Reset here: https://example.com/reset thanks',
      ),
    );
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<MailProvider>.value(
        value: _FixedDetailMailProvider(detail),
        child: const MailDetailScreen(mailId: 'm1', subject: 'Subj'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('https://example.com/reset', findRichText: true),
        findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('https://example.com/reset'));
    await tester.pumpAndSettle();
    expect(find.text('Open link'), findsOneWidget);
    expect(find.text('https://example.com/reset'), findsOneWidget);
  });
}

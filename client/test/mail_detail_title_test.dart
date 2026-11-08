import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/screens/mail/mail_detail_screen.dart';

class _Provider extends MailProvider {
  _Provider(this.value) : super(Dio());
  MailDetail? value;
  @override
  Future<void> openMail(String mailId) async {}
  @override
  MailDetail? get detail => value;
  @override
  bool get detailLoading => value == null;
  @override
  String? get detailError => null;
  void show(MailDetail next) {
    value = next;
    notifyListeners();
  }
}

MailDetail mail(String subject, {String id = 'm1'}) => MailDetail(
      mailId: id,
      subject: subject,
      from: const MailAddress(address: 'sender@example.com'),
      body: const MailBody(content: 'Message body'),
    );

Widget harness(_Provider provider, {String subject = ''}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<MailProvider>.value(
        value: provider,
        child: MailDetailScreen(mailId: 'm1', subject: subject),
      ),
    );

void main() {
  testWidgets('subject is displayed once, in the AppBar only', (tester) async {
    await tester.pumpWidget(harness(_Provider(mail('Actual subject')), subject: 'Old summary'));
    await tester.pump();
    expect(find.text('Actual subject'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Actual subject')), findsOneWidget);
    expect(find.descendant(of: find.byType(ListView), matching: find.text('Actual subject')), findsNothing);
    expect(find.text('Old summary'), findsNothing);
    expect(find.text('Message body'), findsOneWidget);
    expect(find.text('sender@example.com'), findsOneWidget);
  });

  testWidgets('loaded subject replaces the temporary route title', (tester) async {
    final provider = _Provider(null);
    await tester.pumpWidget(harness(provider, subject: 'Summary subject'));
    expect(find.text('Summary subject'), findsOneWidget);
    provider.show(mail('Loaded subject'));
    await tester.pump();
    expect(find.text('Summary subject'), findsNothing);
    expect(find.text('Loaded subject'), findsOneWidget);
  });

  testWidgets('empty loaded subject uses localized no-subject title once', (tester) async {
    await tester.pumpWidget(harness(_Provider(mail('  '))));
    await tester.pump();
    final t = AppLocalizations.of(tester.element(find.byType(MailDetailScreen)));
    expect(find.text(t.noSubject), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text(t.noSubject)), findsOneWidget);
  });

  testWidgets('previous mail is not shown while opening another mail', (tester) async {
    final provider = _Provider(mail('Previous mail', id: 'previous'));
    await tester.pumpWidget(harness(provider, subject: 'Current mail'));
    await tester.pump();
    expect(find.text('Previous mail'), findsNothing);
    expect(find.text('Current mail'), findsOneWidget);
    provider.show(mail('Current loaded mail'));
    await tester.pump();
    expect(find.text('Current loaded mail'), findsOneWidget);
  });

  testWidgets('long subject retains full text with a single ellipsized heading', (tester) async {
    final subject = List.filled(20, '長い件名').join(' ');
    await tester.pumpWidget(harness(_Provider(mail(subject))));
    await tester.pump();
    expect(find.text(subject), findsOneWidget);
    final title = tester.widget<Text>(find.text(subject));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'FileForge';

  @override
  String get mailComposeTooltip => '新規作成';

  @override
  String get mailListEmpty => 'メールがありません';

  @override
  String get mailLoadFailed => 'メールを読み込めませんでした';

  @override
  String get mailDetailTitle => 'メール';

  @override
  String get noSubject => '(件名なし)';

  @override
  String get labelInbox => '受信トレイ';

  @override
  String get labelDrafts => '下書き';

  @override
  String get labelSent => '送信済み';

  @override
  String get draftLoadFailed => '下書きを読み込めませんでした';

  @override
  String get fieldFrom => '差出人';

  @override
  String get fieldTo => '宛先';

  @override
  String get fieldCc => 'Cc';

  @override
  String get fieldBcc => 'Bcc';

  @override
  String get composeTitleNew => '新規メール';

  @override
  String get composeTitleReply => '返信';

  @override
  String get composeTitleReplyAll => '全員に返信';

  @override
  String get composeTitleForward => '転送';

  @override
  String get composeTitleDraft => '下書き';

  @override
  String get saveDraftTooltip => '下書きを保存';

  @override
  String get sendTooltip => '送信';

  @override
  String get ccBccToggle => 'Cc / Bcc';

  @override
  String get subjectLabel => '件名';

  @override
  String get messageLabel => '本文';

  @override
  String get htmlSourceHint => '<p>HTML ソース…</p>';

  @override
  String get formatLabel => '形式:';

  @override
  String get formatPlain => 'プレーン';

  @override
  String get formatHtml => 'HTML';

  @override
  String get attachmentsLabel => '添付ファイル';

  @override
  String get addLabel => '追加';

  @override
  String get removeLabel => '削除';

  @override
  String get waitUploads => '添付ファイルのアップロードが完了するまでお待ちください';

  @override
  String get enterRecipient => '宛先を1件以上入力してください';

  @override
  String invalidAddress(String address) {
    return '無効なアドレス: $address';
  }

  @override
  String get tooManyRecipients => '宛先が多すぎます';

  @override
  String get subjectTooLong => '件名が長すぎます';

  @override
  String get mailSent => 'メールを送信しました';

  @override
  String get serverRejectedRecipient => 'サーバーが宛先を拒否しました';

  @override
  String sendFailed(String code) {
    return '送信に失敗しました: $code';
  }

  @override
  String get draftSaved => '下書きを保存しました';

  @override
  String get draftSaveFailed => '下書きを保存できませんでした';

  @override
  String get draftUpdated => '下書きを更新しました';

  @override
  String get draftUpdateFailed => '下書きを更新できませんでした';

  @override
  String attachFailed(String filename) {
    return '$filename の添付に失敗しました';
  }

  @override
  String get draftConflictTitle => '下書きが他の場所で変更されました';

  @override
  String get draftConflictBody =>
      'この下書きは他の場所で変更されました。最新版を再読み込みしますか？ここで保存していない編集内容は失われます。';

  @override
  String get keepEditing => '編集を続ける';

  @override
  String get reload => '再読み込み';
}

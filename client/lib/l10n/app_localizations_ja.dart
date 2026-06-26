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

  @override
  String get accountConnectTitle => 'メールアカウント';

  @override
  String get accountOnboardingTitle => 'メールアカウントを接続してください';

  @override
  String get accountOnboardingBody =>
      '受信トレイを読み込むには、まずメールアカウントを接続してください。アカウントを接続するまでメールは取得されません。';

  @override
  String get accountConnectCta => 'アカウントを接続';

  @override
  String get accountListLoadFailed => 'アカウントを読み込めませんでした';

  @override
  String get accountGateSessionExpired =>
      'セッションの有効期限が切れました。再度サインインしてください — メールアカウントには影響ありません。';

  @override
  String get accountGateTransientError =>
      'メールサービスに接続できませんでした。アカウントの追加や設定の表示は引き続き可能です。オンラインに戻ったら再試行してください。';

  @override
  String get accountGateRetry => '再試行';

  @override
  String get accountSectionConnected => '接続済みアカウント';

  @override
  String get accountSectionAdd => 'アカウントを追加';

  @override
  String get accountProviderLabel => 'プロバイダ';

  @override
  String get accountAuthCodeLabel => '認証コード';

  @override
  String get accountAuthCodeHint => 'プロバイダの同意画面で取得したコードを貼り付けてください';

  @override
  String get accountAuthCodeHelp =>
      'プロバイダのサイトでアクセスを承認し、返された認証コードをここに貼り付けてください。';

  @override
  String get accountConnectAction => '接続';

  @override
  String accountOAuthConnectWith(String provider) {
    return '$providerでログイン';
  }

  @override
  String get accountOAuthLaunching => 'ログイン画面を開いています…';

  @override
  String get accountOAuthLaunchFailed => 'ログインページを開けませんでした';

  @override
  String get accountOAuthAwaitTitle => 'ブラウザで続けてください';

  @override
  String get accountOAuthAwaitBody => '開いたブラウザでアクセスを承認し、この画面に戻ると、接続を自動的に確認します。';

  @override
  String get accountOAuthCheckAction => '完了しました — 今すぐ確認';

  @override
  String get accountOAuthReopen => 'ログインを再度開く';

  @override
  String get accountAdvancedToggle => '詳細: コードを手動で入力';

  @override
  String get accountConnecting => '接続中…';

  @override
  String get accountConnected => 'アカウントを接続しました';

  @override
  String get accountEmpty => '接続済みのアカウントはまだありません';

  @override
  String get accountAuthCodeRequired => '認証コードを入力してください';

  @override
  String get accountOAuthNotConfigured =>
      'サーバーにメールOAuthが設定されていません。管理者にお問い合わせください。';

  @override
  String get accountConflict => 'そのアカウントは既に接続されています';

  @override
  String get accountConnectFailed => 'アカウントの接続に失敗しました';

  @override
  String get accountOAuthExchangeFailed =>
      'サインインは成功しましたが、サーバーがアカウント接続を完了できませんでした（OAuth交換に失敗）。もう一度お試しください。';

  @override
  String get accountConnectSessionExpired =>
      'セッションの有効期限が切れました。再度サインインしてからアカウントを接続し直してください。';

  @override
  String get accountConnectUnreachable =>
      'メールサーバーに接続できませんでした。ネットワークを確認してもう一度お試しください。';

  @override
  String get accountConnectMalformed =>
      'メールサーバーから予期しない応答が返りました（エンドポイントが未デプロイの可能性）。もう一度試すか、管理者にお問い合わせください。';

  @override
  String get accountConnectInvalid =>
      'この内容では接続できませんでした。プロバイダーとコードを確認してもう一度お試しください。';

  @override
  String get accountRemoveTooltip => 'アカウントを解除';

  @override
  String get accountRemoveConfirmTitle => 'アカウントを解除しますか？';

  @override
  String accountRemoveConfirmBody(String email) {
    return '$email を解除しますか？同期されたメールも削除されます。';
  }

  @override
  String get accountRemoved => 'アカウントを解除しました';

  @override
  String get accountRemoveFailed => 'アカウントの解除に失敗しました';

  @override
  String get accountManageTooltip => 'メールアカウントの管理';

  @override
  String get accountReauthBannerTitle => '再接続が必要です';

  @override
  String accountReauthBannerBody(String email) {
    return '$email の認証の有効期限が切れました。メールの送受信を続けるにはアカウントを再接続してください。';
  }

  @override
  String get accountReauthAction => '再接続';

  @override
  String get cancel => 'キャンセル';
}

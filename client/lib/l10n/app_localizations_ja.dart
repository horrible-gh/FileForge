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
  String get attachmentDownloaded => '添付ファイルを保存しました';

  @override
  String get attachmentDownloadFailed => '添付ファイルをダウンロードできませんでした';

  @override
  String get mailActionCopy => 'コピー';

  @override
  String get mailCopySubject => '件名をコピー';

  @override
  String get mailCopyBody => '本文をコピー';

  @override
  String get mailCopyFrom => '差出人アドレスをコピー';

  @override
  String get mailCopied => 'クリップボードにコピーしました';

  @override
  String get mailLinkOpenTitle => 'リンクを開く';

  @override
  String get mailLinkOpenConfirm => 'このリンクを外部ブラウザで開きますか？';

  @override
  String get mailLinkOpenAction => '開く';

  @override
  String get mailLinkOpenFailed => 'リンクを開けませんでした';

  @override
  String get mailPin => 'ピン留め';

  @override
  String get mailUnpin => 'ピン留め解除';

  @override
  String get mailPinnedTray => 'ピン留め';

  @override
  String mailPinnedTrayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ピン留め $count件',
    );
    return '$_temp0';
  }

  @override
  String get mailPinnedTrayExpand => 'ピン留めを表示';

  @override
  String get mailPinnedTrayCollapse => 'ピン留めを隠す';

  @override
  String get mailMarkAllRead => 'すべて既読にする';

  @override
  String mailMarkedAllRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件を既読にしました',
      zero: '未読メールはありません',
    );
    return '$_temp0';
  }

  @override
  String get mailMarkAllReadFailed => 'すべて既読にできませんでした';

  @override
  String mailSyncAccountFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアカウントを同期できませんでした',
      one: '1件のアカウントを同期できませんでした',
    );
    return '$_temp0';
  }

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

  @override
  String get commonSave => '保存';

  @override
  String get commonSaved => '保存しました';

  @override
  String get commonDelete => '削除';

  @override
  String get commonConfirm => '確認';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonCopy => 'コピー';

  @override
  String get commonCopied => 'コピーしました';

  @override
  String get commonDownload => 'ダウンロード';

  @override
  String get commonRename => '名前を変更';

  @override
  String get commonShare => '共有';

  @override
  String get commonCreate => '作成';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonEdit => '編集';

  @override
  String get commonPassword => 'パスワード';

  @override
  String get commonUsername => 'ユーザー名';

  @override
  String get commonSearch => '検索';

  @override
  String get loginSignIn => 'サインイン';

  @override
  String get totpTitle => '二要素認証';

  @override
  String get totpCodeLabel => '認証コード';

  @override
  String get totpVerify => '確認';

  @override
  String get storageNotFound => 'ストレージが見つかりません。';

  @override
  String get listEmptyNoStorages => 'ストレージがありません';

  @override
  String get listLoadFailed => 'リストを読み込めませんでした';

  @override
  String get noteNew => '新規ノート';

  @override
  String get noteName => 'ノート名';

  @override
  String get noteCreateNew => '新規ノートを作成';

  @override
  String get notesEmpty => 'ノートがありません';

  @override
  String get folderNew => '新規フォルダー';

  @override
  String get folderName => 'フォルダー名';

  @override
  String get renameNewName => '新しい名前';

  @override
  String deleteConfirmName(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get bulkDeleteTitle => '一括削除';

  @override
  String bulkDeleteConfirmCount(int count) {
    return '$count件を削除しますか？';
  }

  @override
  String get navSelectAll => 'すべて選択';

  @override
  String get navSelectionMode => '選択モード';

  @override
  String get navExitSearch => '検索を終了';

  @override
  String get navSearch => '検索';

  @override
  String get navSearchHint => '検索...';

  @override
  String get navLogout => 'ログアウト';

  @override
  String get navUploadFile => 'ファイルをアップロード';

  @override
  String get navManageShareLinks => '共有リンクを管理';

  @override
  String get navSecuritySettings => 'セキュリティ設定';

  @override
  String get navServerSettings => 'サーバー設定';

  @override
  String get previewUnsavedChanges => '保存されていない変更があります。';

  @override
  String get previewDontSave => '保存しない';

  @override
  String get previewRewind10 => '10秒戻る';

  @override
  String get previewPause => '一時停止';

  @override
  String get previewPlay => '再生';

  @override
  String get previewForward10 => '10秒進む';

  @override
  String get serverAddress => 'サーバーアドレス';

  @override
  String get serverAddressHint => '例: 192.168.1.10:8000';

  @override
  String get serverTestConnection => '接続をテスト';

  @override
  String get securityEnable2fa => '二段階認証を有効化';

  @override
  String get securityScanQr => '認証アプリで下のQRコードをスキャンしてください。';

  @override
  String get securityQrUnavailable => 'QR画像を表示できません';

  @override
  String get securityRecoveryInfo => 'アクセスできなくなった場合、リカバリーコードでアカウントに再アクセスできます。';

  @override
  String get securityAuthCode => '認証コード';

  @override
  String get securityEnable => '有効化';

  @override
  String get securityDisable2fa => '二段階認証を無効化';

  @override
  String get securityCurrentCode => '現在のコード';

  @override
  String get securityDisable => '無効化';

  @override
  String get securityRegenRecovery => 'リカバリーコードを再生成';

  @override
  String get securityRegenerate => '再生成';

  @override
  String get securityNewRecoveryInfo => '新しいリカバリーコードです。安全な場所に保管してください。';

  @override
  String get securityRecoveryCopied => 'リカバリーコードをコピーしました';

  @override
  String get shareDeleteLinkTitle => '共有リンクを削除';

  @override
  String shareDeleteLinkBody(String name) {
    return '$nameのリンクを削除しますか？';
  }

  @override
  String get shareNoLinks => '共有リンクがありません';

  @override
  String get sharedFileTitle => '共有ファイル';

  @override
  String get sharePasswordProtected => 'このリンクはパスワードで保護されています';

  @override
  String get shareLinkCopied => 'リンクをコピーしました';

  @override
  String get shareCopyLink => 'リンクをコピー';

  @override
  String get shareFolderEmpty => 'フォルダーは空です';

  @override
  String get shareSetPassword => 'パスワードを設定';

  @override
  String get shareEnterPassword => 'パスワードを入力';

  @override
  String get shareCreateLink => 'リンクを作成';

  @override
  String get actionPreview => 'プレビュー';

  @override
  String get storageNone => 'ストレージなし';

  @override
  String get uploadClearAll => 'すべてクリア';

  @override
  String get vaultOffline => 'オフライン';

  @override
  String get vaultSync => '同期';

  @override
  String get vaultLock => 'ロック';

  @override
  String get vaultUnlockTitle => 'ボルトのロックを解除';

  @override
  String get vaultUnlockDesc => 'ログインパスワードでボルトを開きます。パスワードはこの端末から外に出ません。';

  @override
  String get vaultUnlock => 'ロックを解除';

  @override
  String get vaultEmpty => '保存された項目はありません';

  @override
  String get vaultCopyPassword => 'パスワードをコピー';

  @override
  String get vaultPasswordCopied => 'パスワードをコピーしました';

  @override
  String get vaultSaved => '保存しました';

  @override
  String get vaultSaveFailed => '保存に失敗しました';

  @override
  String get vaultDeleted => '削除しました';

  @override
  String get vaultDeleteFailed => '削除に失敗しました';

  @override
  String vaultDeleteConfirm(String title) {
    return '「$title」を削除しますか？';
  }

  @override
  String get vaultEntryNew => '新規項目';

  @override
  String get vaultEntryEdit => '項目を編集';

  @override
  String get vaultFieldTitle => 'タイトル';

  @override
  String get vaultFieldUrl => 'URL';

  @override
  String get vaultFieldCategory => '分類';

  @override
  String get vaultFieldNotes => 'メモ';

  @override
  String get vaultCategoryWork => '仕事';

  @override
  String get vaultCategoryPersonal => '個人';

  @override
  String get vaultCategoryEntertainment => 'エンターテインメント';

  @override
  String get vaultManageCategories => '分類を管理';

  @override
  String get vaultCategoryAll => 'すべて';

  @override
  String get vaultCategoryNew => '新しい分類';

  @override
  String get vaultCategoryEdit => '分類を編集';

  @override
  String get vaultCategoryName => '名前';

  @override
  String get vaultCategoryIcon => 'アイコン';

  @override
  String get vaultCategoryColor => '色';

  @override
  String get vaultCategoryAdded => '分類を追加しました';

  @override
  String get vaultCategoryUpdated => '分類を更新しました';

  @override
  String get vaultCategoryDeleted => '分類を削除しました';

  @override
  String get vaultCategoryActionFailed => '分類の操作に失敗しました';

  @override
  String get vaultCategoryDefaultLocked => '既定の分類は編集・削除できません';

  @override
  String vaultCategoryDeleteConfirm(String name) {
    return '「$name」分類を削除しますか？この分類の項目は「個人」に移動します。';
  }

  @override
  String get vaultMsgDecryptBanner =>
      'ボルトの復号に失敗しました。ログインパスワードが正しいか確認してから、もう一度ロックを解除してください。（保護: この状態では変更をサーバーに保存しません）';

  @override
  String get vaultMsgDecryptBlockedSave =>
      '復号に失敗した状態では保存できません。既存のボルトを上書きしないようにブロックしました — パスワードを確認してもう一度ロックを解除してください。';

  @override
  String get vaultMsgOfflineMode =>
      'オフラインモード: この端末に保存されたボルトを表示します。オンラインに戻ると同期されます。';

  @override
  String get vaultMsgOfflineSaved =>
      'オフライン: 変更はこの端末にのみ保存しました。オンラインに戻るとサーバーと同期されます。';

  @override
  String get vaultMsgSessionExpired => 'セッションの有効期限が切れました。再度サインインしてください。';

  @override
  String get vaultMsgSyncFailed => 'ボルトの同期に失敗しました。';

  @override
  String get fileDownloadFailed => 'ダウンロードに失敗しました';

  @override
  String get fileDownloadComplete => 'ダウンロードが完了しました';

  @override
  String get fileDownloading => 'ダウンロード中…';

  @override
  String fileDownloadingPercent(int percent) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get fileRenamed => '名前を変更しました';

  @override
  String get fileNameExists => '同じ名前のファイルが既に存在します';

  @override
  String get fileRenameFailed => '名前の変更に失敗しました';

  @override
  String get fileDeleted => '削除しました';

  @override
  String get itemNotFound => '項目が見つかりません';

  @override
  String get fileDeleteFailed => '削除に失敗しました';

  @override
  String get noteNameExists => '同じ名前のノートが既に存在します';

  @override
  String get noteCreateFailed => 'ノートの作成に失敗しました';

  @override
  String get searchNoResults => '検索結果がありません';

  @override
  String get filesEmpty => 'ファイルがありません';

  @override
  String get folderCreated => 'フォルダーを作成しました';

  @override
  String get folderCreateFailed => 'フォルダーの作成に失敗しました';

  @override
  String get viewGrid => 'グリッド表示';

  @override
  String get viewList => 'リスト表示';

  @override
  String get totpEnterRecoveryCodeError => '8文字のリカバリーコードを入力してください';

  @override
  String get totpEnterCodeError => '6桁のコードを入力してください';

  @override
  String get totpRecoveryPrompt => 'リカバリーコードを入力してください';

  @override
  String get totpCodePrompt => '認証アプリの6桁のコードを入力してください';

  @override
  String get totpUseAuthCode => '認証コードを使う';

  @override
  String get totpUseRecovery => 'リカバリーコードを使う';

  @override
  String get previewFileNotFound => 'ファイルが見つかりません';

  @override
  String get previewAccessDenied => 'アクセスが拒否されました';

  @override
  String get previewLoadFailed => 'ファイルを読み込めません';

  @override
  String get previewSaveNoPermission => '保存する権限がありません';

  @override
  String get previewSaveFailed => '保存に失敗しました';

  @override
  String get previewImageFailed => '画像を表示できません';

  @override
  String get previewPdfFailed => 'PDFを表示できません';

  @override
  String get previewVideoFailed => '動画を再生できません';

  @override
  String get previewAudioFailed => '音声を再生できません';

  @override
  String get previewUnsupported => 'このファイル形式はプレビューに対応していません';

  @override
  String get securityTotpStatusFailed => 'TOTPの状態を取得できませんでした';

  @override
  String get securitySetupFailed => '設定に失敗しました。もう一度お試しください';

  @override
  String get security2faEnabled => '二段階認証を有効にしました';

  @override
  String get security2faDisabled => '二段階認証を無効にしました';

  @override
  String get securityRecoveryRegenerated => 'リカバリーコードを再生成しました';

  @override
  String get shareDeleteLinkFailed => 'リンクの削除に失敗しました';

  @override
  String shareCreateLinkFailed(String error) {
    return 'リンクの作成に失敗しました: $error';
  }

  @override
  String get loginSubtitle => 'ワークスペースに戻るにはアカウント情報を入力してください';

  @override
  String get loginUsernameRequired => 'ユーザー名を入力してください';

  @override
  String get loginPasswordRequired => 'パスワードを入力してください';

  @override
  String get totpInvalidCode => '認証コードが正しくありません';

  @override
  String get totpAuthError => '認証中にエラーが発生しました';

  @override
  String get securityInvalidCode => 'コードが正しくありません';

  @override
  String get securitySectionTitle => '二段階認証 (TOTP)';

  @override
  String get securitySectionDesc =>
      'Google Authenticator などの認証アプリでセキュリティを強化します';

  @override
  String get securityStatusEnabled => '有効';

  @override
  String get securityStatusDisabled => '無効';

  @override
  String get securityStep1 => 'ステップ1. QRコードをスキャン';

  @override
  String get securityStep2 => 'ステップ2. リカバリーコードを保存';

  @override
  String get securityStep3 => 'ステップ3. 認証コードを入力';

  @override
  String get serverInvalidFormat => '形式が正しくありません';

  @override
  String get serverPortRequired => 'ポート番号が必要です (例: 192.168.1.10:8000)';

  @override
  String get serverPortNumeric => 'ポート番号は数値である必要があります';

  @override
  String get serverPortRange => 'ポートは1〜65535の範囲である必要があります';

  @override
  String get serverAddressDesc => '接続するサーバーのホストとポートを入力してください。';

  @override
  String get shareUnknownError => '不明なエラーが発生しました';

  @override
  String get shareCreateLinkTitle => '共有リンクを作成';

  @override
  String get navFoldersHeader => 'フォルダー';

  @override
  String get storageSectionLabel => 'ストレージ';

  @override
  String get uploadWaiting => '待機中';

  @override
  String get uploadDropHere => 'ここにファイルをドロップ';

  @override
  String selectedCount(int count) {
    return '$count件選択中';
  }

  @override
  String bulkDeleted(int count) {
    return '$count件を削除しました';
  }

  @override
  String bulkDeletePartial(int done, int total) {
    return '一部の項目を削除できませんでした ($done/$total)';
  }

  @override
  String get relativeJustNow => 'たった今';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count分前',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count時間前',
    );
    return '$_temp0';
  }
}

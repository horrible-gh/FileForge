// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FileForge';

  @override
  String get mailComposeTooltip => 'Compose';

  @override
  String get mailListEmpty => 'No mail';

  @override
  String get mailLoadFailed => 'Failed to load mail';

  @override
  String get mailDetailTitle => 'Mail';

  @override
  String get noSubject => '(no subject)';

  @override
  String get labelInbox => 'Inbox';

  @override
  String get labelDrafts => 'Drafts';

  @override
  String get labelSent => 'Sent';

  @override
  String get draftLoadFailed => 'Failed to load draft';

  @override
  String get fieldFrom => 'From';

  @override
  String get fieldTo => 'To';

  @override
  String get fieldCc => 'Cc';

  @override
  String get fieldBcc => 'Bcc';

  @override
  String get composeTitleNew => 'New mail';

  @override
  String get composeTitleReply => 'Reply';

  @override
  String get composeTitleReplyAll => 'Reply all';

  @override
  String get composeTitleForward => 'Forward';

  @override
  String get composeTitleDraft => 'Draft';

  @override
  String get saveDraftTooltip => 'Save draft';

  @override
  String get sendTooltip => 'Send';

  @override
  String get ccBccToggle => 'Cc / Bcc';

  @override
  String get subjectLabel => 'Subject';

  @override
  String get messageLabel => 'Message';

  @override
  String get htmlSourceHint => '<p>HTML source…</p>';

  @override
  String get formatLabel => 'Format:';

  @override
  String get formatPlain => 'Plain';

  @override
  String get formatHtml => 'HTML';

  @override
  String get attachmentsLabel => 'Attachments';

  @override
  String get attachmentDownloaded => 'Attachment saved';

  @override
  String get attachmentDownloadFailed => 'Failed to download attachment';

  @override
  String get mailActionCopy => 'Copy';

  @override
  String get mailCopySubject => 'Copy subject';

  @override
  String get mailCopyBody => 'Copy body';

  @override
  String get mailCopyFrom => 'Copy sender address';

  @override
  String get mailCopied => 'Copied to clipboard';

  @override
  String get mailPin => 'Pin';

  @override
  String get mailUnpin => 'Unpin';

  @override
  String get mailPinnedTray => 'Pinned';

  @override
  String mailPinnedTrayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pinned',
      one: '1 pinned',
    );
    return '$_temp0';
  }

  @override
  String get mailPinnedTrayExpand => 'Show pinned';

  @override
  String get mailPinnedTrayCollapse => 'Hide pinned';

  @override
  String get mailMarkAllRead => 'Mark all as read';

  @override
  String mailMarkedAllRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Marked $count mails as read',
      one: 'Marked 1 mail as read',
      zero: 'No unread mail',
    );
    return '$_temp0';
  }

  @override
  String get mailMarkAllReadFailed => 'Failed to mark all as read';

  @override
  String get addLabel => 'Add';

  @override
  String get removeLabel => 'Remove';

  @override
  String get waitUploads => 'Wait for attachments to finish uploading';

  @override
  String get enterRecipient => 'Enter at least one recipient';

  @override
  String invalidAddress(String address) {
    return 'Invalid address: $address';
  }

  @override
  String get tooManyRecipients => 'Too many recipients';

  @override
  String get subjectTooLong => 'Subject is too long';

  @override
  String get mailSent => 'Mail sent';

  @override
  String get serverRejectedRecipient => 'Server rejected a recipient';

  @override
  String sendFailed(String code) {
    return 'Send failed: $code';
  }

  @override
  String get draftSaved => 'Draft saved';

  @override
  String get draftSaveFailed => 'Failed to save draft';

  @override
  String get draftUpdated => 'Draft updated';

  @override
  String get draftUpdateFailed => 'Failed to update draft';

  @override
  String attachFailed(String filename) {
    return 'Failed to attach $filename';
  }

  @override
  String get draftConflictTitle => 'Draft changed elsewhere';

  @override
  String get draftConflictBody =>
      'This draft was modified in another place. Reload the latest version? Your unsaved edits here will be lost.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get reload => 'Reload';

  @override
  String get accountConnectTitle => 'Mail accounts';

  @override
  String get accountOnboardingTitle => 'Connect a mail account';

  @override
  String get accountOnboardingBody =>
      'Before your inbox can load, connect a mail account. Nothing is fetched until an account is connected.';

  @override
  String get accountConnectCta => 'Connect account';

  @override
  String get accountListLoadFailed => 'Failed to load accounts';

  @override
  String get accountGateSessionExpired =>
      'Your session has expired. Please sign in again — your mail accounts are unaffected.';

  @override
  String get accountGateTransientError =>
      'Couldn\'t reach the mail service. You can still add an account or open settings; tap retry when you\'re back online.';

  @override
  String get accountGateRetry => 'Retry';

  @override
  String get accountSectionConnected => 'Connected accounts';

  @override
  String get accountSectionAdd => 'Add an account';

  @override
  String get accountProviderLabel => 'Provider';

  @override
  String get accountAuthCodeLabel => 'Authorization code';

  @override
  String get accountAuthCodeHint =>
      'Paste the code from the provider consent screen';

  @override
  String get accountAuthCodeHelp =>
      'Approve access on the provider\'s site, then paste the returned authorization code here.';

  @override
  String get accountConnectAction => 'Connect';

  @override
  String accountOAuthConnectWith(String provider) {
    return 'Sign in with $provider';
  }

  @override
  String get accountOAuthLaunching => 'Opening sign-in…';

  @override
  String get accountOAuthLaunchFailed => 'Couldn\'t open the sign-in page';

  @override
  String get accountOAuthAwaitTitle => 'Finish in your browser';

  @override
  String get accountOAuthAwaitBody =>
      'Approve access in the browser that opened, then come back here — we\'ll detect the connection automatically.';

  @override
  String get accountOAuthCheckAction => 'I\'ve finished — check now';

  @override
  String get accountOAuthReopen => 'Open sign-in again';

  @override
  String get accountAdvancedToggle => 'Advanced: enter a code manually';

  @override
  String get accountConnecting => 'Connecting…';

  @override
  String get accountConnected => 'Account connected';

  @override
  String get accountEmpty => 'No accounts connected yet';

  @override
  String get accountAuthCodeRequired => 'Enter the authorization code';

  @override
  String get accountOAuthNotConfigured =>
      'Mail OAuth is not configured on the server. Contact your administrator.';

  @override
  String get accountConflict => 'That account is already connected';

  @override
  String get accountConnectFailed => 'Failed to connect the account';

  @override
  String get accountOAuthExchangeFailed =>
      'Signed in, but the server couldn\'t finish connecting the account (OAuth exchange failed). Please try again.';

  @override
  String get accountConnectSessionExpired =>
      'Your session has expired. Sign in again, then reconnect the account.';

  @override
  String get accountConnectUnreachable =>
      'Couldn\'t reach the mail service. Check your connection and try again.';

  @override
  String get accountConnectMalformed =>
      'The mail server returned an unexpected response (the endpoint may not be deployed yet). Try again, or contact your administrator.';

  @override
  String get accountConnectInvalid =>
      'Couldn\'t connect with these details. Check the provider and code, then try again.';

  @override
  String get accountRemoveTooltip => 'Remove account';

  @override
  String get accountRemoveConfirmTitle => 'Remove account?';

  @override
  String accountRemoveConfirmBody(String email) {
    return 'Disconnect $email? Its synced mail will be removed.';
  }

  @override
  String get accountRemoved => 'Account removed';

  @override
  String get accountRemoveFailed => 'Failed to remove the account';

  @override
  String get accountManageTooltip => 'Manage mail accounts';

  @override
  String get accountReauthBannerTitle => 'Reconnection required';

  @override
  String accountReauthBannerBody(String email) {
    return 'Authentication for $email has expired. Reconnect the account to keep sending and receiving mail.';
  }

  @override
  String get accountReauthAction => 'Reconnect';

  @override
  String get cancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaved => 'Saved';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonOk => 'OK';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonPassword => 'Password';

  @override
  String get commonUsername => 'Username';

  @override
  String get commonSearch => 'Search';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get totpTitle => 'Two-Factor Authentication';

  @override
  String get totpCodeLabel => 'Authentication code';

  @override
  String get totpVerify => 'Verify';

  @override
  String get storageNotFound => 'Storage not found.';

  @override
  String get listEmptyNoStorages => 'No storages';

  @override
  String get listLoadFailed => 'Failed to load list';

  @override
  String get noteNew => 'New Note';

  @override
  String get noteName => 'Note name';

  @override
  String get noteCreateNew => 'Create New Note';

  @override
  String get notesEmpty => 'No notes';

  @override
  String get folderNew => 'New Folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get renameNewName => 'New name';

  @override
  String deleteConfirmName(String name) {
    return 'Delete \'$name\'?';
  }

  @override
  String get bulkDeleteTitle => 'Bulk Delete';

  @override
  String bulkDeleteConfirmCount(int count) {
    return 'Delete $count items?';
  }

  @override
  String get navSelectAll => 'Select all';

  @override
  String get navSelectionMode => 'Selection mode';

  @override
  String get navExitSearch => 'Exit search';

  @override
  String get navSearch => 'Search';

  @override
  String get navSearchHint => 'Search...';

  @override
  String get navLogout => 'Logout';

  @override
  String get navUploadFile => 'Upload File';

  @override
  String get navManageShareLinks => 'Manage Share Links';

  @override
  String get navSecuritySettings => 'Security Settings';

  @override
  String get navServerSettings => 'Server Settings';

  @override
  String get previewUnsavedChanges => 'You have unsaved changes.';

  @override
  String get previewDontSave => 'Don\'t Save';

  @override
  String get previewRewind10 => 'Rewind 10s';

  @override
  String get previewPause => 'Pause';

  @override
  String get previewPlay => 'Play';

  @override
  String get previewForward10 => 'Forward 10s';

  @override
  String get serverAddress => 'Server Address';

  @override
  String get serverAddressHint => 'e.g., 192.168.1.10:8000';

  @override
  String get serverTestConnection => 'Test Connection';

  @override
  String get securityEnable2fa => 'Enable Two-Step Authentication';

  @override
  String get securityScanQr =>
      'Scan the QR code below with your authenticator app.';

  @override
  String get securityQrUnavailable => 'Unable to display QR image';

  @override
  String get securityRecoveryInfo =>
      'If you lose access, recovery codes can help you regain account access.';

  @override
  String get securityAuthCode => 'Authentication Code';

  @override
  String get securityEnable => 'Enable';

  @override
  String get securityDisable2fa => 'Disable Two-Step Authentication';

  @override
  String get securityCurrentCode => 'Current Code';

  @override
  String get securityDisable => 'Disable';

  @override
  String get securityRegenRecovery => 'Regenerate Recovery Codes';

  @override
  String get securityRegenerate => 'Regenerate';

  @override
  String get securityNewRecoveryInfo =>
      'New recovery codes. Store them in a safe place.';

  @override
  String get securityRecoveryCopied => 'Recovery codes copied';

  @override
  String get shareDeleteLinkTitle => 'Delete Share Link';

  @override
  String shareDeleteLinkBody(String name) {
    return 'Delete link for $name?';
  }

  @override
  String get shareNoLinks => 'No shared links';

  @override
  String get sharedFileTitle => 'Shared File';

  @override
  String get sharePasswordProtected => 'This link is password protected';

  @override
  String get shareLinkCopied => 'Link copied';

  @override
  String get shareCopyLink => 'Copy Link';

  @override
  String get shareFolderEmpty => 'Folder is empty';

  @override
  String get shareSetPassword => 'Set Password';

  @override
  String get shareEnterPassword => 'Enter password';

  @override
  String get shareCreateLink => 'Create Link';

  @override
  String get actionPreview => 'Preview';

  @override
  String get storageNone => 'No Storage';

  @override
  String get uploadClearAll => 'Clear All';

  @override
  String get vaultOffline => 'Offline';

  @override
  String get vaultSync => 'Sync';

  @override
  String get vaultLock => 'Lock';

  @override
  String get vaultUnlockTitle => 'Unlock vault';

  @override
  String get vaultUnlockDesc =>
      'Open the vault with your login password. Your password never leaves this device.';

  @override
  String get vaultUnlock => 'Unlock';

  @override
  String get vaultEmpty => 'No saved entries';

  @override
  String get vaultCopyPassword => 'Copy password';

  @override
  String get vaultPasswordCopied => 'Password copied';

  @override
  String get vaultSaved => 'Saved';

  @override
  String get vaultSaveFailed => 'Failed to save';

  @override
  String get vaultDeleted => 'Deleted';

  @override
  String get vaultDeleteFailed => 'Failed to delete';

  @override
  String vaultDeleteConfirm(String title) {
    return 'Delete entry \'$title\'?';
  }

  @override
  String get vaultEntryNew => 'New entry';

  @override
  String get vaultEntryEdit => 'Edit entry';

  @override
  String get vaultFieldTitle => 'Title';

  @override
  String get vaultFieldCategory => 'Category';

  @override
  String get vaultFieldNotes => 'Notes';

  @override
  String get vaultCategoryWork => 'Work';

  @override
  String get vaultCategoryPersonal => 'Personal';

  @override
  String get vaultCategoryEntertainment => 'Entertainment';

  @override
  String get vaultManageCategories => 'Manage categories';

  @override
  String get vaultCategoryAll => 'All';

  @override
  String get vaultCategoryNew => 'New category';

  @override
  String get vaultCategoryEdit => 'Edit category';

  @override
  String get vaultCategoryName => 'Name';

  @override
  String get vaultCategoryIcon => 'Icon';

  @override
  String get vaultCategoryColor => 'Color';

  @override
  String get vaultCategoryAdded => 'Category added';

  @override
  String get vaultCategoryUpdated => 'Category updated';

  @override
  String get vaultCategoryDeleted => 'Category deleted';

  @override
  String get vaultCategoryActionFailed => 'Category operation failed';

  @override
  String get vaultCategoryDefaultLocked =>
      'Default categories can\'t be edited or deleted';

  @override
  String vaultCategoryDeleteConfirm(String name) {
    return 'Delete category \'$name\'? Its entries will move to \'Personal\'.';
  }

  @override
  String get vaultMsgDecryptBanner =>
      'Vault decryption failed. Make sure your login password is correct, then unlock again. (Protection: changes are not saved to the server in this state.)';

  @override
  String get vaultMsgDecryptBlockedSave =>
      'Can\'t save while decryption has failed. Saving was blocked to avoid overwriting your existing vault — check your password and unlock again.';

  @override
  String get vaultMsgOfflineMode =>
      'Offline mode: showing the vault stored on this device. It will sync when you\'re back online.';

  @override
  String get vaultMsgOfflineSaved =>
      'Offline: changes were saved only on this device. They\'ll sync with the server when you\'re back online.';

  @override
  String get vaultMsgSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get vaultMsgSyncFailed => 'Failed to sync the vault.';

  @override
  String get fileDownloadFailed => 'Download failed';

  @override
  String get fileDownloadComplete => 'Download complete';

  @override
  String get fileRenamed => 'Renamed';

  @override
  String get fileNameExists => 'A file with this name already exists';

  @override
  String get fileRenameFailed => 'Failed to rename';

  @override
  String get fileDeleted => 'Deleted';

  @override
  String get itemNotFound => 'Item not found';

  @override
  String get fileDeleteFailed => 'Failed to delete';

  @override
  String get noteNameExists => 'A note with this name already exists';

  @override
  String get noteCreateFailed => 'Failed to create note';

  @override
  String get searchNoResults => 'No search results';

  @override
  String get filesEmpty => 'No files';

  @override
  String get folderCreated => 'Folder created';

  @override
  String get folderCreateFailed => 'Failed to create folder';

  @override
  String get viewGrid => 'Grid view';

  @override
  String get viewList => 'List view';

  @override
  String get totpEnterRecoveryCodeError => 'Enter 8-character recovery code';

  @override
  String get totpEnterCodeError => 'Enter 6-digit code';

  @override
  String get totpRecoveryPrompt => 'Enter your recovery code';

  @override
  String get totpCodePrompt => 'Enter 6-digit code from your authenticator app';

  @override
  String get totpUseAuthCode => 'Use authentication code';

  @override
  String get totpUseRecovery => 'Use recovery code';

  @override
  String get previewFileNotFound => 'File not found';

  @override
  String get previewAccessDenied => 'Access denied';

  @override
  String get previewLoadFailed => 'Unable to load file';

  @override
  String get previewSaveNoPermission => 'No permission to save';

  @override
  String get previewSaveFailed => 'Save failed';

  @override
  String get previewImageFailed => 'Unable to display image';

  @override
  String get previewPdfFailed => 'Unable to display PDF';

  @override
  String get previewVideoFailed => 'Unable to play video';

  @override
  String get previewAudioFailed => 'Unable to play audio';

  @override
  String get previewUnsupported =>
      'This file type is not supported for preview';

  @override
  String get securityTotpStatusFailed => 'Failed to retrieve TOTP status';

  @override
  String get securitySetupFailed => 'Setup failed. Please try again';

  @override
  String get security2faEnabled => 'Two-step authentication has been enabled';

  @override
  String get security2faDisabled => 'Two-step authentication has been disabled';

  @override
  String get securityRecoveryRegenerated =>
      'Recovery codes have been regenerated';

  @override
  String get shareDeleteLinkFailed => 'Failed to delete link';

  @override
  String shareCreateLinkFailed(String error) {
    return 'Failed to create link: $error';
  }

  @override
  String get loginSubtitle =>
      'Enter your account information to return to your workspace';

  @override
  String get loginUsernameRequired => 'Please enter your username';

  @override
  String get loginPasswordRequired => 'Please enter your password';

  @override
  String get totpInvalidCode => 'Invalid authentication code';

  @override
  String get totpAuthError => 'Authentication error occurred';

  @override
  String get securityInvalidCode => 'Invalid code';

  @override
  String get securitySectionTitle => 'Two-Step Authentication (TOTP)';

  @override
  String get securitySectionDesc =>
      'Extra security using authenticator apps like Google Authenticator';

  @override
  String get securityStatusEnabled => 'Enabled';

  @override
  String get securityStatusDisabled => 'Disabled';

  @override
  String get securityStep1 => 'Step 1. Scan QR Code';

  @override
  String get securityStep2 => 'Step 2. Save Recovery Codes';

  @override
  String get securityStep3 => 'Step 3. Enter Authentication Code';

  @override
  String get serverInvalidFormat => 'Invalid format';

  @override
  String get serverPortRequired =>
      'Port number is required (e.g., 192.168.1.10:8000)';

  @override
  String get serverPortNumeric => 'Port number must be numeric';

  @override
  String get serverPortRange => 'Port must be between 1 and 65535';

  @override
  String get serverAddressDesc =>
      'Enter the host and port of the server to connect to.';

  @override
  String get shareUnknownError => 'An unknown error occurred';

  @override
  String get shareCreateLinkTitle => 'Create Share Link';

  @override
  String get navFoldersHeader => 'Folders';

  @override
  String get storageSectionLabel => 'Storage';

  @override
  String get uploadWaiting => 'Waiting';

  @override
  String get uploadDropHere => 'Drop files here';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String bulkDeleted(int count) {
    return '$count items deleted';
  }

  @override
  String bulkDeletePartial(int done, int total) {
    return 'Some items failed to delete ($done/$total)';
  }

  @override
  String get relativeJustNow => 'Just now';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }
}

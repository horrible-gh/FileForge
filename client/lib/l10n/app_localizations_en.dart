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
  String get cancel => 'Cancel';
}

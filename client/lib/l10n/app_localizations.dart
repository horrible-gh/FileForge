import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ];

  /// Application title.
  ///
  /// In en, this message translates to:
  /// **'FileForge'**
  String get appTitle;

  /// No description provided for @mailComposeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Compose'**
  String get mailComposeTooltip;

  /// No description provided for @mailListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No mail'**
  String get mailListEmpty;

  /// No description provided for @mailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load mail'**
  String get mailLoadFailed;

  /// No description provided for @mailDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get mailDetailTitle;

  /// No description provided for @noSubject.
  ///
  /// In en, this message translates to:
  /// **'(no subject)'**
  String get noSubject;

  /// No description provided for @labelInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get labelInbox;

  /// No description provided for @labelDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get labelDrafts;

  /// No description provided for @labelSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get labelSent;

  /// No description provided for @draftLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load draft'**
  String get draftLoadFailed;

  /// No description provided for @fieldFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fieldFrom;

  /// No description provided for @fieldTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get fieldTo;

  /// No description provided for @fieldCc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get fieldCc;

  /// No description provided for @fieldBcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get fieldBcc;

  /// No description provided for @composeTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New mail'**
  String get composeTitleNew;

  /// No description provided for @composeTitleReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get composeTitleReply;

  /// No description provided for @composeTitleReplyAll.
  ///
  /// In en, this message translates to:
  /// **'Reply all'**
  String get composeTitleReplyAll;

  /// No description provided for @composeTitleForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get composeTitleForward;

  /// No description provided for @composeTitleDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get composeTitleDraft;

  /// No description provided for @saveDraftTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraftTooltip;

  /// No description provided for @sendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendTooltip;

  /// No description provided for @ccBccToggle.
  ///
  /// In en, this message translates to:
  /// **'Cc / Bcc'**
  String get ccBccToggle;

  /// No description provided for @subjectLabel.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get subjectLabel;

  /// No description provided for @messageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageLabel;

  /// No description provided for @htmlSourceHint.
  ///
  /// In en, this message translates to:
  /// **'<p>HTML source…</p>'**
  String get htmlSourceHint;

  /// No description provided for @formatLabel.
  ///
  /// In en, this message translates to:
  /// **'Format:'**
  String get formatLabel;

  /// No description provided for @formatPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get formatPlain;

  /// No description provided for @formatHtml.
  ///
  /// In en, this message translates to:
  /// **'HTML'**
  String get formatHtml;

  /// No description provided for @attachmentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsLabel;

  /// No description provided for @attachmentDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Attachment saved'**
  String get attachmentDownloaded;

  /// No description provided for @attachmentDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to download attachment'**
  String get attachmentDownloadFailed;

  /// No description provided for @mailActionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get mailActionCopy;

  /// No description provided for @mailCopySubject.
  ///
  /// In en, this message translates to:
  /// **'Copy subject'**
  String get mailCopySubject;

  /// No description provided for @mailCopyBody.
  ///
  /// In en, this message translates to:
  /// **'Copy body'**
  String get mailCopyBody;

  /// No description provided for @mailCopyFrom.
  ///
  /// In en, this message translates to:
  /// **'Copy sender address'**
  String get mailCopyFrom;

  /// No description provided for @mailCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get mailCopied;

  /// No description provided for @mailLinkOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get mailLinkOpenTitle;

  /// No description provided for @mailLinkOpenConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open this link in your external browser?'**
  String get mailLinkOpenConfirm;

  /// No description provided for @mailLinkOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get mailLinkOpenAction;

  /// No description provided for @mailLinkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link'**
  String get mailLinkOpenFailed;

  /// No description provided for @mailPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get mailPin;

  /// No description provided for @mailUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get mailUnpin;

  /// No description provided for @mailPinnedTray.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get mailPinnedTray;

  /// Count shown next to the pinned tray header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pinned} other{{count} pinned}}'**
  String mailPinnedTrayCount(int count);

  /// No description provided for @mailPinnedTrayExpand.
  ///
  /// In en, this message translates to:
  /// **'Show pinned'**
  String get mailPinnedTrayExpand;

  /// No description provided for @mailPinnedTrayCollapse.
  ///
  /// In en, this message translates to:
  /// **'Hide pinned'**
  String get mailPinnedTrayCollapse;

  /// No description provided for @mailMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get mailMarkAllRead;

  /// Toast after marking all mail as read; count is how many were unread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No unread mail} =1{Marked 1 mail as read} other{Marked {count} mails as read}}'**
  String mailMarkedAllRead(int count);

  /// No description provided for @mailMarkAllReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to mark all as read'**
  String get mailMarkAllReadFailed;

  /// Warning banner when some accounts failed to sync during the last refresh; count is how many.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account didn\'\'t sync} other{{count} accounts didn\'\'t sync}}'**
  String mailSyncAccountFailed(int count);

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addLabel;

  /// No description provided for @removeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// No description provided for @waitUploads.
  ///
  /// In en, this message translates to:
  /// **'Wait for attachments to finish uploading'**
  String get waitUploads;

  /// No description provided for @enterRecipient.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one recipient'**
  String get enterRecipient;

  /// Shown when a typed recipient address is malformed.
  ///
  /// In en, this message translates to:
  /// **'Invalid address: {address}'**
  String invalidAddress(String address);

  /// No description provided for @tooManyRecipients.
  ///
  /// In en, this message translates to:
  /// **'Too many recipients'**
  String get tooManyRecipients;

  /// No description provided for @subjectTooLong.
  ///
  /// In en, this message translates to:
  /// **'Subject is too long'**
  String get subjectTooLong;

  /// No description provided for @mailSent.
  ///
  /// In en, this message translates to:
  /// **'Mail sent'**
  String get mailSent;

  /// No description provided for @serverRejectedRecipient.
  ///
  /// In en, this message translates to:
  /// **'Server rejected a recipient'**
  String get serverRejectedRecipient;

  /// Send failure with a server error code.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {code}'**
  String sendFailed(String code);

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSaved;

  /// No description provided for @draftSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save draft'**
  String get draftSaveFailed;

  /// No description provided for @draftUpdated.
  ///
  /// In en, this message translates to:
  /// **'Draft updated'**
  String get draftUpdated;

  /// No description provided for @draftUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update draft'**
  String get draftUpdateFailed;

  /// Attachment upload failure with the file name.
  ///
  /// In en, this message translates to:
  /// **'Failed to attach {filename}'**
  String attachFailed(String filename);

  /// No description provided for @draftConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Draft changed elsewhere'**
  String get draftConflictTitle;

  /// No description provided for @draftConflictBody.
  ///
  /// In en, this message translates to:
  /// **'This draft was modified in another place. Reload the latest version? Your unsaved edits here will be lost.'**
  String get draftConflictBody;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @accountConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Mail accounts'**
  String get accountConnectTitle;

  /// No description provided for @accountOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a mail account'**
  String get accountOnboardingTitle;

  /// No description provided for @accountOnboardingBody.
  ///
  /// In en, this message translates to:
  /// **'Before your inbox can load, connect a mail account. Nothing is fetched until an account is connected.'**
  String get accountOnboardingBody;

  /// No description provided for @accountConnectCta.
  ///
  /// In en, this message translates to:
  /// **'Connect account'**
  String get accountConnectCta;

  /// No description provided for @accountListLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load accounts'**
  String get accountListLoadFailed;

  /// No description provided for @accountGateSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again — your mail accounts are unaffected.'**
  String get accountGateSessionExpired;

  /// No description provided for @accountGateTransientError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the mail service. You can still add an account or open settings; tap retry when you\'re back online.'**
  String get accountGateTransientError;

  /// No description provided for @accountGateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get accountGateRetry;

  /// No description provided for @accountSectionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected accounts'**
  String get accountSectionConnected;

  /// No description provided for @accountSectionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountSectionAdd;

  /// No description provided for @accountProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get accountProviderLabel;

  /// No description provided for @accountAuthCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Authorization code'**
  String get accountAuthCodeLabel;

  /// No description provided for @accountAuthCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the code from the provider consent screen'**
  String get accountAuthCodeHint;

  /// No description provided for @accountAuthCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'Approve access on the provider\'s site, then paste the returned authorization code here.'**
  String get accountAuthCodeHelp;

  /// No description provided for @accountConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get accountConnectAction;

  /// OAuth connect button label; provider is a display name like Google.
  ///
  /// In en, this message translates to:
  /// **'Sign in with {provider}'**
  String accountOAuthConnectWith(String provider);

  /// No description provided for @accountOAuthLaunching.
  ///
  /// In en, this message translates to:
  /// **'Opening sign-in…'**
  String get accountOAuthLaunching;

  /// No description provided for @accountOAuthLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the sign-in page'**
  String get accountOAuthLaunchFailed;

  /// No description provided for @accountOAuthAwaitTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish in your browser'**
  String get accountOAuthAwaitTitle;

  /// No description provided for @accountOAuthAwaitBody.
  ///
  /// In en, this message translates to:
  /// **'Approve access in the browser that opened, then come back here — we\'ll detect the connection automatically.'**
  String get accountOAuthAwaitBody;

  /// No description provided for @accountOAuthCheckAction.
  ///
  /// In en, this message translates to:
  /// **'I\'ve finished — check now'**
  String get accountOAuthCheckAction;

  /// No description provided for @accountOAuthReopen.
  ///
  /// In en, this message translates to:
  /// **'Open sign-in again'**
  String get accountOAuthReopen;

  /// No description provided for @accountAdvancedToggle.
  ///
  /// In en, this message translates to:
  /// **'Advanced: enter a code manually'**
  String get accountAdvancedToggle;

  /// No description provided for @accountConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get accountConnecting;

  /// No description provided for @accountConnected.
  ///
  /// In en, this message translates to:
  /// **'Account connected'**
  String get accountConnected;

  /// No description provided for @accountEmpty.
  ///
  /// In en, this message translates to:
  /// **'No accounts connected yet'**
  String get accountEmpty;

  /// No description provided for @accountAuthCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the authorization code'**
  String get accountAuthCodeRequired;

  /// No description provided for @accountOAuthNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Mail OAuth is not configured on the server. Contact your administrator.'**
  String get accountOAuthNotConfigured;

  /// No description provided for @accountConflict.
  ///
  /// In en, this message translates to:
  /// **'That account is already connected'**
  String get accountConflict;

  /// No description provided for @accountConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect the account'**
  String get accountConnectFailed;

  /// No description provided for @accountOAuthExchangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Signed in, but the server couldn\'t finish connecting the account (OAuth exchange failed). Please try again.'**
  String get accountOAuthExchangeFailed;

  /// No description provided for @accountConnectSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again, then reconnect the account.'**
  String get accountConnectSessionExpired;

  /// No description provided for @accountConnectUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the mail service. Check your connection and try again.'**
  String get accountConnectUnreachable;

  /// No description provided for @accountConnectMalformed.
  ///
  /// In en, this message translates to:
  /// **'The mail server returned an unexpected response (the endpoint may not be deployed yet). Try again, or contact your administrator.'**
  String get accountConnectMalformed;

  /// No description provided for @accountConnectInvalid.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect with these details. Check the provider and code, then try again.'**
  String get accountConnectInvalid;

  /// No description provided for @accountRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get accountRemoveTooltip;

  /// No description provided for @accountRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove account?'**
  String get accountRemoveConfirmTitle;

  /// Confirm dialog body for removing a mail account.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {email}? Its synced mail will be removed.'**
  String accountRemoveConfirmBody(String email);

  /// No description provided for @accountRemoved.
  ///
  /// In en, this message translates to:
  /// **'Account removed'**
  String get accountRemoved;

  /// No description provided for @accountRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove the account'**
  String get accountRemoveFailed;

  /// No description provided for @accountManageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage mail accounts'**
  String get accountManageTooltip;

  /// No description provided for @accountReauthBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnection required'**
  String get accountReauthBannerTitle;

  /// Banner body shown when a connected account needs to re-authenticate (status=reauth_required).
  ///
  /// In en, this message translates to:
  /// **'Authentication for {email} has expired. Reconnect the account to keep sending and receiving mail.'**
  String accountReauthBannerBody(String email);

  /// No description provided for @accountReauthAction.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get accountReauthAction;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get commonSaved;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// No description provided for @commonDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get commonPassword;

  /// No description provided for @commonUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get commonUsername;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginSignIn;

  /// No description provided for @totpTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Authentication'**
  String get totpTitle;

  /// No description provided for @totpCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Authentication code'**
  String get totpCodeLabel;

  /// No description provided for @totpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get totpVerify;

  /// No description provided for @storageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Storage not found.'**
  String get storageNotFound;

  /// No description provided for @listEmptyNoStorages.
  ///
  /// In en, this message translates to:
  /// **'No storages'**
  String get listEmptyNoStorages;

  /// No description provided for @listLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load list'**
  String get listLoadFailed;

  /// No description provided for @noteNew.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get noteNew;

  /// No description provided for @noteName.
  ///
  /// In en, this message translates to:
  /// **'Note name'**
  String get noteName;

  /// No description provided for @noteCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create New Note'**
  String get noteCreateNew;

  /// No description provided for @notesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notes'**
  String get notesEmpty;

  /// No description provided for @folderNew.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get folderNew;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @renameNewName.
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get renameNewName;

  /// Confirm dialog body when deleting a single named item.
  ///
  /// In en, this message translates to:
  /// **'Delete \'{name}\'?'**
  String deleteConfirmName(String name);

  /// No description provided for @bulkDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk Delete'**
  String get bulkDeleteTitle;

  /// Confirm dialog body when deleting multiple items.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} items?'**
  String bulkDeleteConfirmCount(int count);

  /// No description provided for @navSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get navSelectAll;

  /// No description provided for @navSelectionMode.
  ///
  /// In en, this message translates to:
  /// **'Selection mode'**
  String get navSelectionMode;

  /// No description provided for @navExitSearch.
  ///
  /// In en, this message translates to:
  /// **'Exit search'**
  String get navExitSearch;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get navSearchHint;

  /// No description provided for @navLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get navLogout;

  /// No description provided for @navUploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload File'**
  String get navUploadFile;

  /// No description provided for @navManageShareLinks.
  ///
  /// In en, this message translates to:
  /// **'Manage Share Links'**
  String get navManageShareLinks;

  /// No description provided for @navSecuritySettings.
  ///
  /// In en, this message translates to:
  /// **'Security Settings'**
  String get navSecuritySettings;

  /// No description provided for @navServerSettings.
  ///
  /// In en, this message translates to:
  /// **'Server Settings'**
  String get navServerSettings;

  /// No description provided for @previewUnsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes.'**
  String get previewUnsavedChanges;

  /// No description provided for @previewDontSave.
  ///
  /// In en, this message translates to:
  /// **'Don\'t Save'**
  String get previewDontSave;

  /// No description provided for @previewRewind10.
  ///
  /// In en, this message translates to:
  /// **'Rewind 10s'**
  String get previewRewind10;

  /// No description provided for @previewPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get previewPause;

  /// No description provided for @previewPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get previewPlay;

  /// No description provided for @previewForward10.
  ///
  /// In en, this message translates to:
  /// **'Forward 10s'**
  String get previewForward10;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server Address'**
  String get serverAddress;

  /// No description provided for @serverAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., 192.168.1.10:8000'**
  String get serverAddressHint;

  /// No description provided for @serverTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get serverTestConnection;

  /// No description provided for @securityEnable2fa.
  ///
  /// In en, this message translates to:
  /// **'Enable Two-Step Authentication'**
  String get securityEnable2fa;

  /// No description provided for @securityScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code below with your authenticator app.'**
  String get securityScanQr;

  /// No description provided for @securityQrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unable to display QR image'**
  String get securityQrUnavailable;

  /// No description provided for @securityRecoveryInfo.
  ///
  /// In en, this message translates to:
  /// **'If you lose access, recovery codes can help you regain account access.'**
  String get securityRecoveryInfo;

  /// No description provided for @securityAuthCode.
  ///
  /// In en, this message translates to:
  /// **'Authentication Code'**
  String get securityAuthCode;

  /// No description provided for @securityEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get securityEnable;

  /// No description provided for @securityDisable2fa.
  ///
  /// In en, this message translates to:
  /// **'Disable Two-Step Authentication'**
  String get securityDisable2fa;

  /// No description provided for @securityCurrentCode.
  ///
  /// In en, this message translates to:
  /// **'Current Code'**
  String get securityCurrentCode;

  /// No description provided for @securityDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get securityDisable;

  /// No description provided for @securityRegenRecovery.
  ///
  /// In en, this message translates to:
  /// **'Regenerate Recovery Codes'**
  String get securityRegenRecovery;

  /// No description provided for @securityRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get securityRegenerate;

  /// No description provided for @securityNewRecoveryInfo.
  ///
  /// In en, this message translates to:
  /// **'New recovery codes. Store them in a safe place.'**
  String get securityNewRecoveryInfo;

  /// No description provided for @securityRecoveryCopied.
  ///
  /// In en, this message translates to:
  /// **'Recovery codes copied'**
  String get securityRecoveryCopied;

  /// No description provided for @shareDeleteLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Share Link'**
  String get shareDeleteLinkTitle;

  /// Confirm dialog body when deleting a share link for a node.
  ///
  /// In en, this message translates to:
  /// **'Delete link for {name}?'**
  String shareDeleteLinkBody(String name);

  /// No description provided for @shareNoLinks.
  ///
  /// In en, this message translates to:
  /// **'No shared links'**
  String get shareNoLinks;

  /// No description provided for @sharedFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Shared File'**
  String get sharedFileTitle;

  /// No description provided for @sharePasswordProtected.
  ///
  /// In en, this message translates to:
  /// **'This link is password protected'**
  String get sharePasswordProtected;

  /// No description provided for @shareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get shareLinkCopied;

  /// No description provided for @shareCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get shareCopyLink;

  /// No description provided for @shareFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get shareFolderEmpty;

  /// No description provided for @shareSetPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get shareSetPassword;

  /// No description provided for @shareEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get shareEnterPassword;

  /// No description provided for @shareCreateLink.
  ///
  /// In en, this message translates to:
  /// **'Create Link'**
  String get shareCreateLink;

  /// No description provided for @actionPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get actionPreview;

  /// No description provided for @storageNone.
  ///
  /// In en, this message translates to:
  /// **'No Storage'**
  String get storageNone;

  /// No description provided for @uploadClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get uploadClearAll;

  /// No description provided for @vaultOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get vaultOffline;

  /// No description provided for @vaultSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get vaultSync;

  /// No description provided for @vaultLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get vaultLock;

  /// No description provided for @vaultUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock vault'**
  String get vaultUnlockTitle;

  /// No description provided for @vaultUnlockDesc.
  ///
  /// In en, this message translates to:
  /// **'Open the vault with your login password. Your password never leaves this device.'**
  String get vaultUnlockDesc;

  /// No description provided for @vaultUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get vaultUnlock;

  /// No description provided for @vaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved entries'**
  String get vaultEmpty;

  /// No description provided for @vaultCopyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get vaultCopyPassword;

  /// No description provided for @vaultPasswordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied'**
  String get vaultPasswordCopied;

  /// No description provided for @vaultSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get vaultSaved;

  /// No description provided for @vaultSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save'**
  String get vaultSaveFailed;

  /// No description provided for @vaultDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get vaultDeleted;

  /// No description provided for @vaultDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete'**
  String get vaultDeleteFailed;

  /// Confirm dialog body when deleting a vault password entry.
  ///
  /// In en, this message translates to:
  /// **'Delete entry \'{title}\'?'**
  String vaultDeleteConfirm(String title);

  /// No description provided for @vaultEntryNew.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get vaultEntryNew;

  /// No description provided for @vaultEntryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get vaultEntryEdit;

  /// No description provided for @vaultFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get vaultFieldTitle;

  /// No description provided for @vaultFieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get vaultFieldCategory;

  /// No description provided for @vaultFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get vaultFieldNotes;

  /// No description provided for @vaultCategoryWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get vaultCategoryWork;

  /// No description provided for @vaultCategoryPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get vaultCategoryPersonal;

  /// No description provided for @vaultCategoryEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get vaultCategoryEntertainment;

  /// No description provided for @vaultManageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get vaultManageCategories;

  /// No description provided for @vaultCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get vaultCategoryAll;

  /// No description provided for @vaultCategoryNew.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get vaultCategoryNew;

  /// No description provided for @vaultCategoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get vaultCategoryEdit;

  /// No description provided for @vaultCategoryName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get vaultCategoryName;

  /// No description provided for @vaultCategoryIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get vaultCategoryIcon;

  /// No description provided for @vaultCategoryColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get vaultCategoryColor;

  /// No description provided for @vaultCategoryAdded.
  ///
  /// In en, this message translates to:
  /// **'Category added'**
  String get vaultCategoryAdded;

  /// No description provided for @vaultCategoryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Category updated'**
  String get vaultCategoryUpdated;

  /// No description provided for @vaultCategoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Category deleted'**
  String get vaultCategoryDeleted;

  /// No description provided for @vaultCategoryActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Category operation failed'**
  String get vaultCategoryActionFailed;

  /// No description provided for @vaultCategoryDefaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Default categories can\'t be edited or deleted'**
  String get vaultCategoryDefaultLocked;

  /// Confirm dialog body when deleting a custom vault category; its entries are re-homed to the Personal default.
  ///
  /// In en, this message translates to:
  /// **'Delete category \'{name}\'? Its entries will move to \'Personal\'.'**
  String vaultCategoryDeleteConfirm(String name);

  /// No description provided for @vaultMsgDecryptBanner.
  ///
  /// In en, this message translates to:
  /// **'Vault decryption failed. Make sure your login password is correct, then unlock again. (Protection: changes are not saved to the server in this state.)'**
  String get vaultMsgDecryptBanner;

  /// No description provided for @vaultMsgDecryptBlockedSave.
  ///
  /// In en, this message translates to:
  /// **'Can\'t save while decryption has failed. Saving was blocked to avoid overwriting your existing vault — check your password and unlock again.'**
  String get vaultMsgDecryptBlockedSave;

  /// No description provided for @vaultMsgOfflineMode.
  ///
  /// In en, this message translates to:
  /// **'Offline mode: showing the vault stored on this device. It will sync when you\'re back online.'**
  String get vaultMsgOfflineMode;

  /// No description provided for @vaultMsgOfflineSaved.
  ///
  /// In en, this message translates to:
  /// **'Offline: changes were saved only on this device. They\'ll sync with the server when you\'re back online.'**
  String get vaultMsgOfflineSaved;

  /// No description provided for @vaultMsgSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get vaultMsgSessionExpired;

  /// No description provided for @vaultMsgSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync the vault.'**
  String get vaultMsgSyncFailed;

  /// No description provided for @fileDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get fileDownloadFailed;

  /// No description provided for @fileDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get fileDownloadComplete;

  /// No description provided for @fileRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get fileRenamed;

  /// No description provided for @fileNameExists.
  ///
  /// In en, this message translates to:
  /// **'A file with this name already exists'**
  String get fileNameExists;

  /// No description provided for @fileRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to rename'**
  String get fileRenameFailed;

  /// No description provided for @fileDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get fileDeleted;

  /// No description provided for @itemNotFound.
  ///
  /// In en, this message translates to:
  /// **'Item not found'**
  String get itemNotFound;

  /// No description provided for @fileDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete'**
  String get fileDeleteFailed;

  /// No description provided for @noteNameExists.
  ///
  /// In en, this message translates to:
  /// **'A note with this name already exists'**
  String get noteNameExists;

  /// No description provided for @noteCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create note'**
  String get noteCreateFailed;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No search results'**
  String get searchNoResults;

  /// No description provided for @filesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get filesEmpty;

  /// No description provided for @folderCreated.
  ///
  /// In en, this message translates to:
  /// **'Folder created'**
  String get folderCreated;

  /// No description provided for @folderCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create folder'**
  String get folderCreateFailed;

  /// No description provided for @viewGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get viewGrid;

  /// No description provided for @viewList.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get viewList;

  /// No description provided for @totpEnterRecoveryCodeError.
  ///
  /// In en, this message translates to:
  /// **'Enter 8-character recovery code'**
  String get totpEnterRecoveryCodeError;

  /// No description provided for @totpEnterCodeError.
  ///
  /// In en, this message translates to:
  /// **'Enter 6-digit code'**
  String get totpEnterCodeError;

  /// No description provided for @totpRecoveryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code'**
  String get totpRecoveryPrompt;

  /// No description provided for @totpCodePrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter 6-digit code from your authenticator app'**
  String get totpCodePrompt;

  /// No description provided for @totpUseAuthCode.
  ///
  /// In en, this message translates to:
  /// **'Use authentication code'**
  String get totpUseAuthCode;

  /// No description provided for @totpUseRecovery.
  ///
  /// In en, this message translates to:
  /// **'Use recovery code'**
  String get totpUseRecovery;

  /// No description provided for @previewFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get previewFileNotFound;

  /// No description provided for @previewAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get previewAccessDenied;

  /// No description provided for @previewLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load file'**
  String get previewLoadFailed;

  /// No description provided for @previewSaveNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No permission to save'**
  String get previewSaveNoPermission;

  /// No description provided for @previewSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get previewSaveFailed;

  /// No description provided for @previewImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to display image'**
  String get previewImageFailed;

  /// No description provided for @previewPdfFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to display PDF'**
  String get previewPdfFailed;

  /// No description provided for @previewVideoFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to play video'**
  String get previewVideoFailed;

  /// No description provided for @previewAudioFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to play audio'**
  String get previewAudioFailed;

  /// No description provided for @previewUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This file type is not supported for preview'**
  String get previewUnsupported;

  /// No description provided for @securityTotpStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to retrieve TOTP status'**
  String get securityTotpStatusFailed;

  /// No description provided for @securitySetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Setup failed. Please try again'**
  String get securitySetupFailed;

  /// No description provided for @security2faEnabled.
  ///
  /// In en, this message translates to:
  /// **'Two-step authentication has been enabled'**
  String get security2faEnabled;

  /// No description provided for @security2faDisabled.
  ///
  /// In en, this message translates to:
  /// **'Two-step authentication has been disabled'**
  String get security2faDisabled;

  /// No description provided for @securityRecoveryRegenerated.
  ///
  /// In en, this message translates to:
  /// **'Recovery codes have been regenerated'**
  String get securityRecoveryRegenerated;

  /// No description provided for @shareDeleteLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete link'**
  String get shareDeleteLinkFailed;

  /// Toast shown when creating a share link fails; error is the server message.
  ///
  /// In en, this message translates to:
  /// **'Failed to create link: {error}'**
  String shareCreateLinkFailed(String error);

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your account information to return to your workspace'**
  String get loginSubtitle;

  /// No description provided for @loginUsernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your username'**
  String get loginUsernameRequired;

  /// No description provided for @loginPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get loginPasswordRequired;

  /// No description provided for @totpInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid authentication code'**
  String get totpInvalidCode;

  /// No description provided for @totpAuthError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error occurred'**
  String get totpAuthError;

  /// No description provided for @securityInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code'**
  String get securityInvalidCode;

  /// No description provided for @securitySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Two-Step Authentication (TOTP)'**
  String get securitySectionTitle;

  /// No description provided for @securitySectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Extra security using authenticator apps like Google Authenticator'**
  String get securitySectionDesc;

  /// No description provided for @securityStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get securityStatusEnabled;

  /// No description provided for @securityStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get securityStatusDisabled;

  /// No description provided for @securityStep1.
  ///
  /// In en, this message translates to:
  /// **'Step 1. Scan QR Code'**
  String get securityStep1;

  /// No description provided for @securityStep2.
  ///
  /// In en, this message translates to:
  /// **'Step 2. Save Recovery Codes'**
  String get securityStep2;

  /// No description provided for @securityStep3.
  ///
  /// In en, this message translates to:
  /// **'Step 3. Enter Authentication Code'**
  String get securityStep3;

  /// No description provided for @serverInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid format'**
  String get serverInvalidFormat;

  /// No description provided for @serverPortRequired.
  ///
  /// In en, this message translates to:
  /// **'Port number is required (e.g., 192.168.1.10:8000)'**
  String get serverPortRequired;

  /// No description provided for @serverPortNumeric.
  ///
  /// In en, this message translates to:
  /// **'Port number must be numeric'**
  String get serverPortNumeric;

  /// No description provided for @serverPortRange.
  ///
  /// In en, this message translates to:
  /// **'Port must be between 1 and 65535'**
  String get serverPortRange;

  /// No description provided for @serverAddressDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the host and port of the server to connect to.'**
  String get serverAddressDesc;

  /// No description provided for @shareUnknownError.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred'**
  String get shareUnknownError;

  /// No description provided for @shareCreateLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Share Link'**
  String get shareCreateLinkTitle;

  /// No description provided for @navFoldersHeader.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get navFoldersHeader;

  /// No description provided for @storageSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageSectionLabel;

  /// No description provided for @uploadWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get uploadWaiting;

  /// No description provided for @uploadDropHere.
  ///
  /// In en, this message translates to:
  /// **'Drop files here'**
  String get uploadDropHere;

  /// App bar title showing how many items are selected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// Toast after a bulk delete completes.
  ///
  /// In en, this message translates to:
  /// **'{count} items deleted'**
  String bulkDeleted(int count);

  /// Toast when only some of a bulk delete succeeded.
  ///
  /// In en, this message translates to:
  /// **'Some items failed to delete ({done}/{total})'**
  String bulkDeletePartial(int done, int total);

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeJustNow;

  /// Relative time, minutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute ago} other{{count} minutes ago}}'**
  String relativeMinutesAgo(int count);

  /// Relative time, hours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String relativeHoursAgo(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

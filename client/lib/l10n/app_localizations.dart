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

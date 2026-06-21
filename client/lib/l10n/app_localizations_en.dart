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
}

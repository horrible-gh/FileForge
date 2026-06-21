// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'FileForge';

  @override
  String get mailComposeTooltip => '편지 쓰기';

  @override
  String get mailListEmpty => '메일 없음';

  @override
  String get mailLoadFailed => '메일을 불러오지 못했습니다';

  @override
  String get mailDetailTitle => '메일';

  @override
  String get noSubject => '(제목 없음)';

  @override
  String get labelInbox => '받은편지함';

  @override
  String get labelDrafts => '임시보관함';

  @override
  String get labelSent => '보낸편지함';

  @override
  String get draftLoadFailed => '초안을 불러오지 못했습니다';

  @override
  String get fieldFrom => '보낸사람';

  @override
  String get fieldTo => '받는사람';

  @override
  String get fieldCc => '참조';

  @override
  String get fieldBcc => '숨은참조';

  @override
  String get composeTitleNew => '새 메일';

  @override
  String get composeTitleReply => '답장';

  @override
  String get composeTitleReplyAll => '전체답장';

  @override
  String get composeTitleForward => '전달';

  @override
  String get composeTitleDraft => '초안';

  @override
  String get saveDraftTooltip => '초안 저장';

  @override
  String get sendTooltip => '보내기';

  @override
  String get ccBccToggle => '참조 / 숨은참조';

  @override
  String get subjectLabel => '제목';

  @override
  String get messageLabel => '내용';

  @override
  String get htmlSourceHint => '<p>HTML 소스…</p>';

  @override
  String get formatLabel => '형식:';

  @override
  String get formatPlain => '일반';

  @override
  String get formatHtml => 'HTML';

  @override
  String get attachmentsLabel => '첨부파일';

  @override
  String get addLabel => '추가';

  @override
  String get removeLabel => '삭제';

  @override
  String get waitUploads => '첨부파일 업로드가 끝날 때까지 기다려 주세요';

  @override
  String get enterRecipient => '받는사람을 한 명 이상 입력하세요';

  @override
  String invalidAddress(String address) {
    return '잘못된 주소: $address';
  }

  @override
  String get tooManyRecipients => '받는사람이 너무 많습니다';

  @override
  String get subjectTooLong => '제목이 너무 깁니다';

  @override
  String get mailSent => '메일을 보냈습니다';

  @override
  String get serverRejectedRecipient => '서버가 받는사람을 거부했습니다';

  @override
  String sendFailed(String code) {
    return '보내기 실패: $code';
  }

  @override
  String get draftSaved => '초안을 저장했습니다';

  @override
  String get draftSaveFailed => '초안을 저장하지 못했습니다';

  @override
  String get draftUpdated => '초안을 갱신했습니다';

  @override
  String get draftUpdateFailed => '초안을 갱신하지 못했습니다';

  @override
  String attachFailed(String filename) {
    return '$filename 첨부에 실패했습니다';
  }

  @override
  String get draftConflictTitle => '초안이 다른 곳에서 변경됨';

  @override
  String get draftConflictBody =>
      '이 초안이 다른 곳에서 수정되었습니다. 최신 버전을 다시 불러올까요? 여기서 저장하지 않은 편집 내용은 사라집니다.';

  @override
  String get keepEditing => '계속 편집';

  @override
  String get reload => '다시 불러오기';
}

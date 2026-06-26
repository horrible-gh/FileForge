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

  @override
  String get accountConnectTitle => '메일 계정';

  @override
  String get accountOnboardingTitle => '메일 계정을 연결하세요';

  @override
  String get accountOnboardingBody =>
      '받은편지함을 불러오려면 먼저 메일 계정을 연결해야 합니다. 계정을 연결하기 전에는 메일을 가져오지 않습니다.';

  @override
  String get accountConnectCta => '계정 연결';

  @override
  String get accountListLoadFailed => '계정을 불러오지 못했습니다';

  @override
  String get accountGateSessionExpired =>
      '세션이 만료되었습니다. 다시 로그인해 주세요 — 메일 계정에는 영향이 없습니다.';

  @override
  String get accountGateTransientError =>
      '메일 서비스에 연결하지 못했습니다. 계정 추가와 설정 열기는 계속 가능합니다. 온라인 상태가 되면 다시 시도하세요.';

  @override
  String get accountGateRetry => '다시 시도';

  @override
  String get accountSectionConnected => '연결된 계정';

  @override
  String get accountSectionAdd => '계정 추가';

  @override
  String get accountProviderLabel => '제공자';

  @override
  String get accountAuthCodeLabel => '인증 코드';

  @override
  String get accountAuthCodeHint => '제공자 동의 화면에서 받은 코드를 붙여넣으세요';

  @override
  String get accountAuthCodeHelp =>
      '제공자 사이트에서 접근을 승인한 뒤, 반환된 인증 코드를 여기에 붙여넣으세요.';

  @override
  String get accountConnectAction => '연결';

  @override
  String accountOAuthConnectWith(String provider) {
    return '$provider(으)로 로그인';
  }

  @override
  String get accountOAuthLaunching => '로그인 화면 여는 중…';

  @override
  String get accountOAuthLaunchFailed => '로그인 페이지를 열 수 없습니다';

  @override
  String get accountOAuthAwaitTitle => '브라우저에서 마저 진행하세요';

  @override
  String get accountOAuthAwaitBody =>
      '열린 브라우저에서 접근을 승인한 뒤 이 화면으로 돌아오면, 연결을 자동으로 확인합니다.';

  @override
  String get accountOAuthCheckAction => '완료했어요 — 지금 확인';

  @override
  String get accountOAuthReopen => '로그인 다시 열기';

  @override
  String get accountAdvancedToggle => '고급: 코드 직접 입력';

  @override
  String get accountConnecting => '연결 중…';

  @override
  String get accountConnected => '계정을 연결했습니다';

  @override
  String get accountEmpty => '아직 연결된 계정이 없습니다';

  @override
  String get accountAuthCodeRequired => '인증 코드를 입력하세요';

  @override
  String get accountOAuthNotConfigured => '서버에 메일 OAuth 설정이 없습니다. 관리자에게 문의하세요.';

  @override
  String get accountConflict => '이미 연결된 계정입니다';

  @override
  String get accountConnectFailed => '계정 연결에 실패했습니다';

  @override
  String get accountOAuthExchangeFailed =>
      '로그인은 됐지만 서버가 계정 연결을 마치지 못했습니다(OAuth 교환 실패). 다시 시도해 주세요.';

  @override
  String get accountConnectSessionExpired =>
      '세션이 만료되었습니다. 다시 로그인한 뒤 계정을 연결해 주세요.';

  @override
  String get accountConnectUnreachable =>
      '메일 서버에 연결할 수 없습니다. 네트워크를 확인하고 다시 시도해 주세요.';

  @override
  String get accountConnectMalformed =>
      '메일 서버가 예기치 않은 응답을 보냈습니다(엔드포인트가 아직 배포되지 않았을 수 있음). 다시 시도하거나 관리자에게 문의하세요.';

  @override
  String get accountConnectInvalid =>
      '이 정보로는 연결할 수 없습니다. 제공자와 코드를 확인하고 다시 시도해 주세요.';

  @override
  String get accountRemoveTooltip => '계정 해제';

  @override
  String get accountRemoveConfirmTitle => '계정을 해제할까요?';

  @override
  String accountRemoveConfirmBody(String email) {
    return '$email 계정을 해제할까요? 동기화된 메일도 함께 삭제됩니다.';
  }

  @override
  String get accountRemoved => '계정을 해제했습니다';

  @override
  String get accountRemoveFailed => '계정 해제에 실패했습니다';

  @override
  String get accountManageTooltip => '메일 계정 관리';

  @override
  String get accountReauthBannerTitle => '재연결이 필요합니다';

  @override
  String accountReauthBannerBody(String email) {
    return '$email 계정의 인증이 만료되었습니다. 메일을 계속 주고받으려면 계정을 다시 연결해 주세요.';
  }

  @override
  String get accountReauthAction => '재연결';

  @override
  String get cancel => '취소';
}

-- mailanchor.ui.0003 T1 — FileForge 연합 인증 다리(RS256 토큰 공유).
-- FileForge가 발급한 토큰의 subject(외부 user_id)를 로컬 app_user에 안정적으로 매핑한다.
-- 로컬 비번 로그인 사용자는 NULL(연합 대상 아님). 연합 provisioning 시에만 채워진다.
ALTER TABLE app_user ADD COLUMN external_subject TEXT;
-- 동일 외부 subject가 두 로컬 계정으로 갈라지는 것을 방지(NULL은 제약 비대상).
CREATE UNIQUE INDEX ux_app_user_external_subject
    ON app_user(external_subject) WHERE external_subject IS NOT NULL;

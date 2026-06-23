-- mailanchor.ui.0003 T1 — FileForge 연합 인증 다리(RS256 토큰 공유). [MySQL]
-- FileForge 토큰의 subject(외부 user_id)를 로컬 app_user 에 안정 매핑한다.
-- 로컬 비번 로그인 사용자는 NULL(연합 대상 아님).
-- 방언 메모: MySQL UNIQUE 인덱스는 NULL 다건을 허용하므로 SQLite의
-- `WHERE external_subject IS NOT NULL` 부분 유니크와 동작 동등하다.
ALTER TABLE app_user ADD COLUMN external_subject VARCHAR(255);
CREATE UNIQUE INDEX ux_app_user_external_subject ON app_user(external_subject);

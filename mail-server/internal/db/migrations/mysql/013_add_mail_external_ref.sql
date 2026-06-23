-- NR0003 §5.E 해소: 동기화(F)가 mail.find_by_external_ref(account_id, external_id)를
-- 핵심 알고리즘으로 쓴다. external_ref 컬럼+유니크 인덱스 추가. [MySQL]
-- 방언 메모: MySQL UNIQUE 인덱스는 NULL 을 서로 다른 값으로 취급하므로,
-- SQLite의 `WHERE external_ref IS NOT NULL` 부분 유니크와 동작이 동등하다
-- (NULL=로컬 outbound 다건 허용, 비-NULL만 계정범위 중복차단).
ALTER TABLE mail ADD COLUMN external_ref VARCHAR(255);
CREATE UNIQUE INDEX ix_mail_external_ref ON mail(account_id, external_ref);

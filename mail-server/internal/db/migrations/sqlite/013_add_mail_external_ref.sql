-- NR0003 §5.E 해소: L0013 동기화는 mail.find_by_external_ref(account_id, external_id)를
-- 핵심 알고리즘으로 쓰지만 DB0008에는 external_ref 컬럼이 없었다(DB0008 DEFERRED).
-- 동기화(F) 모듈 구현을 위해 가산 마이그레이션으로 컬럼+유니크 인덱스를 추가한다.
ALTER TABLE mail ADD COLUMN external_ref TEXT;          -- 외부 메시지 식별자(provider 발급)
-- 계정 범위 내 external_ref 중복 삽입 방지(발신 echo 흡수). NULL(로컬 outbound)은 유니크 제약 비대상.
CREATE UNIQUE INDEX ix_mail_external_ref ON mail(account_id, external_ref) WHERE external_ref IS NOT NULL;

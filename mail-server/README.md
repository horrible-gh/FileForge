# mailanchord — MailAnchor Go 백엔드 (Phase 0 베이스)

R0001 「메일앵커 흡수」의 **초기 구현(베이스)**. 설계계약(P0007·L0010·L0011·DB0008)을 정본으로 하는,
cgo 없는 단일 바이너리 Go 서비스다. 메일/관리/동기화(Phase 1)는 이 베이스 위에 얹는다(NR0003 §6).

## 무엇이 들어있나 (Phase 0)
- **config** — env 기반 설정. 토큰 TTL 기본값 = L0010 §1(access 900s, refresh 30일).
- **DB 마이그레이션** — DB0008 001~012 + **013(external_ref, NR0003 §5.E 해소)**. SQLite 방언, `embed`로 번들, `schema_migrations`로 추적. FK 강제(ON), 부분 인덱스 포함.
- **공통 봉투** — P0007 §1 성공/에러 봉투 + 에러 카탈로그 13종(P0007 §5).
- **인증(A)** — P0007 §6.1 `/auth/login·refresh·logout·session`.
  - 비번 **argon2id**(L0011 §1), 로그인 실패 잠금(in-memory, L0011 §2.5), 미존재 더미검증.
  - access **무상태 HS256 JWT**(L0010: DB 미저장), refresh **회전형 opaque**(해시만 저장, 재사용 탐지 시 체인 폐기 — L0010 §2.1).
  - 인증 미들웨어(Bearer) + `/me` 데모.

## 결정 반영 (NR0003 §7)
- D1 인증 소유권 = **Go 자체 소유**(`/auth/*` 구현). D2 본문 = DB `body_content`. D3 external_ref = **마이그 013 추가**. D4 범위 = DB0008 정본(star/pin/folder 제외).

## 빌드·실행
```sh
go test ./...                 # 유닛 + 인증 플로 스모크
go build ./cmd/mailanchord
MAILANCHOR_JWT_SECRET=... ./mailanchord -seed-email a@b.com -seed-password pw   # 개발용 사용자 시드(가입은 DEFERRED)
MAILANCHOR_JWT_SECRET=... ./mailanchord                                          # 서버 기동(:8090, /api/v1)
```

## 환경변수
| 변수 | 기본값 | 의미 |
|---|---|---|
| `MAILANCHOR_ADDR` | `:8090` | 리슨 주소 |
| `MAILANCHOR_CONTEXT` | `/api/v1` | API 베이스 경로(P0007) |
| `MAILANCHOR_DB_PATH` | `./mailanchor.db` | SQLite 파일 |
| `MAILANCHOR_JWT_SECRET` | (개발용 폴백) | HS256 서명키 — 운영 필수 |
| `MAILANCHOR_ACCESS_TTL_SEC` | `900` | access TTL |
| `MAILANCHOR_REFRESH_TTL_SEC` | `2592000` | refresh TTL(30일) |
| `GOOGLE_CLIENT_ID` | (없음) | Gmail OAuth 클라이언트 ID. 없으면 `/accounts/oauth/authorize?provider=gmail`는 503 `oauth not configured` |
| `GOOGLE_CLIENT_SECRET` | (없음) | Gmail OAuth 클라이언트 secret |
| `GOOGLE_REDIRECT_URI` | (없음) | Google Cloud Console의 Authorized redirect URI와 동일해야 함. 로컬 예: `http://localhost:8090/api/v1/accounts/oauth/callback` |
| `MAILANCHOR_OAUTH_RETURN_URL` | (없음) | OAuth 완료 후 앱으로 되돌릴 URL. 없으면 서버가 자체 완료 HTML을 렌더링 |
| `MAILANCHOR_FILEFORGE_JWT_PUBKEY` | (없음) | FileForge RS256 공개키(PEM 인라인). 설정 시 토큰 공유 다리 ON |
| `MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE` | (없음) | 위 키를 파일 경로로 주입(인라인 미설정 시) |
| `MAILANCHOR_FILEFORGE_ISSUER` | (없음) | 기대 `iss` 클레임(설정 시 강제) |
| `MAILANCHOR_FILEFORGE_AUDIENCE` | (없음) | 기대 `aud` 클레임(설정 시 강제) |

`MAILANCHOR_OAUTH_GMAIL_CLIENT_ID`, `MAILANCHOR_OAUTH_GMAIL_CLIENT_SECRET`,
`MAILANCHOR_OAUTH_GMAIL_REDIRECT_URI`도 legacy fallback으로 읽지만, 신규 설정은
`GOOGLE_*`를 우선한다. `/api/v1/healthz`의 `oauth_configured`와 `oauth_providers`로
기동 직후 OAuth 설정 반영 여부를 확인할 수 있다.

> **`GOOGLE_*`를 넣었는데 서버가 안 뜨는 경우**: 이 값들은 서버 기동을 막지 않는다(미설정은
> `/accounts/oauth/authorize`만 503으로 만들 뿐이다). 기동 실패의 실제 원인은 거의 항상
> `MAILANCHOR_ADDR`(기본 `:8090`) **포트 중복**이다 - 이전 `mailanchord` 인스턴스가 아직 그
> 포트를 잡고 있으면 새 프로세스가 `bind: address already in use`로 즉시 종료된다. 기존
> 인스턴스를 먼저 종료(`taskkill /F /IM mailanchord.exe`)하고 해당 포트가 비었는지 확인한 뒤
> 다시 기동한다. 루트 `run-server.ps1` 또는 `scripts/run-mail-server.ps1`는 재기동 시 포트가
> 실제로 해제될 때까지 대기한 후 빌드/기동한다.

## FileForge 토큰 공유 다리 (구현됨, mailanchor.ui.0003 T1)
폴리글랏(Python FileForge ↔ Go) 경계를 **시크릿 없이** 잇는 연합 인증. FileForge 공개키만 경계를
넘는다(`internal/auth/federated.go`).
- **동작** — Bearer 토큰은 먼저 자체 HS256으로 검증하고, *유효하지 않으면*(만료는 그대로 TOKEN_EXPIRED)
  FileForge 공개키로 **RS256** 검증을 재시도한다. 통과하면 토큰 `sub`(FileForge user id)에 묶인
  로컬 `app_user`를 **최초 1회 just-in-time provisioning**(마이그 015 `external_subject`, 시스템 라벨·설정 시드)하고
  이후 동일 subject는 멱등 재사용한다. `email`/`display_name` 클레임은 best-effort(없으면 결정론적 합성).
- **보안** — RS256만 허용(`alg=HS256` confusion 거부), iss/aud 강제(설정 시), 서명·만료 검증.
- **검증** — 유닛(`federated_test.go`: provisioning·멱등·만료/iss/aud/위조키/alg-confusion 거부) +
  **라이브 로컬 스모크 1건**: FileForge 서명 RS256 토큰 하나로 실서버 `/me`·`/mails`·`/auth/session` = 200,
  미인증/위조 = 401, app_user 1행 멱등 생성 확인(완료기준 충족).
- **발급 측 완료(mailanchor.ui.0003 T0004)** — FileForge(Python) `routers/login/jwt_keys.py`가 access 토큰을
  **RS256**으로 발급(개인키 서명, `email`/`display_name`/`iss`/`aud` 클레임 동봉). refresh/totp-pending은 내부용
  HS256 유지. **종단 라이브 스모크**: FileForge가 실제 서명한 RS256 토큰 1개로 Go `/me`·`/mails`·`/auth/session` = 200,
  `app_user`에 `email=smoke@fileforge.example`·`display_name`이 토큰 클레임에서 적재(합성 아님), 멱등 1행 확인.

## Phase 1 — DB-only 슬라이스 (구현됨, `internal/mailapi`)
보호 라우트 그룹에 마운트됨(모두 access 필요):
- **라벨(M)** — `GET/POST /labels`, `PATCH/DELETE /labels/{id}`. LABEL_DUPLICATE(409), 시스템 라벨 불변(403).
- **설정(M)** — `GET/PATCH /settings/display`, `GET/PATCH /settings/sync`. 열거 검증(VALIDATION_FAILED).
- **메일 읽기경로(C)** — `GET /mails`(키셋 커서·라벨/검색/unread 필터, L0012 §2.1), `GET /mails/{id}`(상세+첨부+라벨), `PATCH /mails/{id}`(is_read·labels_add/remove 트랜잭션, L0012 §2.5).
- `Store.SeedMail`은 동기화(F)가 쓸 데이터를 대신 넣는 테스트/개발용(HTTP 쓰기경로는 미구현).

## Phase 1 — 잔여 (외부 서비스 의존, 다음 작업)
- **발송(D)/SMTP, 동기화(F)/IMAP, 계정 OAuth, 첨부 바이트** — 기존 MailAnchor(Python) 로직을 go-imap/go-message/go-smtp/x/oauth2/go-redis로 이식. F는 마이그 013(external_ref) 머지(L0013) 위.
- 운영 전환: ~~HS256→RS256(폴리글랏 시)~~ **→ 수신·발급 양측 완료(T1, 위 「FileForge 토큰 공유 다리」). 종단 라이브 검증됨.** Accept-Language 협상, 멀티 방언(MySQL/PG) 마이그.
- **T3 SMTP — 전송 스모크 추가됨**: `smtpx`에 **루프백 소켓 라이브 전송 테스트**(`sender_send_test.go`: 실 TCP 소켓으로 net/smtp EHLO→MAIL→RCPT→DATA→QUIT 완주, 봉투에 To+Cc+**Bcc** 포함·헤더엔 Bcc 미노출 검증)를 추가했다. 기존 테스트는 `build()`만 덮었음. 단 이는 **전송 계층** 스모크이지 *실 계정/프로바이더* 스모크는 아님.
- **T2 IMAP / T3 실계정 / T4 Gmail OAuth / T5 E2E — 실계정 라이브 스모크 잔여**: 어댑터(`imapx`/`smtpx`/`oauthx`)는 구현·유닛 그린(`go test ./...` all ok)이나, R0001의 완료기준인 *실 크리덴셜 라이브 스모크*는 무인 환경에 실 메일계정/Gmail OAuth 클라이언트가 없어 미수행. 주입 시 `MAILANCHOR_SMTP_*`(발송)·계정 행(IMAP)·`MAILANCHOR_OAUTH_GMAIL_*`(OAuth)로 수행.

# mail-server/ — NON-OPERATIONAL LEGACY (do not run)

> **This directory is a stale, non-operational copy. It is NOT built or started by
> any setup/run script (NR0003, group 0002).** The standalone MailAnchor backend
> was absorbed into the FileForge FastAPI server: the mail subsystem now lives at
> `server/routers/mail/*` and is served on the same origin as the file API
> (`http://localhost:8000/fileforge/mail/*`). There is no separate `:8090`
> process, no separate `mail-server/.env`, and the `mail-server` setup target is a
> no-op kept only for automation compatibility.
>
> Run the project from the repository root instead: `./run-server.sh` (or
> `.\run-server.ps1`). The notes below are retained for historical reference only.

---

FileForge Server Application (legacy reference)

## Local OAuth test setup

1. Copy `.env.sample` to `.env` and `logger.json.sample` to `logger.json`.
2. Keep `CONTEXT=/fileforge` when using the UI sample config.
3. Set these Google OAuth values in `.env`:
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`
   - `GOOGLE_REDIRECT_URI=http://127.0.0.1:8000/fileforge/oauth/gmail/callback`
4. Add the same `GOOGLE_REDIRECT_URI` to the Google Cloud Console OAuth client's Authorized redirect URIs. The value must match exactly.
5. Keep the browser return URL separate from CORS:
   - `ALLOWED_ORIGIN=http://localhost:11001,http://127.0.0.1:11001`
   - `FRONTEND_BASE_URL=http://localhost:11001`
   - `OAUTH_SUCCESS_REDIRECT_URL=http://localhost:11001/dashboard/mail/oauth/gmail/callback`
6. Start Redis on `localhost:6379`; Gmail OAuth state is stored there for 10 minutes.

If the API server is not running on `127.0.0.1:8000`, update both `GOOGLE_REDIRECT_URI` and the Google Cloud Console redirect URI to the actual local API origin.

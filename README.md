# FileForge

> A lightweight self-hosted file hub for developers, personal servers, and small internal tools.

FileForge is a compact file management system built around a FastAPI backend and a Flutter client.  
It is designed for people who want a practical file layer they can run on their own server without adopting a full cloud suite or groupware platform.

Use it as a personal file server, a project attachment backend, or a simple internal file hub for tools that need uploads, downloads, previews, sharing, and authentication.

---

## Why FileForge?

Many file platforms are powerful, but they often come with more scope than a small project actually needs.

FileForge focuses on a narrower goal:

- keep files on infrastructure you control
- provide a clean client for everyday file operations
- support common file-server features without becoming a full collaboration suite
- remain small enough to understand, modify, and integrate into other systems

It is not trying to replace every feature of large platforms such as Nextcloud or Seafile.  
Instead, FileForge is intended to be a lightweight file hub that can be embedded into a personal or internal service ecosystem.

---

## Project Status

FileForge is an early-stage project.

It is currently suitable as a personal or internal-use system for developers who can review and operate their own deployment. Public packaging, one-command production deployment, and full hardening are not the current priority.

Before exposing FileForge to the internet, review your reverse proxy, HTTPS, CORS, authentication, secrets, storage permissions, and backup strategy.

---

## Core Features

- File upload and download
- Batch download as ZIP
- Folder tree navigation
- File preview for common formats
  - PDF
  - images
  - video
  - audio
- Public share links
- Share pages
- JWT-based authentication
- TOTP two-factor authentication
- File search
- Endpoint rate limiting
- Multi-language support
  - Korean
  - English
  - Japanese
- Local filesystem storage with UUID-based directories
- SQLite by default, with MySQL and PostgreSQL support

---

## Architecture

```text
FileForge
├── server/   FastAPI backend
└── client/   Flutter cross-platform client
```

### Server

The server provides the API, authentication, file metadata handling, sharing logic, rate limiting, and storage access.

### Client

The client is built with Flutter and is intended to run across web, mobile, and desktop targets from a single codebase.

---

## Technology Stack

| Layer | Stack |
|---|---|
| Backend | Python, FastAPI |
| Authentication | JWT, TOTP |
| Cache / Token blacklist | Redis |
| Database | SQLite, MySQL, PostgreSQL |
| Client | Flutter, Dart |
| Storage | Local filesystem, UUID-based paths |
| Supported client targets | Web, Android, iOS, Windows, macOS, Linux |

---

## Repository Layout

```text
FileForge/
├── server/                 # Backend API
├── client/                 # Flutter client
├── run-server.bat          # Windows helper script for server startup
├── run-app-chrome.bat      # Windows helper script for Flutter web startup
├── .gitignore
└── README.md
```

---

## Getting Started

### Prerequisites

- Python 3.10+
- Flutter 3.x SDK
- Redis
- Git

Redis is used for token blacklist and related authentication state.

---

## Server Setup

```bash
cd server
cp .env.sample .env
pip install -r requirements.txt
python app.py
```

Then edit `.env` for your environment.

The server starts at:

```text
http://localhost:8000
```

If `CONTEXT` is configured, the API path may be served under that prefix.

---

## Client Setup

```bash
cd client
cp config/dev.json config/prod.json
flutter pub get
flutter run
```

For production configuration:

```bash
flutter run --dart-define=ENV=prod
```

Edit the client config before using a remote server.

---

## Server Configuration

Common `.env` values:

| Key | Description | Default |
|---|---|---|
| `SECRET_KEY` | JWT signing secret | Required |
| `DB_TYPE` | `sqlite`, `mysql`, or `postgresql` | `sqlite` |
| `DB_PATH` | SQLite database path | `./fileforge.db` |
| `CONTEXT` | API path prefix | `/fileforge` |
| `ALLOWED_ORIGIN` | CORS allowed origins | `*` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Access token lifetime in minutes | `30` |

For internet-facing deployments, avoid using `ALLOWED_ORIGIN=*` unless you fully understand the risk.

---

## Client Configuration

Common client config values:

| Key | Description |
|---|---|
| `SERVER_URL` | Full URL to the FileForge API |
| `SHARE_BASE_URL` | Base URL used for generated share links |

Example:

```json
{
  "SERVER_URL": "https://example.com/fileforge",
  "SHARE_BASE_URL": "https://example.com/fileforge/share"
}
```

---

## Deployment Notes

FileForge can be placed behind a reverse proxy such as Nginx or Caddy.

Recommended production basics:

- Use HTTPS
- Set a strong `SECRET_KEY`
- Restrict CORS origins
- Run the server behind a reverse proxy
- Protect upload/storage directories with correct filesystem permissions
- Keep Redis private
- Back up the database and storage directory together
- Review maximum upload size limits at both app and reverse proxy level

---

## Security Notes

FileForge handles user authentication and file access, so deployment security matters.

Before using it outside a private network, review:

- secret management
- token expiration policy
- TOTP recovery process
- CORS policy
- public share link behavior
- rate limit settings
- file size limits
- MIME type handling
- reverse proxy headers
- backup and restore procedure

This project is provided as-is. You are responsible for reviewing and securing your own deployment.

---

## Intended Use Cases

FileForge is a good fit for:

- personal self-hosted file storage
- small internal tools that need file uploads
- project attachment storage
- lightweight file sharing behind your own domain
- developer-controlled environments
- systems where a full cloud suite would be excessive

FileForge is probably not the right fit if you need:

- enterprise compliance workflows
- large-scale multi-tenant SaaS hosting
- real-time collaborative editing
- mature desktop sync clients
- a fully packaged consumer product experience

---

## Roadmap Ideas

### Deployment & Operations
- Docker Compose based one-command deployment
- Health check endpoints and upgrade path documentation

### File Management
- Bulk move, copy, rename, and delete actions
- Drag-and-drop upload and large file handling improvements

### Sharing & Access Control
- Expiring and password-protected share links
- Per-folder access rules and download limit controls

### Developer & Integration
- Webhook support for upload/download events
- File attachment backend for internal tools and AI workflows

### Search & Metadata
- Full-text search for supported document types
- Tag-based organization and custom metadata fields

### Security & Reliability
- Audit logs for sensitive operations
- File integrity checks and safer default configuration

### Client Experience
- Better responsive layout for desktop, tablet, and mobile
- Dark mode support and multi-language UI refinement

### Long-Term Vision

FileForge aims to be a compact, self-hosted file infrastructure layer —
light enough for a personal server, structured enough for internal tools,
and open enough to become the file backend of larger systems.

The focus remains on the file workflows that actually matter:
upload, organize, preview, share, protect, and integrate.

---

## Development Philosophy

FileForge is built with a practical bias:

- simple enough to operate on a personal server
- modular enough to integrate into other systems
- explicit enough to debug without a large platform stack
- useful before it becomes perfect

The goal is not to build the biggest file platform.  
The goal is to provide a file layer that is understandable, controllable, and easy to adapt.

---

## License

MIT

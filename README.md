# FileForge

> A self-hosted personal file management service with a cross-platform client.

![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

FileForge is a self-hosted file storage and management solution.  
The backend is built with **Python / FastAPI** and the client is a **Flutter** app that runs on Web, Android, iOS, and Desktop from a single codebase.

## Repository Structure

```
FileForge/
├── server/     Backend API (Python / FastAPI)
└── client/     Cross-platform client (Flutter)
```

## Technology Stack

| Component | Stack |
|-----------|-------|
| Server | Python, FastAPI, JWT, Redis |
| Database | SQLite (default) · MySQL · PostgreSQL |
| Client | Flutter / Dart |
| Platforms | Web, Android, iOS, Windows, macOS, Linux |
| Storage | File system (UUID-based directories) |

## Features

- 📁 File upload / download / batch download (zip)
- 🌲 Folder tree navigation
- 👁️ File preview — PDF, video, audio, images
- 🔗 Shared links & public share pages
- 🔐 TOTP 2-factor authentication
- 🌐 Multi-language support (Korean / English / Japanese)
- 🔍 File search
- ⚡ Rate limiting per endpoint

## Getting Started

### Prerequisites

- Python 3.10+
- Flutter 3.x SDK
- Redis (required for token blacklist)

### Server

```bash
cd server
cp .env.sample .env
# Edit .env — set DB_TYPE, credentials, SECRET_KEY, etc.
pip install -r requirements.txt
python app.py
```

The server starts at `http://localhost:8000` by default.  
See `.env.sample` for all available configuration options including database type (`sqlite` / `mysql` / `postgresql`) and rate limits.

### Client

```bash
cd client
# Copy and edit the config for your environment
cp config/dev.json config/prod.json
# Edit config/prod.json — set SERVER_URL to your server address
flutter pub get
flutter run          # dev (auto-detects platform)
# or
flutter run --dart-define=ENV=prod   # production config
```

## Configuration

### Server — `.env`

| Key | Description | Default |
|-----|-------------|---------|
| `SECRET_KEY` | JWT signing secret | *(required)* |
| `DB_TYPE` | `sqlite` / `mysql` / `postgresql` | `sqlite` |
| `DB_PATH` | Path to SQLite file | `./fileforge.db` |
| `CONTEXT` | API path prefix | `/fileforge` |
| `ALLOWED_ORIGIN` | CORS allowed origins (comma-separated) | `*` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | JWT expiry in minutes | `30` |

### Client — `config/`

| Key | Description |
|-----|-------------|
| `SERVER_URL` | Full URL to the FileForge API (e.g. `http://localhost:8000/fileforge`) |
| `SHARE_BASE_URL` | Base URL used when generating share links |

## License

MIT

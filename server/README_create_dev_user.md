# FileForge Dev User Creation Tool

**⚠️ Development/Testing Only** — Do not use in production!

## Overview

`create_dev_user.py` is a command-line utility for creating development and test users in FileForge server. It provides a convenient way to generate users with default or custom credentials, manage JWT tokens, and list/delete users directly from the database.

## Quick Start

### Basic Usage

```bash
# Create a single dev user (dev1@fileforge.local)
python create_dev_user.py

# Create multiple dev users (dev1~dev5@fileforge.local)
python create_dev_user.py --count 5

# Create a user with custom email and password
python create_dev_user.py --email testuser@company.com --password mypassword

# Create an admin user
python create_dev_user.py --email admin@test.local --role admin

# List all users
python create_dev_user.py --list

# Re-issue JWT token for a user
python create_dev_user.py --token dev1@fileforge.local

# Delete a user
python create_dev_user.py --delete dev1@fileforge.local
```

## Command-Line Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--email EMAIL` | string | `dev{N}@fileforge.local` | Email address for the user |
| `--password PASSWORD` | string | `devpass123` | User password |
| `--role {user,admin}` | choice | `user` | User role |
| `--count N` | integer | `1` | Number of users to create |
| `--storage NAME` | string | - | Storage name to assign. Auto-creates the storage if it doesn't exist |
| `--list` | flag | - | List all registered users |
| `--delete EMAIL` | string | - | Delete a specific user |
| `--token EMAIL` | string | - | Re-issue JWT token for a user |

## Examples

### Create 10 dev users quickly
```bash
python create_dev_user.py --count 10
```

### Create a user with a specific storage

```bash
# Assign existing storage (or create it if it doesn't exist)
python create_dev_user.py --email dev1@fileforge.local --storage mystore

# Create 5 dev users all linked to the same storage
python create_dev_user.py --count 5 --storage shared-storage
```

### Create an admin account
```bash
python create_dev_user.py --email admin@dev.local --role admin --password admin123
```

### View all current users
```bash
python create_dev_user.py --list
```

### Get a fresh JWT token for testing
```bash
python create_dev_user.py --token dev1@fileforge.local
```

### Clean up test users
```bash
python create_dev_user.py --delete dev2@fileforge.local
python create_dev_user.py --delete dev3@fileforge.local
```

## Features

✅ **Multi-Database Support**
- SQLite
- MySQL
- PostgreSQL

✅ **Password Security**
- Uses `pbkdf2_sha256` hashing (compatible with FileForge login)
- Integrates with PassLib

✅ **JWT Token Generation**
- Generates HS256 tokens for testing API endpoints
- Falls back gracefully if SECRET_KEY is not set

✅ **Duplicate Prevention**
- Skips users that already exist (doesn't fail)

✅ **Role Management**
- Create regular users (default) or admin users

✅ **Database Integration**
- Automatically connects to FileForge database (via config.py)
- Respects existing schema (groups, users tables)

## Environment Requirements

### Prerequisites

Ensure these Python packages are installed:
```bash
pip install passlib PyJWT pydantic-settings sqloader auth2fa
```

Or install all dependencies:
```bash
pip install -r requirements.txt
```

### Configuration

The tool reads database configuration from `.env` file. Required variables:

```env
DB_TYPE=sqlite           # or mysql, postgresql
DB_PATH=fileforge.db     # SQLite file path
SECRET_KEY=your-secret   # For JWT token generation
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

## Default Credentials

- **Email Pattern**: `dev{N}@fileforge.local` (e.g., dev1, dev2, ...)
- **Password**: `devpass123`
- **Role**: `user`

⚠️ These defaults are for development only. Change passwords in production environments.

## Database Schema

The tool creates users in the `users` table with the following fields:

| Column | Type | Notes |
|--------|------|-------|
| `group_uuid` | TEXT | Links to Anonymous group (auto-detected) |
| `user_uuid` | TEXT | Unique identifier (UUID4) |
| `user_id` | TEXT | Login identifier (unique) |
| `user_name` | TEXT | Display name |
| `password` | TEXT | Hashed (pbkdf2_sha256) |
| `email` | TEXT | Email address |
| `role` | TEXT | 'user' or 'admin' |
| `created_at` | DATETIME | Creation timestamp |
| `modified_at` | DATETIME | Last modification timestamp |

## Limitations

1. **No Storage Mapping**: Without `--storage`, users are linked to the first existing storage. Use `--storage NAME` to assign a specific storage or auto-create one.

2. **No 2FA Setup**: Created users do not have TOTP/2FA configured. Can be set up after login.

3. **No Email Verification**: Users are marked as registered without email verification.

4. **SQLite-Only Tested**: While code supports MySQL/PostgreSQL, actual testing was limited to SQLite.

## Troubleshooting

### "Database connection failed"
- Check `.env` file is properly configured
- Ensure database file/server is accessible
- Verify DB credentials (for MySQL/PostgreSQL)

### "Secret key is not set"
- Add `SECRET_KEY` to `.env` if you need JWT tokens
- Script still creates users even if this is missing

### "User not found" when deleting/listing
- Check spelling of email
- Use `--list` to see exact user email format

### PassLib errors
- Ensure `passlib>=1.7.4` is installed
- Run: `pip install passlib --upgrade`

## Security Warnings

🔒 **For Development/Testing Only**
- Do not use default passwords in production
- Do not expose this script in production environments
- Consider disabling this script when not needed

## License

Part of FileForge server codebase.

---

**For more details, see `CREATE_DEV_USER_REPORT.md`**

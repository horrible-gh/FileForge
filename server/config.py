from pydantic_settings import BaseSettings
from pydantic import field_validator
from enum import Enum
from sqloader.init import database_init
from auth2fa import TwoFactorAuth
import redis
import os
import re


# 🔹 Define DB_TYPE explicitly with an enum
class DBType(str, Enum):
    MYSQL = "mysql"
    SQLITE = "sqlite"
    SQLITE3 = "sqlite3"
    LOCAL = "local"
    POSTGRESQL = "postgresql"

# 🔹 settings class (using Pydantic)
class Settings(BaseSettings):
    ALLOWED_ORIGIN: str
    SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    CONTEXT: str
    DB_TYPE: DBType  # enum applied
    DB_HOST: str = ""
    DB_PORT: int = 0
    DB_USER: str = ""
    DB_PASSWORD: str = ""
    DB_DATABASE: str = ""
    DB_SCHEMA: str = ""
    DB_LOG: bool = True
    DB_PATH: str = ""

    # 🔹 Gmail OAuth credential (MailAnchor mail integration). MailAnchorServer/config.pytext same convention.
    #    text text text official settingstext, default value ""text can be left empty without affecting startup.
    #    (previously undeclared + pydantic extra="forbid" default value text .envtext translated text
    #     startuptext extra_forbidden ValidationErrortext failed immediately.)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = ""

    # 🔹 Official FileForge storage root (0021/R0001). The platform keeps user files
    #    under the storages subsystem whose physical files land beneath this root
    #    (the `storage` storage = storage_path `/storage` → `./storage`, `note` = `./note`).
    #    Mail artifacts must live under this official root, NOT in a self-invented
    #    server-local `./data/mails` directory (see mail_storage_base()).
    STORAGE_ROOT_PATH: str = "./storage"

    # 🔹 Mail subsystem settings (absorbed from legacy mail-server, NR0003 Gap B/D).
    #    All carry defaults so a shared .env without these keys cannot cause a
    #    boot-death (extra="ignore" + defaults). MailAnchorServer/config.py equivalents.
    #
    #    0021/R0001: default is now EMPTY so mail data is derived from the official
    #    STORAGE_ROOT_PATH (→ `{STORAGE_ROOT_PATH}/mail`) instead of the legacy
    #    server-local `./data/mails`. Set explicitly only to override that location
    #    (e.g. an absolute mount). Resolve via mail_storage_base(), never read this
    #    field directly — empty means "derive", and call sites must honor that.
    MAIL_STORAGE_BASE_PATH: str = ""
    ENVIRONMENT: str = ""
    FRONTEND_BASE_URL: str = ""
    OAUTH_SUCCESS_REDIRECT_URL: str = ""
    # 🔹 Deeplink (custom scheme) for auto-returning to the mobile app after OAuth success. R0001/NR0003/T0004 §Option C.
    #    Used only in desktop/mobile/local setups where there is no web-front redirect
    #    (OAUTH_SUCCESS_REDIRECT_URL/FRONTEND_BASE_URL) and the self-contained success page is shown.
    #    If set, the success page auto-redirects to this scheme so that on mobile the browser is
    #    left and the app is brought back to the foreground (the client reloads the account list on
    #    receiving the deeplink); on desktop/web, auto window-close and a manual "Return to the app"
    #    button act as the fallback. If empty, the deeplink step is skipped.
    #    The same scheme must be registered in the client (Android intent-filter / iOS CFBundleURLTypes).
    OAUTH_SUCCESS_DEEPLINK: str = "fileforge://oauth/gmail/success"

    RATE_LIMIT_DEFAULT: str = "100/hour"
    RATE_LIMIT_LOGIN: str = "5/minute"
    RATE_LIMIT_UPLOAD: str = "20/hour"
    RATE_LIMIT_DOWNLOAD: str = "50/hour"

    # 🔹 Redis settings (DB_* translated text text). default value localhost/6379text preserve existing behavior(backward compatibility).
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: str = ""   # empty disables AUTH
    REDIS_SSL: bool = False    # support remote/managed Redis TLS

    # .envtext empty value("")text int/bool parse errortext translated text translated text absorbed as the default(0101 incident-family mitigation)
    @field_validator("REDIS_PORT", "REDIS_DB", mode="before")
    @classmethod
    def _blank_int_to_default(cls, v, info):
        if v is None or (isinstance(v, str) and v.strip() == ""):
            return cls.model_fields[info.field_name].default
        return v

    @field_validator("REDIS_SSL", mode="before")
    @classmethod
    def _blank_bool_to_default(cls, v):
        if v is None or (isinstance(v, str) and v.strip() == ""):
            return False
        return v

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()


# 🔹 Effective base directory for mail artifacts (.eml bodies, attachments, drafts,
#    compose attachments). 0021/R0001 (rev1): mail data must live under the storage
#    that is DESIGNATED IN THE DB — the `storages` row whose storage_type='mail'
#    (e.g. storage_path `C:\storage\mailanchor`), resolved per-user via
#    `user_storages`. The previous rev derived a config-only `{STORAGE_ROOT_PATH}/mail`
#    and so wrote nowhere near the DB-designated path (review reject: files never
#    appeared under C:\storage\mailanchor). Resolution order:
#      1. explicit MAIL_STORAGE_BASE_PATH (ops override / absolute mount) — always wins.
#      2. DB-designated mail storage for the owning user (account_uuid → user_uuid →
#         user_storages ⋈ storages where storage_type='mail'); else the newest active
#         mail-type storage globally.
#      3. fallback `{STORAGE_ROOT_PATH}/mail` (tests / no-DB / mail storage not yet
#         provisioned) — keeps the app booting on deployments without a mail storage.
#    All mail call sites must use this resolver and pass whatever identity they have
#    (account_uuid preferred, else user_uuid). Never read settings.MAIL_STORAGE_BASE_PATH.

# Cache successful DB resolutions for the process lifetime so a sync of hundreds of
# messages does not re-query per message. Only positive (DB-backed) results are cached
# — the config fallback is intentionally not cached so a later-provisioned mail
# storage is picked up without a restart of the resolver state.
_mail_base_cache: dict = {}


def clear_mail_storage_cache() -> None:
    """Drop the resolver cache (tests / after re-provisioning a mail storage)."""
    _mail_base_cache.clear()


def _physical_mail_base(storage_path: str) -> str:
    """Turn a `storages.storage_path` into a filesystem base, mirroring
    storages._helper.get_physical_path: platform-relative roots ('/mail') become
    CWD-relative ('mail'); absolute roots ('C:\\storage\\mailanchor') stay absolute."""
    p = (storage_path or "").replace("/", os.sep).lstrip(os.sep)
    return p or "."


def _query_designated_mail_storage(account_uuid=None, user_uuid=None):
    """Return the storage_path of the DB-designated mail storage, or None.

    Per-user designation (via user_storages) is preferred so a multi-account / multi
    -tenant deployment routes each user's mail to their own mail storage; falls back
    to the newest active mail-type storage when no per-user mapping exists. Any DB /
    schema error (e.g. a sqlite test DB without a storages.storage_type column) is
    swallowed so the caller falls back to the config base.
    """
    try:
        inst = db.db_instance
        if inst is None:
            return None
        uid = user_uuid
        if not uid and account_uuid:
            row = inst.fetch_one(
                adapt_query("SELECT user_uuid FROM mail_accounts WHERE account_uuid = ?"),
                (account_uuid,),
            )
            if row:
                uid = row["user_uuid"] if isinstance(row, dict) else row[0]
        if uid:
            row = inst.fetch_one(
                adapt_query(
                    "SELECT s.storage_path FROM user_storages us "
                    "JOIN storages s ON s.storage_uuid = us.storage_uuid "
                    "WHERE us.user_uuid = ? AND s.storage_type = 'mail' "
                    "AND s.status = 'active' "
                    "ORDER BY us.is_default DESC, s.created_at ASC LIMIT 1"
                ),
                (uid,),
            )
            if row:
                sp = row["storage_path"] if isinstance(row, dict) else row[0]
                if sp:
                    return sp
        # No per-user mapping → newest active mail-type storage (system designation).
        row = inst.fetch_one(
            adapt_query(
                "SELECT storage_path FROM storages "
                "WHERE storage_type = 'mail' AND status = 'active' "
                "ORDER BY created_at DESC LIMIT 1"
            ),
            (),
        )
        if row:
            sp = row["storage_path"] if isinstance(row, dict) else row[0]
            if sp:
                return sp
    except Exception:
        return None
    return None


def mail_storage_base(account_uuid: str = None, user_uuid: str = None) -> str:
    explicit = (settings.MAIL_STORAGE_BASE_PATH or "").strip()
    if explicit:
        return explicit

    cache_key = ("a", account_uuid) if account_uuid else \
                ("u", user_uuid) if user_uuid else ("_", "_")
    if cache_key in _mail_base_cache:
        return _mail_base_cache[cache_key]

    storage_path = _query_designated_mail_storage(account_uuid, user_uuid)
    if storage_path:
        base = _physical_mail_base(storage_path)
        _mail_base_cache[cache_key] = base
        return base

    # Fallback (not cached): official storage root subtree.
    return os.path.join(settings.STORAGE_ROOT_PATH or "./storage", "mail")


# 🔹 central Redis client(single instance/pool). 4text translated text consolidates duplicate creation code.
#    decode_responses=True preserved(callers depend on string comparison), password="" → None normalizationtext avoid unnecessary AUTH.
redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    password=settings.REDIS_PASSWORD or None,
    ssl=settings.REDIS_SSL,
    decode_responses=True,
)


class Auth2FAAdapter:
    """
    auth2fatext SQLStoragetext expected execute(path, **kwargs) interfacetext
    sqloadertext SQLiteWrapper(db_instance)text adapter that connects.
    """

    def __init__(self, db_instance):
        self.db = db_instance
        import auth2fa as _auth2fa_mod
        self._sql_dir = os.path.join(os.path.dirname(_auth2fa_mod.__file__), "sql")

    def _is_mysql(self):
        from sqloader._prototype import MYSQL
        return getattr(self.db, "db_type", None) == MYSQL

    def _is_postgresql(self):
        from sqloader._prototype import POSTGRESQL
        return getattr(self.db, "db_type", None) == POSTGRESQL

    def _prepare(self, sql, kwargs):
        """
        SQLtext parameterstext DB convert for the DB type.
        - SQLite: :param_name as-is, params=dict
        - MySQL: :param_name → %s (positional), params=list (normalize_params text)
                 ON CONFLICT → ON DUPLICATE KEY UPDATE
        return: (sql, params)
        """
        if not kwargs:
            params = None
        elif self._is_mysql():
            # :param_name extract in order → %s replace + translated text list
            param_names = re.findall(r":(\w+)", sql)
            sql = re.sub(r":\w+", "%s", sql)
            # ON CONFLICT (...) DO UPDATE SET col = EXCLUDED.col → ON DUPLICATE KEY UPDATE
            def replace_conflict(m):
                set_clause = m.group(1)
                pairs = re.findall(r"(\w+)\s*=\s*EXCLUDED\.\w+", set_clause)
                updates = ", ".join(f"{col} = VALUES({col})" for col in pairs)
                return f"ON DUPLICATE KEY UPDATE {updates}"
            sql = re.sub(
                r"ON CONFLICT\s*\([^)]+\)\s*DO UPDATE\s+SET\s+((?:\w+\s*=\s*EXCLUDED\.\w+,?\s*)+)",
                replace_conflict,
                sql,
                flags=re.IGNORECASE,
            )
            params = [kwargs[name] for name in param_names]
        elif self._is_postgresql():
            param_names = re.findall(r":(\w+)", sql)
            sql = re.sub(r":\w+", "%s", sql)
            params = [kwargs[name] for name in param_names]
        else:
            params = kwargs

        return sql, params

    def execute(self, path, **kwargs):
        sql_file = os.path.join(self._sql_dir, path + ".sql")
        with open(sql_file, "r", encoding="utf-8") as f:
            raw_sql = f.read()

        # remove comments
        lines = [l for l in raw_sql.splitlines() if not l.strip().startswith("--")]
        sql_stripped = " ".join(lines).strip()

        sql_stripped, params = self._prepare(sql_stripped, kwargs)

        if sql_stripped.upper().startswith("SELECT"):
            rows = self.db.fetch_all(sql_stripped, params)
            if rows is None:
                return []
            return [dict(row) for row in rows]
        else:
            # CREATE TABLE text handle multiple statements
            statements = [s.strip() for s in sql_stripped.split(";") if s.strip()]
            for stmt in statements:
                self.db.execute(stmt, params)
            return []


# 🔹 DB settings class (singleton pattern applied)
class DatabaseSetting:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(DatabaseSetting, cls).__new__(cls)
            cls._instance._init_db()
        return cls._instance

    def _init_db(self):
        """DB initialize"""
        self.db_instance = None
        self.sqloader = None
        self.migrator = None
        self.tfa = None
        self.config = {}

        if settings.DB_TYPE.value == DBType.MYSQL:
            self.config = {
                "type": settings.DB_TYPE.value,
                f"{settings.DB_TYPE.value}": {
                    "host": settings.DB_HOST,
                    "port": settings.DB_PORT,
                    "user": settings.DB_USER,
                    "password": settings.DB_PASSWORD,
                    "database": settings.DB_DATABASE,
                    "schema": settings.DB_SCHEMA,
                    "log": settings.DB_LOG,
                },
                "service": {
                    "log": True,
                    "sqloder": "res/sql/sqloader/mysql"
                },
                "migration": {
                    "auto_migration": True,
                    "migration_path": "res/sql/migration/mysql"
                },
            }
        elif settings.DB_TYPE.value in (DBType.SQLITE, DBType.SQLITE3, DBType.LOCAL):
            self.config = {
                "type": settings.DB_TYPE.value,
                f"{settings.DB_TYPE.value}": {
                    "db_name": settings.DB_PATH
                },
                "service": {
                    "log": True,
                    "sqloder": "res/sql/sqloader/sqlite"
                },
                "migration": {
                    "auto_migration": True,
                    "migration_path": "res/sql/migration/sqlite"
                },
            }
        elif settings.DB_TYPE.value == DBType.POSTGRESQL:
            if settings.DB_PORT == 0:
                settings.DB_PORT = None
            self.config = {
                "type": settings.DB_TYPE.value,
                "postgresql": {
                    "host": settings.DB_HOST,
                    "port": settings.DB_PORT,
                    "user": settings.DB_USER,
                    "password": settings.DB_PASSWORD,
                    "database": settings.DB_DATABASE,
                    "log": settings.DB_LOG,
                },
                "service": {
                    "log": True,
                    "sqloder": "res/sql/sqloader/postgresql"
                },
                "migration": {
                    "migration_path": "res/sql/migration/postgresql",
                    "auto_migration": True,
                },
            }

        self.instance_init()


    def instance_init(self):
        """DB instance initialize"""
        self.db_instance, self.sqloader, self.migrator = database_init(self.config)
        adapter = Auth2FAAdapter(self.db_instance)
        self.tfa = TwoFactorAuth(sq=adapter, issuer="FileForge")

    def get_db_instance(self):
        return self.db_instance

    def get_sqloader_instance(self):
        return self.sqloader

# 🔹 translated text object creation
db = DatabaseSetting()

# keep compatibility with existing imports
tfa = db.tfa

# 🔹 sqloadertext raw bypass(inline) SQLtext placeholder converter.
#    sqlite3 drivertext '?'(qmark), pymysql/psycopgtext '%s'(pyformat)text uses.
#    text SQLtext '?'text hard-coded code(create_dev_user.py·_helper.py·totp.py text)text
#    text translated text must go through DB_TYPEtext works regardless of. mysql/postgresql pathtranslated text
#    literal '%'text '%%'text escapetext pyformat prevent misinterpretation.
def adapt_query(sql: str) -> str:
    if settings.DB_TYPE in (DBType.MYSQL, DBType.POSTGRESQL):
        return sql.replace("%", "%%").replace("?", "%s")
    return sql


# 🔹 FastAPItext dependency injectiontext translated text text
def get_db_instance():
    return db.get_db_instance()

def get_sqloader_instance():
    return db.get_sqloader_instance()

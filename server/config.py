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

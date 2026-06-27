from pydantic_settings import BaseSettings
from enum import Enum
from sqloader.init import database_init
from auth2fa import TwoFactorAuth
import os
import re
import redis

# 🔹 Enum을 사용하여 DB_TYPE을 명확하게 정의
class DBType(str, Enum):
    MYSQL = "mysql"
    SQLITE = "sqlite"
    SQLITE3 = "sqlite3"
    LOCAL = "local"

# 🔹 설정 클래스 (Pydantic 활용)
class Settings(BaseSettings):
    ALLOWED_ORIGIN: str
    SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    CONTEXT: str
    DB_TYPE: DBType  # Enum 적용
    DB_HOST: str = ""
    DB_PORT: int = 0
    DB_USER: str = ""
    DB_PASSWORD: str = ""
    DB_DATABASE: str = ""
    DB_SCHEMA: str = ""
    DB_LOG: bool = True
    DB_PATH: str = ""
    ENVIRONMENT: str = ""

    # 🔹 메일 저장 경로 설정 추가
    MAIL_STORAGE_BASE_PATH: str = "./data/mails"

    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = ""
    FRONTEND_BASE_URL: str = ""
    OAUTH_SUCCESS_REDIRECT_URL: str = ""
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0

    class Config:
        env_file = ".env"

settings = Settings()
redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    decode_responses=True,
)


class Auth2FAAdapter:
    """
    auth2fa의 SQLStorage가 기대하는 execute(path, **kwargs) 인터페이스를
    sqloader의 SQLiteWrapper(db_instance)로 연결하는 어댑터.
    """

    def __init__(self, db_instance):
        self.db = db_instance
        import auth2fa as _auth2fa_mod
        self._sql_dir = os.path.join(os.path.dirname(_auth2fa_mod.__file__), "sql")

    def _is_mysql(self):
        from sqloader._prototype import MYSQL
        return getattr(self.db, "db_type", None) == MYSQL

    def _prepare(self, sql, kwargs):
        """
        SQL과 파라미터를 DB 타입에 맞게 변환.
        - SQLite: :param_name 그대로, params=dict
        - MySQL: :param_name → %s (positional), params=list (normalize_params 호환)
                 ON CONFLICT → ON DUPLICATE KEY UPDATE
        반환: (sql, params)
        """
        if not kwargs:
            params = None
        elif self._is_mysql():
            # :param_name 순서대로 추출 → %s 치환 + 순서대로 list
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
        else:
            params = kwargs

        return sql, params

    def execute(self, path, **kwargs):
        sql_file = os.path.join(self._sql_dir, path + ".sql")
        with open(sql_file, "r", encoding="utf-8") as f:
            raw_sql = f.read()

        # 주석 제거
        lines = [l for l in raw_sql.splitlines() if not l.strip().startswith("--")]
        sql_stripped = " ".join(lines).strip()

        sql_stripped, params = self._prepare(sql_stripped, kwargs)

        if sql_stripped.upper().startswith("SELECT"):
            rows = self.db.fetch_all(sql_stripped, params)
            if rows is None:
                return []
            return [dict(row) for row in rows]
        else:
            # CREATE TABLE 등 다중 구문 처리
            statements = [s.strip() for s in sql_stripped.split(";") if s.strip()]
            for stmt in statements:
                self.db.execute(stmt, params)
            return []


# 🔹 DB 설정 클래스 (싱글톤 패턴 적용)
class DatabaseSetting:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(DatabaseSetting, cls).__new__(cls)
            cls._instance._init_db()
        return cls._instance

    def _init_db(self):
        """DB 초기화"""
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

        self.instance_init()


    def instance_init(self):
        """DB 인스턴스 초기화"""
        self.db_instance, self.sqloader, self.migrator = database_init(self.config)
        adapter = Auth2FAAdapter(self.db_instance)
        self.tfa = TwoFactorAuth(sq=adapter, issuer="MailAnchor")

    def get_db_instance(self):
        return self.db_instance

    def get_sqloader_instance(self):
        return self.sqloader

# 🔹 싱글톤 객체 생성
db = DatabaseSetting()

# 기존 임포트 호환성 유지
tfa = db.tfa

# 🔹 FastAPI에서 의존성 주입으로 사용할 함수
def get_db_instance():
    return db.get_db_instance()

def get_sqloader_instance():
    return db.get_sqloader_instance()

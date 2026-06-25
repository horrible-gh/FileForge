from pydantic_settings import BaseSettings
from pydantic import field_validator
from enum import Enum
from sqloader.init import database_init
from auth2fa import TwoFactorAuth
import redis
import os
import re


# 🔹 Enum을 사용하여 DB_TYPE을 명확하게 정의
class DBType(str, Enum):
    MYSQL = "mysql"
    SQLITE = "sqlite"
    SQLITE3 = "sqlite3"
    LOCAL = "local"
    POSTGRESQL = "postgresql"

# 🔹 설정 클래스 (Pydantic 활용)
class Settings(BaseSettings):
    ALLOWED_ORIGIN: str
    SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
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

    # 🔹 Gmail OAuth credential (MailAnchor 메일 연동). MailAnchorServer/config.py와 동일 컨벤션.
    #    이 세 값은 정식 설정 항목이며, 기본값 ""로 비워 두어도 기동에는 영향이 없다.
    #    (이전엔 미선언 + pydantic extra="forbid" 기본값 탓에 .env에 넣으면
    #     기동이 extra_forbidden ValidationError로 즉시 죽었다.)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = ""

    RATE_LIMIT_DEFAULT: str = "100/hour"
    RATE_LIMIT_LOGIN: str = "5/minute"
    RATE_LIMIT_UPLOAD: str = "20/hour"
    RATE_LIMIT_DOWNLOAD: str = "50/hour"

    # 🔹 Redis 설정 (DB_* 컨벤션과 동일). 기본값 localhost/6379로 기존 동작 무변경(하위호환).
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: str = ""   # 비어있으면 AUTH 미사용
    REDIS_SSL: bool = False    # 원격/관리형 Redis TLS 대응

    # .env의 빈 값("")이 int/bool 파싱 오류를 일으키지 않도록 기본값으로 흡수(0101 인시던트 계열 대응)
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

settings = Settings()

# 🔹 중앙 Redis 클라이언트(단일 인스턴스/풀). 4개 라우터의 중복 생성 코드를 통합한다.
#    decode_responses=True 보존(호출부가 문자열 비교에 의존), password="" → None 정규화로 불필요한 AUTH 방지.
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

    def _is_postgresql(self):
        from sqloader._prototype import POSTGRESQL
        return getattr(self.db, "db_type", None) == POSTGRESQL

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
        """DB 인스턴스 초기화"""
        self.db_instance, self.sqloader, self.migrator = database_init(self.config)
        adapter = Auth2FAAdapter(self.db_instance)
        self.tfa = TwoFactorAuth(sq=adapter, issuer="FileForge")

    def get_db_instance(self):
        return self.db_instance

    def get_sqloader_instance(self):
        return self.sqloader

# 🔹 싱글톤 객체 생성
db = DatabaseSetting()

# 기존 임포트 호환성 유지
tfa = db.tfa

# 🔹 sqloader를 우회하는 원시(inline) SQL용 플레이스홀더 변환기.
#    sqlite3 드라이버는 '?'(qmark), pymysql/psycopg는 '%s'(pyformat)를 사용한다.
#    원시 SQL에 '?'를 하드코딩한 코드(create_dev_user.py·_helper.py·totp.py 등)는
#    이 함수를 거쳐야 DB_TYPE에 무관하게 동작한다. mysql/postgresql 경로에서는
#    리터럴 '%'를 '%%'로 escape하여 pyformat 오해석을 막는다.
def adapt_query(sql: str) -> str:
    if settings.DB_TYPE in (DBType.MYSQL, DBType.POSTGRESQL):
        return sql.replace("%", "%%").replace("?", "%s")
    return sql


# 🔹 FastAPI에서 의존성 주입으로 사용할 함수
def get_db_instance():
    return db.get_db_instance()

def get_sqloader_instance():
    return db.get_sqloader_instance()

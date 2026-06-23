"""RS256 key management for the FileForge -> MailAnchor token-sharing bridge
(mailanchor.ui.0003 T1, issuance side).

FileForge mints **access** tokens with an RSA *private* key (RS256). The matching
*public* key is the only thing that crosses the polyglot boundary: the Go server
(`internal/auth/federated.go`) verifies FileForge tokens against it without sharing a
secret, and FileForge itself verifies its own access tokens with the same public key.

Refresh tokens and the short-lived TOTP-pending temp token stay HS256 (see login.py):
they never leave FileForge, so there is no reason to expose them to the public-key path.

This module deliberately reads its configuration straight from ``os.environ`` instead of
``config.settings`` so it can be imported (and unit-tested) without booting the DB
singleton that ``config`` constructs at import time.

Key resolution order:
  1. ``JWT_PRIVATE_KEY``       — inline PEM (PKCS8/PKCS1), may contain newlines.
  2. ``JWT_PRIVATE_KEY_FILE``  — path to a PEM private key.
  3. ``JWT_KEYS_DIR``/jwt_private.pem — loaded if present, otherwise a fresh RSA-2048
     keypair is generated and persisted here (private + jwt_public.pem) so dev/smoke
     runs have a stable, exportable key with zero manual setup. If the directory cannot
     be written, the generated key is used ephemerally (in-memory only).

The exported public key is always PKIX ("PUBLIC KEY"), which Go's parseRSAPublicKey
accepts.
"""

import os
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

ACCESS_ALG = "RS256"
DEFAULT_ISSUER = "fileforge"
DEFAULT_AUDIENCE = "mailanchor"
DEFAULT_KEYS_DIR = "./keys"


class _KeyManager:
    def __init__(self):
        self.issuer = os.environ.get("JWT_ISSUER", DEFAULT_ISSUER)
        self.audience = os.environ.get("JWT_AUDIENCE", DEFAULT_AUDIENCE)
        self.private_pem, self.public_pem = self._load_or_generate()

    # -- key loading -----------------------------------------------------------
    def _load_or_generate(self):
        inline = os.environ.get("JWT_PRIVATE_KEY", "").strip()
        if inline:
            return self._from_private(self._load_private(inline.encode()))

        path = os.environ.get("JWT_PRIVATE_KEY_FILE", "").strip()
        if path:
            return self._from_private(self._load_private(Path(path).read_bytes()))

        keys_dir = Path(os.environ.get("JWT_KEYS_DIR", DEFAULT_KEYS_DIR))
        priv_path = keys_dir / "jwt_private.pem"
        if priv_path.exists():
            return self._from_private(self._load_private(priv_path.read_bytes()))

        # No key configured: generate a stable keypair and persist it so the public
        # key can be exported to the Go server and survives restarts.
        priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        priv_pem, pub_pem = self._from_private(priv)
        try:
            keys_dir.mkdir(parents=True, exist_ok=True)
            priv_path.write_bytes(priv_pem)
            (keys_dir / "jwt_public.pem").write_bytes(pub_pem)
            try:
                os.chmod(priv_path, 0o600)
            except OSError:
                pass  # best-effort on platforms without POSIX perms
        except OSError:
            pass  # read-only fs: fall back to an ephemeral in-memory key
        return priv_pem, pub_pem

    @staticmethod
    def _load_private(pem_bytes):
        return serialization.load_pem_private_key(pem_bytes, password=None)

    @staticmethod
    def _from_private(priv):
        priv_pem = priv.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        pub_pem = priv.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        return priv_pem, pub_pem

    # -- token ops -------------------------------------------------------------
    def sign_access(self, data: dict, expires_delta: timedelta) -> str:
        now = datetime.now(timezone.utc)
        payload = dict(data)
        payload.update(
            {
                "iss": self.issuer,
                "aud": self.audience,
                "iat": now,
                "exp": now + expires_delta,
            }
        )
        return jwt.encode(payload, self.private_pem, algorithm=ACCESS_ALG)

    def verify_access(self, token: str, verify_exp: bool = True) -> dict:
        # algorithms is pinned to RS256, so an HS256 token forged with the public key
        # as the HMAC secret (alg-confusion) is rejected before signature checking.
        return jwt.decode(
            token,
            self.public_pem,
            algorithms=[ACCESS_ALG],
            audience=self.audience,
            issuer=self.issuer,
            options={"verify_exp": verify_exp},
        )


_lock = threading.Lock()
_manager = None


def manager() -> _KeyManager:
    global _manager
    if _manager is None:
        with _lock:
            if _manager is None:
                _manager = _KeyManager()
    return _manager


def reset_manager() -> None:
    """Drop the cached manager so the next call re-reads the environment (tests)."""
    global _manager
    _manager = None


def sign_access(data: dict, expires_delta: timedelta) -> str:
    return manager().sign_access(data, expires_delta)


def verify_access(token: str, verify_exp: bool = True) -> dict:
    return manager().verify_access(token, verify_exp)


def public_key_pem() -> bytes:
    return manager().public_pem


def issuer() -> str:
    return manager().issuer


def audience() -> str:
    return manager().audience

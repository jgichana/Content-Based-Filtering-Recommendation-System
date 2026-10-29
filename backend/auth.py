"""
Authentication helpers for the API.

Two ways to sign in, both ending in the same short-lived JWT that the mobile
app sends as `Authorization: Bearer <token>`:

1. Email + password  -> password hashed with bcrypt, stored on `caregivers`.
2. Google Sign-In    -> the app sends Google's ID token, we verify it with
                        Google's public keys and link/create the caregiver.

Environment variables:
    JWT_SECRET          secret used to sign tokens (REQUIRED in production)
    JWT_TTL_HOURS       token lifetime, default 168 (7 days)
    GOOGLE_CLIENT_IDS   comma-separated OAuth client IDs whose ID tokens are
                        accepted (the "Web application" client ID that the app
                        passes as serverClientId, plus the iOS client ID if used)
"""
from __future__ import annotations

import datetime as dt
import os
import warnings

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_DEV_SECRET = "dev-only-insecure-secret-change-me"
JWT_SECRET = os.environ.get("JWT_SECRET", _DEV_SECRET)
JWT_ALGORITHM = "HS256"
JWT_TTL_HOURS = int(os.environ.get("JWT_TTL_HOURS", "168"))
GOOGLE_CLIENT_IDS = [c.strip() for c in os.environ.get("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]

if JWT_SECRET == _DEV_SECRET:
    warnings.warn("JWT_SECRET is not set; using an insecure development secret.", stacklevel=1)

# bcrypt only looks at the first 72 bytes of a password (bcrypt>=5 rejects longer input).
MAX_PASSWORD_BYTES = 72

_bearer = HTTPBearer(auto_error=False)


# --------------------------------------------------------------------------- #
# Passwords
# --------------------------------------------------------------------------- #
def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str | None) -> bool:
    if not password_hash:
        return False
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


# --------------------------------------------------------------------------- #
# Tokens
# --------------------------------------------------------------------------- #
def create_access_token(caregiver_id: int) -> str:
    now = dt.datetime.now(dt.timezone.utc)
    payload = {"sub": str(caregiver_id), "iat": now, "exp": now + dt.timedelta(hours=JWT_TTL_HOURS)}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def current_caregiver_id(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> int:
    """FastAPI dependency: the caregiver_id of the signed-in user, or 401."""
    unauthorized = HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        "Not signed in or session expired",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if creds is None or creds.scheme.lower() != "bearer":
        raise unauthorized
    try:
        payload = jwt.decode(creds.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise unauthorized


# --------------------------------------------------------------------------- #
# Google
# --------------------------------------------------------------------------- #
def verify_google_id_token(token: str) -> dict:
    """Return the verified Google claims (sub, email, name, ...) or raise 401."""
    if not GOOGLE_CLIENT_IDS:
        raise HTTPException(503, "Google sign-in is not configured on the server (GOOGLE_CLIENT_IDS).")

    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    try:
        claims = id_token.verify_oauth2_token(token, google_requests.Request(), audience=GOOGLE_CLIENT_IDS)
    except ValueError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid Google token: {exc}")

    if claims.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid Google token issuer")
    if not claims.get("email") or not claims.get("email_verified"):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Google account email is not verified")
    return claims

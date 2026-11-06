"""
account/token_revocation.py

Server-side "log out everywhere" for stateless SimpleJWT tokens —
with NO new model fields and NO migrations.
"""

import time

from django.core.cache import caches
from django.conf import settings
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken

# NOTE: do NOT import anything from rest_framework.views / rest_framework_simplejwt.views
# here. This module is listed in REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"], and
# importing DRF views triggers loading that setting -> circular import.
# The refresh view lives in account/token_refresh_views.py instead.

CACHE_ALIAS = "auth_revocation"
_KEY = "jwt_revoked_before:{}"


def _cache():
    return caches[CACHE_ALIAS]


def _ttl_seconds():
    # Keep the marker as long as the longest-lived token could still be valid.
    return int(settings.SIMPLE_JWT["REFRESH_TOKEN_LIFETIME"].total_seconds()) + 3600


def revoke_user_tokens(user_id, cutoff=None, effective_at=None):
    """
    Invalidate every JWT (access + refresh) issued to this user before `cutoff`
    (default: now).

    `effective_at` (unix ts, default: now) lets the logout take effect later —
    tokens keep working until then. Used by the app-update download so the old
    app is not signed out (and its download killed) while the installer is
    still arriving on the user's machine.
    """
    now = int(time.time())
    cutoff = int(cutoff if cutoff is not None else now)
    effective_at = int(effective_at if effective_at is not None else now)

    # Keep enforcing any revocation that is already active, so scheduling a
    # new (future) logout never brings older revoked sessions back to life.
    prev_cutoff = 0
    existing = _read_marker(user_id)
    if existing:
        old_cutoff, old_effective, old_prev = existing
        prev_cutoff = max(old_prev, old_cutoff if old_effective <= now else 0)

    _cache().set(
        _KEY.format(user_id),
        {"cutoff": cutoff, "effective_at": effective_at, "prev_cutoff": prev_cutoff},
        timeout=_ttl_seconds() + max(0, effective_at - now),
    )


def _read_marker(user_id):
    """Return (cutoff, effective_at, prev_cutoff) or None. Accepts the old plain-int format."""
    value = _cache().get(_KEY.format(user_id))
    if value is None:
        return None
    if isinstance(value, dict):
        return int(value["cutoff"]), int(value["effective_at"]), int(value.get("prev_cutoff", 0))
    return int(value), int(value), 0  # legacy marker: active immediately


def is_token_revoked(user_id, iat):
    marker = _read_marker(user_id)
    if marker is None:
        return False
    cutoff, effective_at, prev_cutoff = marker
    if iat is None:  # very old tokens without iat — treat as revoked
        return True
    iat = int(iat)
    if iat < prev_cutoff:
        return True  # an earlier, already-active logout still applies
    if time.time() < effective_at:
        return False  # logout scheduled but not active yet
    return iat < cutoff


class RevocableJWTAuthentication(JWTAuthentication):
    def get_validated_token(self, raw_token):
        token = super().get_validated_token(raw_token)
        user_id = token.get(settings.SIMPLE_JWT.get("USER_ID_CLAIM", "user_id"))
        if user_id is not None and is_token_revoked(user_id, token.get("iat")):
            raise InvalidToken({"detail": "Session ended — please sign in again.",
                                "code": "token_revoked"})
        return token


class RevocableTokenRefreshSerializer(TokenRefreshSerializer):
    def validate(self, attrs):
        try:
            refresh = RefreshToken(attrs["refresh"])
        except TokenError as e:
            raise InvalidToken(e.args[0])
        user_id = refresh.get(settings.SIMPLE_JWT.get("USER_ID_CLAIM", "user_id"))
        if user_id is not None and is_token_revoked(user_id, refresh.get("iat")):
            raise InvalidToken({"detail": "Session ended — please sign in again.",
                                "code": "token_revoked"})
        return super().validate(attrs)
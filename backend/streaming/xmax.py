"""XMax credentials for the browser SDK (permanent-key mode)."""

from django.conf import settings
from account.models import SiteSettings


def create_realtime_token():
    key = SiteSettings.get().xmax_api_key.strip()
    if not key:
        raise ValueError("XMax API key is not configured in admin Site Settings")
    if settings.XMAX_ENVIRONMENT not in {"global", "china"}:
        raise ValueError("Invalid XMAX_ENVIRONMENT")
    return {"api_key": key, "expires_at": None}

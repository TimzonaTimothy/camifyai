"""Minimal settings for provider tests; no production database or credentials."""

SECRET_KEY = "provider-tests-only"
INSTALLED_APPS = [
    "django.contrib.auth", "django.contrib.contenttypes", "account", "streaming",
]
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}}
AUTH_USER_MODEL = "account.Account"
DEFAULT_AUTO_FIELD = "django.db.models.AutoField"
USE_TZ = True
REST_FRAMEWORK = {"UNAUTHENTICATED_USER": None}
# These database-free tests do not access the account image fields.
SILENCED_SYSTEM_CHECKS = ["fields.E210"]

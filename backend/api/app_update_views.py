"""
api/app_update_views.py

Serves the latest desktop-app version info AND the installer binary —
both completely public, no authentication required.

To release a new version:
  1. Upload the new installer to  <BASE_DIR>/downloads/StreamAI-Setup-<version>.exe
     (or any filename — just update INSTALLER_FILENAME below).
  2. Bump LATEST_VERSION.
  3. Update RELEASE_NOTES if needed.
  4. Deploy — no migration needed.
"""

import logging
import time
from pathlib import Path

from django.conf import settings
from django.http import HttpResponse, JsonResponse, StreamingHttpResponse, Http404
from django.views.decorators.http import require_GET, require_POST, require_http_methods
from django.views.decorators.csrf import csrf_exempt

from account.token_revocation import RevocableJWTAuthentication, revoke_user_tokens

# ── Edit these for every release ─────────────────────────────────────────────

LATEST_VERSION     = "1.0.11"
INSTALLER_FILENAME = "StreamAI-Setup-1.0.11.exe"   # file inside BASE_DIR/downloads/
RELEASE_NOTES      = "Required update — your current version will stop working. Update now to keep using the Playground."
MANDATORY          = True   # True = banner cannot be dismissed

# ─────────────────────────────────────────────────────────────────────────────

DOWNLOADS_DIR = Path(settings.BASE_DIR) / "downloads"

# How long the old app keeps working after the server has finished sending the
# installer. The web server (Passenger / LiteSpeed / any proxy) buffers the
# response, so "finished sending" happens long before the user has actually
# received the file on a slow connection. The app polls /auth/poll/ every few
# seconds — if the logout is active while the download is still running, that
# poll gets 401, the app signs the user out and the download is killed
# ("download failed"). Size this to the slowest download you expect.
LOGOUT_GRACE_SECONDS = int(getattr(settings, "APP_UPDATE_LOGOUT_GRACE_SECONDS", 20 * 60))

logger = logging.getLogger(__name__)


@require_GET
@csrf_exempt
def latest_version(request):
    """
    GET /api/v1/app/latest-version/

    Returns version metadata. download_url points to the public
    binary endpoint below — no login needed (sending a Bearer token signs the
    user out *after* the download, never during it).
    """
    download_url = request.build_absolute_uri("/api/v1/app/download/")

    return JsonResponse({
        "version":       LATEST_VERSION,
        "download_url":  download_url,
        "release_notes": RELEASE_NOTES,
        "mandatory":     MANDATORY,
        # New clients: after the installer is saved and verified, POST here
        # with the Bearer token to sign out immediately (see update_downloaded).
        "downloaded_url": request.build_absolute_uri("/api/v1/app/update-downloaded/"),
    })


@require_http_methods(["GET", "HEAD"])
@csrf_exempt
def download_installer(request):
    """
    GET /api/v1/app/download/

    Streams the installer binary — no authentication required.

    Optional logout: if the request carries a valid
    "Authorization: Bearer <access token>" header, every JWT issued to that
    user up to now is revoked — but only LOGOUT_GRACE_SECONDS after the file
    has been fully handed to the web server, so the app stays signed in (and
    keeps polling happily) while the download is still running.
    A dropped download never schedules a logout.
    Missing / invalid / expired tokens are ignored — the download still works.
    """
    installer_path = DOWNLOADS_DIR / INSTALLER_FILENAME

    if not installer_path.exists():
        logger.error("App installer missing: %s", installer_path)
        raise Http404("Installer not found.")

    size = installer_path.stat().st_size

    if request.method == "HEAD":
        response = HttpResponse(content_type="application/octet-stream")
    else:
        # Identify the user now, but do NOT revoke yet. Tokens issued before
        # this moment are the ones that will be revoked.
        user_id = _authenticated_user_id(request)
        response = StreamingHttpResponse(
            _stream_then_schedule_logout(installer_path, user_id, int(time.time())),
            content_type="application/octet-stream",
        )
    response["Content-Length"] = str(size)
    response["Content-Disposition"] = f'attachment; filename="{INSTALLER_FILENAME}"'
    response["Cache-Control"] = "no-store, no-transform"   # no proxy gzip / caching
    response["X-Accel-Buffering"] = "no"
    return response


@require_POST
@csrf_exempt
def update_downloaded(request):
    """
    POST /api/v1/app/update-downloaded/   (Authorization: Bearer <access>)

    For new app builds: call this after the installer has been saved to disk
    and its size checked, right before launching it. Signs the user out of
    every session immediately. Always returns 200 so the client never blocks
    the install on it.
    """
    user_id = _authenticated_user_id(request)
    if user_id is not None:
        try:
            revoke_user_tokens(user_id)
        except Exception:
            logger.exception("Failed to revoke tokens for user %s", user_id)
    return JsonResponse({"logged_out": user_id is not None})


def _authenticated_user_id(request):
    """Return the user's pk from a valid Bearer token, else None."""
    if not request.META.get("HTTP_AUTHORIZATION"):
        return None
    try:
        result = RevocableJWTAuthentication().authenticate(request)
    except Exception:
        return None  # bad/expired/already-revoked token — just serve the file
    if result:
        user, _token = result
        return user.pk
    return None


def _stream_then_schedule_logout(path, user_id, cutoff, chunk_size=512 * 1024):
    """
    Yield the file in chunks. Only once the last chunk has been handed over,
    schedule the logout (effective LOGOUT_GRACE_SECONDS from now). If the
    connection drops mid-way the generator is closed early and nothing is
    scheduled. Errors here must never break the download itself.
    """
    with open(path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            yield chunk
    if user_id is not None:
        try:
            revoke_user_tokens(
                user_id,
                cutoff=cutoff,
                effective_at=int(time.time()) + LOGOUT_GRACE_SECONDS,
            )
        except Exception:
            logger.exception("Failed to schedule logout for user %s", user_id)
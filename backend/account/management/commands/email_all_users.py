"""
Send one announcement email to every active user.

Usage (from /home/deepyhfd/streamai, with the virtualenv active):

    python manage.py email_all_users --test you@example.com   # send ONE copy to yourself first
    python manage.py email_all_users --dry-run                # list who would get it, send nothing
    python manage.py email_all_users                          # send to everyone

Each user gets their own email (no CC/BCC lists, so nobody sees other addresses).
Sends in batches with a pause between them, so the hosting SMTP limit isn't hit.
If it stops partway, re-run with --start N (N = the number it printed last).
"""

import time

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.mail import EmailMultiAlternatives, get_connection
from django.core.management.base import BaseCommand
from django.utils.html import escape

# ---------------------------------------------------------------- edit me
SUBJECT = "Sorry for the disruption and thank you for your patience"

BODY = """Hi {name},

We want to say a sincere sorry for the recent disruption you may have experienced with camifyai.

Our team has been working hard behind the scenes to fix the issue, strengthen our systems and make the app faster and more reliable for you. Everything is now back up and running.

Please download and install the latest version of camifyai here:
{download_url}

If you're asked to sign in again, that's expected, it's part of the security improvements we've made.

Thank you for your patience and for sticking with us. If anything still isn't working as it should, just reply to this email and we'll sort it out.

Warm regards,
The camifyai Team
"""

# Always serves the newest installer (api/app_update_views.download_installer).
DOWNLOAD_URL = getattr(settings, "SITE_URL", "https://streamaicam.com").rstrip("/") + "/download/"
# ------------------------------------------------------------------------


def render_body(name):
    return BODY.format(name=name, download_url=DOWNLOAD_URL)


def display_name(user):
    first = (getattr(user, "first_name", "") or "").strip()
    return first or "there"


def to_html(text):
    paragraphs = escape(text).strip().split("\n\n")
    inner = "".join(f"<p>{p.replace(chr(10), '<br>')}</p>" for p in paragraphs)
    # Turn the bare download link into a button (the plain-text version keeps the URL).
    button = (
        f'<a href="{DOWNLOAD_URL}" style="display:inline-block;margin:6px 0;padding:12px 22px;'
        'background:#2563eb;color:#ffffff;text-decoration:none;border-radius:6px;'
        f'font-weight:bold">Download the latest version</a>'
        f'<br><span style="font-size:12px;color:#666">or open: {DOWNLOAD_URL}</span>'
    )
    inner = inner.replace(escape(DOWNLOAD_URL), button, 1)
    return (
        '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;'
        'line-height:1.6;color:#222;max-width:560px">' + inner + "</div>"
    )


class Command(BaseCommand):
    help = "Email an announcement to all active users."

    def add_arguments(self, parser):
        parser.add_argument("--test", metavar="EMAIL", help="Send a single copy to this address only.")
        parser.add_argument("--dry-run", action="store_true", help="List recipients without sending.")
        parser.add_argument("--batch-size", type=int, default=50)
        parser.add_argument("--pause", type=int, default=60, help="Seconds to wait between batches.")
        parser.add_argument("--start", type=int, default=0, help="Skip the first N users (to resume).")

    def handle(self, *args, **opts):
        from_email = settings.DEFAULT_FROM_EMAIL

        if opts["test"]:
            body = render_body("there")
            msg = EmailMultiAlternatives(SUBJECT, body, from_email, [opts["test"]])
            msg.attach_alternative(to_html(body), "text/html")
            msg.send()
            self.stdout.write(self.style.SUCCESS(f"Test email sent to {opts['test']}"))
            return

        User = get_user_model()
        users = list(
            User.objects.filter(is_active=True)
            .exclude(email__isnull=True)
            .exclude(email="")
            .order_by("pk")
        )[opts["start"]:]

        total = len(users)
        self.stdout.write(f"{total} recipients (starting at #{opts['start']})")

        if opts["dry_run"]:
            for u in users:
                self.stdout.write(f"  {u.email}")
            return

        sent, failed = 0, []
        size = max(1, opts["batch_size"])

        for i in range(0, total, size):
            batch = users[i:i + size]
            connection = get_connection()
            connection.open()
            try:
                for u in batch:
                    body = render_body(display_name(u))
                    msg = EmailMultiAlternatives(SUBJECT, body, from_email, [u.email], connection=connection)
                    msg.attach_alternative(to_html(body), "text/html")
                    try:
                        msg.send()
                        sent += 1
                    except Exception as e:  # keep going if one address fails
                        failed.append((u.email, str(e)))
            finally:
                connection.close()

            done = opts["start"] + i + len(batch)
            self.stdout.write(f"Sent {sent}, failed {len(failed)} — processed up to #{done}")

            if i + size < total:
                time.sleep(opts["pause"])

        self.stdout.write(self.style.SUCCESS(f"Done. Sent {sent} of {total}."))
        for email, err in failed:
            self.stdout.write(self.style.WARNING(f"  FAILED {email}: {err}"))
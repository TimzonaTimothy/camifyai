import logging
import threading

from django.conf import settings
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes, parser_classes
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import SiteSettings, UserProfile, WatermarkFeePayment, WatermarkPaymentMethod

from .payment_views import _send_email_to_many

logger = logging.getLogger(__name__)



# ── Email helper ──────────────────────────────────────────────────────────────



def _notify_admin_watermark_proof(user_email, payment_id, currency, tx_hash, fee):
    admin_emails = getattr(
        settings, 'ADMIN_EMAILS',
        ['support@deepfakessoftwares.com', 'vitalischima77@gmail.com']
    )
    if isinstance(admin_emails, str):
        admin_emails = [admin_emails]

    base_url   = getattr(settings, 'BASE_URL', '')
    admin_link = f"{base_url}/admin/account/watermarkfeepayment/?status__exact=pending"

    html = f"""
    <div style="font-family:sans-serif;max-width:580px;margin:auto;
                padding:28px;background:#0f172a;border-radius:12px;
                border:1px solid #1e293b;">
      <h2 style="color:#f59e0b;margin-top:0;">&#9888;&nbsp; New Watermark Fee Proof</h2>
      <table style="width:100%;border-collapse:collapse;font-size:14px;color:#cbd5e1;">
        <tr><td style="padding:8px 0;color:#94a3b8;width:140px;">User</td>
            <td style="padding:8px 0;color:#f1f5f9;font-weight:600;">{user_email}</td></tr>
        <tr><td style="padding:8px 0;color:#94a3b8;">Payment ID</td>
            <td style="padding:8px 0;color:#f1f5f9;font-weight:600;">#{payment_id}</td></tr>
        <tr><td style="padding:8px 0;color:#94a3b8;">Amount</td>
            <td style="padding:8px 0;color:#f1f5f9;font-weight:600;">${fee} USD</td></tr>
        <tr><td style="padding:8px 0;color:#94a3b8;">Method</td>
            <td style="padding:8px 0;color:#f1f5f9;">{currency.upper() if currency else '—'}</td></tr>
        <tr><td style="padding:8px 0;color:#94a3b8;">TX Hash</td>
            <td style="padding:8px 0;color:#f1f5f9;font-family:monospace;word-break:break-all;">{tx_hash or '—'}</td></tr>
      </table>
      <a href="{admin_link}"
         style="display:inline-block;margin-top:16px;padding:12px 24px;
                background:#4f46e5;color:#fff;text-decoration:none;
                border-radius:8px;font-weight:600;font-size:14px;">
        Review in Admin Panel
      </a>
    </div>
    """
    _send_email_to_many(
        admin_emails,
        f"[Action Required] Watermark Fee Proof #{payment_id} — {user_email}",
        html,
    )

# ── Announcement ──────────────────────────────────────────────────────────────

class AnnouncementView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        cfg = SiteSettings.get()
        return Response({
            "active":          cfg.announcement_active and bool(cfg.announcement_text),
            "text":            cfg.announcement_text if cfg.announcement_active else "",
            "min_app_version": cfg.min_app_version or "",
        })


# ── Watermark fee status ──────────────────────────────────────────────────────

class WatermarkFeeStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        cfg = SiteSettings.get()                          # add this
        fee = str(cfg.watermark_fee_usd or "100.00")     # add this
        pending = (
            WatermarkFeePayment.objects
            .filter(user=request.user, status=WatermarkFeePayment.STATUS_PENDING)
            .order_by("-created_at")
            .first()
        )
        return Response({
            "paid":            profile.watermark_fee_paid,
            "fee_usd":         fee,                       # now dynamic
            "pending_payment": pending is not None,
            "payment_id":      pending.id if pending else None,
        })


# ── Payment methods (admin-managed) ──────────────────────────────────────────

class WatermarkPaymentMethodsView(APIView):
    """GET /api/v1/watermark-fee/methods/"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        methods = (
            WatermarkPaymentMethod.objects
            .filter(is_active=True)
            .order_by('sort_order', 'id')
            .values('id', 'name', 'identifier',
                    'address', 'extra_info', 'icon_emoji')
        )
        return Response(list(methods))


# ── Submit proof ──────────────────────────────────────────────────────────────

@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def submit_watermark_fee_proof(request):
    cfg = SiteSettings.get()
    fee = str(cfg.watermark_fee_usd)
    user    = request.user
    profile, _ = UserProfile.objects.get_or_create(user=user)

    if profile.watermark_fee_paid:
        return Response(
            {"error": "Your watermark fee has already been confirmed."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    proof_image = request.FILES.get("proof_image")
    if not proof_image:
        return Response(
            {"error": "proof_image is required."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    tx_hash   = request.data.get("tx_hash",   "").strip()
    notes     = request.data.get("notes",     "").strip()
    method_id = request.data.get("method_id", "").strip()

    # Resolve currency from WatermarkPaymentMethod
    currency = ""
    if method_id:
        try:
            method   = WatermarkPaymentMethod.objects.get(
                id=int(method_id), is_active=True
            )
            currency = method.identifier
        except (WatermarkPaymentMethod.DoesNotExist, ValueError):
            pass

    # Upsert — reuse existing pending record
    existing = (
        WatermarkFeePayment.objects
        .filter(user=user, status=WatermarkFeePayment.STATUS_PENDING)
        .order_by("-created_at")
        .first()
    )

    if existing:
        existing.proof_image = proof_image
        existing.tx_hash     = tx_hash
        existing.currency    = currency
        existing.notes       = notes
        existing.save()
        payment = existing
        created = False
    else:
        payment = WatermarkFeePayment.objects.create(
            user        = user,
            amount_usd = fee,
            currency    = currency,
            proof_image = proof_image,
            tx_hash     = tx_hash,
            notes       = notes,
        )
        created = True

    # Email admin (background thread — does not delay response)
    _notify_admin_watermark_proof(
        user_email = user.email,
        payment_id = payment.id,
        currency   = currency,
        tx_hash    = tx_hash,
        fee        = fee,
    )

    return Response(
        {
            "detail":     "Proof submitted. An admin will review shortly.",
            "payment_id": payment.id,
            "created":    created,
        },
        status=status.HTTP_201_CREATED,
    )
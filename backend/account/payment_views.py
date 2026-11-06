"""
payments views
==============

Payment flow (manual crypto / bank transfer):
  POST /api/v1/payments/create/          → records a PENDING payment, returns payment instructions
  GET  /api/v1/payments/<id>/status/     → Flutter polls this (stays "waiting" until admin confirms)

FLUTTERWAVE (Card / Bank / Mobile Money):
  POST /api/v1/payments/flutterwave/initiate/   → creates tx_ref, returns payment_url
  POST /api/v1/payments/flutterwave/webhook/    → Flutterwave calls this (IPN)
  GET  /api/v1/payments/flutterwave/verify/<tx_ref>/  → Flutter calls this after redirect

Admin confirms manual payments via the Django admin action "Confirm selected payments".
When confirmed, credits are added atomically and the user receives a Resend email.
"""

import json
import logging
import secrets

from decimal import Decimal
from django.conf import settings
from django.core.mail import EmailMessage
from django.db import transaction
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

import requests as http_requests

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

import random
from .models import CryptoPayment, UserProfile, CryptoWallet, FiatCurrency
from . import nowpayments

logger = logging.getLogger(__name__)

FLUTTERWAVE_API = "https://api.flutterwave.com/v3"
UNDERPAYMENT_TOLERANCE = 0.99


# ─────────────────────────────────────────────────────────────────────────────
# SHARED HELPERS
# ─────────────────────────────────────────────────────────────────────────────
def _send_email(to: str, subject: str, html: str):
    """Send an HTML email via Django's configured SMTP backend (EMAIL_* in settings.py)."""
    from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "support@streamaicam.com")

    try:
        message = EmailMessage(subject, html, from_email, [to])
        message.content_subtype = "html"
        message.send(fail_silently=False)
        logger.info(f"Email sent to {to}: {subject}")
        return True
    except Exception as e:
        logger.error(f"Email send to {to} failed: {e}")
        return False


def _send_email_to_many(recipients: list, subject: str, html: str):
    """Send the same HTML email to multiple recipients via SMTP."""
    for addr in recipients:
        _send_email(addr, subject, html)
        
        
def get_pack_by_id(pack_id):
    for pack in settings.CREDIT_PACKS:
        if pack["id"] == pack_id:
            return pack
    return None


def _get_user_profile(user):
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


def _send_resend_email(to: str, subject: str, html: str):
    """Send an email via the Resend API."""
    api_key = getattr(settings, "RESEND_API_KEY", "")
    from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "noreply@streamaicam.com")

    if not api_key:
        logger.error("RESEND_API_KEY is not configured — cannot send email.")
        return False

    try:
        resp = http_requests.post(
            "https://api.resend.com/emails",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "from": from_email,
                "to": [to],
                "subject": subject,
                "html": html,
            },
            timeout=10,
        )
        if resp.status_code in (200, 201):
            logger.info(f"Resend email sent to {to}: {subject}")
            return True
        else:
            logger.error(f"Resend error {resp.status_code}: {resp.text}")
            return False
    except Exception as e:
        logger.error(f"Resend exception: {e}")
        return False


def _send_resend_email_to_many(recipients: list, subject: str, html: str):
    """Send an email to multiple recipients via Resend."""
    for addr in recipients:
        _send_resend_email(addr, subject, html)


def _credit_user_atomic(payment):
    """
    Atomically confirm a payment and add credits to the user.
    Returns (success: bool, new_balance: float)
    """
    with transaction.atomic():
        locked = CryptoPayment.objects.select_for_update().get(pk=payment.pk)

        if locked.status == CryptoPayment.STATUS_CONFIRMED:
            logger.info(f"Payment {payment.pk} already confirmed — skipping double credit")
            profile = _get_user_profile(locked.user)
            return False, float(profile.credits)

        locked.status       = CryptoPayment.STATUS_CONFIRMED
        locked.confirmed_at = timezone.now()
        locked.save(update_fields=[
            "status", "confirmed_at",
            "nowpayments_payment_id",
            "flutterwave_transaction_id",
        ])

        profile = _get_user_profile(locked.user)
        profile = UserProfile.objects.select_for_update().get(pk=profile.pk)
        new_balance = profile.add_credits(locked.credits_to_add)
        profile.plan = locked.pack_id
        profile.save(update_fields=["plan", "credits"])

        def send_notifications():
            try:
                # ── User confirmation email ──────────────────────────────────
                # user_html = f"""
                # <div style="font-family:sans-serif;max-width:560px;margin:auto;padding:24px;background:#fff;border-radius:8px;">
                #   <h2 style="color:#4f46e5;margin-bottom:4px;">Payment Confirmed ✓</h2>
                #   <p style="color:#374151;">Hi {locked.user.email},</p>
                #   <p style="color:#374151;">Your payment has been confirmed and <strong>{locked.credits_to_add} credits</strong> have been added to your account.</p>
                #   <table style="border-collapse:collapse;width:100%;margin:16px 0;font-size:14px;">
                #     <tr style="background:#f9fafb;">
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Pack</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">{locked.pack_label}</td>
                #     </tr>
                #     <tr>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Credits Added</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">{locked.credits_to_add:,}</td>
                #     </tr>
                #     <tr style="background:#f9fafb;">
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">Amount Paid</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#111827;">${locked.amount_usd}</td>
                #     </tr>
                #     <tr>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#6b7280;font-weight:600;">New Balance</td>
                #       <td style="padding:10px 12px;border:1px solid #e5e7eb;color:#16a34a;font-weight:600;">{float(new_balance):,.0f} credits</td>
                #     </tr>
                #   </table>
                #   <p style="color:#6b7280;font-size:13px;">Thank you for your purchase! Open the app to start using your credits.</p>
                # </div>
                # """
                # _send_resend_email(
                #     locked.user.email,
                #     f"Payment Confirmed — {locked.credits_to_add:,} credits added to your account",
                #     user_html,
                # )

                # ── Admin notification ───────────────────────────────────────
                admin_emails = getattr(settings, "ADMIN_EMAILS", ["support@streamaicam.com","vitalischima77@gmail.com"])
                if isinstance(admin_emails, str):
                    admin_emails = [admin_emails]

                admin_html = f"""
                <div style="font-family:sans-serif;max-width:560px;margin:auto;padding:24px;">
                  <h2 style="color:#16a34a;">Payment Confirmed</h2>
                  <p><strong>User:</strong> {locked.user.email}</p>
                  <p><strong>Pack:</strong> {locked.pack_label} ({locked.credits_to_add:,} credits)</p>
                  <p><strong>Amount:</strong> ${locked.amount_usd}</p>
                  <p><strong>Gateway:</strong> {locked.gateway}</p>
                  <p><strong>Payment ID:</strong> {locked.pk}</p>
                </div>
                """
                _send_resend_email_to_many(
                    admin_emails,
                    f"Payment Confirmed: {locked.pack_label} — {locked.user.email}",
                    admin_html,
                )

            except Exception as e:
                logger.error(f"Failed to send payment confirmation emails: {e}")

        transaction.on_commit(send_notifications)

    logger.info(
        f"Payment confirmed: gateway={locked.gateway} user={locked.user.email} "
        f"credits_added={locked.credits_to_add} new_balance={new_balance}"
    )
    return True, float(new_balance)


def _flutterwave_headers():
    return {
        "Authorization": f"Bearer {settings.FLUTTERWAVE_SECRET_KEY}",
        "Content-Type":  "application/json",
    }


def _check_flutterwave_status(payment):
    """Proactively check Flutterwave to see if a transaction has completed."""
    if not payment.flutterwave_tx_ref:
        return False

    try:
        resp = http_requests.get(
            f"{FLUTTERWAVE_API}/transactions",
            headers=_flutterwave_headers(),
            params={"tx_ref": payment.flutterwave_tx_ref},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()

        for tx in data.get("data", []):
            if tx.get("status") == "successful":
                fw_amount = float(tx.get("amount", 0))
                expected  = float(payment.amount_usd)

                if fw_amount < expected * UNDERPAYMENT_TOLERANCE:
                    logger.warning(
                        f"Flutterwave proactive check: underpayment on payment {payment.id} "
                        f"expected={expected} received={fw_amount}"
                    )
                    continue

                payment.flutterwave_transaction_id = str(tx.get("id", ""))
                success, _ = _credit_user_atomic(payment)
                return success

    except Exception as e:
        logger.error(f"Error checking Flutterwave status for {payment.id}: {e}")

    return False


# ─────────────────────────────────────────────────────────────────────────────
# CREDIT PACKS LIST
# ─────────────────────────────────────────────────────────────────────────────

class CreditPacksView(APIView):
    """GET /api/v1/payments/packs/"""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response(settings.CREDIT_PACKS)


class WalletAddressesView(APIView):
    """
    GET /api/v1/payments/wallets/

    Returns one randomly selected active wallet address per network.
    If multiple wallets share the same network key, a different address
    may be returned on each call — spreading funds across wallets and
    making on-chain reconciliation easier.

    Response shape (same contract the Flutter app already expects):
    {
      "usdttrc20": {"address": "T...", "label": "USDT TRC20", "network": "usdttrc20"},
      "btc":       {"address": "1...", "label": "Bitcoin",    "network": "btc"},
      ...
    }
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        active_wallets = list(
            CryptoWallet.objects.filter(is_active=True)
            .values('network', 'label', 'address')
        )

        # Group wallets by network, then pick one at random per network
        grouped = {}
        for w in active_wallets:
            grouped.setdefault(w['network'], []).append(w)

        result = {}
        for network, wallets in grouped.items():
            chosen = random.choice(wallets)
            result[network] = {
                'address': chosen['address'],
                'label':   chosen['label'],
                'network': network,
            }

        return Response(result)



class CurrenciesView(APIView):
    """
    GET /api/v1/payments/currencies/

    Returns the crypto and fiat currency lists the Flutter app should display.
    Crypto currencies are derived from active CryptoWallet entries (deduplicated
    by network). Fiat currencies come from FiatCurrency records.

    Response:
    {
      "crypto": [
        {"id": "usdttrc20", "label": "USDT TRC20"},
        ...
      ],
      "fiat": [
        {"id": "NGN", "label": "NGN", "flag": "🇳🇬"},
        ...
      ]
    }
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        crypto = nowpayments.currencies()

        # Fiat: all active fiat currencies ordered by sort_order
        fiat = list(
            FiatCurrency.objects.filter(is_active=True)
            .values('currency_id', 'label', 'flag')
        )
        fiat_out = [
            {'id': f['currency_id'], 'label': f['label'], 'flag': f['flag']}
            for f in fiat
        ]

        return Response({'crypto': crypto, 'fiat': fiat_out, 'crypto_provider': 'nowpayments',
                         'fee_paid_by_user': settings.NOWPAYMENTS_FEE_PAID_BY_USER})


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENT HISTORY — paginated
# ─────────────────────────────────────────────────────────────────────────────

class PaymentHistoryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        page      = max(1, int(request.query_params.get("page", 1)))
        page_size = min(50, max(1, int(request.query_params.get("page_size", 10))))
        offset    = (page - 1) * page_size

        qs     = CryptoPayment.objects.filter(user=request.user).order_by("-created_at")
        total  = qs.count()
        sliced = qs.values(
            "id", "pack_id", "pack_label", "amount_usd",
            "credits_to_add", "currency", "gateway",
            "status", "payment_url", "created_at", "confirmed_at", "nowpayments_invoice_id",
        )[offset: offset + page_size]
        results = list(sliced)
        for entry in results:
            entry["payment_provider"] = "nowpayments" if entry.pop("nowpayments_invoice_id") else "manual"

        return Response({
            "results":     results,
            "count":       total,
            "total_pages": max(1, -(-total // page_size)),
            "page":        page,
            "page_size":   page_size,
        })


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENT STATUS POLL
# ─────────────────────────────────────────────────────────────────────────────

class PaymentStatusView(APIView):
    """GET /api/v1/payments/<payment_id>/status/"""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, payment_id):
        try:
            payment = CryptoPayment.objects.get(id=payment_id, user=request.user)
        except CryptoPayment.DoesNotExist:
            return Response({"error": "Payment not found."}, status=404)

        if payment.status in (CryptoPayment.STATUS_WAITING, CryptoPayment.STATUS_CONFIRMING):
            if payment.gateway == CryptoPayment.GATEWAY_FLUTTERWAVE:
                _check_flutterwave_status(payment)
                payment.refresh_from_db()
            elif payment.nowpayments_invoice_id and payment.nowpayments_payment_id:
                try:
                    nowpayments.settle(payment.nowpayments_payment_id)
                    payment.refresh_from_db()
                except nowpayments.ProviderError:
                    logger.warning("NOWPayments verification deferred for payment %s", payment.pk)

        return Response({
            "payment_id":      payment.id,
            "status":          payment.status,
            "gateway":         payment.gateway,
            "credits":         payment.credits_to_add,
            "confirmed_at":    payment.confirmed_at,
            "credits_balance": float(_get_user_profile(request.user).credits),
            "payment_url": payment.payment_url,
            "payment_provider": "nowpayments" if payment.nowpayments_invoice_id else "manual",
        })


# ─────────────────────────────────────────────────────────────────────────────
# MANUAL PAYMENT — admin confirms via Django admin action
# ─────────────────────────────────────────────────────────────────────────────

class CreatePaymentView(APIView):
    """Create a hosted USDT checkout; credit is granted only after verified settlement."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        pack_id = str(request.data.get("pack_id", "")).strip()
        currency = str(request.data.get("currency", "usdtbsc")).strip().lower()
        pack = get_pack_by_id(pack_id)
        if not pack:
            return Response({"error": "Invalid credit pack."}, status=400)
        if currency not in {entry["id"] for entry in nowpayments.currencies()}:
            return Response({"error": "Select a supported USDT network."}, status=400)
        payment = CryptoPayment.objects.create(
            user=request.user, pack_id=pack_id, pack_label=pack["label"],
            amount_usd=Decimal(str(pack["price_usd"])), credits_to_add=pack["credits"],
            currency=currency, gateway=CryptoPayment.GATEWAY_CRYPTO,
            status=CryptoPayment.STATUS_WAITING,
        )
        callback = settings.NOWPAYMENTS_CALLBACK_URL or settings.BASE_URL.rstrip("/") + "/api/v1/payments/webhook/"
        try:
            url = nowpayments.create_invoice(payment, callback)
        except nowpayments.ProviderError as error:
            payment.status = CryptoPayment.STATUS_FAILED
            payment.save(update_fields=["status"])
            if isinstance(error, nowpayments.BelowMinimum):
                return Response({"error": str(error)}, status=400)
            logger.warning("NOWPayments checkout unavailable for payment %s", payment.pk)
            return Response({"error": "Crypto checkout is unavailable. Please try again later."}, status=503)
        return Response({
            "payment_id": payment.pk, "payment_url": url, "status": payment.status,
            "amount_usd": str(payment.amount_usd), "credits": payment.credits_to_add,
            "currency": currency, "gateway": "crypto", "payment_provider": "nowpayments",
            "fee_paid_by_user": settings.NOWPAYMENTS_FEE_PAID_BY_USER,
            "message": "Complete payment in the secure checkout. Streaming time is added automatically after settlement.",
        }, status=201)


@method_decorator(csrf_exempt, name="dispatch")
class PaymentWebhookView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        payload = request.data
        if not isinstance(payload, dict) or not nowpayments.valid_signature(payload, request.headers.get("x-nowpayments-sig", "")):
            return Response({"error": "Invalid signature."}, status=401)
        if not payload.get("payment_id"):
            return Response({"status": "ignored"})
        try:
            payment = nowpayments.settle(payload["payment_id"])
        except nowpayments.ProviderError:
            # Retry rather than acknowledge a payment we have not verified.
            return Response({"error": "Payment verification pending."}, status=503)
        return Response({"status": payment.status})


# ─────────────────────────────────────────────────────────────────────────────
# FLUTTERWAVE GATEWAY
# ─────────────────────────────────────────────────────────────────────────────

class InitiateFlutterwavePaymentView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    SUPPORTED_CURRENCIES = {"NGN", "GHS", "KES", "ZAR", "UGX", "TZS", "USD", "EUR", "GBP"}

    def post(self, request):
        pack_id  = request.data.get("pack_id", "").strip()
        currency = request.data.get("currency", "USD").strip().upper()

        pack = get_pack_by_id(pack_id)
        if not pack:
            return Response({"error": f"Invalid pack_id '{pack_id}'."}, status=status.HTTP_400_BAD_REQUEST)

        if currency not in self.SUPPORTED_CURRENCIES:
            return Response(
                {"error": f"Unsupported currency '{currency}'.", "supported": sorted(self.SUPPORTED_CURRENCIES)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tx_ref     = f"fw-{request.user.id}-{pack_id}-{secrets.token_hex(8)}"
        user       = request.user
        user_email = user.email
        user_name  = getattr(user, "username", None) or user_email.split("@")[0]

        payload = {
            "tx_ref":       tx_ref,
            "amount":       float(pack["price_usd"]),
            "currency":     currency,
            "redirect_url": f"{settings.BASE_URL}/api/v1/payments/flutterwave/verify/{tx_ref}/",
            "meta":         {"user_id": user.id, "pack_id": pack_id, "credits": pack["credits"]},
            "customer":     {"email": user_email, "name": user_name},
            "customizations": {
                "title":       "DeepFakes Software Credits",
                "description": f"{pack['label']} — {pack['credits']} credits",
                "logo":        f"{settings.BASE_URL}/static/assets/img/logo/logo.png",
            },
        }

        try:
            resp = http_requests.post(f"{FLUTTERWAVE_API}/payments", headers=_flutterwave_headers(), json=payload, timeout=15)
            resp.raise_for_status()
            data = resp.json()
        except http_requests.RequestException as e:
            logger.error(f"Flutterwave initiate error: {e}")
            return Response({"error": "Card payment provider unavailable. Try again later."}, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        if data.get("status") != "success":
            return Response({"error": data.get("message", "Payment initiation failed.")}, status=status.HTTP_400_BAD_REQUEST)

        payment_link = data["data"]["link"]
        payment = CryptoPayment.objects.create(
            user=user, pack_id=pack_id, pack_label=pack["label"],
            amount_usd=Decimal(pack["price_usd"]), credits_to_add=pack["credits"],
            currency=currency, gateway=CryptoPayment.GATEWAY_FLUTTERWAVE,
            flutterwave_tx_ref=tx_ref, payment_url=payment_link, status=CryptoPayment.STATUS_WAITING,
        )

        return Response({
            "payment_id": payment.id, "payment_url": payment_link, "tx_ref": tx_ref,
            "amount": pack["price_usd"], "currency": currency, "credits": pack["credits"],
            "gateway": "flutterwave", "message": "Open payment_url to complete your purchase.",
        }, status=status.HTTP_201_CREATED)


class VerifyFlutterwavePaymentView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, tx_ref):
        try:
            payment = CryptoPayment.objects.get(
                flutterwave_tx_ref=tx_ref, gateway=CryptoPayment.GATEWAY_FLUTTERWAVE, user=request.user)
        except CryptoPayment.DoesNotExist:
            return Response({"error": "Payment not found."}, status=404)

        if payment.status == CryptoPayment.STATUS_CONFIRMED:
            return Response({"status": "confirmed", "credits": payment.credits_to_add,
                             "credits_balance": float(_get_user_profile(request.user).credits)})

        transaction_id = request.query_params.get("transaction_id") or request.query_params.get("flw_ref")
        if not transaction_id:
            return Response({"status": payment.status, "credits": payment.credits_to_add,
                             "credits_balance": float(_get_user_profile(request.user).credits)})

        try:
            resp = http_requests.get(f"{FLUTTERWAVE_API}/transactions/{transaction_id}/verify",
                                     headers=_flutterwave_headers(), timeout=15)
            resp.raise_for_status()
            data = resp.json()
        except http_requests.RequestException as e:
            logger.error(f"Flutterwave verify error: {e}")
            return Response({"error": "Could not verify payment."}, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        fw_data = data.get("data", {})
        fw_status = fw_data.get("status", "")
        fw_amount = float(fw_data.get("amount", 0))
        expected_amount = float(payment.amount_usd)

        if fw_status != "successful":
            payment.status = CryptoPayment.STATUS_FAILED
            payment.save(update_fields=["status"])
            return Response({"status": "failed", "reason": fw_status})

        if fw_amount < expected_amount * UNDERPAYMENT_TOLERANCE:
            return Response({"status": "amount_mismatch", "expected": expected_amount, "received": fw_amount})

        payment.flutterwave_transaction_id = str(transaction_id)
        payment.save(update_fields=["flutterwave_transaction_id"])
        credited, new_balance = _credit_user_atomic(payment)

        return Response({"status": "confirmed", "gateway": "flutterwave",
                         "credits": payment.credits_to_add, "credits_balance": new_balance})


@method_decorator(csrf_exempt, name="dispatch")
class FlutterwaveWebhookView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        flw_secret    = getattr(settings, "FLUTTERWAVE_WEBHOOK_HASH", "")
        flw_signature = request.headers.get("verif-hash", "")
        if flw_secret and flw_signature != flw_secret:
            return Response({"error": "Invalid signature"}, status=403)

        try:
            payload = json.loads(request.body)
        except json.JSONDecodeError:
            return Response({"error": "Invalid JSON"}, status=400)

        event          = payload.get("event", "")
        fw_data        = payload.get("data", {})
        tx_ref         = fw_data.get("tx_ref", "")
        transaction_id = str(fw_data.get("id", ""))
        fw_status      = fw_data.get("status", "")
        fw_amount      = float(fw_data.get("amount", 0))

        if event != "charge.completed" or fw_status != "successful":
            return Response({"status": "ignored"})

        try:
            payment = CryptoPayment.objects.filter(
                flutterwave_tx_ref=tx_ref, gateway=CryptoPayment.GATEWAY_FLUTTERWAVE
            ).select_related("user").first()
            if not payment:
                return Response({"status": "not_found"}, status=404)
        except Exception as e:
            logger.error(f"Error finding Flutterwave payment: {e}")
            return Response({"error": "Could not locate payment"}, status=400)

        expected_amount = float(payment.amount_usd)
        if fw_amount < expected_amount * UNDERPAYMENT_TOLERANCE:
            return Response({"status": "amount_mismatch"}, status=400)

        try:
            verify_resp = http_requests.get(f"{FLUTTERWAVE_API}/transactions/{transaction_id}/verify",
                                            headers=_flutterwave_headers(), timeout=15)
            verify_resp.raise_for_status()
            if verify_resp.json().get("data", {}).get("status", "") != "successful":
                return Response({"status": "verification_failed"}, status=400)
        except http_requests.RequestException as e:
            logger.error(f"Flutterwave verify failed in webhook: {e}")
            return Response({"status": "verification_unavailable"}, status=503)

        payment.flutterwave_transaction_id = transaction_id
        payment.save(update_fields=["flutterwave_transaction_id"])
        credited, _ = _credit_user_atomic(payment)

        return Response({"status": "credited" if credited else "already_confirmed",
                         "credits_added": payment.credits_to_add, "user": payment.user.email})
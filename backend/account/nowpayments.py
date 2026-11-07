"""NOWPayments hosted checkout and verified, idempotent settlement."""
import hashlib
import hmac
import json
import re
from decimal import Decimal, InvalidOperation
from urllib.parse import urlparse

import requests
from django.conf import settings
from django.db import transaction
from .models import CryptoPayment

API = "https://api.nowpayments.io/v1"
NETWORKS = {
    "usdtbsc": "USDT · BNB Smart Chain (BEP20)",
    "usdttrc20": "USDT · TRON (TRC20)",
}


class ProviderError(Exception):
    pass


class BelowMinimum(ProviderError):
    pass


def currencies():
    # Offer only the configured settlement asset, avoiding cross-network requests.
    payout_currency = settings.NOWPAYMENTS_PAYOUT_CURRENCY.strip().lower()
    return [{"id": code, "label": NETWORKS[code]} for code in settings.NOWPAYMENTS_CURRENCIES
            if code in NETWORKS and code == payout_currency]


def number(value):
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        raise ProviderError("Invalid provider amount")
    if not result.is_finite() or result < 0:
        raise ProviderError("Invalid provider amount")
    return result


def request(method, path, **kwargs):
    if not settings.NOWPAYMENTS_API_KEY:
        raise ProviderError("NOWPayments is not configured")
    try:
        response = requests.request(method, API + path,
            headers={"x-api-key": settings.NOWPAYMENTS_API_KEY, "Content-Type": "application/json"},
            timeout=20, **kwargs)
        response.raise_for_status()
        result = response.json()
    except (requests.RequestException, ValueError) as error:
        raise ProviderError("NOWPayments is temporarily unavailable") from error
    if not isinstance(result, dict):
        raise ProviderError("Invalid provider response")
    return result


def create_invoice(payment, callback_url):
    if payment.currency != settings.NOWPAYMENTS_PAYOUT_CURRENCY.strip().lower():
        raise ProviderError("Payment and payout must use the same USDT network")
    if not settings.NOWPAYMENTS_IPN_SECRET:
        raise ProviderError("NOWPayments IPN secret is not configured")
    parsed = urlparse(callback_url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ProviderError("A public HTTPS callback URL is required")
    fees_by_user = settings.NOWPAYMENTS_FEE_PAID_BY_USER
    minimum = request("GET", "/min-amount", params={
        "currency_from": payment.currency,
        "currency_to": settings.NOWPAYMENTS_PAYOUT_CURRENCY,
        "fiat_equivalent": "usd", "is_fixed_rate": "true",
        "is_fee_paid_by_user": str(fees_by_user).lower(),
    })
    minimum_amount = number(minimum.get("min_amount"))
    if minimum_amount <= 0:
        raise ProviderError("Invalid provider minimum")
    estimate = request("GET", "/estimate", params={
        "amount": str(payment.amount_usd), "currency_from": "usd", "currency_to": payment.currency,
    })
    if number(estimate.get("estimated_amount")) < minimum_amount:
        raise BelowMinimum("This pack is below the current network minimum. Choose a larger pack or another network.")
    payload = {
        "price_amount": float(payment.amount_usd), "price_currency": "usd",
        "pay_currency": payment.currency, "order_id": f"camify-{payment.pk}",
        "order_description": f"camifyai · {payment.pack_label}",
        "ipn_callback_url": callback_url,
        "is_fixed_rate": False,
        "is_fee_paid_by_user": False,
    }
    # Checkout redirects never confirm payments; only verified provider settlement does.
    result = request("POST", "/invoice", json=payload)
    invoice_id = str(result.get("id") or "")
    checkout_url = result.get("invoice_url") or ""
    if not isinstance(checkout_url, str):
        raise ProviderError("Invalid checkout response")
    parsed = urlparse(checkout_url)
    if not invoice_id.isdigit() or parsed.scheme != "https" or parsed.hostname != "nowpayments.io":
        raise ProviderError("Invalid checkout response")
    payment.nowpayments_invoice_id = invoice_id
    payment.payment_url = checkout_url
    payment.save(update_fields=["nowpayments_invoice_id", "payment_url"])
    return checkout_url


def valid_signature(payload, signature):
    secret = settings.NOWPAYMENTS_IPN_SECRET
    if not secret or not isinstance(signature, str):
        return False
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    expected = hmac.new(secret.encode(), canonical.encode(), hashlib.sha512).hexdigest()
    return hmac.compare_digest(expected, signature.lower())


def settle(provider_payment_id):
    """Verify through the authenticated API, then lock the exact invoice before crediting."""
    provider_payment_id = str(provider_payment_id)
    if not re.fullmatch(r"[0-9]{1,100}", provider_payment_id):
        raise ProviderError("Invalid payment identifier")
    data = request("GET", f"/payment/{provider_payment_id}")
    if str(data.get("payment_id")) != provider_payment_id:
        raise ProviderError("Payment identifier mismatch")
    invoice_id = str(data.get("invoice_id") or "")
    if not invoice_id.isdigit():
        raise ProviderError("Missing invoice identifier")
    with transaction.atomic():
        payment = CryptoPayment.objects.select_for_update().filter(
            nowpayments_invoice_id=invoice_id, gateway=CryptoPayment.GATEWAY_CRYPTO).first()
        if payment is None:
            raise ProviderError("Unknown invoice")
        if (data.get("order_id") != f"camify-{payment.pk}"
                or str(data.get("price_currency", "")).lower() != "usd"
                or number(data.get("price_amount")) != payment.amount_usd):
            raise ProviderError("Invoice details do not match")
        if payment.nowpayments_payment_id and payment.nowpayments_payment_id != provider_payment_id:
            raise ProviderError("A different payment is already associated with this invoice")
        payment.nowpayments_payment_id = provider_payment_id
        payment.save(update_fields=["nowpayments_payment_id"])
        if payment.status == CryptoPayment.STATUS_CONFIRMED:
            return payment
        state = data.get("payment_status")
        if state == "finished":
            # Never grant a full pack for a partial payment or a merely confirmed deposit.
            due = number(data.get("pay_amount"))
            paid = number(data.get("actually_paid"))
            if due <= 0 or paid < due:
                raise ProviderError("Payment has not been paid in full")
            from .payment_views import _credit_user_atomic
            _credit_user_atomic(payment)
            payment.refresh_from_db()
        elif state in {"confirming", "confirmed", "sending", "partially_paid"}:
            payment.status = CryptoPayment.STATUS_CONFIRMING
            payment.save(update_fields=["status"])
        elif state in {"failed", "expired", "refunded"}:
            payment.status = CryptoPayment.STATUS_EXPIRED if state == "expired" else CryptoPayment.STATUS_FAILED
            payment.save(update_fields=["status"])
        return payment

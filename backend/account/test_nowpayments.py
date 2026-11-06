import hashlib
import hmac
import json
from decimal import Decimal
from unittest.mock import patch

from django.conf import settings
from django.test import TestCase, override_settings
from rest_framework.test import APIClient
from .models import Account, CryptoPayment, UserProfile
from . import nowpayments


class NowPaymentsTests(TestCase):
    def setUp(self):
        self.user = Account.objects.create_user("payer@example.com", "test-password")
        self.profile = UserProfile.objects.create(user=self.user, credits=0)
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        self.payment = CryptoPayment.objects.create(user=self.user, pack_id="starter", pack_label="Starter",
            amount_usd=20, credits_to_add=1200, currency="usdtbsc", gateway="crypto",
            nowpayments_invoice_id="1001", payment_url="https://nowpayments.io/payment/?iid=1001")

    def details(self, **changes):
        data = {"payment_id": 5001, "invoice_id": 1001, "order_id": f"camify-{self.payment.pk}",
            "price_currency": "usd", "price_amount": 20, "pay_currency": "usdtbsc",
            "pay_amount": 20.6, "actually_paid": 20.6, "payment_status": "finished"}
        data.update(changes)
        return data

    def webhook(self, payload, signature=None):
        canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        if signature is None:
            signature = hmac.new(settings.NOWPAYMENTS_IPN_SECRET.encode(), canonical.encode(), hashlib.sha512).hexdigest()
        return APIClient().post("/webhook/", payload, format="json", HTTP_X_NOWPAYMENTS_SIG=signature)

    def balance(self):
        self.profile.refresh_from_db()
        return self.profile.credits

    @patch("account.nowpayments.request")
    def test_checkout_checks_minimum_and_adds_customer_paid_fees(self, request):
        request.side_effect = [{"min_amount": 5}, {"estimated_amount": 20},
            {"id": 1002, "invoice_url": "https://nowpayments.io/payment/?iid=1002"}]
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdtbsc"}, format="json")
        self.assertEqual(response.status_code, 201)
        created = CryptoPayment.objects.get(pk=response.data["payment_id"])
        payload = request.call_args.kwargs["json"]
        self.assertEqual(payload["order_id"], f"camify-{created.pk}")
        self.assertEqual(payload["price_amount"], 20)
        self.assertTrue(payload["is_fee_paid_by_user"])
        self.assertTrue(payload["is_fixed_rate"])
        self.assertEqual(payload["pay_currency"], "usdtbsc")
        self.assertEqual(created.nowpayments_invoice_id, "1002")
        self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request")
    def test_below_minimum_does_not_create_provider_invoice(self, request):
        request.side_effect = [{"min_amount": 25}, {"estimated_amount": 20}]
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdtbsc"}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request", side_effect=nowpayments.ProviderError("private diagnostics"))
    def test_provider_failure_is_not_charged_or_exposed(self, request):
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdtbsc"}, format="json")
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("private diagnostics", str(response.data))
        self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request")
    def test_rejects_non_usdt_network_before_calling_provider(self, request):
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdterc20"}, format="json")
        self.assertEqual(response.status_code, 400)
        request.assert_not_called()

    @patch("account.nowpayments.request")
    def test_finished_is_verified_and_duplicate_callbacks_credit_once(self, request):
        request.return_value = self.details()
        payload = {"payment_id": 5001, "payment_status": "finished"}
        self.assertEqual(self.webhook(payload).status_code, 200)
        self.assertEqual(self.webhook(payload).status_code, 200)
        self.assertEqual(self.balance(), Decimal("1200"))
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.nowpayments_payment_id, "5001")
        self.assertEqual(self.payment.status, "confirmed")

    @patch("account.nowpayments.request")
    def test_invalid_signature_never_fetches_or_credits(self, request):
        response = self.webhook({"payment_id": 5001}, signature="invalid")
        self.assertEqual(response.status_code, 401)
        request.assert_not_called()
        self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request")
    def test_callback_cannot_claim_finished_while_provider_reports_partial(self, request):
        request.return_value = self.details(payment_status="partially_paid", actually_paid=5)
        response = self.webhook({"payment_id": 5001, "payment_status": "finished"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.balance(), 0)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, "confirming")

    @patch("account.nowpayments.request")
    def test_confirmed_deposit_waits_for_finished_settlement(self, request):
        request.return_value = self.details(payment_status="confirmed")
        self.webhook({"payment_id": 5001})
        self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request")
    def test_finished_underpayment_or_wrong_order_price_is_rejected(self, request):
        for changes in ({"actually_paid": 5}, {"price_amount": 1}, {"price_currency": "eur"},
                        {"order_id": "camify-other"}, {"invoice_id": 9999}, {"payment_id": 9999}):
            with self.subTest(changes=changes):
                request.return_value = self.details(**changes)
                self.assertEqual(self.webhook({"payment_id": 5001}).status_code, 503)
                self.assertEqual(self.balance(), 0)

    @patch("account.nowpayments.request")
    def test_poll_reconciles_bound_provider_payment(self, request):
        self.payment.nowpayments_payment_id = "5001"
        self.payment.save()
        request.return_value = self.details()
        response = self.client.get(f"/{self.payment.pk}/status/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "confirmed")
        self.assertEqual(self.balance(), 1200)

    def test_another_user_cannot_poll_a_payment(self):
        other = Account.objects.create_user("other@example.com", "test-password")
        self.client.force_authenticate(other)
        self.assertEqual(self.client.get(f"/{self.payment.pk}/status/").status_code, 404)

    def test_history_distinguishes_hosted_and_manual_payments(self):
        response = self.client.get("/")
        self.assertEqual(response.data["results"][0]["payment_provider"], "nowpayments")
        self.assertNotIn("nowpayments_invoice_id", response.data["results"][0])

    @override_settings(NOWPAYMENTS_IPN_SECRET="")
    def test_missing_webhook_secret_is_rejected(self):
        self.assertEqual(self.webhook({"payment_id": 5001}, signature="x").status_code, 401)

    @override_settings(NOWPAYMENTS_CALLBACK_URL="http://localhost:8000/webhook/")
    @patch("account.nowpayments.request")
    def test_local_callback_is_rejected_before_provider_request(self, request):
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdtbsc"}, format="json")
        self.assertEqual(response.status_code, 503)
        request.assert_not_called()

    @patch("account.nowpayments.request")
    def test_separate_invoices_both_add_to_the_same_balance(self, request):
        request.return_value = self.details()
        nowpayments.settle(5001)
        second = CryptoPayment.objects.create(user=self.user, pack_id="starter", pack_label="Starter",
            amount_usd=20, credits_to_add=1200, currency="usdtbsc", gateway="crypto", nowpayments_invoice_id="1002")
        request.return_value = self.details(payment_id=5002, invoice_id=1002, order_id=f"camify-{second.pk}")
        nowpayments.settle(5002)
        self.assertEqual(self.balance(), 2400)

    @patch("account.nowpayments.request")
    def test_expired_invoice_does_not_credit(self, request):
        request.return_value = self.details(payment_status="expired", actually_paid=0)
        nowpayments.settle(5001)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, "expired")
        self.assertEqual(self.balance(), 0)

    def test_checkout_requires_authentication(self):
        response = APIClient().post("/create/", {"pack_id": "starter", "currency": "usdtbsc"}, format="json")
        self.assertIn(response.status_code, (401, 403))

    @patch("account.nowpayments.request")
    def test_cross_network_checkout_is_rejected(self, request):
        response = self.client.post("/create/", {"pack_id": "starter", "currency": "usdttrc20"}, format="json")
        self.assertEqual(response.status_code, 400)
        request.assert_not_called()

    def test_only_matching_settlement_network_is_offered(self):
        self.assertEqual(nowpayments.currencies(), [{"id": "usdtbsc", "label": "USDT · BNB Smart Chain (BEP20)"}])

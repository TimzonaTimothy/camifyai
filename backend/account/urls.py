from django.urls import path, re_path
from .views import *
from .views import DesktopVerifyOTPView
from django.conf import settings
from django.conf.urls.static import static
from django.views.static import serve

from account.token_refresh_views import RevocableTokenRefreshView as TokenRefreshView

from .views import (
    RegisterView,
    LoginView,
    MeView,
    DashboardStatsView,
    PollStatusView,
    UsageLogListView,
)

from .payment_views import (
    CreditPacksView,
    WalletAddressesView,
    CurrenciesView,
    CreatePaymentView,
    PaymentWebhookView,
    PaymentHistoryView,
    PaymentStatusView,
    InitiateFlutterwavePaymentView,
    VerifyFlutterwavePaymentView,
    FlutterwaveWebhookView,
)

from .watermark_fee_views import (
    AnnouncementView,
    WatermarkFeeStatusView,
    submit_watermark_fee_proof,
    WatermarkPaymentMethodsView,
)

app_name = 'account'

urlpatterns = [
    path('download/', download_app_view, name='download_app'),
    path('activate/<uidb64>/<token>/', activate, name='activate'),
    path('sign_up', sign_up, name="sign_up"),
    path('sign_in', sign_in, name="sign_in"),
    path('logout', user_logout, name="logout"),
    path('forget_password', forgetpassword, name="forget_password"),
    path('resetpassword_validate/<uidb64>/<token>/', resetpassword_validate, name='resetpassword_validate'),
    path('resetpassword', resetpassword, name='resetpassword'),

    # ── Auth ─────────────────────────────────────────────────────────────────
    path("register/",  RegisterView.as_view(),    name="register"),
    path("login/",     LoginView.as_view(),        name="login"),
    path("refresh/",   TokenRefreshView.as_view(), name="token_refresh"),

    # ── Profile ───────────────────────────────────────────────────────────────
    path("me/",        MeView.as_view(),           name="me"),

    # ── Dashboard & polling ───────────────────────────────────────────────────
    path("dashboard/", DashboardStatsView.as_view(), name="dashboard"),
    path("poll/",      PollStatusView.as_view(),     name="poll"),

    # ── Usage history ─────────────────────────────────────────────────────────
    path("usage/",     UsageLogListView.as_view(),   name="usage"),

    # ── Announcement banner + app version gate ────────────────────────────────
    # GET /api/v1/announcement/
    path("announcement/", AnnouncementView.as_view(), name="announcement"),

    # ── Watermark Fee ─────────────────────────────────────────────────────────
    # GET  /api/v1/watermark-fee/status/
    # POST /api/v1/watermark-fee/submit/  (multipart: proof_image, tx_hash, currency, notes)
    path("watermark-fee/status/", WatermarkFeeStatusView.as_view(),  name="watermark_fee_status"),
    path("watermark-fee/submit/", submit_watermark_fee_proof,         name="watermark_fee_submit"),
    path("watermark-fee/methods/", WatermarkPaymentMethodsView.as_view(), name="watermark_fee_methods"),

    # ── Payments — shared ────────────────────────────────────────────────────
    path("packs/",                           CreditPacksView.as_view(),         name="credit_packs"),
    path("payments/wallets/",                WalletAddressesView.as_view(),      name="wallet_addresses"),
    path("payments/currencies/",             CurrenciesView.as_view(),           name="currencies"),
    path("payments/",                        PaymentHistoryView.as_view(),       name="payment_history"),
    path("<int:payment_id>/status/",         PaymentStatusView.as_view(),        name="payment_status"),

    # ── Payments — Crypto / NOWPayments ─────────────────────────────────────
    path("payments/create/",                 CreatePaymentView.as_view(),        name="create_crypto_payment"),
    path("webhook/",                         PaymentWebhookView.as_view(),       name="crypto_webhook"),
    path("payments/<int:payment_id>/proof/", submit_payment_proof),

    # ── Payments — Flutterwave ────────────────────────────────────────────────
    path("payments/flutterwave/initiate/",          InitiateFlutterwavePaymentView.as_view(), name="fw_initiate"),
    path("payments/flutterwave/webhook/",           FlutterwaveWebhookView.as_view(),         name="fw_webhook"),
    path("payments/flutterwave/verify/<str:tx_ref>/", VerifyFlutterwavePaymentView.as_view(), name="fw_verify"),

    # ── Desktop App — password management ────────────────────────────────────
    path("desktop/forgot-password/",  DesktopForgotPasswordView.as_view(),  name="desktop_forgot_password"),
    path("desktop/verify-otp/",       DesktopVerifyOTPView.as_view(),       name="desktop_verify_otp"),
    path("desktop/change-password/",  DesktopChangePasswordView.as_view(),  name="desktop_change_password"),

] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
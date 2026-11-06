from django.urls import path
from .payment_views import (
    CreditPacksView,
    CreatePaymentView,
    PaymentWebhookView,
    PaymentHistoryView,
    PaymentStatusView,
)

urlpatterns = [
    path("packs/",                      CreditPacksView.as_view(),    name="credit_packs"),
    path("create/",                     CreatePaymentView.as_view(),  name="create_payment"),
    path("webhook/",                    PaymentWebhookView.as_view(), name="payment_webhook"),
    path("",                            PaymentHistoryView.as_view(), name="payment_history"),
    path("<int:payment_id>/status/",    PaymentStatusView.as_view(),  name="payment_status"),
]

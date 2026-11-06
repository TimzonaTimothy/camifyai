from streaming.test_settings import *
ROOT_URLCONF = "account.payments_urls"
MIGRATION_MODULES = {"account": None}
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
CREDIT_PACKS = [{"id": "starter", "label": "Starter", "price_usd": "20.00", "credits": 1200}]
NOWPAYMENTS_API_KEY = "test-api-key"
NOWPAYMENTS_IPN_SECRET = "test-ipn-secret"
NOWPAYMENTS_CURRENCIES = ["usdtbsc", "usdttrc20"]
NOWPAYMENTS_PAYOUT_CURRENCY = "usdtbsc"
NOWPAYMENTS_FEE_PAID_BY_USER = True
NOWPAYMENTS_CALLBACK_URL = "https://camifyai.example/api/v1/payments/webhook/"
BASE_URL = "https://camifyai.example"

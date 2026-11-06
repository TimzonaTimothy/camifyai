from django.db import models
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager,PermissionsMixin, Group, Permission
from django.db.models import Q
from django.utils import timezone
from django.conf import settings
from datetime import timedelta
from decimal import Decimal
from django.template.loader import render_to_string
from django.core.mail import EmailMessage
import uuid
import secrets
import hashlib


class MyAccountManager(BaseUserManager):
    def create_user(self,email,password=None):
        if not email:
            raise ValueError('User must have an email address')

        user = self.model(
            email = self.normalize_email(email),
        )

        user.set_password(password)
        user.save(using=self._db)
        
        return user

    def create_superuser(self,email,password):
        user = self.create_user(
            email = self.normalize_email(email),
            password=password,
        )

        user.is_admin = True
        user.is_active = True
        user.is_staff = True
        user.is_superadmin = True
        user.is_superuser = True

        user.save(using=self._db)
        return user


class Account(AbstractBaseUser,PermissionsMixin):
    email         = models.EmailField(max_length=100, unique=True)
    
    last_activity = models.DateTimeField(auto_now=True,editable=False)

    date_joined   = models.DateTimeField(blank=True,null=True) 
    last_login    = models.DateTimeField(blank=True,null=True)   
    is_admin      = models.BooleanField(default=False)
    is_staff      = models.BooleanField(default=False)
    is_active     = models.BooleanField(default=True)
    is_superadmin = models.BooleanField(default=False)
    is_superuser = models.BooleanField(default=False)

    groups = models.ManyToManyField(
        Group, 
        related_name="account_users",
        blank=True
    )
    
    user_permissions = models.ManyToManyField(
        Permission, 
        related_name="account_users_permissions",
        blank=True
    )

    USERNAME_FIELD = 'email'

    objects = MyAccountManager()
        
    def full_name(self):
        return f"{self.first_name} {self.last_name}"

    def has_perm(self, perm, obj=None):
        return self.is_admin
    
    def has_module_perms(self, app_label):
        return self.is_superuser

    def has_module_perms(self, add_label):
        return True
    
    class Meta:
        ordering = ["-date_joined"]


class UserProfile(models.Model):
    PLAN_FREE = "free"

    PLAN_CHOICES = [
        ("free", "Free"),
        ("starter", "Starter"),
        ("creator", "Creator"),
        ("pro", "Pro"),
        ("agency", "Agency"),
        ("power", "Power"),
    ]

    user = models.OneToOneField(Account, on_delete=models.CASCADE)
    credits = models.DecimalField(
        max_digits=14,
        decimal_places=4,
        default=Decimal("0.0000"),
    )
    plan = models.CharField(max_length=20, choices=PLAN_CHOICES, default=PLAN_FREE)

    # ── Watermark fee ─────────────────────────────────────────────────────────
    watermark_fee_paid = models.BooleanField(
        default=False,
        verbose_name="Watermark Fee Paid",
        help_text=(
            "If True, this user has paid the $100 watermark removal fee "
            "and gets the clean (no-watermark) Decart API key."
        ),
    )

    def has_credits(self, amount):
        """Check if user has enough credits."""
        return self.credits >= Decimal(str(amount))

    def deduct_credits(self, amount):
        """
        Deduct credits from user balance.
        Raises ValueError if insufficient credits.
        """
        amount = Decimal(str(amount))
        if not self.has_credits(amount):
            raise ValueError(
                f"Insufficient credits. Required: {amount}, Available: {self.credits}"
            )
        self.credits -= amount
        self.save(update_fields=["credits"])
        return self.credits
 
    def add_credits(self, amount):
        """Add credits to user balance (called after payment confirms)."""
        amount = Decimal(str(amount))
        self.credits += amount
        self.save(update_fields=["credits"])
        return self.credits
 
    def __str__(self):
        return f"{self.user.email} | {self.credits} credits"
        
        
# ─── Site Settings (singleton) ───────────────────────────────────────────────
class SiteSettings(models.Model):
    """
    Singleton model — only one row ever exists (pk=1).
    Edit via Django Admin → Site Settings.
    """
    xmax_api_key = models.CharField(
        max_length=300,
        blank=True,
        default="",
        verbose_name="XMax API Key",
        help_text="Permanent key for realtime streaming. Changes apply to new and reconnected sessions.",
    )

    # ── Decart API keys ───────────────────────────────────────────────────────
    decart_api_key = models.CharField(
        max_length=300,
        verbose_name="Decart API Key (with watermark)",
        help_text=(
            "Used for users who have NOT paid the watermark removal fee. "
            "Change here anytime without touching code."
        ),
    )
    decart_api_key_no_watermark = models.CharField(
        max_length=300,
        blank=True,
        default='',
        verbose_name="Decart API Key (watermark removed)",
        help_text=(
            "Used for users who HAVE paid the watermark removal fee. "
            "Leave blank to fall back to the default key."
        ),
    )

    # ── Announcement banner ───────────────────────────────────────────────────
    announcement_active = models.BooleanField(
        default=False,
        verbose_name="Show Announcement Banner",
        help_text="Toggle the announcement banner on/off without clearing the text.",
    )
    announcement_text = models.TextField(
        blank=True,
        default='',
        verbose_name="Announcement Text",
        help_text=(
            "Text shown as a dismissible banner to ALL users inside the app. "
            "Leave blank to hide the banner even if the toggle is on."
        ),
    )

    # ── Minimum app version gate ──────────────────────────────────────────────
    min_app_version = models.CharField(
        max_length=20,
        blank=True,
        default='',
        verbose_name="Minimum App Version",
        help_text=(
            "If set, users running an older version will be blocked from "
            "using the playground/app until they update. Format: 1.0.6"
        ),
    )

    watermark_fee_usd = models.DecimalField(
        max_digits=8,
        decimal_places=2,
        default=200.00,
        verbose_name='Watermark Fee (USD)',
        help_text='Amount users must pay to remove the watermark. Change here without touching code.',
    )

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Site Settings"
        verbose_name_plural = "Site Settings"

    def __str__(self):
        return "Site Settings"

    def save(self, *args, **kwargs):
        self.pk = 1  # enforce singleton
        super().save(*args, **kwargs)

    @classmethod
    def get(cls):
        """Return the singleton row, seeding from settings.py on first access."""
        from django.conf import settings as django_settings
        obj, _ = cls.objects.get_or_create(
            pk=1,
            defaults={"decart_api_key": getattr(django_settings, "DECART_API_KEY", "")},
        )
        return obj

    def get_decart_key_for_user(self, profile):
        """
        Return the correct Decart API key for a given UserProfile.
        Users who have paid the watermark fee get the clean key (if configured).
        Everyone else gets the standard key.
        """
        if profile.watermark_fee_paid and self.decart_api_key_no_watermark:
            return self.decart_api_key_no_watermark
        return self.decart_api_key


class WatermarkPaymentMethod(models.Model):
    """
    Admin-managed payment methods for the $100 watermark removal fee.
    Add/edit/reorder via Django Admin → Watermark Payment Methods.
    Flutter fetches these from GET /api/v1/watermark-fee/methods/.
    """
    name       = models.CharField(
        max_length=100,
        verbose_name='Method Name',
        help_text='e.g. USDT TRC20, Bitcoin, Bank Transfer',
    )
    identifier = models.CharField(
        max_length=50,
        unique=True,
        verbose_name='Identifier',
        help_text='Short key used internally, e.g. usdttrc20, btc, bank',
    )
    address = models.CharField(
        max_length=500,
        verbose_name='Wallet Address / Account Number',
        help_text='The address or account number users will send $100 to.',
    )
    extra_info = models.TextField(
        blank=True,
        default='',
        verbose_name='Extra Info',
        help_text='Optional: bank name, network, memo. Shown to user below address.',
    )
    icon_emoji = models.CharField(
        max_length=10,
        default='💵',
        verbose_name='Icon Emoji',
        help_text='Emoji shown next to the method name in the app.',
    )
    is_active  = models.BooleanField(
        default=True,
        verbose_name='Active',
        help_text='Only active methods are shown to users.',
    )
    sort_order = models.PositiveIntegerField(
        default=0,
        verbose_name='Sort Order',
        help_text='Lower = shown first.',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table   = 'account_watermarkpaymentmethod'
        ordering   = ['sort_order', 'id']
        verbose_name        = 'Watermark Payment Method'
        verbose_name_plural = 'Watermark Payment Methods'

    def __str__(self):
        status = 'active' if self.is_active else 'inactive'
        return f'{self.icon_emoji} {self.name} ({status})'

class APIKey(models.Model):
    """
    API keys that YOUR users use to authenticate to YOUR platform.
    These keys are completely separate from Decart — users never
    interact with Decart directly.
 
    Security: We only store a hash of the key. The raw key is shown
    once on creation and never stored or retrievable again.
    """
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="api_keys",
    )
    name = models.CharField(max_length=100, default="My Key")
    # Prefix shown in UI e.g. "sk-live-AbCd1234"
    prefix = models.CharField(max_length=20)
    # SHA-256 hash of the full key — used for lookup
    key_hash = models.CharField(max_length=256, unique=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)
 
    class Meta:
        db_table = "users_apikey"
        ordering = ["-created_at"]
 
    @classmethod
    def generate(cls, user, name="My Key"):
        """
        Generate a new API key for a user.
        Returns (APIKey instance, raw_key string).
        The raw_key is only returned ONCE and must be shown to the user immediately.
        """
        raw_key = "sk-live-" + secrets.token_urlsafe(40)
        key_hash = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()
        prefix = raw_key[:18]  # e.g. "sk-live-AbCdEfGhIj"
        instance = cls.objects.create(
            user=user,
            name=name,
            prefix=prefix,
            key_hash=key_hash,
        )
        return instance, raw_key
 
    @classmethod
    def authenticate(cls, raw_key):
        """
        Validate a raw API key and return the associated User.
        Returns None if key is invalid or inactive.
        """
        if not raw_key or not raw_key.startswith("sk-live-"):
            return None
        key_hash = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()
        try:
            obj = cls.objects.select_related("user").get(
                key_hash=key_hash,
                is_active=True,
            )
            obj.last_used_at = timezone.now()
            obj.save(update_fields=["last_used_at"])
            return obj.user
        except cls.DoesNotExist:
            return None
 
    def __str__(self):
        return f"{self.prefix}... ({self.user.email})"

class UsageLog(models.Model):
    """
    Every API call is recorded here.
    Used for: dashboard charts, billing reconciliation, debugging.
    """
    ENDPOINT_REALTIME = "realtime_token"
    ENDPOINT_VIDEO = "queue_video"
    ENDPOINT_IMAGE = "queue_image"
 
    ENDPOINT_CHOICES = [
        (ENDPOINT_REALTIME, "Realtime Token (WebRTC)"),
        (ENDPOINT_VIDEO,    "Queue: Video Generation"),
        (ENDPOINT_IMAGE,    "Queue: Image Generation"),
    ]
 
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="usage_logs",
    )
    endpoint = models.CharField(max_length=50, choices=ENDPOINT_CHOICES)
    model_used = models.CharField(max_length=100, blank=True)
    credits_used = models.DecimalField(max_digits=12, decimal_places=4)
    timestamp = models.DateTimeField(auto_now_add=True)
    metadata = models.JSONField(default=dict, blank=True)
 
    class Meta:
        db_table = "users_usagelog"
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["user", "timestamp"]),
            models.Index(fields=["endpoint"]),
        ]
 
    def __str__(self):
        return f"{self.user.email} | {self.endpoint} | {self.credits_used} credits"
 

class CryptoPayment(models.Model):
    """
    Tracks every payment — both crypto (NOWPayments) and card/bank (Flutterwave).
    When status becomes 'confirmed', credits are added to user account.
    """
    STATUS_WAITING    = "waiting"
    STATUS_CONFIRMING = "confirming"
    STATUS_CONFIRMED  = "confirmed"
    STATUS_FAILED     = "failed"
    STATUS_EXPIRED    = "expired"
 
    STATUS_CHOICES = [
        (STATUS_WAITING,    "Waiting for payment"),
        (STATUS_CONFIRMING, "Confirming"),
        (STATUS_CONFIRMED,  "Confirmed — credits added"),
        (STATUS_FAILED,     "Failed"),
        (STATUS_EXPIRED,    "Expired"),
    ]
 
    GATEWAY_CRYPTO      = "crypto"
    GATEWAY_FLUTTERWAVE = "flutterwave"
 
    GATEWAY_CHOICES = [
        (GATEWAY_CRYPTO,      "Crypto (NOWPayments)"),
        (GATEWAY_FLUTTERWAVE, "Flutterwave (Card/Bank/Mobile Money)"),
    ]
 
    user       = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="payments",
    )
    pack_id    = models.CharField(max_length=50)
    pack_label = models.CharField(max_length=100, blank=True)
 
    amount_usd     = models.DecimalField(max_digits=10, decimal_places=2)
    credits_to_add = models.IntegerField()
    currency       = models.CharField(max_length=30)
 
    gateway = models.CharField(
        max_length=20,
        choices=GATEWAY_CHOICES,
        default=GATEWAY_CRYPTO,
    )
 
    nowpayments_invoice_id = models.CharField(max_length=100, blank=True, default='')
    nowpayments_payment_id = models.CharField(max_length=100, blank=True, default='')
    payment_url            = models.URLField(blank=True)
 
    flutterwave_tx_ref           = models.CharField(max_length=100, blank=True, default='')
    flutterwave_transaction_id   = models.CharField(max_length=100, blank=True, default='')
 
    status       = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_WAITING)
    created_at   = models.DateTimeField(auto_now_add=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
 
    class Meta:
        db_table = "payments_cryptopayment"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "status"]),
            models.Index(fields=["nowpayments_invoice_id"]),
            models.Index(fields=["flutterwave_tx_ref"]),
        ]
 
    def __str__(self):
        return f"{self.user.email} | {self.pack_label} | {self.gateway} | {self.status}"


class PaymentProof(models.Model):
    payment     = models.OneToOneField(CryptoPayment, on_delete=models.CASCADE, related_name='proof')
    proof_image = models.ImageField(upload_to='payment_proofs/')
    tx_hash     = models.CharField(max_length=255, blank=True)
    notes       = models.TextField(blank=True)
    submitted_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'Proof for Payment #{self.payment.id} — {self.payment.user.email}'


# ─── Watermark Fee Payment ────────────────────────────────────────────────────
class WatermarkFeePayment(models.Model):
    """
    Tracks the one-off $100 watermark removal fee.
    Admin confirms via the Django admin action, which flips
    UserProfile.watermark_fee_paid = True so the user gets the clean API key.
    """
    STATUS_PENDING   = "pending"
    STATUS_CONFIRMED = "confirmed"
    STATUS_REJECTED  = "rejected"

    STATUS_CHOICES = [
        (STATUS_PENDING,   "Pending — awaiting proof"),
        (STATUS_CONFIRMED, "Confirmed — fee paid"),
        (STATUS_REJECTED,  "Rejected"),
    ]

    user       = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="watermark_fee_payments",
    )
    amount_usd = models.DecimalField(max_digits=10, decimal_places=2, default="100.00")
    currency   = models.CharField(
        max_length=30,
        blank=True,
        default='',
        help_text="e.g. usdttrc20, btc, NGN",
    )
    status     = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
    )
    proof_image  = models.ImageField(upload_to='watermark_fee_proofs/', blank=True, null=True)
    tx_hash      = models.CharField(max_length=255, blank=True, default='')
    notes        = models.TextField(blank=True, default='')
    created_at   = models.DateTimeField(auto_now_add=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "account_watermarkfeepayment"
        ordering = ["-created_at"]
        verbose_name = "Watermark Fee Payment"
        verbose_name_plural = "Watermark Fee Payments"

    def __str__(self):
        return f"{self.user.email} | ${self.amount_usd} | {self.status}"


class PasswordResetOTP(models.Model):
    """
    Stores a 6-digit OTP for desktop app password resets.
    - Each code expires after 10 minutes.
    - Requesting a new code invalidates all previous ones for that user.
    - Max 3 verification attempts before the code is burned.
    """
    user       = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="password_otps",
    )
    code       = models.CharField(max_length=6)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used    = models.BooleanField(default=False)
    attempts   = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "account_password_reset_otp"
        ordering = ["-created_at"]

    def is_expired(self):
        return timezone.now() > self.expires_at

    def is_valid(self):
        return not self.is_used and not self.is_expired() and self.attempts < 3

    @classmethod
    def create_for_user(cls, user):
        """Invalidate old OTPs and create a fresh 6-digit code (10 min expiry)."""
        import random
        cls.objects.filter(user=user, is_used=False).update(is_used=True)
        code = f"{random.randint(0, 999999):06d}"
        return cls.objects.create(
            user=user,
            code=code,
            expires_at=timezone.now() + timedelta(minutes=10),
        )

    def __str__(self):
        return f"OTP {self.code} for {self.user.email} ({'valid' if self.is_valid() else 'expired/used'})"

class CryptoWallet(models.Model):
    """
    Admin-managed crypto wallet addresses.
    Multiple wallets can exist per network; the API returns one chosen
    at random so consecutive payments to the same network get different
    addresses, making on-chain reconciliation easier.
    """
    network = models.CharField(
        max_length=50,
        help_text=(
            'Currency/network key that matches what the Flutter app sends, '
            'e.g. usdttrc20, usdterc20, usdc, btc, eth, sol'
        ),
    )
    label = models.CharField(
        max_length=100,
        help_text='Human-readable label shown in the app, e.g. "USDT TRC20"',
    )
    address = models.CharField(max_length=255)
    is_active = models.BooleanField(
        default=True,
        help_text='Only active wallets are ever returned to users',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    notes = models.TextField(
        blank=True,
        help_text='Internal notes — never shown to users',
    )

    class Meta:
        db_table = 'account_cryptowallet'
        ordering = ['network', 'id']
        verbose_name = 'Crypto Wallet'
        verbose_name_plural = 'Crypto Wallets'

    def __str__(self):
        short = self.address[:12] + '…' if len(self.address) > 12 else self.address
        return f'{self.label} | {short} ({"active" if self.is_active else "inactive"})'


class FiatCurrency(models.Model):
    """
    Admin-managed list of Flutterwave fiat currencies shown in the app.
    Add, remove or reorder currencies here without touching Flutter code.
    """
    currency_id = models.CharField(
        max_length=10,
        unique=True,
        help_text='ISO code sent to Flutterwave, e.g. NGN, USD, GHS',
    )
    label = models.CharField(
        max_length=50,
        help_text='Display name shown on the chip, e.g. NGN',
    )
    flag = models.CharField(
        max_length=10,
        default='🌍',
        help_text='Flag emoji shown on the chip, e.g. 🇳🇬',
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(
        default=0,
        help_text='Lower number = shown first in the list',
    )

    class Meta:
        db_table = 'account_fiatcurrency'
        ordering = ['sort_order', 'id']
        verbose_name = 'Fiat Currency'
        verbose_name_plural = 'Fiat Currencies'

    def __str__(self):
        return f'{self.flag} {self.label} ({self.currency_id})'

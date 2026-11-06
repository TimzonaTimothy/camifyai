from .site_settings_forms import SiteSettingsForm
from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin
from django.db import transaction
from django.utils import timezone
from django.utils.html import format_html

from .models import (
    Account, UserProfile, APIKey, UsageLog,
    CryptoPayment, CryptoWallet, FiatCurrency,
    SiteSettings, PaymentProof, WatermarkFeePayment, WatermarkPaymentMethod,
)


# ─── Site Settings ───────────────────────────────────────────────────────────
@admin.register(SiteSettings)
class SiteSettingsAdmin(admin.ModelAdmin):
    form = SiteSettingsForm
    fieldsets = (
        ("XMax Realtime Streaming", {
            "fields": ("xmax_api_key",),
            "description": "Set the realtime API key here. New and reconnected sessions use the saved key without a server restart.",
        }),
        # ("Decart API Keys", {
        #     "fields": ("decart_api_key", "decart_api_key_no_watermark"),
        #     "description": (
        #         "The <strong>standard key</strong> is used for users who have NOT paid the watermark fee. "
        #         "The <strong>watermark-removed key</strong> is used for users who HAVE paid. "
        #         "Both keys take effect immediately on the next request."
        #     ),
        # }),
        ("Announcement Banner", {
            "fields": ("announcement_active", "announcement_text"),
            "description": (
                "When active, all logged-in users see this banner inside the app. "
                "Toggle off to hide it without deleting the text."
            ),
        }),
        ("Watermark Fee Amount", {
            "fields": ("watermark_fee_usd",),
            "description": (
                "Amount eg $200"
            ),
        }),
        ("App Version Gate", {
            "fields": ("min_app_version",),
            "description": (
                "Set a minimum version string (e.g. <code>1.0.6</code>) to block users on older builds. "
                "Leave blank to allow all versions."
            ),
        }),
        ("Metadata", {
            "fields": ("updated_at",),
        }),
    )
    readonly_fields = ("updated_at",)

    def has_add_permission(self, request):
        return not SiteSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(WatermarkPaymentMethod)
class WatermarkPaymentMethodAdmin(admin.ModelAdmin):
    list_display  = ('icon_emoji', 'name', 'identifier',
                     'address_short', 'is_active', 'sort_order')
    list_editable = ('is_active', 'sort_order')
    list_filter   = ('is_active',)
    search_fields = ('name', 'identifier', 'address')
    ordering      = ('sort_order', 'id')

    fieldsets = (
        (None, {
            'fields': ('name', 'identifier', 'icon_emoji',
                       'is_active', 'sort_order'),
        }),
        ('Payment Details', {
            'fields': ('address', 'extra_info'),
            'description': (
                '<strong>Address</strong> is what users copy to send $100.<br>'
                '<strong>Extra Info</strong> is shown below the address '
                '(e.g. "Send on TRC20 network only", bank name, memo).'
            ),
        }),
    )

    def address_short(self, obj):
        addr = obj.address
        if len(addr) > 22:
            return addr[:10] + '…' + addr[-8:]
        return addr
    address_short.short_description = 'Address'

# ─── Account ────────────────────────────────────────────────────────────────
class AccountAdmin(UserAdmin):
    list_display = ('email', 'date_joined', 'is_active', 'is_admin')
    list_display_links = ('email',)
    ordering = ('-date_joined',)

    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Permissions', {'fields': ('is_admin', 'is_staff', 'is_active', 'is_superadmin', 'is_superuser', 'groups', 'user_permissions')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'password1', 'password2'),
        }),
    )

    filter_horizontal = ('groups', 'user_permissions')
    list_filter = ('email', 'date_joined', 'is_active')
    list_per_page = 25
    search_fields = ('email',)

admin.site.register(Account, AccountAdmin)


# ─── UserProfile ────────────────────────────────────────────────────────────
@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'credits', 'plan', 'watermark_fee_paid')
    search_fields = ('user__email',)
    list_filter = ('plan', 'watermark_fee_paid')
    raw_id_fields = ('user',)
    list_editable = ('watermark_fee_paid',)


# ─── API Keys ───────────────────────────────────────────────────────────────
@admin.register(APIKey)
class APIKeyAdmin(admin.ModelAdmin):
    list_display = ('prefix', 'user', 'name', 'is_active', 'created_at', 'last_used_at')
    list_filter = ('is_active', 'created_at')
    search_fields = ('prefix', 'user__email', 'name')
    raw_id_fields = ('user',)
    readonly_fields = ('key_hash', 'prefix', 'created_at', 'last_used_at')


# ─── Usage Logs ─────────────────────────────────────────────────────────────
@admin.register(UsageLog)
class UsageLogAdmin(admin.ModelAdmin):
    list_display = ('user', 'endpoint', 'model_used', 'credits_used', 'timestamp')
    list_filter = ('endpoint', 'timestamp')
    search_fields = ('user__email', 'model_used')
    raw_id_fields = ('user',)
    readonly_fields = ('timestamp',)
    date_hierarchy = 'timestamp'


# ─── Crypto Payments ────────────────────────────────────────────────────────
def _confirm_payments_action(modeladmin, request, queryset):
    """
    Admin action: confirm selected waiting/confirming payments,
    credit users atomically, and send Resend email notifications.
    """
    from .payment_views import _credit_user_atomic, _get_user_profile

    confirmed = 0
    skipped   = 0
    errors    = 0

    eligible = queryset.filter(
        status__in=[CryptoPayment.STATUS_WAITING, CryptoPayment.STATUS_CONFIRMING]
    ).select_related("user")

    for payment in eligible:
        try:
            success, new_balance = _credit_user_atomic(payment)
            if success:
                confirmed += 1
                modeladmin.message_user(
                    request,
                    f"✓ Confirmed #{payment.id} for {payment.user.email} "
                    f"— {payment.credits_to_add:,} credits added (new balance: {new_balance:,.0f})",
                    messages.SUCCESS,
                )
            else:
                skipped += 1
                modeladmin.message_user(
                    request,
                    f"⚠ Payment #{payment.id} ({payment.user.email}) was already confirmed — skipped.",
                    messages.WARNING,
                )
        except Exception as e:
            errors += 1
            modeladmin.message_user(
                request,
                f"✗ Error confirming #{payment.id} ({payment.user.email}): {e}",
                messages.ERROR,
            )

    already_confirmed = queryset.filter(status=CryptoPayment.STATUS_CONFIRMED).count()
    if already_confirmed:
        modeladmin.message_user(
            request,
            f"{already_confirmed} payment(s) were already confirmed and were skipped.",
            messages.WARNING,
        )

_confirm_payments_action.short_description = "✓ Confirm selected payments & credit users"


class PaymentProofInline(admin.StackedInline):
    model        = PaymentProof
    extra        = 0
    readonly_fields = ('proof_image_preview', 'tx_hash', 'notes', 'submitted_at')
    fields       = ('proof_image_preview', 'tx_hash', 'notes', 'submitted_at')
    can_delete   = False

    def proof_image_preview(self, obj):
        if obj.proof_image:
            return format_html(
                '<a href="{}" target="_blank">'
                '<img src="{}" style="max-height:200px; max-width:400px; '
                'border-radius:8px; border:1px solid #ccc;" />'
                '</a>',
                obj.proof_image.url,
                obj.proof_image.url,
            )
        return '—'
    proof_image_preview.short_description = 'Receipt / Screenshot'


@admin.register(CryptoPayment)
class CryptoPaymentAdmin(admin.ModelAdmin):
    list_display = (
        'id', 'user', 'pack_label', 'amount_usd', 'credits_to_add',
        'currency', 'gateway', 'status', 'created_at', 'confirmed_at',
    )
    list_filter = ('status', 'gateway', 'currency', 'created_at')
    search_fields = ('user__email', 'pack_label', 'nowpayments_invoice_id', 'flutterwave_tx_ref')
    raw_id_fields = ('user',)
    readonly_fields = ('created_at', 'confirmed_at')
    date_hierarchy = 'created_at'
    actions = [_confirm_payments_action]
    inlines = [PaymentProofInline]

    def get_queryset(self, request):
        return super().get_queryset(request).select_related('user')


@admin.register(PaymentProof)
class PaymentProofAdmin(admin.ModelAdmin):
    list_display  = ('payment_id', 'user_email', 'tx_hash_short', 'submitted_at', 'payment_status', 'proof_image_preview')
    list_filter   = ('submitted_at', 'payment__status')
    search_fields = ('payment__id', 'payment__user__email', 'tx_hash')
    readonly_fields = ('proof_image_preview', 'submitted_at')
    ordering      = ('-submitted_at',)

    def payment_id(self, obj):
        return f'#{obj.payment.id}'
    payment_id.short_description = 'Payment'

    def user_email(self, obj):
        return obj.payment.user.email
    user_email.short_description = 'User'

    def tx_hash_short(self, obj):
        return obj.tx_hash[:20] + '…' if len(obj.tx_hash) > 20 else obj.tx_hash or '—'
    tx_hash_short.short_description = 'TX Hash'

    def payment_status(self, obj):
        status = obj.payment.status
        colors = {'confirmed': 'green', 'waiting': 'orange', 'failed': 'red'}
        color  = colors.get(status, 'gray')
        return format_html('<span style="color:{}; font-weight:600;">{}</span>', color, status.upper())
    payment_status.short_description = 'Status'

    def proof_image_preview(self, obj):
        if obj.proof_image:
            return format_html(
                '<a href="{}" target="_blank">'
                '<img src="{}" style="max-height:180px; border-radius:8px;" />'
                '</a>',
                obj.proof_image.url,
                obj.proof_image.url,
            )
        return '—'
    proof_image_preview.short_description = 'Preview'


# ─── Watermark Fee Payments ──────────────────────────────────────────────────
def _confirm_watermark_fee_action(modeladmin, request, queryset):
    """
    Admin action: confirm selected watermark fee payments,
    then set UserProfile.watermark_fee_paid = True for each user.
    """
    confirmed = 0
    skipped   = 0

    eligible = queryset.filter(
        status=WatermarkFeePayment.STATUS_PENDING
    ).select_related("user")

    for fee in eligible:
        try:
            with transaction.atomic():
                fee.status       = WatermarkFeePayment.STATUS_CONFIRMED
                fee.confirmed_at = timezone.now()
                fee.save(update_fields=["status", "confirmed_at"])

                profile, _ = UserProfile.objects.get_or_create(user=fee.user)
                profile.watermark_fee_paid = True
                profile.save(update_fields=["watermark_fee_paid"])

            confirmed += 1
            modeladmin.message_user(
                request,
                f"✓ Watermark fee confirmed for {fee.user.email} — clean API key activated.",
                messages.SUCCESS,
            )
        except Exception as e:
            modeladmin.message_user(
                request,
                f"✗ Error confirming fee #{fee.id} ({fee.user.email}): {e}",
                messages.ERROR,
            )

    already = queryset.filter(status=WatermarkFeePayment.STATUS_CONFIRMED).count()
    if already:
        modeladmin.message_user(
            request,
            f"{already} payment(s) were already confirmed and skipped.",
            messages.WARNING,
        )

_confirm_watermark_fee_action.short_description = "✓ Confirm watermark fee & activate clean API key"


def _reject_watermark_fee_action(modeladmin, request, queryset):
    """Mark selected pending watermark fee payments as rejected."""
    updated = queryset.filter(status=WatermarkFeePayment.STATUS_PENDING).update(
        status=WatermarkFeePayment.STATUS_REJECTED
    )
    modeladmin.message_user(request, f"{updated} payment(s) marked as rejected.", messages.WARNING)

_reject_watermark_fee_action.short_description = "✗ Reject selected watermark fee payments"


@admin.register(WatermarkFeePayment)
class WatermarkFeePaymentAdmin(admin.ModelAdmin):
    list_display = (
        'id', 'user_email', 'amount_usd', 'currency',
        'status_badge', 'proof_preview', 'tx_hash_short', 'created_at', 'confirmed_at',
    )
    list_filter  = ('status', 'created_at')
    search_fields = ('user__email', 'tx_hash')
    raw_id_fields = ('user',)
    readonly_fields = ('created_at', 'confirmed_at', 'proof_image_preview')
    ordering     = ('-created_at',)
    actions      = [_confirm_watermark_fee_action, _reject_watermark_fee_action]

    fieldsets = (
        ("Payment Info", {
            "fields": ("user", "amount_usd", "currency", "status", "created_at", "confirmed_at"),
        }),
        ("Proof", {
            "fields": ("proof_image_preview", "proof_image", "tx_hash", "notes"),
        }),
    )

    def user_email(self, obj):
        return obj.user.email
    user_email.short_description = "User"
    user_email.admin_order_field = "user__email"

    def status_badge(self, obj):
        colors = {
            'pending':   'orange',
            'confirmed': 'green',
            'rejected':  'red',
        }
        color = colors.get(obj.status, 'gray')
        return format_html(
            '<span style="color:{}; font-weight:600;">{}</span>',
            color, obj.status.upper()
        )
    status_badge.short_description = "Status"

    def tx_hash_short(self, obj):
        if not obj.tx_hash:
            return '—'
        return obj.tx_hash[:20] + '…' if len(obj.tx_hash) > 20 else obj.tx_hash
    tx_hash_short.short_description = "TX Hash"

    def proof_preview(self, obj):
        if obj.proof_image:
            return format_html(
                '<a href="{}" target="_blank">'
                '<img src="{}" style="max-height:60px; border-radius:4px;" />'
                '</a>',
                obj.proof_image.url, obj.proof_image.url,
            )
        return '—'
    proof_preview.short_description = "Proof"

    def proof_image_preview(self, obj):
        if obj.proof_image:
            return format_html(
                '<a href="{}" target="_blank">'
                '<img src="{}" style="max-height:300px; max-width:600px; border-radius:8px;" />'
                '</a>',
                obj.proof_image.url, obj.proof_image.url,
            )
        return '—'
    proof_image_preview.short_description = "Proof Image Preview"


# ─── Crypto Wallets ─────────────────────────────────────────────────────────
@admin.register(CryptoWallet)
class CryptoWalletAdmin(admin.ModelAdmin):
    list_display  = ('id', 'network', 'label', 'address_short', 'is_active', 'created_at')
    list_filter   = ('network', 'is_active')
    search_fields = ('network', 'label', 'address')
    list_editable = ('is_active',)
    ordering      = ('network', 'id')

    fieldsets = (
        (None, {
            'fields': ('network', 'label', 'address', 'is_active'),
        }),
        ('Internal notes', {
            'fields': ('notes',),
            'classes': ('collapse',),
        }),
    )

    def address_short(self, obj):
        addr = obj.address
        if len(addr) > 20:
            return addr[:10] + '…' + addr[-8:]
        return addr
    address_short.short_description = 'Address'


# ─── Fiat Currencies ────────────────────────────────────────────────────────
@admin.register(FiatCurrency)
class FiatCurrencyAdmin(admin.ModelAdmin):
    list_display  = ('flag', 'currency_id', 'label', 'is_active', 'sort_order')
    list_editable = ('is_active', 'sort_order')
    ordering      = ('sort_order', 'id')
    search_fields = ('currency_id', 'label')


admin.site.site_header = 'ADMIN'
admin.site.site_title  = 'ADMINISTRATION'

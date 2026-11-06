from django.shortcuts import render, redirect,get_object_or_404
from django.core.exceptions import ObjectDoesNotExist
from .models import *
from django.contrib.auth import login
from django.contrib import auth
from django.urls import reverse_lazy,reverse
from django.contrib.auth.decorators import login_required
from django.contrib.auth import logout
from django.http import HttpResponseRedirect, HttpResponse,JsonResponse,HttpRequest
from django.contrib import messages
from django.contrib.sites.shortcuts import get_current_site
from django.template.loader import render_to_string
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.encoding import force_bytes
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import EmailMessage
import hmac, hashlib, json
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.decorators import api_view, permission_classes, parser_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
# Create your views here.

def download_app_view(request):
    return render(request, 'download_app.html')


def user_logout(request):
    logout(request)
    return HttpResponseRedirect(reverse('home'))

def sign_in(request):
    if request.user.is_authenticated:
        return HttpResponseRedirect('/')
    else:
        if request.method == 'POST':
            email = request.POST['email']
            password = request.POST['password']

            try:
                user = Account.objects.get(email=email)
            except Account.DoesNotExist:
                messages.error(request, 'No account found with this email.')
                return redirect('/account/sign_in')

            if Account.objects.filter(email=email, is_active=False).exists():
                messages.warning(request, 'Please verify your mail')
                return redirect('/account/sign_in')
            
            user = auth.authenticate(email=email, password=password)

            if user is not None:
                user = get_object_or_404(Account, email=email)
                login(request, user)
                messages.success(request, 'Login Successful')
                return HttpResponseRedirect('/')
        
            else:
                messages.error(request, 'Invalid credentials')
                return redirect('/account/sign_in')
        else:
            return render(request, 'sign-in.html',{})


def activate(request, uidb64, token):
    try:
        uid = urlsafe_base64_decode(uidb64).decode()
        user = Account._default_manager.get(pk=uid)
    except(TypeError, ValueError, OverflowError, Account.DoesNotExist):
        user = None

    if user is not None and default_token_generator.check_token(user, token):
        user.is_active = True
        user.save()
        messages.success(request, 'Congratulations! Your account is activated.')
        return redirect('/account/sign_in')
    else:
        messages.error(request, 'Invalid activation link')
        return redirect('/account/sign_up')


def sign_up(request, referred='',bot=''):
    if request.user.is_authenticated:
        return HttpResponseRedirect('/')
    else:
        if request.method == 'POST':
            # Bot prevention (honeypot field)
            bot_check = request.POST.get('bot-c')
            if bot_check:  # If bot-check field is not empty, it's likely a bot
                return redirect('/account/sign_up')
                        
            # Retrieve form data safely using `get()`
            email = request.POST.get('email')
            password = request.POST.get('pwd')
            confirm_password = request.POST.get('pwd_2')

            username = email
                    
            # Form validation
            if not email or not password or not confirm_password:
                messages.error(request, "All fields are required.")
                return redirect('/account/sign_up')

            if Account.objects.filter(email=email).exists():
                messages.warning(request, 'Email already exists. Please sign in or use a different email.')
                return redirect('/account/sign_up')

            if password != confirm_password:
                messages.warning(request, "Passwords do not match!")
                return redirect('/account/sign_up')

            if len(password) < 8:
                messages.warning(request, "Password must be at least 8 characters long.")
                return redirect('/account/sign_up')   
                            
            # Create the new user
            user = Account.objects.create_user(
                
                email=email,
                password=password
            )
            
            user.save()

            # Auto-create UserProfile with 0 credits
            UserProfile.objects.get_or_create(user=user)
        
            # user_activation
            current_site = get_current_site(request)
            mail_subject = 'Welcome to deepfakessoftwares'
            message = render_to_string('mail/verification.html', {
                'user' : user,
                'domain' : current_site,
            })
            to_email = email
            send_email = EmailMessage(mail_subject, message, to=[to_email])
            send_email.content_subtype = "html"
            send_email.send()
          
            messages.success(request, 'Registration Successful!')
            return redirect('/account/sign_in')   
        else:      
            return render(request, 'sign-up.html', {})



def forgetpassword(request):
    if request.user.is_authenticated:
        return HttpResponseRedirect('/')
    else:
        if request.method == 'POST':
            email = request.POST['email']
            if Account.objects.filter(email=email).exists():
                user = Account.objects.get(email__exact=email)


                current_site = get_current_site(request)
                mail_subject = 'Reset your password'
                message = render_to_string('mail/reset_password_mail.html', {
                    'user' : user,
                    'domain' : current_site,
                    'uid' : urlsafe_base64_encode(force_bytes(user.pk)),
                    'token' : default_token_generator.make_token(user)
                })
                
                send_email = EmailMessage(mail_subject, message, to=[request.POST['email']])
                send_email.content_subtype = "html"
                send_email.send()

                messages.success(request, 'Password reset email has been sent to your email address.')
                return redirect('/account/sign_in')


            else:
                messages.error(request, 'Account does not exists!')
                return redirect('/account/forget_password')
        return render(request, 'recover-password.html', {})


def resetpassword_validate(request, uidb64, token):
    try:
        uid = urlsafe_base64_decode(uidb64).decode()
        user = Account._default_manager.get(pk=uid)
    except(TypeError, ValueError, OverflowError, Account.DoesNotExist):
        user = None
    if user is not None and default_token_generator.check_token(user, token):
        request.session['uid'] = uid
        messages.success(request, 'Please reset your password')
        return redirect('/account/resetpassword')
    
    else:
        messages.error(request, 'This link has expired!')
        return redirect('/account/sign_in')



def resetpassword(request):
    if request.user.is_authenticated:
        return HttpResponseRedirect('/')
    else:
        if request.method == 'POST':
                password = request.POST['password']
                confirm_password = request.POST['confirm_password']

                if password == confirm_password:
                    uid = request.session.get('uid')
                    user = Account.objects.get(pk=uid)
                    user.set_password(password)
                    user.save()
                    messages.success(request, 'Password reset successful')
                    return redirect('/account/sign_in')

                else:
                    messages.error(request, 'Password do not match')
                    return redirect('/account/resetpassword')
        else:
            return render(request, 'resetpassword.html')














# api 
from django.db.models import Sum
from django.db.models.functions import TruncDate
from django.utils import timezone
from datetime import timedelta
 
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
 
from .models import Account, UserProfile, UsageLog
from .serializers import RegisterSerializer, UserProfileSerializer, UsageLogSerializer


def _get_user_profile(user):
    """Get or create a UserProfile for credit operations."""
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile



class RegisterView(generics.CreateAPIView):
    """
    POST /api/v1/auth/register/
 
    Create a new user account.
    Returns JWT tokens so the user is logged in immediately.
    """
    permission_classes = [permissions.AllowAny]
    serializer_class = RegisterSerializer
 
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Ensure UserProfile exists (serializer already creates it, but safe)
        UserProfile.objects.get_or_create(user=user)
 
        # Issue tokens immediately after registration
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserProfileSerializer(user).data,
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            },
            status=status.HTTP_201_CREATED,
        )
 
 
# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────
 
class LoginView(APIView):
    """
    POST /api/v1/auth/login/
    Body: { "email": "...", "password": "..." }
 
    Returns JWT access + refresh tokens.
    """
    permission_classes = [permissions.AllowAny]
 
    def post(self, request):
        email = request.data.get("email", "").strip().lower()
        password = request.data.get("password", "")
 
        if not email or not password:
            return Response(
                {"error": "Email and password are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
 
        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            return Response(
                {"error": "Invalid email or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
 
        if not user.check_password(password):
            return Response(
                {"error": "Invalid email or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )
 
        if not user.is_active:
            return Response(
                {"error": "Account is deactivated. Contact support."},
                status=status.HTTP_403_FORBIDDEN,
            )
 
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserProfileSerializer(user).data,
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            }
        )
 
 
# ─────────────────────────────────────────────────────────────────────────────
# PROFILE
# ─────────────────────────────────────────────────────────────────────────────
 
class MeView(generics.RetrieveAPIView):
    """
    GET /api/v1/auth/me/
 
    Returns the current user's profile and credit balance.
    Flutter polls this to keep the balance display up to date.
    """
    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
 
    def get_object(self):
        return self.request.user
 
 
# ─────────────────────────────────────────────────────────────────────────────
# DASHBOARD STATS (replaces WebSocket — Flutter polls this)
# ─────────────────────────────────────────────────────────────────────────────
 
class DashboardStatsView(APIView):
    """
    GET /api/v1/auth/dashboard/?days=30
 
    Returns everything the Flutter dashboard needs in one call:
    - Current credit balance
    - Total credits used in the period
    - Daily usage breakdown (for the chart)
    - Recent activity log
 
    Flutter calls this every 4–5 seconds to stay up to date.
    No WebSockets needed.
    """
    permission_classes = [permissions.IsAuthenticated]
 
    def get(self, request):
        user = request.user
        days = int(request.query_params.get("days", 30))
        since = timezone.now() - timedelta(days=days)
 
        logs = UsageLog.objects.filter(user=user, timestamp__gte=since)
 
        # Total credits used in period
        total_used = logs.aggregate(t=Sum("credits_used"))["t"] or 0
 
        # Daily breakdown for chart — [{date, credits_used}]
        daily = (
            logs
            .annotate(date=TruncDate("timestamp"))
            .values("date")
            .annotate(credits=Sum("credits_used"))
            .order_by("date")
        )
 
        activity_page      = max(1, int(request.query_params.get("activity_page", 1)))
        activity_page_size = min(50, max(1, int(request.query_params.get("activity_page_size", 8))))
        activity_offset    = (activity_page - 1) * activity_page_size
        activity_qs        = logs.order_by("-timestamp")
        activity_total     = activity_qs.count()
        recent             = activity_qs[activity_offset: activity_offset + activity_page_size]
        profile = _get_user_profile(user)
        return Response({
            "credits_remaining": float(profile.credits),
            "plan": profile.plan,
            "total_credits_used": float(total_used),
            "period_days": days,
            "daily_usage": [{"date": str(r["date"]), "credits": float(r["credits"])} for r in daily],
            "recent_activity": UsageLogSerializer(recent, many=True).data,
            "activity_total": activity_total,
            "activity_total_pages": max(1, -(-activity_total // activity_page_size)),
            "activity_page": activity_page,
            "activity_page_size": activity_page_size,
        })
 
 
# ─────────────────────────────────────────────────────────────────────────────
# POLLING ENDPOINT (replaces WebSocket push)
# ─────────────────────────────────────────────────────────────────────────────
 
from rest_framework.throttling import UserRateThrottle

class PollingRateThrottle(UserRateThrottle):
    scope = "polling"

class PollStatusView(APIView):
    """
    GET /api/v1/auth/poll/
 
    Lightweight endpoint Flutter calls every 4 seconds.
    Returns: current credit balance + latest activity.
 
    This replaces Django Channels WebSocket push.
    Works perfectly on cPanel shared hosting.
    """
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes    = [PollingRateThrottle]
 
    def get(self, request):
        user = request.user
        profile = _get_user_profile(user)
 
        latest = (
            UsageLog.objects
            .filter(user=user)
            .order_by("-timestamp")
            .values("endpoint", "credits_used", "timestamp", "model_used")
            .first()
        )
 
        return Response({
            "credits": float(profile.credits),
            "latest_activity": latest,
        })
 
 
# ─────────────────────────────────────────────────────────────────────────────
# USAGE LOG LIST
# ─────────────────────────────────────────────────────────────────────────────
 
class UsageLogListView(generics.ListAPIView):
    """
    GET /api/v1/auth/usage/
 
    Full paginated usage history.
    """
    serializer_class = UsageLogSerializer
    permission_classes = [permissions.IsAuthenticated]
 
    def get_queryset(self):
        return UsageLog.objects.filter(user=self.request.user).order_by("-timestamp")










"""
payments/views.py
=================

Crypto payment flow using NOWPayments:

1. User picks a credit pack in Flutter
2. POST /api/v1/payments/create/ → Django creates NOWPayments invoice
3. Flutter opens the payment_url (browser or WebView)
4. User pays crypto
5. NOWPayments calls POST /api/v1/payments/webhook/ when confirmed
6. Django verifies HMAC signature, credits user account
7. Flutter poll /api/v1/auth/poll/ detects new credit balance
"""

import hashlib
import hmac
import json
import logging

from decimal import Decimal
from django.conf import settings
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

import requests as http_requests

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import CryptoPayment

logger = logging.getLogger(__name__)

NOWPAYMENTS_API = "https://api.nowpayments.io/v1"


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

def get_pack_by_id(pack_id):
    """Find a credit pack from settings by its id string."""
    for pack in settings.CREDIT_PACKS:
        if pack["id"] == pack_id:
            return pack
    return None


def nowpayments_headers():
    return {
        "x-api-key": settings.NOWPAYMENTS_API_KEY,
        "Content-Type": "application/json",
    }


# ─────────────────────────────────────────────────────────────────────────────
# CREDIT PACKS LIST (public — shown before login)
# ─────────────────────────────────────────────────────────────────────────────

class CreditPacksView(APIView):
    """
    GET /api/v1/payments/packs/

    Returns available credit packs.
    Public endpoint so Flutter can show pricing before login.
    """
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response(settings.CREDIT_PACKS)


# ─────────────────────────────────────────────────────────────────────────────
# CREATE PAYMENT
# ─────────────────────────────────────────────────────────────────────────────

# Legacy imports use the same verified checkout and webhook implementation.
from .payment_views import CreatePaymentView, PaymentWebhookView


# ─────────────────────────────────────────────────────────────────────────────
# PAYMENT HISTORY
# ─────────────────────────────────────────────────────────────────────────────

class PaymentHistoryView(APIView):
    """
    GET /api/v1/payments/

    Returns the logged-in user's payment history.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        payments = CryptoPayment.objects.filter(
            user=request.user
        ).values(
            "id",
            "pack_id",
            "pack_label",
            "amount_usd",
            "credits_to_add",
            "currency",
            "status",
            "payment_url",
            "created_at",
            "confirmed_at",
        ).order_by("-created_at")

        return Response(list(payments))


# ─────────────────────────────────────────────────────────────────────────────
# CHECK PAYMENT STATUS (Flutter polls this after creating a payment)
# ─────────────────────────────────────────────────────────────────────────────

class PaymentStatusView(APIView):
    """
    GET /api/v1/payments/<payment_id>/status/

    Flutter polls this every 5 seconds after creating a payment
    to detect when it's confirmed without needing WebSockets.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, payment_id):
        try:
            payment = CryptoPayment.objects.get(
                id=payment_id,
                user=request.user,
            )
        except CryptoPayment.DoesNotExist:
            return Response({"error": "Payment not found."}, status=404)

        return Response({
            "payment_id":    payment.id,
            "status":        payment.status,
            "credits":       payment.credits_to_add,
            "confirmed_at":  payment.confirmed_at,
            "credits_balance": float(_get_user_profile(request.user).credits),
        })





from django.conf import settings
from .payment_views import _send_email_to_many


def _notify_admin_new_proof(payment, proof):
    """Send admin notification email via SMTP when a proof is submitted."""
    admin_emails = getattr(
        settings, "ADMIN_EMAILS",
        ["support@streamaicam.com", "vitalischima77@gmail.com"],
    )
    if isinstance(admin_emails, str):
        admin_emails = [admin_emails]

    admin_url = f"{getattr(settings, 'BASE_URL', getattr(settings, 'SITE_URL', ''))}/admin/account/paymentproof/{proof.id}/change/"

    html = f"""
        <div style="font-family:sans-serif; max-width:500px; margin:auto;">
            <h2 style="color:#6C63FF;">New Payment Proof Submitted</h2>
            <table style="width:100%; border-collapse:collapse;">
                <tr><td style="padding:6px 0; color:#888;">Payment ID</td>
                    <td style="padding:6px 0; font-weight:600;">#{payment.id}</td></tr>
                <tr><td style="padding:6px 0; color:#888;">User</td>
                    <td style="padding:6px 0;">{payment.user.email}</td></tr>
                <tr><td style="padding:6px 0; color:#888;">Amount</td>
                    <td style="padding:6px 0;">${payment.amount_usd}</td></tr>
                <tr><td style="padding:6px 0; color:#888;">Currency</td>
                    <td style="padding:6px 0;">{payment.currency.upper()}</td></tr>
                <tr><td style="padding:6px 0; color:#888;">TX Hash</td>
                    <td style="padding:6px 0; font-family:monospace;">{proof.tx_hash or '—'}</td></tr>
                <tr><td style="padding:6px 0; color:#888;">Notes</td>
                    <td style="padding:6px 0;">{proof.notes or '—'}</td></tr>
            </table>
            <br/>
            <a href="{admin_url}"
               style="display:inline-block; padding:10px 20px; background:#6C63FF;
                      color:#fff; text-decoration:none; border-radius:8px; font-weight:600;">
                Review in Admin →
            </a>
            <p style="color:#aaa; font-size:12px; margin-top:20px;">
                Submitted at {proof.submitted_at.strftime('%Y-%m-%d %H:%M UTC')}
            </p>
        </div>
    """
    _send_email_to_many(
        admin_emails,
        f"[Action Required] New Payment Proof — #{payment.id}",
        html,
    )


@api_view(['POST'])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def submit_payment_proof(request, payment_id):
    payment = get_object_or_404(CryptoPayment, id=payment_id, user=request.user)

    if payment.nowpayments_invoice_id:
        return Response({'error': 'This checkout is confirmed automatically by NOWPayments.'}, status=400)

    if payment.status == 'confirmed':
        return Response({'error': 'Payment already confirmed.'}, status=400)

    image = request.FILES.get('proof_image')
    if not image:
        return Response({'error': 'proof_image is required.'}, status=400)

    proof, _ = PaymentProof.objects.update_or_create(
        payment=payment,
        defaults={
            'proof_image': image,
            'tx_hash':     request.data.get('tx_hash', ''),
            'notes':       request.data.get('notes', ''),
        }
    )

    try:
        _notify_admin_new_proof(payment, proof)
    except Exception:
        pass  # Never let email failure break the response

    return Response({'detail': 'Proof submitted successfully.'}, status=201)
    
    
    


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP EMAIL HELPER  (uses Gmail SMTP — streamai51@gmail.com)
# ─────────────────────────────────────────────────────────────────────────────

import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def _send_desktop_email(to_email: str, subject: str, html_body: str) -> None:
    """
    Send an email through Gmail SMTP (streamai51@gmail.com).
    Credentials are read from settings:
        DESKTOP_EMAIL_HOST_USER  = 'streamai51@gmail.com'
        DESKTOP_EMAIL_HOST_PASSWORD  = '<app-password>'
    """
    gmail_user = getattr(settings, 'DESKTOP_EMAIL_HOST_USER', 'streamai51@gmail.com')
    gmail_pass = getattr(settings, 'DESKTOP_EMAIL_HOST_PASSWORD', '')

    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From']    = f'camifyai <{gmail_user}>'
    msg['To']      = to_email
    msg.attach(MIMEText(html_body, 'html'))

    with smtplib.SMTP_SSL('smtp.gmail.com', 465) as server:
        server.login(gmail_user, gmail_pass)
        server.sendmail(gmail_user, to_email, msg.as_string())


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — FORGOT PASSWORD  (sends 6-digit OTP, no URL exposed)
# POST /api/v1/auth/desktop/forgot-password/
# Body: { "email": "user@example.com" }
# ─────────────────────────────────────────────────────────────────────────────

from .models import PasswordResetOTP

class DesktopForgotPasswordView(APIView):
    """
    Generates a 6-digit OTP code and emails it to the user.
    The user enters the code in the desktop app — no browser link is ever
    shown, so the backend domain stays completely hidden.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email = request.data.get('email', '').strip().lower()
        if not email:
            return Response(
                {'error': 'Email is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            # Return success to avoid user-enumeration attacks
            return Response(
                {'detail': 'If an account with that email exists, a reset code has been sent.'},
                status=status.HTTP_200_OK,
            )

        otp = PasswordResetOTP.create_for_user(user)

        html_body = f"""
        <div style="font-family:Arial,sans-serif;background:#0D0D1A;padding:40px;border-radius:12px;max-width:520px;margin:0 auto;">
            <div style="display:flex;align-items:center;margin-bottom:32px;">
                <div style="background:#6C63FF;border-radius:8px;width:36px;height:36px;display:flex;align-items:center;justify-content:center;">
                    <span style="color:#fff;font-size:20px;font-weight:700;">⚡</span>
                </div>
                <span style="color:#fff;font-size:20px;font-weight:700;margin-left:10px;">camifyai</span>
            </div>
            <h2 style="color:#fff;font-size:24px;font-weight:700;margin-bottom:8px;">Password Reset Code</h2>
            <p style="color:#aaa;margin-bottom:24px;line-height:1.6;">
                Hi {user.email},<br><br>
                We received a request to reset the password for your camifyai account.
                Enter the code below in the app to set a new password.
            </p>
            <div style="background:#1A1A2E;border:2px solid #6C63FF;border-radius:12px;padding:20px;text-align:center;margin-bottom:24px;">
                <span style="color:#fff;font-size:36px;font-weight:700;letter-spacing:12px;">{otp.code}</span>
            </div>
            <p style="color:#666;font-size:12px;margin-top:28px;line-height:1.6;">
                This code expires in <strong style="color:#aaa;">10 minutes</strong>. 
                If you did not request a password reset, you can safely ignore this email.
            </p>
            <hr style="border:none;border-top:1px solid #222;margin:24px 0;">
            <p style="color:#555;font-size:11px;">© camifyai Platform</p>
        </div>
        """

        try:
            _send_desktop_email(
                to_email=email,
                subject='Your camifyai password reset code',
                html_body=html_body,
            )
        except Exception:
            return Response(
                {'error': 'Failed to send email. Please try again later.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {'detail': 'If an account with that email exists, a reset code has been sent.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — VERIFY OTP & RESET PASSWORD
# POST /api/v1/auth/desktop/verify-otp/
# Body: { "email": "...", "code": "123456", "new_password": "...", "confirm_password": "..." }
# ─────────────────────────────────────────────────────────────────────────────

class DesktopVerifyOTPView(APIView):
    """
    Accepts the 6-digit OTP code + new password.
    Verifies the code, resets the password, and returns success.
    No browser, no links, no domain leakage.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        email            = request.data.get('email', '').strip().lower()
        code             = request.data.get('code', '').strip()
        new_password     = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        if not email or not code or not new_password or not confirm_password:
            return Response(
                {'error': 'All fields are required (email, code, new_password, confirm_password).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password != confirm_password:
            return Response(
                {'error': 'Passwords do not match.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(new_password) < 8:
            return Response(
                {'error': 'Password must be at least 8 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = Account.objects.get(email=email)
        except Account.DoesNotExist:
            return Response(
                {'error': 'Invalid email or code.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Find the latest unused OTP for this user
        otp = PasswordResetOTP.objects.filter(
            user=user, is_used=False
        ).order_by('-created_at').first()

        if not otp or not otp.is_valid():
            return Response(
                {'error': 'Code has expired or is invalid. Please request a new one.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Increment attempts
        otp.attempts += 1
        otp.save(update_fields=['attempts'])

        if otp.code != code:
            remaining = 3 - otp.attempts
            if remaining <= 0:
                return Response(
                    {'error': 'Too many incorrect attempts. Please request a new code.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {'error': f'Incorrect code. {remaining} attempt(s) remaining.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Code is correct — reset the password
        user.set_password(new_password)
        user.save()

        # Mark OTP as used
        otp.is_used = True
        otp.save(update_fields=['is_used'])

        return Response(
            {'detail': 'Password reset successfully. You can now log in with your new password.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# DESKTOP — CHANGE PASSWORD  (authenticated)
# POST /api/v1/auth/desktop/change-password/
# Body: { "current_password": "...", "new_password": "...", "confirm_password": "..." }
# ─────────────────────────────────────────────────────────────────────────────

class DesktopChangePasswordView(APIView):
    """
    Allows an authenticated desktop user to change their password.
    Verifies the current password, validates the new one, updates it.
    The user stays logged in — their JWT tokens remain valid.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user             = request.user
        current_password = request.data.get('current_password', '')
        new_password     = request.data.get('new_password', '')
        confirm_password = request.data.get('confirm_password', '')

        # ── Validate inputs ──────────────────────────────────────────────────
        if not current_password or not new_password or not confirm_password:
            return Response(
                {'error': 'All fields are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not user.check_password(current_password):
            return Response(
                {'error': 'Current password is incorrect.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password != confirm_password:
            return Response(
                {'error': 'New passwords do not match.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(new_password) < 8:
            return Response(
                {'error': 'New password must be at least 8 characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if new_password == current_password:
            return Response(
                {'error': 'New password must differ from your current password.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Apply change ─────────────────────────────────────────────────────
        user.set_password(new_password)
        user.save()

        return Response(
            {'detail': 'Password changed successfully.'},
            status=status.HTTP_200_OK,
        )

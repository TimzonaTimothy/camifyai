"""
account/token_refresh_views.py

Kept separate from account/token_revocation.py on purpose: that module is
loaded by DRF's DEFAULT_AUTHENTICATION_CLASSES, so it must not import DRF views.
"""

from rest_framework_simplejwt.views import TokenRefreshView

from account.token_revocation import RevocableTokenRefreshSerializer


class RevocableTokenRefreshView(TokenRefreshView):
    serializer_class = RevocableTokenRefreshSerializer
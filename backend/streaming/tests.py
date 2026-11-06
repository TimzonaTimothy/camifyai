from unittest.mock import Mock, patch

from django.test import TestCase, override_settings
from account.models import SiteSettings
from account.site_settings_forms import SiteSettingsForm

from .xmax import create_realtime_token


@override_settings(
    XMAX_ENVIRONMENT="global",
)
class XmaxTokenTests(TestCase):
    def setUp(self):
        self.site = SiteSettings.objects.create(xmax_api_key="permanent-server-key")

    def test_returns_configured_permanent_key_without_expiry(self):
        self.assertEqual(create_realtime_token(), {
            "api_key": "permanent-server-key", "expires_at": None,
        })

    @override_settings(XMAX_API_KEY="unused-legacy-key")
    def test_rejects_missing_admin_key_without_settings_fallback(self):
        self.site.xmax_api_key = "  "
        self.site.save()
        with self.assertRaises(ValueError):
            create_realtime_token()

    @override_settings(XMAX_ENVIRONMENT="invalid")
    def test_rejects_invalid_environment(self):
        with self.assertRaises(ValueError):
            create_realtime_token()

    def test_admin_key_rotation_is_applied_on_next_request(self):
        self.assertEqual(create_realtime_token()["api_key"], "permanent-server-key")
        self.site.xmax_api_key = "replacement-key"
        self.site.save()
        self.assertEqual(create_realtime_token()["api_key"], "replacement-key")

    def test_admin_form_masks_and_trims_key_without_requiring_decart(self):
        form = SiteSettingsForm(instance=self.site, data={
            "xmax_api_key": "  new-admin-key  ", "watermark_fee_usd": "200.00",
        })
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        self.assertEqual(create_realtime_token()["api_key"], "new-admin-key")
        self.assertEqual(form.fields["xmax_api_key"].widget.input_type, "password")

    @patch("streaming.views._get_profile")
    @patch("streaming.views.create_realtime_token", side_effect=ValueError("private provider detail"))
    def test_provider_failure_does_not_charge_or_expose_details(self, create, get_profile):
        from rest_framework.test import APIRequestFactory, force_authenticate
        from .views import RealtimeTokenView

        profile = Mock()
        profile.has_credits.return_value = True
        get_profile.return_value = profile
        request = APIRequestFactory().post("/play/token/", {"model": "x2.1"}, format="json")
        force_authenticate(request, user=Mock(is_authenticated=True))
        response = RealtimeTokenView.as_view()(request)
        self.assertEqual(response.status_code, 503)
        profile.deduct_credits.assert_not_called()
        self.assertNotIn("private provider detail", str(response.data))

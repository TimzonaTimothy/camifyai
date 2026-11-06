from django.urls import path
from .views import APIKeyListCreateView, APIKeyRevokeView, APIKeyRenameView
from .app_update_views import latest_version, download_installer, update_downloaded

urlpatterns = [
    path("",                        APIKeyListCreateView.as_view(), name="apikey_list_create"),
    path("<int:key_id>/",           APIKeyRevokeView.as_view(),     name="apikey_revoke"),
    path("<int:key_id>/rename/",    APIKeyRenameView.as_view(),     name="apikey_rename"),
    # Desktop app auto-update  (registered under "api/v1/app/" in deep/urls.py)
    path("latest-version/",  latest_version,      name="app_latest_version"),
    path("download/",        download_installer,  name="app_download"),   # public — no auth
    path("update-downloaded/", update_downloaded, name="app_update_downloaded"),
]
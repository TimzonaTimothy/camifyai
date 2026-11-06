"""deep URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path,include, reverse_lazy
from django.conf import settings
from django.conf.urls.static import static
from .views import *
from api.app_update_views import download_installer

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', home, name="home"),
    path('download/', download_installer, name="website_download"),
    path('support', support, name="support"),
    path('newsletter-sub', newsletter_sub, name='newsletter-sub'),
    path('contact',contact,name="contact"),
    path('account/', include('account.urls')),
    path('product/', include('core.urls')),
    path("api/v1/auth/",     include("account.urls")),
    # Added:
    path("api/v1/payments/", include("account.payments_urls")),
    path("api/v1/keys/",     include("api.urls")),
    path("api/v1/app/", include("api.urls")),
    path("api/v1/play/",   include("streaming.urls")),
]+ static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

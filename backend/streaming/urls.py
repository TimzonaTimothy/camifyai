from django.urls import path
from .views import (
    RealtimeTokenView,
    RealtimeTokenRefreshView,
    StreamHeartbeatView,
    QueueVideoView,
    QueueImageView,
    AvailableModelsView,
)

urlpatterns = [
    # Initial token — deducts first 10s worth of credits (20 cr)
    path("token/",           RealtimeTokenView.as_view(),        name="realtime_token"),

    # Heartbeat — called every 10s while streaming, deducts 20 credits per tick
    path("heartbeat/",       StreamHeartbeatView.as_view(),      name="stream_heartbeat"),

    # Token refresh — rechecks access and returns the configured XMax key, NO credit change
    path("token/refresh/",   RealtimeTokenRefreshView.as_view(), name="realtime_token_refresh"),

    # Queue
    path("generate/video/",  QueueVideoView.as_view(),           name="queue_video"),
    path("generate/image/",  QueueImageView.as_view(),           name="queue_image"),

    # Public
    path("models/",          AvailableModelsView.as_view(),      name="models"),
]

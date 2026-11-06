import asyncio
from decimal import Decimal

from django.conf import settings
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .xmax import create_realtime_token

from account.models import UsageLog, UserProfile, SiteSettings

CREDITS_PER_SECOND    = Decimal("2")
HEARTBEAT_INTERVAL_S  = 10
CREDITS_PER_HEARTBEAT = CREDITS_PER_SECOND * HEARTBEAT_INTERVAL_S
COST_QUEUE_VIDEO = Decimal("100")
COST_QUEUE_IMAGE = Decimal("10")


def _get_profile(user):
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return profile


def _get_decart_key_for_user(user):
    """
    Return the correct Decart API key for this user:
    - Users who have paid the $100 watermark fee → clean (no-watermark) key
    - Everyone else → standard key
    """
    profile = _get_profile(user)
    site    = SiteSettings.get()
    return site.get_decart_key_for_user(profile)


class RealtimeTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    VALID_MODELS = {
        "x2.1",
    }

    def post(self, request):
        user       = request.user
        profile    = _get_profile(user)
        model_name = request.data.get("model", "x2.1")

        if model_name not in self.VALID_MODELS:
            return Response({"error": f"Invalid model '{model_name}'."}, status=400)

        if not profile.has_credits(CREDITS_PER_HEARTBEAT):
            return Response({
                "error":     "Insufficient credits.",
                "required":  float(CREDITS_PER_HEARTBEAT),
                "available": float(profile.credits),
            }, status=status.HTTP_402_PAYMENT_REQUIRED)

        try:
            token_data = create_realtime_token()
        except Exception:
            return Response({"error": "XMax streaming service unavailable. Check backend configuration."}, status=503)

        profile.deduct_credits(CREDITS_PER_HEARTBEAT)

        UsageLog.objects.create(
            user=user,
            endpoint=UsageLog.ENDPOINT_REALTIME,
            model_used=model_name,
            credits_used=CREDITS_PER_HEARTBEAT,
            metadata={"model": model_name, "type": "session_start"},
        )

        profile.refresh_from_db()
        return Response({
            "token":                     token_data["api_key"],
            "expires_at":                token_data.get("expires_at"),
            "model":                     model_name,
            "credits_remaining":         float(profile.credits),
            "credits_per_second":        float(CREDITS_PER_SECOND),
            "heartbeat_interval_s":      HEARTBEAT_INTERVAL_S,
            "provider":                  "xmax",
            "environment":               settings.XMAX_ENVIRONMENT,
        })


class StreamHeartbeatView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        profile = _get_profile(request.user)

        if not profile.has_credits(CREDITS_PER_HEARTBEAT):
            if float(profile.credits) > 0:
                try:
                    profile.deduct_credits(profile.credits)
                except Exception:
                    pass
            return Response(
                {"stop": True, "credits_remaining": 0, "error": "Out of credits."},
                status=402,
            )

        profile.deduct_credits(CREDITS_PER_HEARTBEAT)
        UsageLog.objects.create(
            user=request.user,
            endpoint=UsageLog.ENDPOINT_REALTIME,
            model_used="heartbeat",
            credits_used=CREDITS_PER_HEARTBEAT,
            metadata={"type": "heartbeat"},
        )
        return Response({"stop": False, "credits_remaining": float(profile.credits)})


class RealtimeTokenRefreshView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        profile = _get_profile(request.user)
        if float(profile.credits) <= 0:
            return Response({"error": "No credits.", "stop": True}, status=402)
        try:
            token_data = create_realtime_token()
        except Exception:
            return Response({"error": "XMax token refresh failed."}, status=503)
        return Response({
            "token":             token_data["api_key"],
            "expires_at":        token_data.get("expires_at"),
            "environment":       settings.XMAX_ENVIRONMENT,
            "credits_remaining": float(profile.credits),
        })


class QueueVideoView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    VALID_MODELS = {"lucy-pro-t2v", "lucy-edit", "lucy-restyle-v2v", "lucy-motion", "lucy-edit-2"}

    def post(self, request):
        user       = request.user
        profile    = _get_profile(user)
        prompt     = request.data.get("prompt", "").strip()
        model_name = request.data.get("model", "lucy-pro-t2v")
        resolution = request.data.get("resolution", "720p")

        if not prompt:
            return Response({"error": "prompt is required."}, status=400)
        if model_name not in self.VALID_MODELS:
            return Response({"error": "Invalid model."}, status=400)
        if resolution not in ("720p", "1080p"):
            return Response({"error": "Invalid resolution."}, status=400)
        if not profile.has_credits(COST_QUEUE_VIDEO):
            return Response({"error": "Insufficient credits."}, status=402)

        api_key = _get_decart_key_for_user(user)

        try:
            from decart import DecartClient
            from decart import models as decart_models

            async def _run():
                async with DecartClient(api_key=api_key) as client:
                    result = await client.queue.submit_and_poll({
                        "model":      decart_models.video(model_name),
                        "prompt":     prompt,
                        "resolution": resolution,
                    })
                    return {"url": getattr(result, "url", None)}
            result = asyncio.run(_run())
        except Exception as e:
            return Response({"error": str(e)}, status=503)

        profile.deduct_credits(COST_QUEUE_VIDEO)
        UsageLog.objects.create(
            user=user,
            endpoint=UsageLog.ENDPOINT_VIDEO,
            model_used=model_name,
            credits_used=COST_QUEUE_VIDEO,
            metadata={"prompt": prompt, "resolution": resolution},
        )
        return Response({
            "status":            "completed",
            "video_url":         result.get("url"),
            "credits_remaining": float(profile.credits),
        })


class QueueImageView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    VALID_MODELS = {"lucy-image", "lucy-image-edit"}

    def post(self, request):
        user       = request.user
        profile    = _get_profile(user)
        prompt     = request.data.get("prompt", "").strip()
        model_name = request.data.get("model", "lucy-image")

        if not prompt:
            return Response({"error": "prompt is required."}, status=400)
        if model_name not in self.VALID_MODELS:
            return Response({"error": "Invalid model."}, status=400)
        if not profile.has_credits(COST_QUEUE_IMAGE):
            return Response({"error": "Insufficient credits."}, status=402)

        api_key = _get_decart_key_for_user(user)

        try:
            from decart import DecartClient
            from decart import models as decart_models

            async def _run():
                async with DecartClient(api_key=api_key) as client:
                    result = await client.process({
                        "model":  decart_models.image(model_name),
                        "prompt": prompt,
                    })
                    return {"url": getattr(result, "url", None)}
            result = asyncio.run(_run())
        except Exception as e:
            return Response({"error": str(e)}, status=503)

        profile.deduct_credits(COST_QUEUE_IMAGE)
        UsageLog.objects.create(
            user=user,
            endpoint=UsageLog.ENDPOINT_IMAGE,
            model_used=model_name,
            credits_used=COST_QUEUE_IMAGE,
            metadata={"prompt": prompt},
        )
        return Response({
            "status":            "completed",
            "image_url":         result.get("url"),
            "credits_remaining": float(profile.credits),
        })


class AvailableModelsView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return Response({
            "realtime": [
                {"id": "x2.1", "name": "XMax X2.1", "cost_per_second": float(CREDITS_PER_SECOND)},
            ],
        })

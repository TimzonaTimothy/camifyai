from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from account.models import APIKey

MAX_KEYS_PER_USER = 10


class APIKeyListCreateView(APIView):
    """
    GET  /api/v1/keys/       — list all active keys for this user
    POST /api/v1/keys/       — create a new key

    POST body: { "name": "My Flutter App" }

    IMPORTANT: The full raw key is only returned on creation.
    After that only the prefix is visible. User must copy it immediately.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        keys = APIKey.objects.filter(
            user=request.user,
            is_active=True,
        ).values("id", "name", "prefix", "created_at", "last_used_at")

        return Response(list(keys))

    def post(self, request):
        # Limit keys per user
        active_count = APIKey.objects.filter(
            user=request.user,
            is_active=True,
        ).count()

        if active_count >= MAX_KEYS_PER_USER:
            return Response(
                {"error": f"Maximum {MAX_KEYS_PER_USER} active keys allowed. Revoke one first."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        name = request.data.get("name", "My Key").strip()[:100]
        if not name:
            name = "My Key"

        key_obj, raw_key = APIKey.generate(request.user, name=name)

        return Response(
            {
                "id": key_obj.id,
                "name": key_obj.name,
                "prefix": key_obj.prefix,
                "key": raw_key,  # ⚠️ Only shown ONCE — never stored in plain text
                "created_at": key_obj.created_at,
                "warning": "Copy this key now. It will never be shown again.",
            },
            status=status.HTTP_201_CREATED,
        )


class APIKeyRevokeView(APIView):
    """
    DELETE /api/v1/keys/<key_id>/

    Soft-delete (deactivate) an API key.
    The key immediately stops working.
    """
    permission_classes = [permissions.IsAuthenticated]

    def delete(self, request, key_id):
        try:
            key = APIKey.objects.get(
                id=key_id,
                user=request.user,
                is_active=True,
            )
        except APIKey.DoesNotExist:
            return Response(
                {"error": "Key not found or already revoked."},
                status=status.HTTP_404_NOT_FOUND,
            )

        key.is_active = False
        key.save(update_fields=["is_active"])

        return Response({"message": f"Key '{key.name}' has been revoked."})


class APIKeyRenameView(APIView):
    """
    PATCH /api/v1/keys/<key_id>/rename/
    Body: { "name": "New Name" }
    """
    permission_classes = [permissions.IsAuthenticated]

    def patch(self, request, key_id):
        try:
            key = APIKey.objects.get(
                id=key_id,
                user=request.user,
                is_active=True,
            )
        except APIKey.DoesNotExist:
            return Response({"error": "Key not found."}, status=404)

        new_name = request.data.get("name", "").strip()[:100]
        if not new_name:
            return Response({"error": "Name cannot be empty."}, status=400)

        key.name = new_name
        key.save(update_fields=["name"])

        return Response({"id": key.id, "name": key.name, "message": "Key renamed."})
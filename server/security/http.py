"""Small pure-ASGI security boundary; never buffers file response bodies."""
from starlette.datastructures import MutableHeaders


class SecurityHeadersMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        # ProxyHeadersMiddleware (Uvicorn) has already resolved scope['client']
        # using its trusted peer list. Do not let downstream session labels
        # re-trust arbitrary forwarded headers supplied by an Internet client.
        scope = dict(scope)
        scope["headers"] = [(k, v) for k, v in scope.get("headers", [])
                            if k.lower() not in {b"x-forwarded-for", b"x-real-ip"}]

        async def protected_send(message):
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                headers["X-Content-Type-Options"] = "nosniff"
                headers["Referrer-Policy"] = "no-referrer"
                headers["X-Frame-Options"] = "DENY"
                # Includes authenticated downloads, vault, mail and token replies;
                # API output must not become a shared CDN cache entry.
                headers["Cache-Control"] = "private, no-store"
            await send(message)
        await self.app(scope, receive, protected_send)

"""Stream-safe pure-ASGI rate-limit middleware.

Why this exists
---------------
`slowapi.middleware.SlowAPIASGIMiddleware` (slowapi 0.1.9) is the pure-ASGI
rate limiter we adopted to escape the `BaseHTTPMiddleware` "No response
returned." 500 blocker (see main.py import note / TSR0012).

But its `_ASGIMiddlewareResponder.send_wrapper` has a streaming bug: it buffers
the `http.response.start` message and then re-sends that buffered message on
**every** `http.response.body` chunk it sees. For a single-chunk response
(typical JSON) only one body message is emitted, so `response.start` is sent
once and everything works. For a **multi-chunk** response — which is exactly
what `FileResponse` produces for any file larger than its 64 KB `chunk_size`
(e.g. a real mail attachment) — the second and subsequent body chunks each
re-emit `response.start`. uvicorn then raises:

    RuntimeError: Expected ASGI message 'http.response.body',
                  but got 'http.response.start'.

and the browser, having received the `Content-Length` header but a truncated
body, reports `net::ERR_CONTENT_LENGTH_MISMATCH` (HTTP 200, 0 bytes). This
silently broke every attachment download (B0001 / 0019.0005-TR rejection).

The fix
-------
Send the buffered `http.response.start` exactly once — on the first
`http.response.body` — then stream every following body chunk straight through.
Rate-limit header injection / error-status rewrite still happen on that single
start message, so behaviour is identical to slowapi for the single-chunk case
and *correct* for the multi-chunk case. All other slowapi machinery (Limiter,
decorators, `_inject_asgi_headers`, exemption logic, limit checking) is reused
verbatim by subclassing, so this is not a fork of the rate-limiting logic — only
the response-relay loop is corrected.
"""

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from slowapi.middleware import SlowAPIASGIMiddleware, _ASGIMiddlewareResponder


class _StreamSafeResponder(_ASGIMiddlewareResponder):
    """`_ASGIMiddlewareResponder` whose send loop is multi-chunk safe."""

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)
        self._start_sent = False

    async def send_wrapper(self, message: Message) -> None:
        if message["type"] == "http.response.start":
            # Buffer the start so headers/status can still be edited based on the
            # rate-limit decision; emit it lazily with the first body chunk.
            self.initial_message = message
            return

        if message["type"] == "http.response.body":
            if not self._start_sent:
                if self.error_response:
                    self.initial_message["status"] = self.error_response.status_code
                if self.inject_headers:
                    headers = MutableHeaders(raw=self.initial_message["headers"])
                    self.limiter._inject_asgi_headers(
                        headers, self.request.state.view_rate_limit
                    )
                await self.send(self.initial_message)
                self._start_sent = True
            # Stream this chunk (and every later chunk) through verbatim. The
            # original code re-sent the buffered start here on every chunk — the
            # root cause of the duplicate-start RuntimeError.
            await self.send(message)
            return

        # Pass through anything else (e.g. http.response.trailers) unchanged.
        await self.send(message)


class StreamSafeSlowAPIASGIMiddleware(SlowAPIASGIMiddleware):
    """Drop-in replacement for `SlowAPIASGIMiddleware` that streams correctly."""

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        await _StreamSafeResponder(self.app)(scope, receive, send)

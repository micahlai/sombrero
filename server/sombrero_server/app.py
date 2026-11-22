"""FastAPI transport. Run with `uvicorn sombrero_server.app:create_app --factory`."""
from __future__ import annotations

import json
import sqlite3

from fastapi import Depends, FastAPI, Header, Request
from fastapi.responses import FileResponse, JSONResponse

from .store import ServiceError, Settings, Store
from .enrollment import redeem_code


def create_app(settings: Settings | None = None) -> FastAPI:
    store = Store(settings or Settings.from_environment())
    app = FastAPI(title="sombrero private messages", version="1.0", docs_url=None,
                  redoc_url=None, openapi_url=None)
    app.state.store = store

    @app.exception_handler(ServiceError)
    async def service_error(_request, error):
        headers = {"Retry-After": "10"} if error.status == 503 else {}
        if error.status == 401:
            headers["WWW-Authenticate"] = "Bearer"
        return JSONResponse({"detail": error.detail}, status_code=error.status, headers=headers)

    @app.exception_handler(sqlite3.OperationalError)
    async def database_error(_request, _error):
        return JSONResponse({"detail": "Message storage unavailable; retry later"},
                            status_code=503, headers={"Retry-After": "10"})

    @app.middleware("http")
    async def response_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def authorized(authorization: str | None = Header(default=None)) -> str:
        return store.authenticate(authorization)

    async def payload(request: Request):
        if request.headers.get("content-type", "").split(";", 1)[0].strip().lower() != "application/json":
            raise ServiceError(415, "Expected application/json")
        body = bytearray()
        async for chunk in request.stream():
            if len(body) + len(chunk) > 256 * 1024:
                raise ServiceError(413, "Message request is too large")
            body.extend(chunk)
        try:
            return json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise ServiceError(422, "Invalid JSON body") from None

    @app.get("/v1/health")
    def health():
        available = store.media_available()
        return JSONResponse({"status": "ok" if available else "unavailable", "mediaAvailable": available},
                            status_code=200 if available else 503)

    @app.get("/v1/me")
    def me(device: str = Depends(authorized)):
        return store.identity(device)

    @app.post("/v1/enrollments/redeem")
    def enroll(authorization: str | None = Header(default=None)):
        return redeem_code(store, authorization)

    @app.post("/v1/attachments")
    async def upload(request: Request, device: str = Depends(authorized)):
        upload = store.upload(device, request.headers.get("content-type", ""),
                              request.headers.get("x-client-upload-id"))
        try:
            length = request.headers.get("content-length")
            if length is not None:
                try:
                    declared = int(length)
                    if declared < 0:
                        raise ValueError()
                except ValueError:
                    raise ServiceError(400, "Invalid content length") from None
                if declared > upload.limit:
                    raise ServiceError(413, "Attachment exceeds the configured size limit")
            async for chunk in request.stream():
                upload.write(chunk)
            return upload.finish()
        finally:
            upload.abort()

    @app.get("/v1/attachments/{attachment_id}")
    def download(attachment_id: str, device: str = Depends(authorized)):
        metadata, path = store.attachment_for_download(device, attachment_id)
        return FileResponse(path, media_type=metadata["mediaType"], filename=metadata["id"],
                            headers={"ETag": '"' + metadata["sha256"] + '"'})

    @app.post("/v1/messages")
    async def send(request: Request, device: str = Depends(authorized)):
        return store.send(device, await payload(request))

    @app.get("/v1/sync")
    def sync(cursor: int = 0, limit: int = 100, device: str = Depends(authorized)):
        return store.sync(device, cursor, limit)

    @app.put("/v1/messages/{message_id}/read")
    def read(message_id: str, device: str = Depends(authorized)):
        return store.mark_read(device, message_id)

    return app

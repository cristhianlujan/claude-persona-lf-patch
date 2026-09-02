from __future__ import annotations

import secrets
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from typing import Any, Callable

from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .engine import ProfileRuntimeEngine
from .hashing import canonical_json_sha256
from .jobs import JobStore
from .models import BatchRequest, ExecuteRequest, JobAccepted
from .settings import Settings, SettingsError


def _job_meta(kind: str, payload: ExecuteRequest | BatchRequest) -> dict[str, Any]:
    rendered = payload.model_dump(mode="json")
    artifact = payload.artifact
    meta: dict[str, Any] = {
        "kind": kind,
        "request_sha256": canonical_json_sha256(rendered),
        "artifact_sha256": artifact.image_sha256,
        "screen_code": artifact.screen_code,
    }
    if isinstance(payload, ExecuteRequest):
        meta.update(
            {
                "request_id": payload.profile.request_id,
                "profiles": [payload.profile.profile_code],
            }
        )
    else:
        meta.update(
            {
                "batch_id": payload.batch_id,
                "profiles": [item.profile_code for item in payload.profiles],
            }
        )
    return meta


def create_app(
    settings: Settings | None = None,
    *,
    engine_factory: Callable[[Settings], ProfileRuntimeEngine] = ProfileRuntimeEngine,
) -> FastAPI:
    runtime_settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = engine_factory(runtime_settings)
        store = JobStore(runtime_settings.state_dir / "jobs.sqlite3")
        engine.initialize()
        store.initialize()
        recovered = store.recover_incomplete()
        executor = ThreadPoolExecutor(
            max_workers=runtime_settings.max_workers,
            thread_name_prefix="lf-profile-runtime",
        )
        app.state.engine = engine
        app.state.job_store = store
        app.state.executor = executor
        app.state.recovered_jobs = recovered
        try:
            yield
        finally:
            executor.shutdown(wait=False, cancel_futures=True)

    app = FastAPI(
        title="LF Hetzner Profile Runtime API",
        version="0.1.0-candidate",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )

    @app.exception_handler(RequestValidationError)
    async def sanitized_validation_error(
        _request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        errors = [
            {
                "type": str(item.get("type", "validation_error")),
                "loc": [str(part) for part in item.get("loc", ())],
            }
            for item in exc.errors()
        ]
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={"detail": "REQUEST_VALIDATION_FAILED", "errors": errors[:100]},
        )

    @app.middleware("http")
    async def enforce_content_length(request: Request, call_next: Any):
        if request.method in {"POST", "PUT", "PATCH"}:
            raw = request.headers.get("content-length")
            if raw is None:
                return JSONResponse(status_code=411, content={"detail": "CONTENT_LENGTH_REQUIRED"})
            try:
                size = int(raw)
            except ValueError:
                return JSONResponse(status_code=400, content={"detail": "CONTENT_LENGTH_INVALID"})
            if size < 0 or size > runtime_settings.max_request_bytes:
                return JSONResponse(status_code=413, content={"detail": "REQUEST_TOO_LARGE"})
        return await call_next(request)

    def authorize(authorization: str | None = Header(default=None)) -> None:
        if runtime_settings.allow_no_auth and not runtime_settings.api_token:
            return
        if not runtime_settings.api_token:
            raise HTTPException(status_code=503, detail="API_AUTH_NOT_CONFIGURED")
        prefix = "Bearer "
        supplied = (
            authorization[len(prefix) :]
            if authorization and authorization.startswith(prefix)
            else ""
        )
        if not supplied or not secrets.compare_digest(supplied, runtime_settings.api_token):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="UNAUTHORIZED",
                headers={"WWW-Authenticate": "Bearer"},
            )

    def submit_job(
        *,
        kind: str,
        external_id: str,
        payload: ExecuteRequest | BatchRequest,
        request: Request,
    ) -> JobAccepted:
        meta = _job_meta(kind, payload)
        store: JobStore = request.app.state.job_store
        job, reused = store.create(
            external_key=f"{kind}:{external_id}", kind=kind, request_meta=meta
        )
        if reused and job.get("request_meta", {}).get("request_sha256") != meta["request_sha256"]:
            raise HTTPException(status_code=409, detail="IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
        if not reused:
            engine: ProfileRuntimeEngine = request.app.state.engine

            def worker() -> None:
                store.start(job["job_id"])
                try:
                    result = (
                        engine.run_execute(payload)
                        if isinstance(payload, ExecuteRequest)
                        else engine.run_batch(payload)
                    )
                    store.complete(job["job_id"], result)
                except Exception as exc:
                    store.fail(
                        job["job_id"],
                        {"code": "UNEXPECTED_JOB_FAILURE", "detail": type(exc).__name__},
                    )

            request.app.state.executor.submit(worker)
        return JobAccepted(
            job_id=job["job_id"],
            status=job["status"],
            reused=reused,
            status_url=f"/v1/jobs/{job['job_id']}",
        )

    @app.get("/health")
    def health(request: Request) -> dict[str, Any]:
        return {
            "status": "ok",
            "service": "lf-profile-runtime-api",
            "runtime_version": runtime_settings.runtime_version,
            "classification": "INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY",
            "recovered_jobs": request.app.state.recovered_jobs,
        }

    @app.get("/runtime", dependencies=[Depends(authorize)])
    def runtime(request: Request) -> dict[str, Any]:
        snapshot = request.app.state.engine.runtime_snapshot()
        snapshot["jobs"] = request.app.state.job_store.stats()
        return snapshot

    @app.post(
        "/v1/profile/execute",
        response_model=JobAccepted,
        status_code=status.HTTP_202_ACCEPTED,
        dependencies=[Depends(authorize)],
    )
    def execute(payload: ExecuteRequest, request: Request) -> JobAccepted:
        return submit_job(
            kind="execute",
            external_id=payload.profile.request_id,
            payload=payload,
            request=request,
        )

    @app.post(
        "/v1/profile/batch",
        response_model=JobAccepted,
        status_code=status.HTTP_202_ACCEPTED,
        dependencies=[Depends(authorize)],
    )
    def batch(payload: BatchRequest, request: Request) -> JobAccepted:
        return submit_job(
            kind="batch", external_id=payload.batch_id, payload=payload, request=request
        )

    @app.get("/v1/jobs/{job_id}", dependencies=[Depends(authorize)])
    def job(job_id: str, request: Request) -> dict[str, Any]:
        record = request.app.state.job_store.get(job_id)
        if record is None:
            raise HTTPException(status_code=404, detail="JOB_NOT_FOUND")
        return record

    return app


try:
    app = create_app()
except SettingsError:
    # Import remains safe for diagnostics; process startup through __main__ still fails closed.
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.get("/health")
    def invalid_configuration() -> JSONResponse:
        return JSONResponse(
            status_code=503,
            content={"status": "error", "code": "RUNTIME_CONFIGURATION_INVALID"},
        )

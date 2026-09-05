from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit


class SettingsError(ValueError):
    pass


def _bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise SettingsError(f"{name}_INVALID_BOOLEAN")


def _int(name: str, default: int, *, minimum: int, maximum: int) -> int:
    raw = os.getenv(name)
    try:
        value = default if raw is None else int(raw)
    except ValueError as exc:
        raise SettingsError(f"{name}_INVALID_INTEGER") from exc
    if not minimum <= value <= maximum:
        raise SettingsError(f"{name}_OUT_OF_RANGE")
    return value


def _require_loopback_url(value: str) -> str:
    parsed = urlsplit(value.rstrip("/"))
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise SettingsError("PROFILE_RUNTIME_LLAMA_BASE_URL_MUST_BE_LOOPBACK_HTTP")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise SettingsError("PROFILE_RUNTIME_LLAMA_BASE_URL_INVALID")
    if parsed.path not in {"", "/"}:
        raise SettingsError("PROFILE_RUNTIME_LLAMA_BASE_URL_PATH_FORBIDDEN")
    return value.rstrip("/")


def _require_loopback_host(value: str) -> str:
    if value not in {"127.0.0.1", "localhost", "::1"}:
        raise SettingsError("PROFILE_RUNTIME_API_HOST_MUST_BE_LOOPBACK")
    return value


@dataclass(frozen=True)
class Settings:
    repo_root: Path
    state_dir: Path
    api_token: str
    api_host: str = "127.0.0.1"
    api_port: int = 8090
    llama_base_url: str = "http://127.0.0.1:8080"
    llama_model: str = "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
    runtime_version: str = "hetzner-profile-runtime-api/0.1.0-candidate"
    resolver_version: str = "structural-context-resolver/v3"
    source_sha: str = "UNVERIFIED_SOURCE_SHA"
    max_workers: int = 1
    max_batch_size: int = 8
    max_request_bytes: int = 20 * 1024 * 1024
    max_prompt_chars: int = 120_000
    max_output_tokens: int = 2048
    llama_timeout_seconds: int = 900
    llama_health_timeout_seconds: int = 3
    cache_max_entries: int = 64
    enable_targeted_reread: bool = True
    allow_model_image: bool = False
    allow_no_auth: bool = False

    @classmethod
    def from_env(cls) -> "Settings":
        discovered_repo = Path(__file__).resolve().parents[3]
        repo_root = Path(
            os.getenv("PROFILE_RUNTIME_REPO_ROOT", str(discovered_repo))
        ).resolve()
        state_dir = Path(
            os.getenv("PROFILE_RUNTIME_STATE_DIR", "/var/lib/lf-profile-runtime-api")
        ).resolve()
        return cls(
            repo_root=repo_root,
            state_dir=state_dir,
            api_token=os.getenv("PROFILE_RUNTIME_API_TOKEN", "").strip(),
            api_host=_require_loopback_host(
                os.getenv("PROFILE_RUNTIME_API_HOST", "127.0.0.1").strip()
            ),
            api_port=_int("PROFILE_RUNTIME_API_PORT", 8090, minimum=1024, maximum=65535),
            llama_base_url=_require_loopback_url(
                os.getenv("PROFILE_RUNTIME_LLAMA_BASE_URL", "http://127.0.0.1:8080").strip()
            ),
            llama_model=os.getenv(
                "PROFILE_RUNTIME_LLAMA_MODEL", "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
            ).strip(),
            runtime_version=os.getenv(
                "PROFILE_RUNTIME_VERSION", "hetzner-profile-runtime-api/0.1.0-candidate"
            ).strip(),
            resolver_version=os.getenv(
                "PROFILE_RUNTIME_RESOLVER_VERSION", "structural-context-resolver/v3"
            ).strip(),
            source_sha=os.getenv("PROFILE_RUNTIME_SOURCE_SHA", "UNVERIFIED_SOURCE_SHA").strip(),
            max_workers=_int("PROFILE_RUNTIME_MAX_WORKERS", 1, minimum=1, maximum=1),
            max_batch_size=_int("PROFILE_RUNTIME_MAX_BATCH_SIZE", 8, minimum=1, maximum=16),
            max_request_bytes=_int(
                "PROFILE_RUNTIME_MAX_REQUEST_BYTES", 20 * 1024 * 1024,
                minimum=1024, maximum=32 * 1024 * 1024,
            ),
            max_prompt_chars=_int(
                "PROFILE_RUNTIME_MAX_PROMPT_CHARS", 120_000,
                minimum=1000, maximum=500_000,
            ),
            max_output_tokens=_int(
                "PROFILE_RUNTIME_MAX_OUTPUT_TOKENS", 2048,
                minimum=128, maximum=8192,
            ),
            llama_timeout_seconds=_int(
                "PROFILE_RUNTIME_LLAMA_TIMEOUT_SECONDS", 900,
                minimum=30, maximum=1800,
            ),
            llama_health_timeout_seconds=_int(
                "PROFILE_RUNTIME_LLAMA_HEALTH_TIMEOUT_SECONDS", 3,
                minimum=1, maximum=15,
            ),
            cache_max_entries=_int(
                "PROFILE_RUNTIME_CACHE_MAX_ENTRIES", 64,
                minimum=1, maximum=512,
            ),
            enable_targeted_reread=_bool("PROFILE_RUNTIME_ENABLE_TARGETED_REREAD", True),
            allow_model_image=_bool("PROFILE_RUNTIME_ALLOW_MODEL_IMAGE", False),
            allow_no_auth=_bool("PROFILE_RUNTIME_ALLOW_NO_AUTH", False),
        )

    def validate(self) -> None:
        if not self.repo_root.is_dir():
            raise SettingsError("PROFILE_RUNTIME_REPO_ROOT_MISSING")
        if not self.llama_model:
            raise SettingsError("PROFILE_RUNTIME_LLAMA_MODEL_MISSING")
        if not self.runtime_version or not self.resolver_version:
            raise SettingsError("PROFILE_RUNTIME_VERSION_MISSING")
        _require_loopback_url(self.llama_base_url)
        _require_loopback_host(self.api_host)
        if not self.api_token and not self.allow_no_auth:
            raise SettingsError("PROFILE_RUNTIME_API_TOKEN_MISSING")

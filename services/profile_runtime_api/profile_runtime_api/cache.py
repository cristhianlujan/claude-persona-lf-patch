from __future__ import annotations

import json
import hashlib
import os
import re
import tempfile
import threading
from collections import OrderedDict
from pathlib import Path
from typing import Any

from .hashing import canonical_json_bytes, canonical_json_sha256

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
FORBIDDEN_CACHE_FIELDS = {
    "profile_contract_valid",
    "semantic_utility",
    "downstream_authorized",
    "authorization",
    "quality_verdict",
}


class CacheError(ValueError):
    pass


def make_cache_key(
    *, image_sha: str, context_sha: str, runtime_version: str, resolver_version: str
) -> str:
    for name, value in (("image_sha", image_sha), ("context_sha", context_sha)):
        if not SHA256_RE.fullmatch(str(value).lower()):
            raise CacheError(f"{name}_must_be_sha256")
    if not runtime_version.strip() or not resolver_version.strip():
        raise CacheError("runtime_and_resolver_version_required")
    payload = {
        "context_sha": context_sha.lower(),
        "image_sha": image_sha.lower(),
        "resolver_version": resolver_version.strip(),
        "runtime_version": runtime_version.strip(),
        "schema": "lf-profile-runtime-structural-cache-key/v1",
    }
    # Byte-for-byte parity with the repository V3 cache-key contract.
    canonical = json.dumps(
        payload, ensure_ascii=True, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "p0v3:" + hashlib.sha256(canonical).hexdigest()


def _forbidden_path(value: Any, path: str = "$") -> str | None:
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key in FORBIDDEN_CACHE_FIELDS:
                return child_path
            found = _forbidden_path(child, child_path)
            if found:
                return found
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found = _forbidden_path(child, f"{path}[{index}]")
            if found:
                return found
    return None


class StructuralCache:
    def __init__(self, root: Path, *, max_entries: int = 64) -> None:
        self.root = root
        self.max_entries = max_entries
        self._memory: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self._lock = threading.RLock()
        self.hits = 0
        self.misses = 0
        self.writes = 0

    def initialize(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)

    def _path(self, key: str) -> Path:
        if not re.fullmatch(r"p0v3:[0-9a-f]{64}", key):
            raise CacheError("cache_key_invalid")
        return self.root / f"{key.split(':', 1)[1]}.json"

    def get(self, key: str) -> dict[str, Any] | None:
        with self._lock:
            if key in self._memory:
                self.hits += 1
                value = self._memory.pop(key)
                self._memory[key] = value
                return json.loads(json.dumps(value))
            path = self._path(key)
            if not path.is_file():
                self.misses += 1
                return None
            try:
                envelope = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                self.misses += 1
                return None
            if not isinstance(envelope, dict) or envelope.get("key") != key:
                self.misses += 1
                return None
            payload = envelope.get("payload")
            if not isinstance(payload, dict) or _forbidden_path(payload):
                self.misses += 1
                return None
            if envelope.get("payload_sha256") != canonical_json_sha256(payload):
                self.misses += 1
                return None
            self.hits += 1
            self._remember(key, payload)
            return json.loads(json.dumps(payload))

    def put(self, key: str, payload: dict[str, Any]) -> None:
        forbidden = _forbidden_path(payload)
        if forbidden:
            raise CacheError(f"forbidden_cached_field:{forbidden}")
        path = self._path(key)
        envelope = {
            "schema": "lf-profile-runtime-structural-cache-entry/v1",
            "key": key,
            "payload": payload,
            "payload_sha256": canonical_json_sha256(payload),
        }
        rendered = canonical_json_bytes(envelope) + b"\n"
        with self._lock:
            self.initialize()
            with tempfile.NamedTemporaryFile(dir=self.root, delete=False) as handle:
                temp_path = Path(handle.name)
                handle.write(rendered)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temp_path, 0o600)
            os.replace(temp_path, path)
            self.writes += 1
            self._remember(key, payload)

    def _remember(self, key: str, payload: dict[str, Any]) -> None:
        self._memory.pop(key, None)
        self._memory[key] = json.loads(json.dumps(payload))
        while len(self._memory) > self.max_entries:
            self._memory.popitem(last=False)

    def stats(self) -> dict[str, int]:
        with self._lock:
            disk_entries = len(list(self.root.glob("*.json"))) if self.root.is_dir() else 0
            return {
                "memory_entries": len(self._memory),
                "disk_entries": disk_entries,
                "hits": self.hits,
                "misses": self.misses,
                "writes": self.writes,
            }

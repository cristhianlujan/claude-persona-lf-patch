from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

TYPED_CONTEXT_SCHEMA = "LF_RUNTIME_TYPED_CONTEXT_V1"
FALLBACK_MODE = "NO_CARD_GOVERNED"


class RuntimeContextBlocked(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe_repo_file(repo_root: Path, ref: str, *, prefix: str) -> Path:
    if not _nonempty(ref):
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_REF_MISSING")
    normalized = str(Path(ref).as_posix())
    parts = Path(normalized).parts
    if normalized.startswith("/") or ".." in parts or (prefix and not normalized.startswith(prefix)):
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_REF_OUT_OF_SCOPE", normalized)
    path = (repo_root / normalized).resolve()
    root = repo_root.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_REF_PATH_ESCAPE", normalized) from exc
    if not path.is_file():
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_REF_NOT_FOUND", normalized)
    return path


def _verify_ref(repo_root: Path, item: dict[str, Any], *, prefix: str) -> dict[str, str]:
    ref = item.get("ref")
    expected_sha = item.get("sha256")
    if not _nonempty(expected_sha) or len(expected_sha) != 64:
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_PROVENANCE_SHA_MISSING", str(ref))
    path = _safe_repo_file(repo_root, ref, prefix=prefix)
    raw = path.read_bytes()
    actual_sha = _sha256(raw)
    if actual_sha != expected_sha:
        raise RuntimeContextBlocked("RUNTIME_CONTEXT_PROVENANCE_SHA_MISMATCH", str(ref))
    return {"ref": str(Path(ref).as_posix()), "sha256": actual_sha}


def _string_list(value: Any, code: str) -> list[str]:
    if not isinstance(value, list) or any(not _nonempty(v) for v in value):
        raise RuntimeContextBlocked(code)
    if len(set(value)) != len(value):
        raise RuntimeContextBlocked(code, "duplicate")
    return list(value)


def _resolve_card(context: dict[str, Any], repo_root: Path, input_fields: dict[str, Any]) -> dict[str, Any]:
    surface = context["surface_code"]
    task = context["task_code"]
    candidates = context.get("card_candidates")
    if not isinstance(candidates, list):
        raise RuntimeContextBlocked("RUNTIME_CARD_CANDIDATES_NOT_ARRAY")

    applicable: list[dict[str, Any]] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise RuntimeContextBlocked("RUNTIME_CARD_CANDIDATE_INVALID")
        card_id = candidate.get("card_id")
        surfaces = candidate.get("surface_codes", [])
        tasks = candidate.get("task_codes", [])
        if not _nonempty(card_id) or not isinstance(surfaces, list) or not isinstance(tasks, list):
            raise RuntimeContextBlocked("RUNTIME_CARD_CANDIDATE_INCOMPLETE")
        if surface in surfaces and task in tasks:
            applicable.append(candidate)

    if not applicable:
        return {
            "status": "FALLBACK",
            "mode": FALLBACK_MODE,
            "card_id": None,
            "card_ref": None,
            "card_sha256": None,
            "schema_invention_allowed": False,
            "reason": "NO_APPLICABLE_CARD",
        }
    if len(applicable) > 1:
        ids = sorted(str(item.get("card_id")) for item in applicable)
        raise RuntimeContextBlocked("RUNTIME_CARD_AMBIGUOUS", ",".join(ids))

    card = applicable[0]
    provenance = _verify_ref(repo_root, card, prefix="cards/")
    required_fields = card.get("required_input_fields", [])
    if not isinstance(required_fields, list) or any(not _nonempty(v) for v in required_fields):
        raise RuntimeContextBlocked("RUNTIME_CARD_REQUIRED_FIELDS_INVALID", card["card_id"])
    missing = sorted(field for field in required_fields if field not in input_fields)
    if missing:
        raise RuntimeContextBlocked("RUNTIME_CARD_REQUIRED_INPUT_MISSING", ",".join(missing))
    schema_ref = card.get("runtime_output_schema_ref")
    schema_provenance = None
    if schema_ref is not None:
        schema_sha = card.get("runtime_output_schema_sha256")
        schema_provenance = _verify_ref(
            repo_root,
            {"ref": schema_ref, "sha256": schema_sha},
            prefix="profiles/",
        )
    return {
        "status": "RESOLVED",
        "mode": "CARD_BOUND",
        "card_id": card["card_id"],
        "card_ref": provenance["ref"],
        "card_sha256": provenance["sha256"],
        "required_input_fields": sorted(required_fields),
        "runtime_output_schema": schema_provenance,
        "schema_invention_allowed": False,
    }


def _resolve_authorities(context: dict[str, Any], repo_root: Path) -> list[dict[str, Any]]:
    required_types = _string_list(context.get("required_authority_types"), "RUNTIME_REQUIRED_AUTHORITY_TYPES_INVALID")
    sources = context.get("authority_sources")
    if not isinstance(sources, list):
        raise RuntimeContextBlocked("RUNTIME_AUTHORITY_SOURCES_NOT_ARRAY")
    current_run_id = context["current_run_id"]
    verified: list[dict[str, Any]] = []
    for source in sources:
        if not isinstance(source, dict):
            raise RuntimeContextBlocked("RUNTIME_AUTHORITY_SOURCE_INVALID")
        authority_type = source.get("authority_type")
        authority_id = source.get("authority_id")
        run_id = source.get("run_id", current_run_id)
        if not _nonempty(authority_type) or not _nonempty(authority_id) or not _nonempty(run_id):
            raise RuntimeContextBlocked("RUNTIME_AUTHORITY_SOURCE_INCOMPLETE")
        if run_id != current_run_id and source.get("cross_run_declared") is not True:
            raise RuntimeContextBlocked("RUNTIME_CROSS_RUN_REFERENCE_UNDECLARED", authority_id)
        provenance = _verify_ref(repo_root, source, prefix="")
        verified.append({
            "authority_type": authority_type,
            "authority_id": authority_id,
            "run_id": run_id,
            "cross_run_declared": bool(source.get("cross_run_declared", False)),
            **provenance,
        })

    for required_type in required_types:
        matches = [item for item in verified if item["authority_type"] == required_type]
        if not matches:
            raise RuntimeContextBlocked("RUNTIME_AUTHORITY_MISSING", required_type)
        digests = {item["sha256"] for item in matches}
        if len(digests) > 1:
            raise RuntimeContextBlocked("RUNTIME_AUTHORITY_INCOMPATIBLE", required_type)
    return sorted(verified, key=lambda item: (item["authority_type"], item["authority_id"]))


def _resolve_adapters(context: dict[str, Any], request: dict[str, Any]) -> list[dict[str, str]]:
    required_codes = _string_list(context.get("required_adapter_codes", []), "RUNTIME_REQUIRED_ADAPTER_CODES_INVALID")
    request_bindings = request.get("lf_adapter_bindings", [])
    if not isinstance(request_bindings, list):
        raise RuntimeContextBlocked("RUNTIME_ADAPTER_BINDINGS_NOT_ARRAY")
    by_code: dict[str, dict[str, Any]] = {}
    for binding in request_bindings:
        if not isinstance(binding, dict):
            raise RuntimeContextBlocked("RUNTIME_ADAPTER_BINDING_INVALID")
        code = binding.get("canonical_adapter_id")
        current_path = binding.get("current_path")
        binding_ref = binding.get("binding_ref")
        if not all(_nonempty(v) for v in (code, current_path, binding_ref)):
            raise RuntimeContextBlocked("RUNTIME_ADAPTER_BINDING_INCOMPLETE")
        if code in by_code:
            raise RuntimeContextBlocked("RUNTIME_ADAPTER_AMBIGUOUS", code)
        by_code[code] = binding
    for code in required_codes:
        if code not in by_code:
            raise RuntimeContextBlocked("RUNTIME_ADAPTER_MISSING", code)
    return [
        {
            "adapter_code": code,
            "current_path": str(Path(by_code[code]["current_path"]).as_posix()),
            "binding_ref": by_code[code]["binding_ref"],
        }
        for code in sorted(by_code)
    ]


def resolve_runtime_context(runtime_context: Any, *, request: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    if not isinstance(runtime_context, dict):
        raise RuntimeContextBlocked("RUNTIME_TYPED_CONTEXT_REQUIRED")
    for key in ("surface_code", "task_code", "current_run_id"):
        if not _nonempty(runtime_context.get(key)):
            raise RuntimeContextBlocked("RUNTIME_CONTEXT_FIELD_MISSING", key)
    input_fields = runtime_context.get("input_fields")
    if not isinstance(input_fields, dict):
        raise RuntimeContextBlocked("RUNTIME_INPUT_FIELDS_NOT_OBJECT")
    input_literal = request.get("input_literal")
    if not _nonempty(input_literal):
        raise RuntimeContextBlocked("RUNTIME_INPUT_LITERAL_MISSING")

    card = _resolve_card(runtime_context, repo_root, input_fields)
    authorities = _resolve_authorities(runtime_context, repo_root)
    adapters = _resolve_adapters(runtime_context, request)
    provenance = {
        "card": None if card["status"] == "FALLBACK" else {
            "ref": card["card_ref"], "sha256": card["card_sha256"]
        },
        "authorities": [{"ref": a["ref"], "sha256": a["sha256"]} for a in authorities],
        "adapters": [{"adapter_code": a["adapter_code"], "binding_ref": a["binding_ref"]} for a in adapters],
    }
    if card["status"] == "FALLBACK" and card["schema_invention_allowed"]:
        raise RuntimeContextBlocked("RUNTIME_FALLBACK_SCHEMA_INVENTION_FORBIDDEN")
    payload = {
        "schema": TYPED_CONTEXT_SCHEMA,
        "surface_code": runtime_context["surface_code"],
        "task_code": runtime_context["task_code"],
        "current_run_id": runtime_context["current_run_id"],
        "input_literal_sha256": _sha256(input_literal.encode("utf-8")),
        "input_fields": input_fields,
        "card_resolution": card,
        "authority_resolution": authorities,
        "adapter_binding": adapters,
        "provenance": provenance,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    payload["typed_context_sha256"] = _sha256(canonical)
    return payload

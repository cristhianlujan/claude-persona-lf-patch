import hashlib
import json
import re
from pathlib import PurePosixPath
from typing import Any, Dict, List


SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
SOURCE_MODES = {"STANDALONE_PROFILE", "EMBEDDED_SKILL_PROFILE"}


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _block(decision: str, details: Dict[str, Any] | None = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "schema_version": "LF_PROFILE_TASK_RUNTIME_BINDING_V1",
        "status": "BLOCKED",
        "decision": decision,
    }
    if details:
        result["details"] = details
    result["binding_digest"] = _digest(result)
    return result


def _repo_path(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and ".." not in path.parts and "." not in path.parts


def _under_root(path: str, root: str) -> bool:
    try:
        PurePosixPath(path).relative_to(PurePosixPath(root))
        return True
    except ValueError:
        return False


def _validate_authority_refs(authority_refs: Any) -> List[str]:
    errors: List[str] = []
    if not isinstance(authority_refs, list) or not authority_refs:
        return ["AUTHORITY_REFS_MISSING"]
    seen: set[str] = set()
    for item in authority_refs:
        if not isinstance(item, dict):
            errors.append("AUTHORITY_REF_INVALID")
            continue
        ref = item.get("ref")
        revision = item.get("revision")
        digest = item.get("digest")
        if not isinstance(ref, str) or not ref.strip():
            errors.append("AUTHORITY_REF_MISSING")
        elif ref in seen:
            errors.append("AUTHORITY_REF_DUPLICATE")
        else:
            seen.add(ref)
        if not isinstance(revision, str) or not revision.strip():
            errors.append("AUTHORITY_REVISION_MISSING")
        if not isinstance(digest, str) or not SHA64_RE.fullmatch(digest):
            errors.append("AUTHORITY_DIGEST_INVALID")
    return sorted(set(errors))


def resolve_task_runtime_binding(
    step_contract: Dict[str, Any],
    worker_binding: Dict[str, Any],
    profile_authority: Dict[str, Any],
    task_authority: Dict[str, Any],
) -> Dict[str, Any]:
    if not all(isinstance(v, dict) for v in (step_contract, worker_binding, profile_authority, task_authority)):
        return _block("BLOCK_BINDING_INPUT_INVALID")

    step_id = step_contract.get("step_id")
    worker_role = step_contract.get("worker_role")
    judge_code = step_contract.get("judge_code") or step_contract.get("judge")
    if not all(isinstance(v, str) and v.strip() for v in (step_id, worker_role, judge_code)):
        return _block("BLOCK_STEP_CONTRACT_INCOMPLETE")

    if worker_binding.get("worker_kind") != "PROFILE":
        return _block("BLOCK_PROFILE_WORKER_KIND_MISMATCH")
    profile_code = worker_binding.get("worker_ref")
    if not isinstance(profile_code, str) or not profile_code.strip():
        return _block("BLOCK_PROFILE_WORKER_REF_MISSING")
    for field in ("binding_authority_ref", "binding_revision", "binding_digest", "source_revision"):
        if not isinstance(worker_binding.get(field), str) or not worker_binding[field].strip():
            return _block("BLOCK_WORKER_BINDING_INCOMPLETE", {"field": field})
    if not SHA64_RE.fullmatch(worker_binding["binding_digest"]):
        return _block("BLOCK_WORKER_BINDING_DIGEST_INVALID")
    if not SHA40_RE.fullmatch(worker_binding["source_revision"]):
        return _block("BLOCK_SOURCE_REVISION_INVALID")

    if profile_authority.get("profile_code") != profile_code:
        return _block("BLOCK_PROFILE_IDENTITY_MISMATCH")
    profile_slug = profile_authority.get("profile_slug")
    if not isinstance(profile_slug, str) or not profile_slug.strip():
        return _block("BLOCK_PROFILE_SLUG_MISSING")
    roles = profile_authority.get("worker_roles")
    if not isinstance(roles, list) or worker_role not in roles:
        return _block("BLOCK_PROFILE_WORKER_ROLE_MISMATCH")
    if profile_authority.get("route_status") != "READY_TO_EXECUTE" or profile_authority.get("downstream_execution_allowed") is not True:
        return _block("BLOCK_PROFILE_ROUTER_NOT_READY")
    if profile_authority.get("currentness_state") != "CURRENT":
        return _block("BLOCK_PROFILE_NOT_CURRENT")
    if profile_authority.get("source_revision") != worker_binding["source_revision"]:
        return _block("BLOCK_SOURCE_REVISION_MISMATCH")

    source_mode = task_authority.get("source_mode")
    source_root = task_authority.get("source_root")
    source_refs = task_authority.get("source_refs")
    if source_mode not in SOURCE_MODES:
        return _block("BLOCK_SOURCE_MODE_INVALID")
    if not _repo_path(source_root):
        return _block("BLOCK_SOURCE_ROOT_INVALID")
    if not isinstance(source_refs, list) or not source_refs:
        return _block("BLOCK_SOURCE_REFS_MISSING")

    source_by_path: Dict[str, Dict[str, Any]] = {}
    for item in source_refs:
        if not isinstance(item, dict):
            return _block("BLOCK_SOURCE_REF_INVALID")
        path = item.get("path")
        sha256 = item.get("sha256")
        revision = item.get("source_revision")
        if not _repo_path(path):
            return _block("BLOCK_SOURCE_REF_PATH_INVALID")
        if not _under_root(path, source_root):
            return _block("BLOCK_SOURCE_PATH_OUTSIDE_ROOT", {"path": path, "source_root": source_root})
        if path in source_by_path:
            return _block("BLOCK_SOURCE_REF_DUPLICATE", {"path": path})
        if not isinstance(sha256, str) or not SHA64_RE.fullmatch(sha256):
            return _block("BLOCK_SOURCE_REF_SHA_INVALID", {"path": path})
        if revision != worker_binding["source_revision"]:
            return _block("BLOCK_SOURCE_REVISION_MISMATCH", {"path": path})
        source_by_path[path] = item

    runtime_schema = task_authority.get("runtime_schema")
    if not isinstance(runtime_schema, dict):
        return _block("BLOCK_RUNTIME_SCHEMA_UNRESOLVED")
    schema_ref = runtime_schema.get("ref")
    schema_sha = runtime_schema.get("sha256")
    if schema_ref not in source_by_path or not isinstance(schema_sha, str) or not SHA64_RE.fullmatch(schema_sha):
        return _block("BLOCK_RUNTIME_SCHEMA_UNRESOLVED")
    if source_by_path[schema_ref]["sha256"] != schema_sha:
        return _block("BLOCK_RUNTIME_SCHEMA_SHA_MISMATCH")
    if runtime_schema.get("selection_mode") != "EXACT_REF":
        return _block("BLOCK_RUNTIME_SCHEMA_UNRESOLVED")

    validator = task_authority.get("deterministic_validator")
    if not isinstance(validator, dict):
        return _block("BLOCK_DETERMINISTIC_VALIDATOR_UNRESOLVED")
    validator_ref = validator.get("ref")
    validator_sha = validator.get("sha256")
    invocation = validator.get("invocation")
    if validator_ref not in source_by_path or not isinstance(validator_sha, str) or not SHA64_RE.fullmatch(validator_sha):
        return _block("BLOCK_DETERMINISTIC_VALIDATOR_UNRESOLVED")
    if source_by_path[validator_ref]["sha256"] != validator_sha:
        return _block("BLOCK_DETERMINISTIC_VALIDATOR_SHA_MISMATCH")
    if invocation not in {"PYTHON_CALLABLE", "CLI"}:
        return _block("BLOCK_DETERMINISTIC_VALIDATOR_INVOCATION_INVALID")
    if invocation == "PYTHON_CALLABLE" and (not isinstance(validator.get("callable"), str) or not validator["callable"].strip()):
        return _block("BLOCK_DETERMINISTIC_VALIDATOR_CALLABLE_MISSING")

    judge = task_authority.get("judge_binding")
    if not isinstance(judge, dict):
        return _block("BLOCK_JUDGE_BINDING_UNRESOLVED")
    judge_ref = judge.get("ref")
    judge_sha = judge.get("sha256")
    if judge.get("judge_code") != judge_code:
        return _block("BLOCK_JUDGE_BINDING_UNRESOLVED", {"expected": judge_code, "actual": judge.get("judge_code")})
    if judge_ref not in source_by_path or not isinstance(judge_sha, str) or not SHA64_RE.fullmatch(judge_sha):
        return _block("BLOCK_JUDGE_BINDING_UNRESOLVED")
    if source_by_path[judge_ref]["sha256"] != judge_sha:
        return _block("BLOCK_JUDGE_BINDING_SHA_MISMATCH")
    if judge.get("worker_must_not_execute_own_judge") is not True:
        return _block("BLOCK_JUDGE_INDEPENDENCE_NOT_ENFORCED")

    authority_errors = _validate_authority_refs(task_authority.get("authority_refs"))
    if authority_errors:
        return _block("BLOCK_BINDING_AUTHORITY_INCOMPLETE", {"errors": authority_errors})

    model_context = task_authority.get("model_context") or {}
    if not isinstance(model_context, dict):
        return _block("BLOCK_MODEL_CONTEXT_INVALID")
    context_refs = model_context.get("source_refs", [])
    if not isinstance(context_refs, list) or any(ref not in source_by_path for ref in context_refs):
        return _block("BLOCK_MODEL_CONTEXT_REF_UNRESOLVED")
    max_chars = model_context.get("max_chars", 0)
    if not isinstance(max_chars, int) or max_chars < 1 or max_chars > 100_000:
        return _block("BLOCK_MODEL_CONTEXT_BUDGET_INVALID")

    material = {
        "step_id": step_id,
        "worker_role": worker_role,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "source_mode": source_mode,
        "source_root": source_root,
        "source_revision": worker_binding["source_revision"],
        "source_refs": sorted(
            [{"path": path, "sha256": item["sha256"]} for path, item in source_by_path.items()],
            key=lambda item: item["path"],
        ),
        "runtime_schema": {"ref": schema_ref, "sha256": schema_sha, "selection_mode": "EXACT_REF"},
        "deterministic_validator": {
            "ref": validator_ref,
            "sha256": validator_sha,
            "invocation": invocation,
            **({"callable": validator["callable"]} if invocation == "PYTHON_CALLABLE" else {}),
        },
        "judge_binding": {
            "judge_code": judge_code,
            "ref": judge_ref,
            "sha256": judge_sha,
            "worker_must_not_execute_own_judge": True,
        },
        "model_context": {"source_refs": context_refs, "max_chars": max_chars},
        "authority_refs": sorted(task_authority["authority_refs"], key=lambda item: item["ref"]),
        "worker_binding_digest": worker_binding["binding_digest"],
    }
    result = {
        "schema_version": "LF_PROFILE_TASK_RUNTIME_BINDING_V1",
        "status": "RESOLVED",
        "decision": "TASK_RUNTIME_BINDING_RESOLVED",
        "binding": material,
    }
    result["binding_digest"] = _digest(material)
    result["resolution_digest"] = _digest(result)
    return result

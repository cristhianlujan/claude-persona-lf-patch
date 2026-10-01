from __future__ import annotations

import hashlib
import importlib.util
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any

from .repository import RepositoryError, SchemaBinding


BINDING_SCHEMA = "LF_PROFILE_TASK_RUNTIME_BINDING_V1"
SOURCE_MODES = {"STANDALONE_PROFILE", "EMBEDDED_SKILL_PROFILE"}


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_json(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class TaskValidatorBinding:
    ref: str
    sha256: str
    invocation: str
    callable_name: str | None


@dataclass(frozen=True)
class TaskJudgeBinding:
    judge_code: str
    ref: str
    sha256: str


@dataclass(frozen=True)
class TaskRuntimeMaterialization:
    profile_code: str
    profile_slug: str
    step_id: str
    worker_role: str
    source_mode: str
    source_root: str
    source_revision: str
    profile_sources: tuple[dict[str, str], ...]
    schema: SchemaBinding
    validator: TaskValidatorBinding
    judge: TaskJudgeBinding
    binding_digest: str
    model_context_refs: tuple[str, ...]
    model_context_chars: int


class TaskRuntimeBindingAdapter:
    """Materialize an already-resolved task binding from exact local repository bytes.

    This adapter is deliberately not an authority resolver. Router/currentness/asset/judge
    selection must already have happened upstream. Here we only verify path scope, bytes,
    digest cross-binding and expose the exact material to the shared Profile Runtime.
    """

    def __init__(self, repo_root: Path, *, max_prompt_chars: int) -> None:
        self.repo_root = repo_root.resolve()
        self.max_prompt_chars = max_prompt_chars

    def materialize(self, resolution: dict[str, Any]) -> TaskRuntimeMaterialization:
        if not isinstance(resolution, dict):
            raise RepositoryError("PROFILE_TASK_BINDING_INVALID")
        if resolution.get("schema_version") != BINDING_SCHEMA:
            raise RepositoryError("PROFILE_TASK_BINDING_SCHEMA_INVALID")
        if resolution.get("status") != "RESOLVED" or resolution.get("decision") != "TASK_RUNTIME_BINDING_RESOLVED":
            raise RepositoryError("PROFILE_TASK_BINDING_NOT_RESOLVED")
        binding = resolution.get("binding")
        digest = resolution.get("binding_digest")
        if not isinstance(binding, dict) or not isinstance(digest, str):
            raise RepositoryError("PROFILE_TASK_BINDING_PAYLOAD_MISSING")
        if _sha256_json(binding) != digest:
            raise RepositoryError("PROFILE_TASK_BINDING_DIGEST_MISMATCH")

        source_mode = binding.get("source_mode")
        source_root_raw = binding.get("source_root")
        if source_mode not in SOURCE_MODES:
            raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_MODE_INVALID")
        if not self._safe_repo_path(source_root_raw):
            raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_ROOT_INVALID")
        source_root = (self.repo_root / source_root_raw).resolve()
        self._within(source_root, self.repo_root, "PROFILE_TASK_BINDING_SOURCE_ROOT_ESCAPE")
        if not source_root.is_dir():
            raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_ROOT_MISSING", source_root_raw)

        source_rows = binding.get("source_refs")
        if not isinstance(source_rows, list) or not source_rows:
            raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_REFS_MISSING")
        sources_by_ref: dict[str, dict[str, str]] = {}
        for row in source_rows:
            if not isinstance(row, dict):
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_REF_INVALID")
            ref = row.get("path")
            expected = row.get("sha256")
            if not self._safe_repo_path(ref) or not isinstance(expected, str) or len(expected) != 64:
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_REF_INVALID", str(ref))
            if ref in sources_by_ref:
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_REF_DUPLICATE", ref)
            path = (self.repo_root / ref).resolve()
            self._within(path, source_root, "PROFILE_TASK_BINDING_SOURCE_PATH_ESCAPE")
            if not path.is_file():
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_MISSING", ref)
            raw = path.read_bytes()
            actual = _sha256_bytes(raw)
            if actual != expected:
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_SHA_MISMATCH", ref)
            try:
                content = raw.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_NOT_UTF8", ref) from exc
            if not content:
                raise RepositoryError("PROFILE_TASK_BINDING_SOURCE_EMPTY", ref)
            sources_by_ref[ref] = {"ref": ref, "content": content, "sha256": actual}

        schema_cfg = binding.get("runtime_schema")
        if not isinstance(schema_cfg, dict) or schema_cfg.get("selection_mode") != "EXACT_REF":
            raise RepositoryError("PROFILE_TASK_BINDING_SCHEMA_UNRESOLVED")
        schema_ref = schema_cfg.get("ref")
        schema_sha = schema_cfg.get("sha256")
        schema_source = sources_by_ref.get(schema_ref)
        if schema_source is None or schema_source.get("sha256") != schema_sha:
            raise RepositoryError("PROFILE_TASK_BINDING_SCHEMA_SHA_MISMATCH")
        try:
            schema_payload = json.loads(schema_source["content"])
        except json.JSONDecodeError as exc:
            raise RepositoryError("PROFILE_TASK_BINDING_SCHEMA_INVALID_JSON", str(schema_ref)) from exc
        if not isinstance(schema_payload, dict):
            raise RepositoryError("PROFILE_TASK_BINDING_SCHEMA_ROOT_INVALID", str(schema_ref))
        schema = SchemaBinding(
            payload=schema_payload,
            raw=schema_source["content"].encode("utf-8"),
            sha256=str(schema_sha),
            source_refs=(str(schema_ref),),
            mode="TASK_BOUND_EXACT_REF",
        )

        validator_cfg = binding.get("deterministic_validator")
        if not isinstance(validator_cfg, dict):
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_UNRESOLVED")
        validator_ref = validator_cfg.get("ref")
        validator_sha = validator_cfg.get("sha256")
        invocation = validator_cfg.get("invocation")
        callable_name = validator_cfg.get("callable")
        validator_source = sources_by_ref.get(validator_ref)
        if validator_source is None or validator_source.get("sha256") != validator_sha:
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_SHA_MISMATCH")
        if invocation not in {"CLI", "PYTHON_CALLABLE"}:
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_INVOCATION_INVALID")
        if invocation == "PYTHON_CALLABLE" and (not isinstance(callable_name, str) or not callable_name.strip()):
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_CALLABLE_MISSING")
        validator = TaskValidatorBinding(
            ref=str(validator_ref),
            sha256=str(validator_sha),
            invocation=str(invocation),
            callable_name=str(callable_name) if isinstance(callable_name, str) else None,
        )

        judge_cfg = binding.get("judge_binding")
        if not isinstance(judge_cfg, dict) or judge_cfg.get("worker_must_not_execute_own_judge") is not True:
            raise RepositoryError("PROFILE_TASK_BINDING_JUDGE_UNRESOLVED")
        judge_ref = judge_cfg.get("ref")
        judge_sha = judge_cfg.get("sha256")
        judge_code = judge_cfg.get("judge_code")
        judge_source = sources_by_ref.get(judge_ref)
        if judge_source is None or judge_source.get("sha256") != judge_sha or not isinstance(judge_code, str) or not judge_code:
            raise RepositoryError("PROFILE_TASK_BINDING_JUDGE_SHA_MISMATCH")
        judge = TaskJudgeBinding(judge_code=judge_code, ref=str(judge_ref), sha256=str(judge_sha))

        context_cfg = binding.get("model_context")
        if not isinstance(context_cfg, dict):
            raise RepositoryError("PROFILE_TASK_BINDING_MODEL_CONTEXT_INVALID")
        context_refs = context_cfg.get("source_refs")
        max_chars = context_cfg.get("max_chars")
        if not isinstance(context_refs, list) or not isinstance(max_chars, int) or max_chars < 1:
            raise RepositoryError("PROFILE_TASK_BINDING_MODEL_CONTEXT_INVALID")
        if max_chars > self.max_prompt_chars:
            raise RepositoryError("PROFILE_TASK_BINDING_MODEL_CONTEXT_POLICY_EXCEEDED", str(max_chars))
        total_chars = 0
        profile_sources: list[dict[str, str]] = []
        for ref in context_refs:
            source = sources_by_ref.get(ref)
            if source is None:
                raise RepositoryError("PROFILE_TASK_BINDING_MODEL_CONTEXT_REF_UNRESOLVED", str(ref))
            total_chars += len(source["content"])
            if total_chars > max_chars:
                raise RepositoryError("PROFILE_TASK_BINDING_MODEL_CONTEXT_BUDGET_EXCEEDED", str(total_chars))
            profile_sources.append({"ref": source["ref"], "content": source["content"]})

        for field in ("profile_code", "profile_slug", "step_id", "worker_role", "source_revision"):
            value = binding.get(field)
            if not isinstance(value, str) or not value.strip():
                raise RepositoryError("PROFILE_TASK_BINDING_IDENTITY_INCOMPLETE", field)

        return TaskRuntimeMaterialization(
            profile_code=binding["profile_code"],
            profile_slug=binding["profile_slug"],
            step_id=binding["step_id"],
            worker_role=binding["worker_role"],
            source_mode=source_mode,
            source_root=source_root_raw,
            source_revision=binding["source_revision"],
            profile_sources=tuple(profile_sources),
            schema=schema,
            validator=validator,
            judge=judge,
            binding_digest=digest,
            model_context_refs=tuple(context_refs),
            model_context_chars=total_chars,
        )

    def load_callable_validator(self, materialized: TaskRuntimeMaterialization) -> tuple[ModuleType, str]:
        if materialized.validator.invocation != "PYTHON_CALLABLE" or not materialized.validator.callable_name:
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_NOT_CALLABLE")
        path = (self.repo_root / materialized.validator.ref).resolve()
        source_root = (self.repo_root / materialized.source_root).resolve()
        self._within(path, source_root, "PROFILE_TASK_BINDING_VALIDATOR_PATH_ESCAPE")
        spec = importlib.util.spec_from_file_location(
            f"lf_profile_task_validator_{materialized.binding_digest[:16]}", path
        )
        if spec is None or spec.loader is None:
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_IMPORT_FAILED", materialized.validator.ref)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        candidate = getattr(module, materialized.validator.callable_name, None)
        if not callable(candidate):
            raise RepositoryError("PROFILE_TASK_BINDING_VALIDATOR_CALLABLE_MISSING", materialized.validator.callable_name)
        return module, materialized.validator.callable_name

    @staticmethod
    def _safe_repo_path(value: Any) -> bool:
        if not isinstance(value, str) or not value.strip():
            return False
        pure = PurePosixPath(value)
        return not pure.is_absolute() and ".." not in pure.parts and "." not in pure.parts

    @staticmethod
    def _within(path: Path, root: Path, code: str) -> None:
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise RepositoryError(code, str(path)) from exc

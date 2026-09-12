from __future__ import annotations

import importlib.util
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any

from .hashing import sha256_bytes

UI_RUNTIME_SCHEMA_BY_MODE = {
    "UI_FOCUSED_DECISION": "ui_focused_decision.schema.json",
    "UI_PRODUCTION_SPEC": "ui_production_spec.schema.json",
    "UI_MISSING_INPUT": "ui_missing_input.schema.json",
}


class RepositoryError(ValueError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


@dataclass(frozen=True)
class SchemaBinding:
    payload: dict[str, Any]
    raw: bytes
    sha256: str
    source_refs: tuple[str, ...]
    mode: str = "AUTO"


@dataclass(frozen=True)
class RuntimeProfileBinding:
    profile_slug: str
    profile_code: str
    default_schema: str
    output_modes: dict[str, str]
    canonical_validator_path: str
    canonical_validator_callable: str
    semantic_utility_path: str
    semantic_utility_callable: str
    governance: dict[str, Any]
    source_ref: str


class RepositoryBindings:
    def __init__(self, repo_root: Path, *, max_prompt_chars: int) -> None:
        self.repo_root = repo_root.resolve()
        self.max_prompt_chars = max_prompt_chars
        self.profiles_root = (self.repo_root / "profiles").resolve()

    def validate(self) -> None:
        required = (
            self.profiles_root,
            self.repo_root
            / "sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_runner.py",
            self.repo_root
            / (
                "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/"
                "structural_context_resolver_v3.py"
            ),
        )
        for path in required:
            if not path.exists():
                raise RepositoryError("REPOSITORY_RUNTIME_BINDING_MISSING", str(path))

    def profile_sources(
        self, profile_slug: str, paths: list[str]
    ) -> list[dict[str, str]]:
        if not paths:
            raise RepositoryError("PROFILE_SOURCE_PATHS_MISSING")
        profile_root = (self.profiles_root / profile_slug).resolve()
        self._within(profile_root, self.profiles_root, "PROFILE_ROOT_PATH_ESCAPE")
        if not profile_root.is_dir():
            raise RepositoryError("PROFILE_ROOT_MISSING", profile_slug)
        sources: list[dict[str, str]] = []
        seen: set[str] = set()
        total_chars = 0
        for raw_path in paths:
            pure = PurePosixPath(raw_path)
            normalized = pure.as_posix()
            if (
                pure.is_absolute()
                or ".." in pure.parts
                or not normalized.startswith(f"profiles/{profile_slug}/")
            ):
                raise RepositoryError("PROFILE_SOURCE_PATH_OUT_OF_SCOPE", normalized)
            if normalized in seen:
                raise RepositoryError("PROFILE_SOURCE_PATH_DUPLICATE", normalized)
            seen.add(normalized)
            path = (self.repo_root / normalized).resolve()
            self._within(path, profile_root, "PROFILE_SOURCE_PATH_ESCAPE")
            if not path.is_file():
                raise RepositoryError("PROFILE_SOURCE_MISSING", normalized)
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as exc:
                raise RepositoryError("PROFILE_SOURCE_READ_FAILED", normalized) from exc
            if not content:
                raise RepositoryError("PROFILE_SOURCE_EMPTY", normalized)
            total_chars += len(content)
            if total_chars > self.max_prompt_chars:
                raise RepositoryError("PROFILE_SOURCE_CONTEXT_BUDGET_EXCEEDED", str(total_chars))
            sources.append({"ref": normalized, "content": content})
        return sorted(sources, key=lambda item: item["ref"])

    def runtime_binding(self, profile_slug: str) -> RuntimeProfileBinding | None:
        profile_root = (self.profiles_root / profile_slug).resolve()
        self._within(profile_root, self.profiles_root, "PROFILE_ROOT_PATH_ESCAPE")
        path = profile_root / "contracts/runtime_binding.json"
        if not path.exists():
            return None
        self._within(path.resolve(), profile_root, "PROFILE_RUNTIME_BINDING_PATH_ESCAPE")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RepositoryError("PROFILE_RUNTIME_BINDING_INVALID_JSON", profile_slug) from exc
        if not isinstance(payload, dict) or payload.get("schema") != "LF_PROFILE_RUNTIME_BINDING_V1":
            raise RepositoryError("PROFILE_RUNTIME_BINDING_SCHEMA_INVALID", profile_slug)
        if payload.get("profile_slug") != profile_slug:
            raise RepositoryError("PROFILE_RUNTIME_BINDING_SLUG_MISMATCH", profile_slug)
        profile_code = payload.get("profile_code")
        runtime_schema = payload.get("runtime_schema")
        canonical = payload.get("canonical_validator")
        semantic = payload.get("semantic_utility")
        governance = payload.get("governance")
        if not isinstance(profile_code, str) or not profile_code:
            raise RepositoryError("PROFILE_RUNTIME_BINDING_CODE_INVALID", profile_slug)
        if not isinstance(runtime_schema, dict) or not isinstance(runtime_schema.get("default"), str) or not isinstance(runtime_schema.get("output_modes"), dict):
            raise RepositoryError("PROFILE_RUNTIME_BINDING_SCHEMA_CONFIG_INVALID", profile_slug)
        if not isinstance(canonical, dict) or not all(isinstance(canonical.get(k), str) and canonical.get(k) for k in ("path", "callable")):
            raise RepositoryError("PROFILE_RUNTIME_BINDING_VALIDATOR_INVALID", profile_slug)
        if not isinstance(semantic, dict) or not all(isinstance(semantic.get(k), str) and semantic.get(k) for k in ("path", "callable")):
            raise RepositoryError("PROFILE_RUNTIME_BINDING_SEMANTIC_UTILITY_INVALID", profile_slug)
        if not isinstance(governance, dict):
            raise RepositoryError("PROFILE_RUNTIME_BINDING_GOVERNANCE_INVALID", profile_slug)
        expected = {
            "source_first_required": True,
            "schema_invention_allowed": False,
            "fail_closed": True,
            "exact_head_evidence_required": True,
            "post_update_baseline_required": True,
        }
        if any(governance.get(k) is not v for k, v in expected.items()):
            raise RepositoryError("PROFILE_RUNTIME_BINDING_GOVERNANCE_WEAK", profile_slug)
        refs = [runtime_schema["default"], *runtime_schema["output_modes"].values(), canonical["path"], semantic["path"]]
        for rel in refs:
            if not isinstance(rel, str) or not rel or rel.startswith("/") or ".." in PurePosixPath(rel).parts:
                raise RepositoryError("PROFILE_RUNTIME_BINDING_REF_INVALID", str(rel))
            resolved = (profile_root / rel).resolve()
            self._within(resolved, profile_root, "PROFILE_RUNTIME_BINDING_REF_ESCAPE")
            if not resolved.is_file():
                raise RepositoryError("PROFILE_RUNTIME_BINDING_REF_MISSING", rel)
        return RuntimeProfileBinding(
            profile_slug=profile_slug,
            profile_code=profile_code,
            default_schema=runtime_schema["default"],
            output_modes=dict(runtime_schema["output_modes"]),
            canonical_validator_path=canonical["path"],
            canonical_validator_callable=canonical["callable"],
            semantic_utility_path=semantic["path"],
            semantic_utility_callable=semantic["callable"],
            governance=dict(governance),
            source_ref=str(path.relative_to(self.repo_root)),
        )

    def validate_profile_identity(self, profile_slug: str, profile_code: str) -> None:
        binding = self.runtime_binding(profile_slug)
        if binding is not None and profile_code != binding.profile_code:
            raise RepositoryError("PROFILE_RUNTIME_IDENTITY_BINDING_MISMATCH", profile_slug)

    def runtime_schema(self, profile_slug: str, output_mode: str = "AUTO") -> SchemaBinding:
        profile_root = (self.profiles_root / profile_slug).resolve()
        self._within(profile_root, self.profiles_root, "PROFILE_ROOT_PATH_ESCAPE")
        schema_root = (profile_root / "schemas").resolve()
        self._within(schema_root, profile_root, "PROFILE_SCHEMA_PATH_ESCAPE")
        if not schema_root.is_dir():
            raise RepositoryError("PROFILE_RUNTIME_SCHEMA_MISSING", profile_slug)

        binding = self.runtime_binding(profile_slug)
        if binding is not None:
            relative = binding.default_schema if output_mode == "AUTO" else binding.output_modes.get(output_mode)
            if not relative:
                raise RepositoryError("RUNTIME_OUTPUT_MODE_UNSUPPORTED", output_mode)
            selected = (profile_root / relative).resolve()
            self._within(selected, schema_root, "PROFILE_SCHEMA_PATH_ESCAPE")
            payload, raw = self._read_schema(selected, schema_root)
            refs = (str(selected.relative_to(self.repo_root)),)
        elif output_mode != "AUTO":
            if profile_slug != "ui_architect":
                raise RepositoryError("RUNTIME_OUTPUT_MODE_PROFILE_MISMATCH", profile_slug)
            filename = UI_RUNTIME_SCHEMA_BY_MODE.get(output_mode)
            if filename is None:
                raise RepositoryError("RUNTIME_OUTPUT_MODE_UNSUPPORTED", output_mode)
            selected = schema_root / filename
            payload, raw = self._read_schema(selected, schema_root)
            refs = (str(selected.relative_to(self.repo_root)),)
        else:
            explicit = schema_root / "runtime_output.schema.json"
            if explicit.exists() or explicit.is_symlink():
                payload, raw = self._read_schema(explicit, schema_root)
                refs = (str(explicit.relative_to(self.repo_root)),)
            else:
                candidates = sorted(
                    path
                    for path in schema_root.glob("*.schema.json")
                    if path.name != "runtime_output.schema.json"
                )
                if not candidates:
                    raise RepositoryError("PROFILE_RUNTIME_SCHEMA_MISSING", profile_slug)
                if len(candidates) > 1:
                    raise RepositoryError(
                        "PROFILE_RUNTIME_SCHEMA_AMBIGUOUS",
                        ",".join(str(path.relative_to(self.repo_root)) for path in candidates),
                    )
                selected = candidates[0]
                payload, raw = self._read_schema(selected, schema_root)
                refs = (str(selected.relative_to(self.repo_root)),)
        return SchemaBinding(
            payload=payload,
            raw=raw,
            sha256=sha256_bytes(raw),
            source_refs=refs,
            mode=output_mode,
        )


    def load_runtime_runner(self) -> ModuleType:
        runtime_dir = self.repo_root / "sandbox/lf_contract_gate_test/profile_execution_runtime"
        return self._load_with_siblings(
            runtime_dir / "profile_runtime_runner.py",
            runtime_dir,
            "lf_profile_runtime_runner",
        )

    def load_ui_composer_boundary(self) -> ModuleType:
        return self._load_file(
            self.repo_root / "profiles/ui_architect/validators/validate_composer_payload_boundary.py",
            "lf_ui_composer_payload_boundary",
        )

    def load_validator(self, profile_slug: str) -> ModuleType | None:
        binding = self.runtime_binding(profile_slug)
        if binding is not None:
            return self._load_file(
                self.profiles_root / profile_slug / binding.canonical_validator_path,
                f"lf_profile_validator_{profile_slug}",
            )
        mapping = {
            "product_director_lf": "profiles/product_director_lf/validators/validate_product_director_output.py",
            "ui_architect": "profiles/ui_architect/validators/validate_ui_architect_output.py",
            "quality_pack": "profiles/quality_pack/validators/validate_routing.py",
        }
        relative = mapping.get(profile_slug)
        if not relative:
            return None
        return self._load_file(self.repo_root / relative, f"lf_profile_validator_{profile_slug}")

    def validator_callable_name(self, profile_slug: str) -> str | None:
        binding = self.runtime_binding(profile_slug)
        return binding.canonical_validator_callable if binding is not None else None

    def load_semantic_utility(self, profile_slug: str) -> tuple[ModuleType, str] | None:
        binding = self.runtime_binding(profile_slug)
        if binding is None:
            return None
        module = self._load_file(
            self.profiles_root / profile_slug / binding.semantic_utility_path,
            f"lf_profile_semantic_utility_{profile_slug}",
        )
        return module, binding.semantic_utility_callable

    @staticmethod
    def _load_file(path: Path, module_name: str) -> ModuleType:
        if not path.is_file():
            raise RepositoryError("REPOSITORY_MODULE_MISSING", str(path))
        spec = importlib.util.spec_from_file_location(module_name, path)
        if spec is None or spec.loader is None:
            raise RepositoryError("REPOSITORY_MODULE_SPEC_INVALID", str(path))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    @staticmethod
    def _load_with_siblings(path: Path, sibling_dir: Path, module_name: str) -> ModuleType:
        import sys

        raw = str(sibling_dir.resolve())
        if raw not in sys.path:
            sys.path.insert(0, raw)
        return RepositoryBindings._load_file(path, module_name)

    @staticmethod
    def _read_schema(path: Path, root: Path) -> tuple[dict[str, Any], bytes]:
        resolved = path.resolve()
        RepositoryBindings._within(resolved, root, "PROFILE_SCHEMA_PATH_ESCAPE")
        if not resolved.is_file():
            raise RepositoryError("PROFILE_RUNTIME_SCHEMA_INVALID", path.name)
        try:
            raw = resolved.read_bytes()
            payload = json.loads(raw.decode("utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RepositoryError("PROFILE_RUNTIME_SCHEMA_INVALID_JSON", path.name) from exc
        if not isinstance(payload, dict):
            raise RepositoryError("PROFILE_RUNTIME_SCHEMA_NOT_OBJECT", path.name)
        return payload, raw

    @staticmethod
    def _within(path: Path, root: Path, code: str) -> None:
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise RepositoryError(code, str(path)) from exc

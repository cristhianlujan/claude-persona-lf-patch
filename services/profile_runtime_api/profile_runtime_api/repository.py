from __future__ import annotations

import importlib.util
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any

from .hashing import sha256_bytes


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

    def runtime_schema(self, profile_slug: str) -> SchemaBinding:
        profile_root = (self.profiles_root / profile_slug).resolve()
        self._within(profile_root, self.profiles_root, "PROFILE_ROOT_PATH_ESCAPE")
        schema_root = (profile_root / "schemas").resolve()
        self._within(schema_root, profile_root, "PROFILE_SCHEMA_PATH_ESCAPE")
        if not schema_root.is_dir():
            raise RepositoryError("PROFILE_RUNTIME_SCHEMA_MISSING", profile_slug)

        explicit = schema_root / "runtime_output.schema.json"
        if explicit.exists() or explicit.is_symlink():
            payload, raw = self._read_schema(explicit, schema_root)
            refs = (str(explicit.relative_to(self.repo_root)),)
        else:
            candidates = sorted(
                path for path in schema_root.glob("*.schema.json")
                if path.name != "runtime_output.schema.json"
            )
            if not candidates:
                raise RepositoryError("PROFILE_RUNTIME_SCHEMA_MISSING", profile_slug)
            parsed = [self._read_schema(path, schema_root)[0] for path in candidates]
            payload = parsed[0] if len(parsed) == 1 else {
                "$schema": "https://json-schema.org/draft/2020-12/schema",
                "anyOf": parsed,
                "x-lf-runtime-schema-source": [path.name for path in candidates],
            }
            raw = (
                json.dumps(
                    payload,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            ).encode("utf-8")
            refs = tuple(str(path.relative_to(self.repo_root)) for path in candidates)
        return SchemaBinding(
            payload=payload,
            raw=raw,
            sha256=sha256_bytes(raw),
            source_refs=refs,
        )

    def load_runtime_runner(self) -> ModuleType:
        runtime_dir = self.repo_root / "sandbox/lf_contract_gate_test/profile_execution_runtime"
        return self._load_with_siblings(
            runtime_dir / "profile_runtime_runner.py",
            runtime_dir,
            "lf_profile_runtime_runner",
        )

    def load_validator(self, profile_slug: str) -> ModuleType | None:
        mapping = {
            "product_director_lf": (
                "profiles/product_director_lf/validators/"
                "validate_product_director_output.py"
            ),
            "ui_architect": "profiles/ui_architect/validators/validate_ui_architect_output.py",
            "quality_pack": "profiles/quality_pack/validators/validate_routing.py",
        }
        relative = mapping.get(profile_slug)
        if not relative:
            return None
        path = self.repo_root / relative
        return self._load_file(path, f"lf_profile_validator_{profile_slug}")

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

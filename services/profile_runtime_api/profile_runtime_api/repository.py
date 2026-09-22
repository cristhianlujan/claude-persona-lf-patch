from __future__ import annotations

import copy
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
    model_context: dict[str, Any] | None = None
    execution_partition: dict[str, Any] | None = None
    execution_budget: dict[str, Any] | None = None
    canonical_quality: dict[str, Any] | None = None
    research_execution: dict[str, Any] | None = None


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
        binding = self.runtime_binding(profile_slug)
        if binding is not None and isinstance(binding.model_context, dict):
            required_refs = set(binding.model_context.get("required_source_refs") or [])
            supplied_refs = set(paths)
            missing = sorted(required_refs - supplied_refs)
            if missing:
                raise RepositoryError(
                    "PROFILE_RUNTIME_REQUIRED_SOURCE_MISSING", ",".join(missing)
                )
            if binding.model_context.get("allow_additional_sources") is False:
                extra = sorted(supplied_refs - required_refs)
                if extra:
                    raise RepositoryError(
                        "PROFILE_RUNTIME_UNDECLARED_SOURCE_FORBIDDEN", ",".join(extra)
                    )
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
        model_context = payload.get("model_context")
        execution_partition = payload.get("execution_partition")
        execution_budget = payload.get("execution_budget")
        canonical_quality = payload.get("canonical_quality")
        research_execution = payload.get("research_execution")
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
        if model_context is not None:
            projection = model_context.get("source_projection") if isinstance(model_context, dict) else None
            required_source_refs = (
                model_context.get("required_source_refs")
                if isinstance(model_context, dict)
                else None
            )
            allow_additional_sources = (
                model_context.get("allow_additional_sources")
                if isinstance(model_context, dict)
                else None
            )
            if (
                not isinstance(model_context, dict)
                or model_context.get("full_source_to_model") is not False
                or not isinstance(required_source_refs, list)
                or not required_source_refs
                or len(required_source_refs) != len(set(required_source_refs))
                or any(
                    not isinstance(value, str)
                    or not value.startswith(f"profiles/{profile_slug}/")
                    or ".." in PurePosixPath(value).parts
                    for value in required_source_refs
                )
                or not isinstance(allow_additional_sources, bool)
                or not isinstance(projection, dict)
                or projection.get("mode") != "MARKDOWN_SECTIONS"
                or not isinstance(projection.get("include_sections"), list)
                or not projection["include_sections"]
                or any(not isinstance(v, str) or not v.strip() for v in projection["include_sections"])
                or not isinstance(projection.get("max_chars"), int)
                or projection["max_chars"] < 256
            ):
                raise RepositoryError("PROFILE_RUNTIME_MODEL_CONTEXT_INVALID", profile_slug)
        if execution_partition is not None:
            classes = execution_partition.get("field_classes") if isinstance(execution_partition, dict) else None
            materialization = execution_partition.get("deterministic_materialization") if isinstance(execution_partition, dict) else None
            limits = execution_partition.get("generation_limits") if isinstance(execution_partition, dict) else None
            if (
                not isinstance(execution_partition, dict)
                or execution_partition.get("schema") != "LF_PROFILE_EXECUTION_PARTITION_V1"
                or not isinstance(classes, dict)
                or not classes
                or any(v not in {"DETERMINISTIC", "SEMANTIC", "HYBRID"} for v in classes.values())
                or not isinstance(materialization, dict)
                or not isinstance(limits, dict)
            ):
                raise RepositoryError("PROFILE_RUNTIME_EXECUTION_PARTITION_INVALID", profile_slug)
            deterministic = {k for k, v in classes.items() if v == "DETERMINISTIC"}
            if deterministic != set(materialization):
                raise RepositoryError("PROFILE_RUNTIME_DETERMINISTIC_MATERIALIZATION_MISMATCH", profile_slug)
            for field, spec in materialization.items():
                if not isinstance(spec, dict) or spec.get("source") not in {"literal", "profile_code", "profile_slug"}:
                    raise RepositoryError("PROFILE_RUNTIME_DETERMINISTIC_MATERIALIZATION_INVALID", field)
                if spec.get("source") == "literal" and "value" not in spec:
                    raise RepositoryError("PROFILE_RUNTIME_DETERMINISTIC_LITERAL_MISSING", field)
        if canonical_quality is not None:
            if not isinstance(canonical_quality, dict):
                raise RepositoryError("PROFILE_RUNTIME_CANONICAL_QUALITY_INVALID", profile_slug)
            required_packs = canonical_quality.get("required_for_profile_pack_ids")
            semantic_result_validator = canonical_quality.get("semantic_result_validator")
            quality_receipt_validator = canonical_quality.get("quality_receipt_validator")
            quality_receipt_materializer = canonical_quality.get("quality_receipt_materializer")
            quality_refs = (
                canonical_quality.get("judge_path"),
                canonical_quality.get("semantic_judge_path"),
                canonical_quality.get("quality_receipt_schema"),
                semantic_result_validator.get("path") if isinstance(semantic_result_validator, dict) else None,
                quality_receipt_validator.get("path") if isinstance(quality_receipt_validator, dict) else None,
                quality_receipt_materializer.get("path") if isinstance(quality_receipt_materializer, dict) else None,
            )
            if (
                not isinstance(required_packs, list)
                or not required_packs
                or any(not isinstance(value, str) or not value.strip() for value in required_packs)
                or len(required_packs) != len(set(required_packs))
                or canonical_quality.get("deterministic_floors_can_accept_quality") is not False
                or canonical_quality.get("receipt_required_for_pass_to_quality_pack") is not True
                or not isinstance(semantic_result_validator, dict)
                or not all(
                    isinstance(semantic_result_validator.get(key), str)
                    and semantic_result_validator.get(key)
                    for key in ("path", "callable")
                )
                or not isinstance(quality_receipt_validator, dict)
                or not all(
                    isinstance(quality_receipt_validator.get(key), str)
                    and quality_receipt_validator.get(key)
                    for key in ("path", "callable")
                )
                or not isinstance(quality_receipt_materializer, dict)
                or not all(
                    isinstance(quality_receipt_materializer.get(key), str)
                    and quality_receipt_materializer.get(key)
                    for key in ("path", "callable")
                )
                or any(not isinstance(value, str) or not value for value in quality_refs)
            ):
                raise RepositoryError("PROFILE_RUNTIME_CANONICAL_QUALITY_INVALID", profile_slug)
        if research_execution is not None:
            if (
                not isinstance(research_execution, dict)
                or research_execution.get("mode") != "EXTERNAL_AUTHORITY_RESOLVER"
                or research_execution.get("requires_evidence_manifest") is not True
                or research_execution.get("requires_query_trace") is not True
                or research_execution.get("requires_resolved_authority_context") is not True
                or not isinstance(research_execution.get("resolver_ref"), str)
                or not research_execution.get("resolver_ref")
            ):
                raise RepositoryError("PROFILE_RUNTIME_RESEARCH_EXECUTION_INVALID", profile_slug)
        if execution_budget is not None:
            if (
                not isinstance(execution_budget, dict)
                or execution_budget.get("resource_class") not in {"STANDARD", "HEAVY_SEMANTIC"}
                or not isinstance(execution_budget.get("max_prompt_tokens"), int)
                or execution_budget.get("max_prompt_tokens") <= 0
                or not isinstance(execution_budget.get("max_output_tokens"), int)
                or execution_budget.get("max_output_tokens") <= 0
                or not isinstance(execution_budget.get("min_available_memory_mb"), int)
                or execution_budget.get("min_available_memory_mb") < 0
                or not isinstance(execution_budget.get("max_swap_used_pct"), (int, float))
                or not 0 <= execution_budget.get("max_swap_used_pct") <= 100
            ):
                raise RepositoryError("PROFILE_RUNTIME_EXECUTION_BUDGET_INVALID", profile_slug)
        refs = [runtime_schema["default"], *runtime_schema["output_modes"].values(), canonical["path"], semantic["path"]]
        if isinstance(canonical_quality, dict):
            refs.extend([
                canonical_quality["judge_path"],
                canonical_quality["semantic_judge_path"],
                canonical_quality["semantic_result_validator"]["path"],
                canonical_quality["quality_receipt_schema"],
                canonical_quality["quality_receipt_validator"]["path"],
                canonical_quality["quality_receipt_materializer"]["path"],
            ])
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
            model_context=dict(model_context) if isinstance(model_context, dict) else None,
            execution_partition=dict(execution_partition) if isinstance(execution_partition, dict) else None,
            execution_budget=dict(execution_budget) if isinstance(execution_budget, dict) else None,
            canonical_quality=copy.deepcopy(canonical_quality) if isinstance(canonical_quality, dict) else None,
            research_execution=copy.deepcopy(research_execution) if isinstance(research_execution, dict) else None,
        )



    @staticmethod
    def _markdown_section_projection(content: str, include_sections: list[str]) -> str:
        wanted = {item.strip() for item in include_sections}
        sections: dict[str, list[str]] = {}
        current: str | None = None
        for line in content.splitlines():
            if line.startswith("## "):
                current = line[3:].strip()
                sections.setdefault(current, [line])
            elif current is not None:
                sections[current].append(line)
        missing = [name for name in include_sections if name not in sections]
        if missing:
            raise RepositoryError("PROFILE_RUNTIME_MODEL_CONTEXT_SECTION_MISSING", ",".join(missing))
        chunks = ["\n".join(sections[name]).strip() for name in include_sections]
        return "\n\n".join(chunks).strip() + "\n"

    def profile_model_sources(
        self, profile_slug: str, canonical_sources: list[dict[str, str]]
    ) -> list[dict[str, str]]:
        binding = self.runtime_binding(profile_slug)
        if binding is None or binding.model_context is None:
            return [dict(item) for item in canonical_sources]
        projection = binding.model_context["source_projection"]
        out: list[dict[str, str]] = []
        total_chars = 0
        for item in canonical_sources:
            content = item["content"]
            if item["ref"].endswith("/SKILL.md"):
                content = self._markdown_section_projection(
                    content, list(projection["include_sections"])
                )
            total_chars += len(content)
            if total_chars > int(projection["max_chars"]):
                raise RepositoryError(
                    "PROFILE_RUNTIME_MODEL_CONTEXT_BUDGET_EXCEEDED", str(total_chars)
                )
            out.append({"ref": item["ref"], "content": content})
        return out

    def model_generation_schema(
        self, profile_slug: str, canonical_schema: dict[str, Any]
    ) -> dict[str, Any]:
        binding = self.runtime_binding(profile_slug)
        if binding is None or binding.execution_partition is None:
            return copy.deepcopy(canonical_schema)
        partition = binding.execution_partition
        classes = partition["field_classes"]
        properties = canonical_schema.get("properties")
        required = canonical_schema.get("required")
        if not isinstance(properties, dict) or not isinstance(required, list):
            raise RepositoryError("PROFILE_RUNTIME_CANONICAL_ROOT_SCHEMA_INVALID", profile_slug)
        if set(classes) != set(properties):
            raise RepositoryError("PROFILE_RUNTIME_PARTITION_SCHEMA_FIELD_MISMATCH", profile_slug)
        model_fields = {k for k, v in classes.items() if v != "DETERMINISTIC"}
        schema = copy.deepcopy(canonical_schema)
        schema["properties"] = {k: v for k, v in schema["properties"].items() if k in model_fields}
        schema["required"] = [k for k in required if k in model_fields]
        limits = partition.get("generation_limits") or {}
        default_max = limits.get("default_string_max_length")
        if isinstance(default_max, int) and default_max > 0:
            def apply_default(node: Any) -> None:
                if isinstance(node, dict):
                    if node.get("type") == "string" and "maxLength" not in node:
                        node["maxLength"] = default_max
                    for value in node.values():
                        apply_default(value)
                elif isinstance(node, list):
                    for value in node:
                        apply_default(value)
            apply_default(schema)
        field_limits = limits.get("fields") or {}
        if not isinstance(field_limits, dict):
            raise RepositoryError("PROFILE_RUNTIME_GENERATION_LIMITS_INVALID", profile_slug)
        for field, cfg in field_limits.items():
            if field not in schema["properties"] or not isinstance(cfg, dict):
                raise RepositoryError("PROFILE_RUNTIME_GENERATION_LIMIT_FIELD_INVALID", str(field))
            for key in ("maxItems", "maxLength"):
                if key in cfg:
                    value = cfg[key]
                    if not isinstance(value, int) or value < 1:
                        raise RepositoryError("PROFILE_RUNTIME_GENERATION_LIMIT_INVALID", f"{field}:{key}")
                    schema["properties"][field][key] = value
        return schema

    def materialize_partitioned_output(
        self, profile_slug: str, model_payload: dict[str, Any]
    ) -> tuple[dict[str, Any], list[str]]:
        binding = self.runtime_binding(profile_slug)
        if binding is None or binding.execution_partition is None:
            return dict(model_payload), []
        classes = binding.execution_partition["field_classes"]
        deterministic = {k for k, v in classes.items() if v == "DETERMINISTIC"}
        leaked = sorted(deterministic & set(model_payload))
        if leaked:
            raise RepositoryError("PROFILE_RUNTIME_MODEL_EMITTED_DETERMINISTIC_FIELDS", ",".join(leaked))
        out = dict(model_payload)
        added: list[str] = []
        for field, spec in binding.execution_partition["deterministic_materialization"].items():
            source = spec["source"]
            if source == "literal":
                value = copy.deepcopy(spec["value"])
            elif source == "profile_code":
                value = binding.profile_code
            elif source == "profile_slug":
                value = binding.profile_slug
            else:
                raise RepositoryError("PROFILE_RUNTIME_DETERMINISTIC_MATERIALIZATION_INVALID", field)
            out[field] = value
            added.append(field)
        return out, sorted(added)

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

    def load_canonical_quality_validator(
        self, profile_slug: str, component: str
    ) -> tuple[ModuleType, str] | None:
        binding = self.runtime_binding(profile_slug)
        quality = binding.canonical_quality if binding is not None else None
        if not isinstance(quality, dict):
            return None
        if component not in {"semantic_result_validator", "quality_receipt_validator", "quality_receipt_materializer"}:
            raise RepositoryError("PROFILE_RUNTIME_CANONICAL_QUALITY_COMPONENT_INVALID", component)
        spec = quality.get(component)
        if not isinstance(spec, dict):
            raise RepositoryError("PROFILE_RUNTIME_CANONICAL_QUALITY_COMPONENT_MISSING", component)
        module = self._load_file(
            self.profiles_root / profile_slug / spec["path"],
            f"lf_profile_{component}_{profile_slug}",
        )
        return module, spec["callable"]

    def canonical_quality_receipt_schema(self, profile_slug: str) -> SchemaBinding | None:
        binding = self.runtime_binding(profile_slug)
        quality = binding.canonical_quality if binding is not None else None
        if not isinstance(quality, dict):
            return None
        profile_root = (self.profiles_root / profile_slug).resolve()
        selected = (profile_root / quality["quality_receipt_schema"]).resolve()
        self._within(selected, profile_root, "PROFILE_RUNTIME_CANONICAL_QUALITY_SCHEMA_ESCAPE")
        payload, raw = self._read_schema(selected, profile_root)
        return SchemaBinding(
            payload=payload,
            raw=raw,
            sha256=sha256_bytes(raw),
            source_refs=(str(selected.relative_to(self.repo_root)),),
            mode="CANONICAL_QUALITY_RECEIPT",
        )

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

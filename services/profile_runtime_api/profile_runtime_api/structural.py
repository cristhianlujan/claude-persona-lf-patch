from __future__ import annotations

import importlib
import json
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .cache import StructuralCache, make_cache_key
from .hashing import canonical_json_sha256
from .models import Artifact, InputGovernanceReceipt
from .settings import Settings

VISIBLE_ROLES = {
    "SHELL_TOPBAR",
    "SHELL_SIDEBAR",
    "BREADCRUMB",
    "PAGE_HEADER",
    "PAGE_ACTIONS",
    "FILTER_BAR",
    "TABLE_SUMMARY",
    "TABLE_HEADER",
    "STATE_BADGE",
    "ROW_ACTION",
    "PAGINATION",
}


class StructuralContextError(RuntimeError):
    def __init__(self, code: str, detail: str | None = None) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}" if detail else code)


@dataclass(frozen=True)
class PreparedContext:
    cache_key: str
    cache_hit: bool
    pack: dict[str, Any]
    prepare_ms: float


class StructuralContextPipeline:
    def __init__(self, settings: Settings, cache: StructuralCache) -> None:
        self.settings = settings
        self.cache = cache
        self.module_root = (
            settings.repo_root
            / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3"
        ).resolve()
        self._modules: dict[str, Any] = {}

    def validate(self) -> None:
        required = (
            "structural_context_resolver_v3.py",
            "build_decomposer_context_pack_v3.py",
            "batched_targeted_reread_v3.py",
            "apply_reread_overlay_v3.py",
        )
        for name in required:
            if not (self.module_root / name).is_file():
                raise StructuralContextError("STRUCTURAL_MODULE_MISSING", name)

    def prepare(
        self, artifact: Artifact, governance: InputGovernanceReceipt
    ) -> PreparedContext:
        started = time.perf_counter()
        key = make_cache_key(
            image_sha=artifact.image_sha256,
            context_sha=governance.context_sha256,
            runtime_version=self.settings.runtime_version,
            resolver_version=self.settings.resolver_version,
        )
        cached = self.cache.get(key)
        if cached is not None:
            cached["pack_sha256"] = canonical_json_sha256(cached)
            cached["downstream_authorized"] = False
            return PreparedContext(
                cache_key=key,
                cache_hit=True,
                pack=cached,
                prepare_ms=round((time.perf_counter() - started) * 1000, 3),
            )
        if not artifact.observations:
            raise StructuralContextError("STRUCTURAL_OBSERVATIONS_REQUIRED_ON_CACHE_MISS")

        resolver = self._module("structural_context_resolver_v3")
        result = resolver.classify(
            [item.model_dump(mode="python") for item in artifact.observations],
            artifact.width_px,
            artifact.height_px,
            governance.context,
        )
        reread_summary: dict[str, Any]
        image = artifact.image_bytes()
        if (
            result.get("residual_count", 0)
            and image is not None
            and self.settings.enable_targeted_reread
        ):
            suffix = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}[
                artifact.image_media_type
            ]
            try:
                with tempfile.TemporaryDirectory(prefix="lf-profile-reread-") as directory:
                    image_path = Path(directory) / f"input{suffix}"
                    image_path.write_bytes(image)
                    reread = self._module("batched_targeted_reread_v3").run(
                        image_path, result.get("residual", [])
                    )
                    result = self._module("apply_reread_overlay_v3").apply_overlay(result, reread)
            except (ImportError, OSError, RuntimeError) as exc:
                raise StructuralContextError("TARGETED_REREAD_FAILED", type(exc).__name__) from exc
            reread_summary = {
                "status": "EXECUTED",
                "regions": len(reread.get("regions", [])),
                "ocr_invocations": reread.get("ocr_invocations"),
                "ocr_ms": reread.get("ocr_ms"),
                "adopted_count": result.get("reread_overlay", {}).get("adopted_count", 0),
                "full_image_model_reread": False,
            }
        elif result.get("residual_count", 0):
            reason = "IMAGE_NOT_SUPPLIED" if image is None else "TARGETED_REREAD_DISABLED"
            reread_summary = {
                "status": "NOT_EXECUTED",
                "reason": reason,
                "regions": result.get("residual_count", 0),
                "full_image_model_reread": False,
            }
        else:
            reread_summary = {
                "status": "NOT_REQUIRED",
                "regions": 0,
                "full_image_model_reread": False,
            }

        try:
            decomposer = self._module("build_decomposer_context_pack_v3").build(
                result,
                artifact.image_sha256,
                governance.context_sha256,
            )
        except ValueError as exc:
            raise StructuralContextError("DECOMPOSER_CONTEXT_PACK_BLOCKED", str(exc)) from exc
        decomposer.pop("profile_contract_valid", None)
        decomposer.pop("semantic_utility", None)
        pack = {
            "schema": "lf-profile-runtime-structural-cache-payload/v1",
            "artifact": {
                "screen_code": artifact.screen_code,
                "filename": artifact.filename,
                "image_sha256": artifact.image_sha256,
                "width_px": artifact.width_px,
                "height_px": artifact.height_px,
            },
            "input_governance": {
                "receipt_ref": governance.receipt_ref,
                "context_sha256": governance.context_sha256,
                "status": governance.status,
                "current": True,
                "ready": True,
            },
            "decomposer_context": decomposer,
            "visible_ui_evidence": self._visible_evidence(result),
            "dynamic_data": {
                "count": int((result.get("counts") or {}).get("DYNAMIC_DATA", 0)),
                "policy": "DYNAMIC_DATA_NOT_CANONICALIZED_OR_EMBEDDED",
            },
            "targeted_reread": reread_summary,
            "resolver_metrics": {
                "input_count": result.get("input_count"),
                "residual_count": result.get("residual_count"),
                "reread_reduction_pct": result.get("reread_reduction_pct"),
                "visible_group_resolutions": result.get("visible_group_resolutions"),
            },
            "data_lineage_policy": "ORIGINAL_EVIDENCE_IMMUTABLE_EFFECTIVE_TEXT_OVERLAY",
            "downstream_authorized": False,
        }
        # Authorization and quality decisions are never cacheable. The explicit
        # false value above is useful to callers but is added only after cache read.
        cache_payload = json.loads(json.dumps(pack))
        cache_payload.pop("downstream_authorized", None)
        self.cache.put(key, cache_payload)
        pack["pack_sha256"] = canonical_json_sha256(cache_payload)
        return PreparedContext(
            cache_key=key,
            cache_hit=False,
            pack=pack,
            prepare_ms=round((time.perf_counter() - started) * 1000, 3),
        )

    @staticmethod
    def _visible_evidence(result: dict[str, Any]) -> list[dict[str, Any]]:
        output: list[dict[str, Any]] = []
        seen: set[tuple[Any, ...]] = set()
        for item in result.get("observations") or []:
            role = item.get("role")
            if role not in VISIBLE_ROLES:
                continue
            text = str(item.get("effective_text") or item.get("text") or "").strip()
            if not text:
                continue
            bbox = [round(float(item.get(key, 0)), 3) for key in ("x", "y", "w", "h")]
            identity = (role, text, *bbox)
            if identity in seen:
                continue
            seen.add(identity)
            output.append(
                {
                    "id": item.get("id"),
                    "role": role,
                    "text": text,
                    "bbox": bbox,
                    "text_source": item.get("effective_text_source", "ORIGINAL_OCR"),
                }
            )
        return output

    def _module(self, name: str) -> Any:
        if name in self._modules:
            return self._modules[name]
        raw = str(self.module_root)
        if raw not in sys.path:
            sys.path.insert(0, raw)
        try:
            module = importlib.import_module(name)
        except ImportError as exc:
            raise StructuralContextError("STRUCTURAL_MODULE_IMPORT_FAILED", name) from exc
        self._modules[name] = module
        return module

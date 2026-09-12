#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any

BASELINE_REL = Path("skills/profile_creator/contracts/s26_profile_baseline_v1.json")
RUNTIME_BINDING_REL = Path("contracts/runtime_binding.json")
PROFILE_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9_]{0,79}$")
PROFILE_CODE_RE = re.compile(r"^[A-Z0-9][A-Z0-9_-]{0,119}$")


def _load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON_ROOT_NOT_OBJECT:{path}")
    return value


def _safe_profile_path(profile_dir: Path, raw: object, *, code: str) -> Path:
    if not isinstance(raw, str) or not raw or raw.startswith("/"):
        raise ValueError(code)
    rel = Path(raw)
    if ".." in rel.parts:
        raise ValueError(code)
    resolved = (profile_dir / rel).resolve()
    try:
        resolved.relative_to(profile_dir.resolve())
    except ValueError as exc:
        raise ValueError(code) from exc
    return resolved


def _callable_exists(path: Path, callable_name: object, *, module_name: str) -> bool:
    if not path.is_file() or not isinstance(callable_name, str) or not callable_name:
        return False
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        return False
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception:
        return False
    return callable(getattr(module, callable_name, None))


def evaluate(repo_root: Path, profile_slug: str) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    baseline = _load_json(repo_root / BASELINE_REL)
    profile_dir = (repo_root / "profiles" / profile_slug).resolve()
    dimensions: dict[str, dict[str, Any]] = {}
    repairs: list[dict[str, Any]] = []
    blockers: list[str] = []

    def set_dim(dim: str, passed: bool, code: str, evidence: Any = None, repair: str | None = None, authority_required: bool = False) -> None:
        dimensions[dim] = {"pass": bool(passed), "code": code, "evidence": evidence}
        if not passed and repair:
            item={"action":repair,"dimension":dim,"authority_required":authority_required}
            if item not in repairs: repairs.append(item)
        if not passed and authority_required:
            blockers.append(code)

    if not PROFILE_SLUG_RE.fullmatch(profile_slug) or not profile_dir.is_dir():
        return {
            "schema":"S26_PROFILE_BASELINE_EVALUATION_V1","profile_slug":profile_slug,
            "decision":"BLOCKED_AUTHORITY_REQUIRED","score":0,"required":10,
            "dimensions":{},"repair_actions":[],"blocking_codes":["PROFILE_TARGET_INVALID"],
            "automatic_impact_authorized":False,"runtime_activation_authorized":False,
        }

    skill = profile_dir / "SKILL.md"
    skill_text = skill.read_text(encoding="utf-8") if skill.is_file() else ""
    set_dim("B01_PROFILE_IDENTITY", skill.is_file(), "PASS" if skill.is_file() else "SKILL_MISSING", str(skill.relative_to(repo_root)) if skill.is_file() else None, "MATERIALIZE_PROFILE_SKILL", True)
    route_sources=[]
    for candidate in [skill, *sorted((profile_dir/'contracts').glob('*.md'))]:
        if candidate.is_file() and "ACTUALIZACION_PERFIL_LF" in candidate.read_text(encoding="utf-8"):
            route_sources.append(str(candidate.relative_to(repo_root)))
    update_route=bool(route_sources)
    set_dim("B02_UPDATE_GOVERNANCE", update_route, "PASS" if update_route else "UPDATE_ROUTE_NOT_DECLARED", route_sources if update_route else None, "DECLARE_GOVERNED_UPDATE_ROUTE")

    binding_path = profile_dir / RUNTIME_BINDING_REL
    binding: dict[str, Any] | None = None
    try:
        if binding_path.is_file(): binding = _load_json(binding_path)
    except Exception:
        binding = None
    valid_binding = bool(binding and binding.get("schema") == "LF_PROFILE_RUNTIME_BINDING_V1" and binding.get("profile_slug") == profile_slug and PROFILE_CODE_RE.fullmatch(str(binding.get("profile_code") or "")))
    set_dim("B03_RUNTIME_BINDING", valid_binding, "PASS" if valid_binding else "RUNTIME_BINDING_MISSING_OR_INVALID", str(binding_path.relative_to(repo_root)) if valid_binding else None, "MATERIALIZE_RUNTIME_BINDING", False)

    schema_pass=False; schema_evidence=None
    validator_pass=False; validator_evidence=None
    semantic_pass=False; semantic_evidence=None
    gov = binding.get("governance") if isinstance(binding, dict) else None
    if valid_binding and isinstance(binding, dict):
        rs=binding.get("runtime_schema")
        default=rs.get("default") if isinstance(rs,dict) else None
        modes=rs.get("output_modes") if isinstance(rs,dict) else None
        try:
            schema_path=_safe_profile_path(profile_dir,default,code="RUNTIME_SCHEMA_PATH_INVALID")
            schema_obj=_load_json(schema_path)
            schema_pass=isinstance(modes,dict) and bool(schema_obj)
            if schema_pass:
                for mode, raw in modes.items():
                    if not isinstance(mode,str) or not mode or not _safe_profile_path(profile_dir,raw,code="RUNTIME_MODE_SCHEMA_PATH_INVALID").is_file():
                        schema_pass=False; break
            schema_evidence=str(schema_path.relative_to(repo_root)) if schema_pass else None
        except Exception:
            schema_pass=False
        cv=binding.get("canonical_validator")
        if isinstance(cv,dict):
            try:
                vp=_safe_profile_path(profile_dir,cv.get("path"),code="CANONICAL_VALIDATOR_PATH_INVALID")
                validator_pass=_callable_exists(vp,cv.get("callable"),module_name=f"lf_s26_baseline_validator_{profile_slug}")
                validator_evidence=str(vp.relative_to(repo_root)) if validator_pass else None
            except Exception: validator_pass=False
        su=binding.get("semantic_utility")
        if isinstance(su,dict):
            try:
                sp=_safe_profile_path(profile_dir,su.get("path"),code="SEMANTIC_UTILITY_PATH_INVALID")
                semantic_pass=_callable_exists(sp,su.get("callable"),module_name=f"lf_s26_baseline_semantic_{profile_slug}")
                semantic_evidence=str(sp.relative_to(repo_root)) if semantic_pass else None
            except Exception: semantic_pass=False
    schema_files=list((profile_dir/'schemas').glob('*.schema.json')) if (profile_dir/'schemas').is_dir() else []
    schema_count=len(schema_files)
    explicit_runtime=(profile_dir/'schemas/runtime_output.schema.json').is_file()
    schema_authority_required=(not valid_binding) and schema_count>1 and not explicit_runtime
    schema_code=(
        "PASS" if schema_pass else
        "RUNTIME_SCHEMA_EXPLICIT_BINDING_REQUIRED" if schema_authority_required else
        "RUNTIME_SCHEMA_DESCRIPTOR_MISSING_EXPLICIT_RUNTIME_OUTPUT_AVAILABLE" if explicit_runtime else
        "RUNTIME_SCHEMA_NOT_BOUND"
    )
    set_dim("B04_RUNTIME_SCHEMA",schema_pass,schema_code,schema_evidence,"BIND_CANONICAL_RUNTIME_SCHEMA",schema_authority_required)
    set_dim("B05_CANONICAL_VALIDATOR",validator_pass,"PASS" if validator_pass else "CANONICAL_VALIDATOR_NOT_BOUND",validator_evidence,"MATERIALIZE_CANONICAL_RUNTIME_VALIDATOR_ADAPTER")
    set_dim("B06_SEMANTIC_UTILITY_FLOOR",semantic_pass,"PASS" if semantic_pass else "SEMANTIC_UTILITY_NOT_BOUND",semantic_evidence,"MATERIALIZE_PROFILE_SEMANTIC_UTILITY")
    ci=(profile_dir/'validators/validate_pack.py').is_file()
    set_dim("B07_CI_PACK_VALIDATOR",ci,"PASS" if ci else "PROFILE_CI_VALIDATOR_NOT_DISCOVERABLE","validators/validate_pack.py" if ci else None,"MATERIALIZE_GENERIC_PROFILE_PACK_ENTRYPOINT")
    sf=isinstance(gov,dict) and gov.get("source_first_required") is True and gov.get("schema_invention_allowed") is False
    set_dim("B08_SOURCE_FIRST_NO_INVENTION",sf,"PASS" if sf else "SOURCE_FIRST_NO_INVENTION_NOT_BOUND",gov if sf else None,"BIND_SOURCE_FIRST_NO_INVENTION")
    fc=isinstance(gov,dict) and gov.get("fail_closed") is True
    set_dim("B09_FAIL_CLOSED",fc,"PASS" if fc else "FAIL_CLOSED_NOT_BOUND",True if fc else None,"BIND_FAIL_CLOSED")
    ec=isinstance(gov,dict) and gov.get("exact_head_evidence_required") is True and gov.get("post_update_baseline_required") is True
    set_dim("B10_EVIDENCE_CLOSURE",ec,"PASS" if ec else "POST_UPDATE_EVIDENCE_CLOSURE_NOT_BOUND",gov if ec else None,"BIND_EXACT_HEAD_AND_POST_UPDATE_BASELINE")

    score=sum(1 for item in dimensions.values() if item["pass"])
    if score==len(baseline["dimensions"]): decision="NO_UPDATE_REQUIRED"
    elif blockers: decision="BLOCKED_AUTHORITY_REQUIRED"
    else: decision="UPDATE_REQUIRED"
    return {
        "schema":"S26_PROFILE_BASELINE_EVALUATION_V1","baseline_schema":baseline["schema"],
        "profile_slug":profile_slug,"decision":decision,"score":score,"required":len(baseline["dimensions"]),
        "compatibility_pct":round(score*100/len(baseline["dimensions"]),1),"dimensions":dimensions,
        "repair_actions":repairs,"blocking_codes":sorted(set(blockers)),
        "post_update_rule":"RERUN_AND_REQUIRE_10_OF_10_BEFORE_PROFILE_UPDATE_CLOSURE",
        "automatic_impact_authorized":False,"runtime_activation_authorized":False,
    }


def main() -> int:
    if len(sys.argv) not in (2,3):
        print("usage: evaluate_s26_profile_baseline.py <profile_slug> [repo_root]",file=sys.stderr); return 2
    slug=sys.argv[1]; repo=Path(sys.argv[2]).resolve() if len(sys.argv)==3 else Path(__file__).resolve().parents[3]
    result=evaluate(repo,slug); print(json.dumps(result,indent=2,sort_keys=True))
    return 0 if result["decision"] in {"NO_UPDATE_REQUIRED","UPDATE_REQUIRED"} else 3

if __name__=="__main__": raise SystemExit(main())

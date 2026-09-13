from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
import uuid
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

EXPECTED_CANDIDATE = "3b39657fbf14f29c7839ecb26d715ed5c6fad59e"
PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SLUG = "ui_architect"
SOURCE_PATHS = [
    "profiles/ui_architect/SKILL.md",
    "profiles/ui_architect/contracts/composer_payload_boundary_v1.md",
]
EKB_REQUIRED_CODES = [
    "PROFILES-EKB-PREFLIGHT-OMISSION-001",
    "AUD-018",
    "GOV-024",
    "GOV-032",
    "CI-014",
]


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=lambda o: o.isoformat() if hasattr(o, "isoformat") else str(o)).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True, default=lambda o: o.isoformat() if hasattr(o, "isoformat") else str(o)) + "\n", encoding="utf-8")


def db_connect():
    import psycopg
    from psycopg.rows import dict_row

    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com").strip()
    if not password:
        raise RuntimeError("LF_SUPABASE_DB_PASSWORD_REQUIRED")
    return psycopg.connect(
        host=host,
        port=5432,
        user=f"postgres.{project}",
        password=password,
        dbname="postgres",
        sslmode="require",
        autocommit=True,
        row_factory=dict_row,
    )


def live_ekb_snapshot(run_id: str) -> dict[str, Any]:
    with db_connect() as conn, conn.cursor() as cur:
        cur.execute(
            """
            select column_name, data_type
            from information_schema.columns
            where table_schema='public' and table_name='lf_error_knowledge'
            order by ordinal_position
            """
        )
        schema = cur.fetchall()
        if not schema:
            raise RuntimeError("EKB_SCHEMA_NOT_FOUND")
        cur.execute("select now() as observed_at")
        observed_at = cur.fetchone()["observed_at"].astimezone(timezone.utc).isoformat()
        cur.execute(
            """
            select codigo,categoria,titulo,severidad,estado,prevencion,validacion,source_ref,updated_at
            from public.lf_error_knowledge
            where lower(estado)='activo' and codigo = any(%s)
            order by codigo
            """,
            (EKB_REQUIRED_CODES,),
        )
        controls = cur.fetchall()
        found = {row["codigo"] for row in controls}
        missing = sorted(set(EKB_REQUIRED_CODES) - found)
        if missing:
            raise RuntimeError("EKB_REQUIRED_CODES_MISSING:" + ",".join(missing))
        cur.execute(
            """
            select regla_codigo,error_codigo,regla,justificacion,prioridad,activa,categoria,lifecycle_phase
            from public.lf_prevention_rules
            where activa=true and (
              error_codigo = any(%s)
              or regla_codigo in ('PRV-AUD-018','PRV-GOVERNED-PATH-WRITE-AUTHORITY-001','PRV-ARC-012')
            )
            order by prioridad desc nulls last, regla_codigo
            """,
            (EKB_REQUIRED_CODES,),
        )
        rules = cur.fetchall()
        cur.execute(
            """
            select categoria,titulo,practica,evidencia,created_at
            from public.lf_best_practices
            where titulo ilike '%%profile%%' or practica ilike '%%profile%%'
               or titulo ilike '%%eviden%%' or practica ilike '%%eviden%%'
               or titulo ilike '%%holdout%%' or practica ilike '%%holdout%%'
            order by created_at desc
            limit 12
            """
        )
        practices = cur.fetchall()
    snapshot = {
        "schema": "S26_F10_LIVE_EKB_SNAPSHOT_V1",
        "run_id": run_id,
        "source": "supabase://mhwmirqcgxxukpctffuv/public",
        "read_mode": "LIVE_CONTROL_PLANE_READBACK",
        "schema_first_verified": True,
        "observed_at": observed_at,
        "lf_error_knowledge_schema": schema,
        "controls": controls,
        "prevention_rules": rules,
        "best_practices": practices,
        "reusable_for_new_run": False,
    }
    snapshot["snapshot_sha256"] = canonical_sha(snapshot)
    return snapshot


def acceptance_contract() -> dict[str, Any]:
    return {
        "implementation_readiness": "STRUCTURED_SPEC_READY_FOR_NEXT_AGENT",
        "minimum_component_count": 9,
        "minimum_hierarchy_depth_edges": 3,
        "minimum_risk_control_count": 4,
        "minimum_state_map_coverage_ratio": 1.0,
        "minimum_variant_guard_coverage_ratio": 1.0,
        "required_component_ids": [
            "header_search", "category_navigation", "featured_services", "service_cards",
            "service_card_template", "service_title", "service_provider", "service_price", "service_cta",
        ],
        "required_design_intents": ["clear", "professional", "easy_to_navigate"],
        "required_responsive_modes": ["desktop", "mobile"],
        "required_sections": ["header", "categories", "featured_services", "service_cards"],
        "required_service_leaf_components": ["service_title", "service_provider", "service_price", "service_cta"],
        "required_source_bindings": {
            "category_navigation.items": "DATA_BOUND",
            "featured_services.items": "DATA_BOUND",
            "service_card_template.fields": "title|provider|price|call_to_action",
            "service_card_template.values": "DATA_BOUND",
            "service_cards.items": "DATA_BOUND",
            "service_cta.destination": "UNRESOLVED_UNTIL_SOURCE",
            "service_cta.label": "DATA_BOUND:call_to_action",
            "service_price.format": "SOURCE_DEFINED",
            "service_price.value": "DATA_BOUND:price",
            "service_provider.value": "DATA_BOUND:provider",
            "service_title.value": "DATA_BOUND:title",
        },
        "required_state_component_ids": ["header_search", "category_navigation", "featured_services", "service_cards", "service_cta"],
        "task_mode": "CREATE_NEW",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidate-repo", type=Path, required=True)
    ap.add_argument("--evidence-dir", type=Path, required=True)
    args = ap.parse_args()
    candidate = args.candidate_repo.resolve()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    import subprocess
    actual_sha = subprocess.check_output(["git", "-C", str(candidate), "rev-parse", "HEAD"], text=True).strip()
    if actual_sha != EXPECTED_CANDIDATE:
        raise RuntimeError(f"FINAL_CANDIDATE_SHA_MISMATCH:{actual_sha}")

    run_id = "S26V3-F10-O5-REAL-E2E-HOLDOUT-R2-" + uuid.uuid4().hex[:12].upper()
    input_literal = (
        "Crea una pantalla real de marketplace para comparar servicios de reparación y mantenimiento de bicicletas. "
        "Mobile-first: buscador primero, categorías visibles, destacados únicamente si la fuente los marca, tarjetas con "
        "título, proveedor, precio y CTA provenientes de datos. No inventes disponibilidad, precio, rutas, promociones ni "
        "resultados. Debe quedar lista para implementación y funcionar también en desktop."
    )
    input_sha = hashlib.sha256(input_literal.encode("utf-8")).hexdigest()

    gate_a = {
        "schema": "S26_F10_GATE_A_ADMISSION_V1",
        "gate": "A_INPUT_ADMISSION",
        "run_id": run_id,
        "project_id": "S26",
        "status": "PASS",
        "input": {"source_type": "USER_TEXT", "content": input_literal, "sha256": input_sha, "content_mutated": False},
        "next_gate": "B_EKB_GOVERNANCE",
    }
    gate_a["receipt_sha256"] = canonical_sha(gate_a)
    write_json(evidence / "gate_a_admission.json", gate_a)

    gate_b = live_ekb_snapshot(run_id)
    gate_b.update({
        "gate": "B_EKB_GOVERNANCE",
        "status": "PASS",
        "upstream_input_sha256": input_sha,
        "next_gate": "C_CARD_SELECTION",
    })
    gate_b["receipt_sha256"] = canonical_sha(gate_b)
    write_json(evidence / "gate_b_ekb_governance.json", gate_b)

    sys.path.insert(0, str(candidate / "services/profile_runtime_api"))
    from profile_runtime_api.engine import ProfileRuntimeEngine
    from profile_runtime_api.hashing import canonical_json_sha256
    from profile_runtime_api.models import ProfileTask
    from profile_runtime_api.repository import RepositoryBindings
    from profile_runtime_api.runtime_authority import resolve_typed_runtime_context
    from profile_runtime_api.settings import Settings

    input_fields = {
        "project_id": "S26",
        "gate_run_id": run_id,
        "task_mode": "CREATE_NEW",
        "profile_slug": PROFILE_SLUG,
        "domain_scope": "GENERIC_SERVICE_MARKETPLACE",
        "execution_mode": "SANDBOX",
        "distribution_mode": "DIRECT",
        "output_contract_version": "UI_PRODUCTION_SPEC_V6",
        "gate_f_acceptance": acceptance_contract(),
        "f10_holdout_generation": "R2_FRESH_NO_HP001_UPSTREAM",
        "f10_live_ekb_snapshot_sha256": gate_b["snapshot_sha256"],
    }
    task = ProfileTask(
        request_id=run_id,
        operation_code="EJECUCION_PERFIL_LF",
        profile_code=PROFILE_CODE,
        profile_slug=PROFILE_SLUG,
        profile_source_paths=SOURCE_PATHS,
        input_literal=input_literal,
        input_fields=input_fields,
        runtime_output_mode="UI_PRODUCTION_SPEC",
        lf_adapter_sources=[],
        required_adapter_codes=[],
        lf_card_sources=[],
        required_card_refs=[],
        send_image_to_model=False,
    )

    repo = RepositoryBindings(candidate, max_prompt_chars=120000)
    repo.validate_profile_identity(PROFILE_SLUG, PROFILE_CODE)
    sources = repo.profile_sources(PROFILE_SLUG, SOURCE_PATHS)
    schema = repo.runtime_schema(PROFILE_SLUG, "UI_PRODUCTION_SPEC")
    governance_context_sha = canonical_sha({
        "gate_a_receipt_sha256": gate_a["receipt_sha256"],
        "gate_b_snapshot_sha256": gate_b["snapshot_sha256"],
        "run_id": run_id,
    })
    context_pack = {
        "schema": "lf-profile-runtime-queue-context/v1",
        "source": "QUEUE_NATIVE_TEXT_PROFILE",
        "e2e_case_source": "S26_F10_REAL_E2E_HOLDOUT_R2",
        "screen_governance_applicable": False,
        "input_governance": {
            "receipt_ref": "w3_repair/gate_b_ekb_governance.json",
            "current": True,
            "ready": True,
            "status": "PASS",
            "decision": "ALLOW",
            "subject_mode": "TEXT_TASK",
            "context_sha256": governance_context_sha,
        },
        "runtime_authority_contract": {
            "current_run_id": run_id,
            "required_authority_types": ["INPUT_GOVERNANCE"],
            "authority_sources": [],
        },
        "downstream_authorized": False,
    }
    context_pack["pack_sha256"] = canonical_json_sha256(context_pack)

    typed_pre = resolve_typed_runtime_context(task, profile_sources=sources, context_pack=context_pack, schema=schema)
    gate_c = {
        "schema": "S26_F10_GATE_C_CARD_SELECTION_V1",
        "gate": "C_CARD_SELECTION",
        "run_id": run_id,
        "status": "PASS",
        "card_resolution": typed_pre["card_resolution"],
        "next_gate": "D_AUTHORITY_RESOLUTION",
    }
    gate_c["receipt_sha256"] = canonical_sha(gate_c)
    write_json(evidence / "gate_c_card_selection.json", gate_c)

    gate_d = {
        "schema": "S26_F10_GATE_D_AUTHORITY_V1",
        "gate": "D_AUTHORITY_RESOLUTION",
        "run_id": run_id,
        "status": "PASS",
        "authority_resolution": typed_pre["authority_resolution"],
        "authority_count": len(typed_pre["authority_resolution"]),
        "next_gate": "E_TYPED_CONTEXT",
    }
    gate_d["receipt_sha256"] = canonical_sha(gate_d)
    write_json(evidence / "gate_d_authority.json", gate_d)

    gate_e = {
        "schema": "S26_F10_GATE_E_TYPED_CONTEXT_V1",
        "gate": "E_TYPED_CONTEXT",
        "run_id": run_id,
        "status": "PASS",
        "typed_context": typed_pre,
        "typed_context_sha256": typed_pre["typed_context_sha256"],
        "next_gate": "F_PROFILE_EXECUTION",
    }
    gate_e["receipt_sha256"] = canonical_sha(gate_e)
    write_json(evidence / "gate_e_typed_context.json", gate_e)

    request_snapshot = {
        "schema": "S26_F10_REAL_E2E_RUNTIME_REQUEST_V1",
        "run_id": run_id,
        "candidate_sha": EXPECTED_CANDIDATE,
        "profile": task.model_dump(mode="python"),
        "context_pack": context_pack,
        "upstream_receipts": {
            "gate_a": gate_a["receipt_sha256"],
            "gate_b": gate_b["receipt_sha256"],
            "gate_c": gate_c["receipt_sha256"],
            "gate_d": gate_d["receipt_sha256"],
            "gate_e": gate_e["receipt_sha256"],
        },
    }
    request_snapshot["request_sha256"] = canonical_sha(request_snapshot)
    write_json(evidence / "runtime_request.json", request_snapshot)

    with tempfile.TemporaryDirectory(prefix="s26-f10-r2-state-") as state_tmp:
        base = Settings.from_env()
        settings = replace(base, repo_root=candidate, state_dir=Path(state_tmp), source_sha=EXPECTED_CANDIDATE)
        engine = ProfileRuntimeEngine(settings)
        engine.initialize()
        t0 = time.perf_counter()
        result = engine._execute_queue_profile(
            task=task,
            context_pack=context_pack,
            context_override={
                "queue_native": False,
                "full_governed_pipeline": True,
                "source": "S26_F10_REAL_E2E_HOLDOUT_R2",
                "runtime_output_mode": "UI_PRODUCTION_SPEC",
                "cache_hit": False,
            },
        )
        wall_ms = round((time.perf_counter() - t0) * 1000, 3)

    write_json(evidence / "runtime_result.json", result)
    runtime_completion = result.get("runtime_completion") or {}
    governed = runtime_completion.get("governed_context_receipt") or {}
    observed_typed = governed.get("runtime_typed_context") or {}
    materialization = runtime_completion.get("output_materialization") or {}
    deterministic_acceptance = materialization.get("deterministic_acceptance") or {}
    runtime_receipt = runtime_completion.get("receipt") or {}
    attestation = runtime_receipt.get("runtime_attestation") or {}

    if runtime_completion.get("status") != "PASS":
        raise RuntimeError("RUNTIME_COMPLETION_NOT_PASS:" + ",".join(runtime_completion.get("blocking_codes") or []))
    if observed_typed.get("typed_context_sha256") != typed_pre["typed_context_sha256"]:
        raise RuntimeError("GATE_E_TO_F_TYPED_CONTEXT_DRIFT")
    if attestation.get("source_sha") != EXPECTED_CANDIDATE:
        raise RuntimeError("RUNTIME_ATTESTATION_SOURCE_SHA_MISMATCH")
    if runtime_receipt.get("execution_origin") != "MODEL_RUNTIME":
        raise RuntimeError("RUNTIME_EXECUTION_ORIGIN_NOT_MODEL_RUNTIME")
    if result.get("profile_contract_valid", {}).get("status") != "PASS":
        raise RuntimeError("PROFILE_CONTRACT_NOT_PASS")
    if result.get("semantic_utility", {}).get("status") != "PASS":
        raise RuntimeError("SEMANTIC_UTILITY_FLOOR_NOT_PASS")
    if not deterministic_acceptance or not all(value is True for value in deterministic_acceptance.values()):
        raise RuntimeError("DETERMINISTIC_MATERIAL_ACCEPTANCE_NOT_PASS")

    materialized_raw = result.get("raw_output")
    if not isinstance(materialized_raw, str):
        raise RuntimeError("MATERIALIZED_OUTPUT_MISSING")
    artifact_payload = json.loads(materialized_raw)
    write_json(evidence / "artifact_payload.json", artifact_payload)

    evidence_text = json.dumps(
        {"request": request_snapshot, "a": gate_a, "b": gate_b, "c": gate_c, "d": gate_d, "e": gate_e, "runtime": result},
        ensure_ascii=False,
        sort_keys=True,
        default=lambda o: o.isoformat() if hasattr(o, "isoformat") else str(o),
    )
    forbidden = [needle for needle in ("s26_hp001", "S26-HP-001", "gate_f_input.json") if needle in evidence_text]
    if forbidden:
        raise RuntimeError("HP001_UPSTREAM_REUSE_DETECTED:" + ",".join(forbidden))

    stage_receipts = {
        "A": file_sha(evidence / "gate_a_admission.json"),
        "B": file_sha(evidence / "gate_b_ekb_governance.json"),
        "C": file_sha(evidence / "gate_c_card_selection.json"),
        "D": file_sha(evidence / "gate_d_authority.json"),
        "E": file_sha(evidence / "gate_e_typed_context.json"),
        "F_G_H_PRODUCER": file_sha(evidence / "runtime_result.json"),
        "ARTIFACT": file_sha(evidence / "artifact_payload.json"),
    }
    execution_receipt = {
        "schema": "S26_F10_REAL_E2E_EXECUTION_RECEIPT_V2",
        "case_id": "S26V3-F10-O5-REAL-E2E-HOLDOUT-R2",
        "run_id": run_id,
        "executed_at": datetime.now(timezone.utc).isoformat(),
        "final_candidate_sha": EXPECTED_CANDIDATE,
        "input_sha256": input_sha,
        "fresh_input": True,
        "fresh_run_identity": True,
        "reused_hp001_upstream_context": False,
        "forbidden_hp001_references": [],
        "full_governed_pipeline_observed": True,
        "typed_context_present": True,
        "typed_context_sha256": typed_pre["typed_context_sha256"],
        "typed_context_consumed_by_runtime_exact_match": True,
        "card_resolution": typed_pre["card_resolution"],
        "authority_resolution_count": len(typed_pre["authority_resolution"]),
        "authority_types": sorted({item["authority_type"] for item in typed_pre["authority_resolution"]}),
        "live_ekb_snapshot_sha256": gate_b["snapshot_sha256"],
        "live_ekb_observed_at": gate_b["observed_at"],
        "runtime_status": runtime_completion.get("status"),
        "runtime_execution_origin": runtime_receipt.get("execution_origin"),
        "runtime_provider": attestation.get("provider"),
        "runtime_model_id": attestation.get("model_id"),
        "runtime_source_sha": attestation.get("source_sha"),
        "profile_contract_status": result.get("profile_contract_valid", {}).get("status"),
        "semantic_utility_floor_status": result.get("semantic_utility", {}).get("status"),
        "deterministic_material_acceptance": deterministic_acceptance,
        "producer_pipeline_status": "PASS",
        "independent_semantic_review": "PENDING_INDEPENDENT_CHAT_CONTEXT",
        "pass": False,
        "blocking_codes": ["INDEPENDENT_CHAT_CONTEXT_REQUIRED"],
        "wall_ms": wall_ms,
        "llama_usage": runtime_completion.get("llama_usage", {}),
        "llama_timings": runtime_completion.get("llama_timings", {}),
        "stage_receipts_sha256": stage_receipts,
        "claim_ceiling": "REAL_A_TO_H_PRODUCER_E2E_OBSERVED_INDEPENDENT_REVIEW_PENDING_NOT_W3_COMPLETE_NOT_GOLDEN_NOT_PRODUCTION",
    }
    execution_receipt["receipt_sha256"] = canonical_sha(execution_receipt)
    write_json(evidence / "f10_real_e2e_execution_receipt.json", execution_receipt)

    print(json.dumps({
        "status": "PASS_PRODUCER_E2E_INDEPENDENT_REVIEW_PENDING",
        "run_id": run_id,
        "final_candidate_sha": EXPECTED_CANDIDATE,
        "full_governed_pipeline_observed": True,
        "typed_context_present": True,
        "authority_resolution_count": len(typed_pre["authority_resolution"]),
        "contract_status": result.get("profile_contract_valid", {}).get("status"),
        "semantic_status": result.get("semantic_utility", {}).get("status"),
        "artifact_sha256": file_sha(evidence / "artifact_payload.json"),
        "receipt_sha256": execution_receipt["receipt_sha256"],
        "wall_ms": wall_ms,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

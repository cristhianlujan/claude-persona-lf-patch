#!/usr/bin/env python3
"""Execute BOUND_SEMANTIC_JUDGE as an isolated post-validator model call.

The worker is deliberately separate from the producer worker. It consumes only
EJECUCION_PERFIL_LF executions whose deterministic output_validate step is clean,
resolves the target profile's judge binding from canonical Supabase asset metadata,
runs one fresh judge model call, validates the receipt deterministically, and
records semantic_judge/report_output through the governed Supabase recorder.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import time
from pathlib import Path
from types import ModuleType
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

from profile_runtime_api.llama import LlamaHTTPClient
from profile_runtime_api.settings import Settings

REPO_ROOT = Path(__file__).resolve().parents[3]
PASS_STATUS = "STEP_PASS_WITH_EVIDENCE"


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _connect() -> psycopg.Connection:
    password = _env("LF_SUPABASE_DB_PASSWORD")
    project = _env("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv")
    host = _env("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com")
    if not password:
        raise SystemExit("SEMANTIC_JUDGE_DB_PASSWORD_MISSING")
    return psycopg.connect(host=host, port=5432, user=f"postgres.{project}", password=password, dbname="postgres", sslmode="require", autocommit=False)


def _canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _load_module(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("SEMANTIC_JUDGE_VALIDATOR_IMPORT_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _safe_profile_root(target_path: str) -> Path:
    relative = Path(target_path)
    if relative.is_absolute() or ".." in relative.parts or len(relative.parts) < 3:
        raise RuntimeError("SEMANTIC_JUDGE_TARGET_PATH_INVALID")
    root = (REPO_ROOT / relative).resolve().parent
    profiles_root = (REPO_ROOT / "profiles").resolve()
    try:
        root.relative_to(profiles_root)
    except ValueError as exc:
        raise RuntimeError("SEMANTIC_JUDGE_PROFILE_ROOT_ESCAPE") from exc
    if not root.is_dir():
        raise RuntimeError("SEMANTIC_JUDGE_PROFILE_ROOT_MISSING")
    return root


def _binding(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict) or payload.get("schema") != "LF_PROFILE_SEMANTIC_JUDGE_BINDING_V1":
        raise RuntimeError("SEMANTIC_JUDGE_BINDING_SCHEMA_INVALID")
    for key in ("prompt_path", "validator_path", "validator_callable", "pass_verdict"):
        if not isinstance(payload.get(key), str) or not payload[key].strip():
            raise RuntimeError(f"SEMANTIC_JUDGE_BINDING_FIELD_INVALID:{key}")
    if payload.get("independence") != {
        "separate_model_call_required": True,
        "producer_prompt_reuse_forbidden": True,
        "producer_self_verdict_forbidden": True,
    }:
        raise RuntimeError("SEMANTIC_JUDGE_INDEPENDENCE_CONTRACT_WEAK")
    return payload


def _bound_file(profile_root: Path, raw: str, code: str) -> Path:
    relative = Path(raw)
    if relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError(code + "_PATH_INVALID")
    path = (profile_root / relative).resolve()
    try:
        path.relative_to(profile_root)
    except ValueError as exc:
        raise RuntimeError(code + "_PATH_ESCAPE") from exc
    if not path.is_file():
        raise RuntimeError(code + "_MISSING")
    return path


JUDGE_SCHEMA: dict[str, Any] = {
    "type": "object", "additionalProperties": False,
    "required": ["verdict","source_refs_inspected","observed_candidate_changes","requirement_reconciliation","change_declaration_reconciliation","scope_conformance_reconciliation","invariant_results","open_design_decisions_found","unsupported_claims","blocking_codes","repair_instructions","next_gate"],
    "properties": {
        "verdict": {"type":"string","enum":["PASS_INDEPENDENT_SEMANTIC","RETURN_TO_WORKER_FOR_SELF_REPAIR","RETURN_TO_ORCHESTRATOR","BLOCK_PIPELINE"]},
        "source_refs_inspected":{"type":"array","maxItems":40,"items":{"type":"string","maxLength":500}},
        "observed_candidate_changes":{"type":"array","maxItems":60,"items":{"type":"object"}},
        "requirement_reconciliation":{"type":"array","maxItems":80,"items":{"type":"object"}},
        "change_declaration_reconciliation":{"type":"array","maxItems":60,"items":{"type":"object"}},
        "scope_conformance_reconciliation":{"type":"array","maxItems":60,"items":{"type":"object"}},
        "invariant_results":{"type":"array","minItems":7,"maxItems":12,"items":{"type":"object"}},
        "open_design_decisions_found":{"type":"array","maxItems":30,"items":{"type":"string","maxLength":500}},
        "unsupported_claims":{"type":"array","maxItems":30,"items":{"type":"string","maxLength":500}},
        "blocking_codes":{"type":"array","maxItems":30,"items":{"type":"string","maxLength":160}},
        "repair_instructions":{"type":"array","maxItems":30,"items":{"type":"string","maxLength":800}},
        "next_gate":{"type":"string","maxLength":160}
    }
}


def _claim(conn: psycopg.Connection) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute("""
            select e.execution_id,e.target_code,e.target_path,e.manifest,
                   i.evidence_payload,x.evidence_payload,o.evidence_payload,
                   a.metadata->'semantic_judge_binding'
              from public.lf_operation_execution e
              join public.lf_operation_execution_steps i on i.execution_id=e.execution_id and i.step_id='input_validate'
              join public.lf_operation_execution_steps x on x.execution_id=e.execution_id and x.step_id='execute_profile'
              join public.lf_operation_execution_steps o on o.execution_id=e.execution_id and o.step_id='output_validate'
              join public.lf_activos a on a.codigo_activo=e.target_code and a.tipo_activo='PERFIL' and a.archived_at is null
              left join public.lf_operation_execution_steps s on s.execution_id=e.execution_id and s.step_id='semantic_judge'
             where e.operation_code='EJECUCION_PERFIL_LF' and e.target_type='PERFIL' and e.status='IN_PROGRESS'
               and i.status=%s and x.status=%s and o.status=%s
               and (s.step_id is null or s.status<>'STEP_PASS_WITH_EVIDENCE')
             order by e.started_at,e.execution_id limit 20
        """, (PASS_STATUS, PASS_STATUS, PASS_STATUS))
        for row in cur.fetchall():
            execution_id = row[0]
            cur.execute("select pg_try_advisory_lock(pg_catalog.hashtextextended(%s,0))", (execution_id,))
            locked = cur.fetchone()
            if locked and locked[0] is True:
                claimed = {
                    "execution_id": execution_id, "target_code": row[1], "target_path": row[2],
                    "manifest": row[3] if isinstance(row[3], dict) else {},
                    "input_payload": row[4] if isinstance(row[4], dict) else {},
                    "execute_payload": row[5] if isinstance(row[5], dict) else {},
                    "output_payload": row[6] if isinstance(row[6], dict) else {},
                    "semantic_judge_binding": row[7] if isinstance(row[7], dict) else None,
                }
                conn.commit()
                return claimed
    conn.rollback()
    return None


def _prepare(claimed: dict[str, Any]) -> dict[str, Any]:
    input_payload, execute_payload, output_payload = claimed["input_payload"], claimed["execute_payload"], claimed["output_payload"]
    packet, scope_digest = input_payload.get("scope_authority_packet"), input_payload.get("scope_authority_packet_sha256")
    candidate, candidate_digest = execute_payload.get("profile_output"), execute_payload.get("candidate_digest")
    if not isinstance(packet, dict) or not isinstance(candidate, dict):
        raise RuntimeError("SEMANTIC_JUDGE_REQUIRED_INPUT_MISSING")
    if not isinstance(scope_digest, str) or re.fullmatch(r"sha256:[0-9a-f]{64}", scope_digest) is None:
        raise RuntimeError("SEMANTIC_JUDGE_SCOPE_DIGEST_INVALID")
    if not isinstance(candidate_digest, str) or re.fullmatch(r"sha256:[0-9a-f]{64}", candidate_digest) is None:
        raise RuntimeError("SEMANTIC_JUDGE_CANDIDATE_DIGEST_INVALID")
    candidate_sha = candidate_digest.split(":",1)[1]
    if _canonical_json_sha256(candidate) != candidate_sha:
        raise RuntimeError("SEMANTIC_JUDGE_CANDIDATE_DIGEST_MISMATCH")
    if output_payload.get("blocking_codes") not in ([], None):
        raise RuntimeError("SEMANTIC_JUDGE_DETERMINISTIC_PREDECESSOR_BLOCKED")
    profile_root = _safe_profile_root(str(claimed["target_path"] or ""))
    binding = _binding(claimed.get("semantic_judge_binding"))
    prompt_path = _bound_file(profile_root, binding["prompt_path"], "SEMANTIC_JUDGE_PROMPT")
    validator_path = _bound_file(profile_root, binding["validator_path"], "SEMANTIC_JUDGE_VALIDATOR")
    return {
        "execution_id":claimed["execution_id"], "profile_root":profile_root, "profile_slug":profile_root.name,
        "binding":binding, "binding_ref":"supabase://public.lf_activos/"+claimed["target_code"]+"#metadata.semantic_judge_binding",
        "prompt_path":prompt_path, "validator_path":validator_path, "candidate":candidate, "candidate_sha":candidate_sha,
        "scope_packet":packet, "scope_sha":scope_digest.split(":",1)[1],
        "deterministic_validation":output_payload.get("output_contract_result") or output_payload.get("deterministic_validation") or {}
    }


def _judge(prepared: dict[str, Any]) -> dict[str, Any]:
    settings = Settings.from_env(); settings.validate(); client = LlamaHTTPClient(settings)
    if client.health().get("ready") is not True:
        raise RuntimeError("SEMANTIC_JUDGE_MODEL_NOT_READY")
    user_payload = {
        "exact_candidate":prepared["candidate"], "scope_authority_packet":prepared["scope_packet"],
        "deterministic_validator_result":prepared["deterministic_validation"], "execution_id":prepared["execution_id"],
        "independence_contract":{"producer_prompt_reused":False,"producer_self_verdict_is_evidence":False,"independently_extract_candidate_changes":True}
    }
    completion = client.chat(system_prompt=prepared["prompt_path"].read_text(encoding="utf-8"), user_prompt=json.dumps(user_payload,ensure_ascii=False,sort_keys=True,separators=(",",":")), schema=JUDGE_SCHEMA, profile_slug=prepared["profile_slug"], schema_mode="AUTO")
    raw = completion.get("content")
    if not isinstance(raw,str): raise RuntimeError("SEMANTIC_JUDGE_MODEL_OUTPUT_MISSING")
    try: result=json.loads(raw)
    except json.JSONDecodeError as exc: raise RuntimeError("SEMANTIC_JUDGE_MODEL_OUTPUT_INVALID_JSON") from exc
    if not isinstance(result,dict): raise RuntimeError("SEMANTIC_JUDGE_MODEL_OUTPUT_NOT_OBJECT")
    result["candidate_sha256"],result["scope_packet_sha256"] = prepared["candidate_sha"],prepared["scope_sha"]
    validator=_load_module(prepared["validator_path"],"lf_bound_semantic_judge_validator")
    evaluate=getattr(validator,prepared["binding"]["validator_callable"],None)
    if not callable(evaluate): raise RuntimeError("SEMANTIC_JUDGE_VALIDATOR_CALLABLE_MISSING")
    validated=evaluate(result,scope_packet=prepared["scope_packet"],expected_candidate_sha256=prepared["candidate_sha"],expected_scope_packet_sha256=prepared["scope_sha"])
    if not isinstance(validated,dict): raise RuntimeError("SEMANTIC_JUDGE_VALIDATOR_RESULT_INVALID")
    passed=validated.get("status")=="PASS" and result.get("verdict")==prepared["binding"]["pass_verdict"]
    return {"status":"PASS" if passed else "FAIL","verdict":result.get("verdict"),"validator_status":validated.get("status"),"producer_independence_proven":True,"model_call_count":1,"candidate_sha256":prepared["candidate_sha"],"scope_packet_sha256":prepared["scope_sha"],"result":result,"validator_result":validated,"judge_binding_ref":prepared["binding_ref"],"judge_prompt_ref":str(prepared["prompt_path"].relative_to(REPO_ROOT)),"model_id":completion.get("model"),"model_call_id":completion.get("id")}


def _record(conn: psycopg.Connection, claimed: dict[str, Any], prepared: dict[str, Any], judged: dict[str, Any]) -> dict[str, Any]:
    execution_id=claimed["execution_id"]; raw_result=judged.get("result") if isinstance(judged.get("result"),dict) else {}
    unsupported=raw_result.get("unsupported_claims") if isinstance(raw_result.get("unsupported_claims"),list) else ["SEMANTIC_JUDGE_UNSUPPORTED_CLAIMS_INVALID"]
    refs=["supabase://public.lf_operation_execution/"+execution_id,"supabase://public.lf_operation_execution_steps/"+execution_id+"/input_validate","supabase://public.lf_operation_execution_steps/"+execution_id+"/execute_profile","supabase://public.lf_operation_execution_steps/"+execution_id+"/output_validate",prepared["binding_ref"],"github://cristhianlujan/claude-persona-lf-patch/"+str(prepared["prompt_path"].relative_to(REPO_ROOT)),"github://cristhianlujan/claude-persona-lf-patch/"+str(prepared["validator_path"].relative_to(REPO_ROOT))]
    payload={"semantic_judge_result":judged,"unsupported_claims":unsupported,"source_refs":refs,"blocking_codes":judged.get("validator_result",{}).get("blocking_codes",[])}
    with conn.cursor() as cur:
        cur.execute("select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",(execution_id,"semantic_judge",f"hetzner://profile-runtime/{execution_id}/independent-semantic-judge",Jsonb(payload),execution_id)); row=cur.fetchone(); semantic=row[0] if row and isinstance(row[0],dict) else {}
        if judged.get("status")!="PASS" or semantic.get("outcome")!="STEP_RECORDED": conn.commit(); return {"semantic":semantic,"report":None}
        report={"result":prepared["binding"]["pass_verdict"],"profile_code":claimed["target_code"],"execution_id":execution_id,"no_write_performed":True,"candidate_sha256":prepared["candidate_sha"],"scope_packet_sha256":prepared["scope_sha"],"evidence_refs":refs}
        cur.execute("select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",(execution_id,"report_output",f"supabase://public.lf_operation_execution_steps/{execution_id}/report_output#semantic-judge-worker",Jsonb(report),execution_id)); rr=cur.fetchone(); report_record=rr[0] if rr and isinstance(rr[0],dict) else {}
    conn.commit(); return {"semantic":semantic,"report":report_record}


def run_once() -> bool:
    conn=_connect(); claimed=None
    try:
        claimed=_claim(conn)
        if claimed is None: return False
        prepared=_prepare(claimed); judged=_judge(prepared); recorded=_record(conn,claimed,prepared,judged)
        print("SEMANTIC_JUDGE_EXECUTION_ID="+claimed["execution_id"]); print("SEMANTIC_JUDGE_VERDICT="+str(judged.get("verdict"))); print("SEMANTIC_JUDGE_VALIDATOR_STATUS="+str(judged.get("validator_status"))); print("SEMANTIC_JUDGE_RECORD="+json.dumps(recorded,ensure_ascii=False,sort_keys=True)); return True
    except Exception as exc:
        conn.rollback(); print(f"SEMANTIC_JUDGE_ERROR={type(exc).__name__}:{str(exc)[:800]}",flush=True); return claimed is not None
    finally:
        if claimed is not None:
            try:
                with conn.cursor() as cur: cur.execute("select pg_advisory_unlock(pg_catalog.hashtextextended(%s,0))",(claimed["execution_id"],))
                conn.commit()
            except Exception: conn.rollback()
        conn.close()


def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("--daemon",action="store_true"); parser.add_argument("--idle-seconds",type=float,default=3.0); args=parser.parse_args()
    if not args.daemon: return 0 if run_once() else 4
    while True:
        if not run_once(): time.sleep(max(0.5,args.idle_seconds))


if __name__=="__main__": raise SystemExit(main())

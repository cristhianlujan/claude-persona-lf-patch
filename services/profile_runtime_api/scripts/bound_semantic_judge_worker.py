#!/usr/bin/env python3
"""Physical consumer for BOUND_SEMANTIC_JUDGE.

Consumes only governed EJECUCION_PERFIL_LF candidates after clean deterministic
validation. Reviewer input is isolated to the exact candidate, exact evidence
manifest, the pre-producer scope packet and bounded authority-reference metadata.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

REPO = "cristhianlujan/claude-persona-lf-patch"
PROVIDER = "HETZNER_LLAMA_SERVER"
CONTEXT_MODE = "ISOLATED_NO_PRODUCER_PRIVATE_CONTEXT"
INPUT_CLASSES = ["SCOPE_AUTHORITY_PACKET", "EXACT_CANDIDATE", "EVIDENCE_MANIFEST", "CURRENT_AUTHORITY_REFS"]
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
GITHUB_REF = re.compile(r"^github://(?P<repo>[^@]+)@(?P<rev>[0-9a-f]{40})/(?P<path>.+)$")
REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_DIR = Path(os.environ.get("PROFILE_RUNTIME_STATE_DIR", "/var/lib/lf-profile-runtime-api"))


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def connect() -> psycopg.Connection:
    password = env("LF_SUPABASE_DB_PASSWORD")
    if not password:
        raise RuntimeError("BOUND_SEMANTIC_DB_PASSWORD_MISSING")
    project = env("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv")
    return psycopg.connect(
        host=env("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com"), port=5432,
        user=f"postgres.{project}", password=password, dbname="postgres", sslmode="require", autocommit=False,
    )


def validate_scope_packet(packet: Any) -> None:
    if not isinstance(packet, dict):
        raise RuntimeError("BOUND_SEMANTIC_SCOPE_PACKET_MISSING")
    lists = ("authorized_requirements", "constraints", "forbidden_changes", "authority_precedence", "related_context_refs", "source_refs")
    if any(not isinstance(packet.get(key), list) for key in lists):
        raise RuntimeError("BOUND_SEMANTIC_SCOPE_PACKET_SHAPE_INVALID")
    seen: set[str] = set()
    for key in ("authorized_requirements", "constraints", "forbidden_changes"):
        for item in packet[key]:
            if not isinstance(item, dict) or not all(isinstance(item.get(k), str) and item[k].strip() for k in ("id", "statement", "source_ref", "materiality")):
                raise RuntimeError("BOUND_SEMANTIC_SCOPE_ITEM_INVALID")
            if item["id"] in seen:
                raise RuntimeError("BOUND_SEMANTIC_SCOPE_ITEM_ID_DUPLICATE")
            seen.add(item["id"])


def safe_local(path: str) -> Path:
    rel = Path(path)
    if rel.is_absolute() or ".." in rel.parts or ":" in path or "\x00" in path:
        raise RuntimeError("BOUND_SEMANTIC_SOURCE_PATH_INVALID")
    resolved = (REPO_ROOT / rel).resolve()
    try:
        resolved.relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise RuntimeError("BOUND_SEMANTIC_SOURCE_PATH_ESCAPE") from exc
    return resolved


def exact_github_text(ref: str) -> str:
    match = GITHUB_REF.fullmatch(ref or "")
    if not match or match.group("repo") != REPO:
        raise RuntimeError("BOUND_SEMANTIC_GITHUB_REF_INVALID")
    revision, path = match.group("rev"), match.group("path")
    if revision == env("PROFILE_RUNTIME_SOURCE_SHA"):
        local = safe_local(path)
        if not local.is_file():
            raise RuntimeError("BOUND_SEMANTIC_LOCAL_SOURCE_MISSING")
        return local.read_text(encoding="utf-8")
    quoted = "/".join(urllib.parse.quote(part, safe="") for part in Path(path).parts)
    headers = {"Accept": "text/plain"}
    token = env("PROFILE_RUNTIME_GITHUB_TOKEN") or env("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"https://raw.githubusercontent.com/{REPO}/{revision}/{quoted}", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read(524289)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError("BOUND_SEMANTIC_EXACT_SOURCE_UNRESOLVED") from exc
    if len(raw) > 524288:
        raise RuntimeError("BOUND_SEMANTIC_EXACT_SOURCE_TOO_LARGE")
    return raw.decode("utf-8")


def profile_quality_sources(execution: dict[str, Any]) -> tuple[str, str, str, str]:
    revision = str(execution.get("profile_source_revision") or "")
    target_path = str(execution.get("target_path") or "")
    if SHA40.fullmatch(revision) is None or not target_path.startswith("profiles/"):
        raise RuntimeError("BOUND_SEMANTIC_PROFILE_SOURCE_BINDING_INVALID")
    root = target_path.rsplit("/", 1)[0]
    binding_ref = f"github://{REPO}@{revision}/{root}/contracts/runtime_binding.json"
    binding = json.loads(exact_github_text(binding_ref))
    quality = binding.get("canonical_quality")
    if not isinstance(quality, dict):
        quality = binding.get("canonical_quality_boundary")
    if not isinstance(quality, dict):
        raise RuntimeError("BOUND_SEMANTIC_QUALITY_BINDING_MISSING")
    judge_path = quality.get("semantic_judge_path")
    validator_path = quality.get("semantic_result_validator_path")
    if not isinstance(validator_path, str):
        validator = quality.get("semantic_result_validator")
        validator_path = validator.get("path") if isinstance(validator, dict) else None
    if not isinstance(judge_path, str) or not isinstance(validator_path, str):
        raise RuntimeError("BOUND_SEMANTIC_QUALITY_PATH_MISSING")
    judge_ref = f"github://{REPO}@{revision}/{root}/{judge_path}"
    validator_ref = f"github://{REPO}@{revision}/{root}/{validator_path}"
    return judge_ref, exact_github_text(judge_ref), validator_ref, exact_github_text(validator_ref)


def claim(conn: psycopg.Connection) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute("""
          with candidate as (
            select e.execution_id
            from public.lf_operation_execution e
            join public.lf_operation_execution_steps ep on ep.execution_id=e.execution_id and ep.step_id='execute_profile' and ep.status='STEP_PASS_WITH_EVIDENCE'
            join public.lf_operation_execution_steps ov on ov.execution_id=e.execution_id and ov.step_id='output_validate' and ov.status='STEP_PASS_WITH_EVIDENCE'
            left join public.lf_operation_execution_steps sj on sj.execution_id=e.execution_id and sj.step_id='semantic_judge'
            where e.operation_code='EJECUCION_PERFIL_LF' and e.target_type='PERFIL' and e.status='IN_PROGRESS'
              and jsonb_typeof(e.manifest->'semantic_scope_authority_packet')='object'
              and (sj.execution_id is null or sj.status<>'STEP_PASS_WITH_EVIDENCE')
            order by e.started_at,e.execution_id for update of e skip locked limit 1
          )
          select e.execution_id,e.target_path,e.manifest->>'profile_source_revision' profile_source_revision,
                 e.manifest->>'runtime_provider' producer_runtime_provider,
                 e.manifest->'semantic_scope_authority_packet' scope_packet,
                 ep.evidence_payload->'profile_output' exact_candidate,
                 ep.evidence_payload->'evidence_manifest' evidence_manifest,
                 ep.evidence_payload->>'candidate_digest' candidate_digest,
                 ov.evidence_payload->'output_contract_result' deterministic_result
          from candidate c join public.lf_operation_execution e using(execution_id)
          join public.lf_operation_execution_steps ep on ep.execution_id=e.execution_id and ep.step_id='execute_profile'
          join public.lf_operation_execution_steps ov on ov.execution_id=e.execution_id and ov.step_id='output_validate'
        """)
        row = cur.fetchone()
        if row is None:
            conn.rollback(); return None
        result = dict(zip([d.name for d in cur.description], row))
        conn.commit(); return result


def authority_refs(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    rows = manifest.get("evidence") if isinstance(manifest, dict) else None
    if not isinstance(rows, list):
        raise RuntimeError("BOUND_SEMANTIC_EVIDENCE_MANIFEST_INVALID")
    keys = ("evidence_id", "subject", "evidence_class", "source_locator", "revision_or_observed_at", "digest", "state")
    return [{key: row.get(key) for key in keys} for row in rows[:64] if isinstance(row, dict)]


def reviewer_id(execution_id: str, candidate_sha: str, revision: str) -> str:
    value = "REVIEW-SEMANTIC-" + hashlib.sha256(f"{execution_id}|{candidate_sha}|{revision}".encode()).hexdigest()[:24]
    if value == execution_id:
        raise RuntimeError("BOUND_SEMANTIC_REVIEWER_NOT_INDEPENDENT")
    return value


def result_schema() -> dict[str, Any]:
    fields = ["verdict","candidate_sha256","scope_packet_sha256","evidence_manifest_sha256","reviewer_execution_id","review_input_sha256","reviewer_context_mode","review_input_classes","source_refs_inspected","observed_candidate_changes","requirement_reconciliation","change_declaration_reconciliation","scope_conformance_reconciliation","invariant_results","open_design_decisions_found","unsupported_claims","blocking_codes","repair_instructions","next_gate"]
    props = {key: {} for key in fields}
    for key in ("verdict","candidate_sha256","scope_packet_sha256","evidence_manifest_sha256","reviewer_execution_id","review_input_sha256","reviewer_context_mode"):
        props[key] = {"type":"string"}
    for key in ("review_input_classes","source_refs_inspected","observed_candidate_changes","requirement_reconciliation","change_declaration_reconciliation","scope_conformance_reconciliation","invariant_results","open_design_decisions_found","unsupported_claims","blocking_codes","repair_instructions"):
        props[key] = {"type":"array"}
    return {"type":"object","required":fields,"properties":props}


def model_call(system_prompt: str, review_input: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    user = json.dumps(review_input, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    max_output = int(env("PROFILE_RUNTIME_SEMANTIC_MAX_OUTPUT_TOKENS", "4096"))
    context = int(env("PROFILE_RUNTIME_SEMANTIC_CONTEXT_TOKENS", "16384"))
    estimated = (len(system_prompt.encode()) + len(user.encode()) + 3) // 4
    if estimated + max_output > context:
        raise RuntimeError("BOUND_SEMANTIC_CONTEXT_BUDGET_EXCEEDED")
    if len(system_prompt) + len(user) > int(env("PROFILE_RUNTIME_MAX_PROMPT_CHARS", "120000")):
        raise RuntimeError("BOUND_SEMANTIC_PROMPT_CHAR_BUDGET_EXCEEDED")
    body = json.dumps({
        "messages":[{"role":"system","content":system_prompt},{"role":"user","content":user}],
        "stream":False,"temperature":0.0,"top_p":1.0,"seed":42,"max_tokens":max_output,"cache_prompt":True,
        "response_format":{"type":"json_object","schema":result_schema()},
    }, ensure_ascii=False).encode()
    request = urllib.request.Request(env("PROFILE_RUNTIME_LLAMA_BASE_URL", "http://127.0.0.1:8080").rstrip("/") + "/v1/chat/completions", data=body, headers={"Content-Type":"application/json","Accept":"application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=float(env("PROFILE_RUNTIME_LLAMA_TIMEOUT_SECONDS", "300"))) as response:
            payload = json.loads(response.read(4194305).decode())
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError("BOUND_SEMANTIC_MODEL_CALL_FAILED") from exc
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("BOUND_SEMANTIC_MODEL_RESPONSE_INVALID")
    message = choices[0].get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, str):
        raise RuntimeError("BOUND_SEMANTIC_MODEL_CONTENT_MISSING")
    result = json.loads(content)
    if not isinstance(result, dict):
        raise RuntimeError("BOUND_SEMANTIC_MODEL_RESULT_INVALID")
    return result, {"provider":PROVIDER,"model_id":str(payload.get("model") or ""),"response_id":str(payload.get("id") or ""),"finish_reason":str(choices[0].get("finish_reason") or ""),"usage":payload.get("usage") if isinstance(payload.get("usage"),dict) else {},"estimated_input_tokens":estimated,"semantic_context_tokens":context}


def run_validator(source: str, result: dict[str, Any], scope: dict[str, Any], expected: dict[str, str]) -> dict[str, Any]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bound-semantic-", dir=STATE_DIR) as tmp:
        root = Path(tmp); validator = root/"validator.py"; result_file=root/"result.json"; scope_file=root/"scope.json"
        validator.write_text(source, encoding="utf-8"); result_file.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8"); scope_file.write_text(json.dumps(scope, ensure_ascii=False), encoding="utf-8")
        cmd=[sys.executable,"-I",str(validator),str(result_file),"--scope-packet",str(scope_file),"--candidate-sha256",expected["candidate_sha256"],"--scope-packet-sha256",expected["scope_packet_sha256"],"--evidence-manifest-sha256",expected["evidence_manifest_sha256"],"--reviewer-execution-id",expected["reviewer_execution_id"],"--review-input-sha256",expected["review_input_sha256"]]
        proc=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=30)
        try: output=json.loads(proc.stdout.strip())
        except json.JSONDecodeError as exc: raise RuntimeError("BOUND_SEMANTIC_VALIDATOR_OUTPUT_INVALID") from exc
        if not isinstance(output,dict): raise RuntimeError("BOUND_SEMANTIC_VALIDATOR_RESULT_INVALID")
        output["exit_code"]=proc.returncode; return output


def server_fingerprints(conn: psycopg.Connection, scope: dict[str, Any], evidence: dict[str, Any]) -> tuple[str,str]:
    with conn.cursor() as cur:
        cur.execute("select encode(extensions.digest(convert_to((%s::jsonb)::text,'UTF8'),'sha256'),'hex'), encode(extensions.digest(convert_to((%s::jsonb)::text,'UTF8'),'sha256'),'hex')",(Jsonb(scope),Jsonb(evidence)))
        row=cur.fetchone()
    return "sha256:"+row[0],"sha256:"+row[1]


def review(conn: psycopg.Connection, claimed: dict[str, Any]) -> None:
    scope,candidate,evidence,deterministic=claimed.get("scope_packet"),claimed.get("exact_candidate"),claimed.get("evidence_manifest"),claimed.get("deterministic_result")
    validate_scope_packet(scope)
    if not isinstance(candidate,dict) or not isinstance(evidence,dict) or not isinstance(deterministic,dict) or deterministic.get("status")!="PASS":
        raise RuntimeError("BOUND_SEMANTIC_INPUT_OR_PREDECESSOR_INVALID")
    candidate_sha=sha256_json(candidate); declared=str(claimed.get("candidate_digest") or "").removeprefix("sha256:")
    if SHA64.fullmatch(declared) is None or declared!=candidate_sha: raise RuntimeError("BOUND_SEMANTIC_CANDIDATE_DIGEST_MISMATCH")
    scope_sha,evidence_sha=sha256_json(scope),sha256_json(evidence)
    rid=reviewer_id(claimed["execution_id"],candidate_sha,claimed["profile_source_revision"])
    review_input={"scope_authority_packet":scope,"exact_candidate":candidate,"evidence_manifest":evidence,"current_authority_refs":authority_refs(evidence)}
    review_sha=sha256_json(review_input)
    expected={"candidate_sha256":candidate_sha,"scope_packet_sha256":scope_sha,"evidence_manifest_sha256":evidence_sha,"reviewer_execution_id":rid,"review_input_sha256":review_sha}
    judge_ref,judge_source,validator_ref,validator_source=profile_quality_sources(claimed)
    facts="\n".join([f"reviewer_execution_id={rid}",f"reviewer_context_mode={CONTEXT_MODE}",f"review_input_classes={'|'.join(INPUT_CLASSES)}",f"candidate_sha256={candidate_sha}",f"scope_packet_sha256={scope_sha}",f"evidence_manifest_sha256={evidence_sha}",f"review_input_sha256={review_sha}","The deterministic output_validate predecessor is server-recorded clean. Use no context outside the supplied JSON."])
    result,attestation=model_call(judge_source+"\n\n## Runtime-bound facts\n"+facts,review_input)
    validation=run_validator(validator_source,result,scope,expected)
    clean=result.get("verdict")=="PASS_INDEPENDENT_SEMANTIC" and validation.get("status")=="PASS" and validation.get("exit_code")==0
    result=dict(result); result["status"]="PASS" if clean else "BLOCKED"
    unsupported=result.get("unsupported_claims") if isinstance(result.get("unsupported_claims"),list) else ["SEMANTIC_JUDGE_UNSUPPORTED_CLAIMS_SHAPE_INVALID"]
    scope_fp,evidence_fp=server_fingerprints(conn,scope,evidence)
    step_payload={"semantic_judge_result":result,"unsupported_claims":unsupported,"semantic_result_validation":validation,"reviewer_runtime_attestation":attestation,"reviewer_execution_id":rid,"reviewer_runtime_provider":PROVIDER,"producer_execution_id":claimed["execution_id"],"producer_runtime_provider":claimed.get("producer_runtime_provider"),"judge_source_ref":judge_ref,"validator_source_ref":validator_ref,"scope_packet_server_fingerprint":scope_fp,"evidence_manifest_server_fingerprint":evidence_fp,"blocking_codes":[] if clean else sorted(set(validation.get("blocking_codes") or result.get("blocking_codes") or ["SEMANTIC_JUDGE_NOT_CLEAN"])),"source_refs":[judge_ref,validator_ref]}
    with conn.cursor() as cur:
        cur.execute("select public.lf_record_profile_semantic_judge_step_v1(%s,%s,%s,%s)",(claimed["execution_id"],f"supabase://public.lf_operation_execution_steps/{claimed['execution_id']}/semantic_judge#bound-independent-review",Jsonb(step_payload),rid))
        row=cur.fetchone()
        if row is None or not isinstance(row[0],dict): raise RuntimeError("BOUND_SEMANTIC_RECORDER_RESULT_INVALID")
        if clean and row[0].get("outcome")!="STEP_RECORDED": raise RuntimeError("BOUND_SEMANTIC_RECORDER_DID_NOT_PASS")
    conn.commit()


def run_once() -> bool:
    conn=connect()
    try:
        claimed=claim(conn)
        if claimed is None: return False
        review(conn,claimed); print(f"BOUND_SEMANTIC_EXECUTION_ID={claimed['execution_id']}",flush=True); return True
    except Exception as exc:
        conn.rollback(); print(f"BOUND_SEMANTIC_ERROR={type(exc).__name__}:{str(exc)[:500]}",flush=True); return True
    finally: conn.close()


def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument("--daemon",action="store_true"); parser.add_argument("--idle-seconds",type=float,default=3.0); args=parser.parse_args()
    if not args.daemon: return 0 if run_once() else 4
    while True:
        if not run_once(): time.sleep(max(0.5,args.idle_seconds))


if __name__=="__main__": raise SystemExit(main())

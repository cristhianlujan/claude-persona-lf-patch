#!/usr/bin/env python3
"""Independent semantic-judge consumer for governed EJECUCION_PERFIL_LF runs.

This worker is deliberately separate from the producer path. It only reviews executions
whose deterministic output_validate predecessor is clean. It receives the exact candidate,
evidence manifest, pre-producer scope authority packet, and bounded authority refs; it never
receives producer private reasoning/chat context.
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
INPUT_CLASSES = [
    "SCOPE_AUTHORITY_PACKET",
    "EXACT_CANDIDATE",
    "EVIDENCE_MANIFEST",
    "CURRENT_AUTHORITY_REFS",
]
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")
GITHUB_REF = re.compile(r"^github://(?P<repo>[^@]+)@(?P<rev>[0-9a-f]{40})/(?P<path>.+)$")
REPO_ROOT = Path(__file__).resolve().parents[3]
STATE_DIR = Path(os.environ.get("PROFILE_RUNTIME_STATE_DIR", "/var/lib/lf-profile-runtime-api"))


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _connect() -> psycopg.Connection:
    password = _env("LF_SUPABASE_DB_PASSWORD")
    project = _env("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv")
    host = _env("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com")
    if not password:
        raise RuntimeError("BOUND_SEMANTIC_DB_PASSWORD_MISSING")
    return psycopg.connect(
        host=host,
        port=5432,
        user=f"postgres.{project}",
        password=password,
        dbname="postgres",
        sslmode="require",
        autocommit=False,
    )


def _validate_scope_packet(packet: Any) -> None:
    if not isinstance(packet, dict):
        raise RuntimeError("BOUND_SEMANTIC_SCOPE_PACKET_MISSING")
    for key in (
        "authorized_requirements",
        "constraints",
        "forbidden_changes",
        "authority_precedence",
        "related_context_refs",
        "source_refs",
    ):
        if not isinstance(packet.get(key), list):
            raise RuntimeError(f"BOUND_SEMANTIC_SCOPE_PACKET_{key.upper()}_INVALID")
    seen: set[str] = set()
    for key in ("authorized_requirements", "constraints", "forbidden_changes"):
        for item in packet[key]:
            if not isinstance(item, dict):
                raise RuntimeError("BOUND_SEMANTIC_SCOPE_ITEM_INVALID")
            item_id = item.get("id")
            if not isinstance(item_id, str) or not item_id or item_id in seen:
                raise RuntimeError("BOUND_SEMANTIC_SCOPE_ITEM_ID_INVALID")
            seen.add(item_id)
            for required in ("statement", "source_ref", "materiality"):
                if not isinstance(item.get(required), str) or not item[required].strip():
                    raise RuntimeError("BOUND_SEMANTIC_SCOPE_ITEM_FIELD_INVALID")


def _safe_repo_path(path: str) -> Path:
    rel = Path(path)
    if rel.is_absolute() or ".." in rel.parts or ":" in path or "\x00" in path:
        raise RuntimeError("BOUND_SEMANTIC_SOURCE_PATH_INVALID")
    resolved = (REPO_ROOT / rel).resolve()
    try:
        resolved.relative_to(REPO_ROOT.resolve())
    except ValueError as exc:
        raise RuntimeError("BOUND_SEMANTIC_SOURCE_PATH_ESCAPE") from exc
    return resolved


def _fetch_exact_github_text(ref: str) -> str:
    match = GITHUB_REF.fullmatch(ref or "")
    if not match or match.group("repo") != REPO:
        raise RuntimeError("BOUND_SEMANTIC_GITHUB_REF_INVALID")
    revision = match.group("rev")
    path = match.group("path")
    current = _env("PROFILE_RUNTIME_SOURCE_SHA")
    if revision == current:
        local = _safe_repo_path(path)
        if not local.is_file():
            raise RuntimeError("BOUND_SEMANTIC_LOCAL_SOURCE_MISSING")
        return local.read_text(encoding="utf-8")

    quoted_path = "/".join(urllib.parse.quote(part, safe="") for part in Path(path).parts)
    url = f"https://raw.githubusercontent.com/{REPO}/{revision}/{quoted_path}"
    headers = {"Accept": "text/plain"}
    token = _env("PROFILE_RUNTIME_GITHUB_TOKEN") or _env("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raw = response.read(512 * 1024 + 1)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError("BOUND_SEMANTIC_EXACT_SOURCE_UNRESOLVED") from exc
    if len(raw) > 512 * 1024:
        raise RuntimeError("BOUND_SEMANTIC_EXACT_SOURCE_TOO_LARGE")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError("BOUND_SEMANTIC_EXACT_SOURCE_NOT_UTF8") from exc


def _runtime_binding(execution: dict[str, Any]) -> tuple[str, str, str, str]:
    revision = str(execution.get("profile_source_revision") or "")
    target_path = str(execution.get("target_path") or "")
    if SHA40.fullmatch(revision) is None or not target_path.startswith("profiles/"):
        raise RuntimeError("BOUND_SEMANTIC_PROFILE_SOURCE_BINDING_INVALID")
    profile_root = target_path.rsplit("/", 1)[0]
    binding_ref = f"github://{REPO}@{revision}/{profile_root}/contracts/runtime_binding.json"
    binding = json.loads(_fetch_exact_github_text(binding_ref))
    boundary = binding.get("canonical_quality_boundary")
    if not isinstance(boundary, dict) or boundary.get("semantic_judge_is_model_executed") is not True:
        raise RuntimeError("BOUND_SEMANTIC_RUNTIME_BINDING_INVALID")
    judge_path = boundary.get("semantic_judge_path")
    validator_path = boundary.get("semantic_result_validator_path")
    if not isinstance(judge_path, str) or not isinstance(validator_path, str):
        raise RuntimeError("BOUND_SEMANTIC_RUNTIME_BINDING_PATH_MISSING")
    judge_ref = f"github://{REPO}@{revision}/{profile_root}/{judge_path}"
    validator_ref = f"github://{REPO}@{revision}/{profile_root}/{validator_path}"
    return judge_ref, _fetch_exact_github_text(judge_ref), validator_ref, _fetch_exact_github_text(validator_ref)


def _claim(conn: psycopg.Connection) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute(
            """
            with candidate as (
              select e.execution_id
              from public.lf_operation_execution e
              join public.lf_operation_execution_steps ov
                on ov.execution_id=e.execution_id
               and ov.step_id='output_validate'
               and ov.status='STEP_PASS_WITH_EVIDENCE'
              join public.lf_operation_execution_steps ep
                on ep.execution_id=e.execution_id
               and ep.step_id='execute_profile'
               and ep.status='STEP_PASS_WITH_EVIDENCE'
              left join public.lf_operation_execution_steps sj
                on sj.execution_id=e.execution_id and sj.step_id='semantic_judge'
              where e.operation_code='EJECUCION_PERFIL_LF'
                and e.target_type='PERFIL'
                and e.status='IN_PROGRESS'
                and jsonb_typeof(e.manifest->'semantic_scope_authority_packet')='object'
                and (sj.execution_id is null or sj.status<>'STEP_PASS_WITH_EVIDENCE')
              order by e.started_at,e.execution_id
              for update of e skip locked
              limit 1
            )
            select e.execution_id,e.target_path,e.manifest->>'profile_source_revision' as profile_source_revision,
                   e.manifest->>'runtime_provider' as producer_runtime_provider,
                   e.manifest->'semantic_scope_authority_packet' as scope_packet,
                   ep.evidence_payload->'profile_output' as exact_candidate,
                   ep.evidence_payload->'evidence_manifest' as evidence_manifest,
                   ep.evidence_payload->>'candidate_digest' as candidate_digest,
                   ov.evidence_payload->'output_contract_result' as deterministic_result
            from candidate c
            join public.lf_operation_execution e on e.execution_id=c.execution_id
            join public.lf_operation_execution_steps ep on ep.execution_id=e.execution_id and ep.step_id='execute_profile'
            join public.lf_operation_execution_steps ov on ov.execution_id=e.execution_id and ov.step_id='output_validate'
            """
        )
        row = cur.fetchone()
        if row is None:
            conn.rollback()
            return None
        cols = [d.name for d in cur.description]
        result = dict(zip(cols, row))
        conn.commit()
        return result


def _bounded_authority_refs(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    rows = manifest.get("evidence") if isinstance(manifest, dict) else None
    if not isinstance(rows, list):
        raise RuntimeError("BOUND_SEMANTIC_EVIDENCE_MANIFEST_INVALID")
    out: list[dict[str, Any]] = []
    for row in rows[:64]:
        if not isinstance(row, dict):
            continue
        out.append({
            key: row.get(key)
            for key in ("evidence_id", "subject", "evidence_class", "source_locator", "revision_or_observed_at", "digest", "state")
        })
    return out


def _reviewer_execution_id(producer_execution_id: str, candidate_sha: str, revision: str) -> str:
    digest = hashlib.sha256(f"{producer_execution_id}|{candidate_sha}|{revision}".encode()).hexdigest()[:24]
    value = f"REVIEW-SEMANTIC-{digest}"
    if value == producer_execution_id:
        raise RuntimeError("BOUND_SEMANTIC_REVIEWER_ID_NOT_INDEPENDENT")
    return value


def _result_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "required": [
            "verdict","candidate_sha256","scope_packet_sha256","evidence_manifest_sha256",
            "reviewer_execution_id","review_input_sha256","reviewer_context_mode","review_input_classes",
            "source_refs_inspected","observed_candidate_changes","requirement_reconciliation",
            "change_declaration_reconciliation","scope_conformance_reconciliation","invariant_results",
            "open_design_decisions_found","unsupported_claims","blocking_codes","repair_instructions","next_gate"
        ],
        "properties": {
            "verdict": {"type":"string"},
            "candidate_sha256": {"type":"string"},
            "scope_packet_sha256": {"type":"string"},
            "evidence_manifest_sha256": {"type":"string"},
            "reviewer_execution_id": {"type":"string"},
            "review_input_sha256": {"type":"string"},
            "reviewer_context_mode": {"type":"string"},
            "review_input_classes": {"type":"array","items":{"type":"string"}},
            "source_refs_inspected": {"type":"array","items":{"type":"string"}},
            "observed_candidate_changes": {"type":"array","items":{"type":"object"}},
            "requirement_reconciliation": {"type":"array","items":{"type":"object"}},
            "change_declaration_reconciliation": {"type":"array","items":{"type":"object"}},
            "scope_conformance_reconciliation": {"type":"array","items":{"type":"object"}},
            "invariant_results": {"type":"array","items":{"type":"object"}},
            "open_design_decisions_found": {"type":"array","items":{}},
            "unsupported_claims": {"type":"array","items":{}},
            "blocking_codes": {"type":"array","items":{"type":"string"}},
            "repair_instructions": {"type":"array","items":{}},
            "next_gate": {}
        }
    }


def _call_model(judge_prompt: str, review_input: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    user_content = json.dumps(review_input, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    prompt_chars = len(judge_prompt) + len(user_content)
    semantic_context_tokens = int(_env("PROFILE_RUNTIME_SEMANTIC_CONTEXT_TOKENS", "16384"))
    max_output_tokens = int(_env("PROFILE_RUNTIME_SEMANTIC_MAX_OUTPUT_TOKENS", "4096"))
    estimated_input_tokens = (len(judge_prompt.encode("utf-8")) + len(user_content.encode("utf-8")) + 3) // 4
    if estimated_input_tokens + max_output_tokens > semantic_context_tokens:
        raise RuntimeError("BOUND_SEMANTIC_CONTEXT_BUDGET_EXCEEDED")
    max_prompt_chars = int(_env("PROFILE_RUNTIME_MAX_PROMPT_CHARS", "120000"))
    if prompt_chars > max_prompt_chars:
        raise RuntimeError("BOUND_SEMANTIC_PROMPT_CHAR_BUDGET_EXCEEDED")
    payload = {
        "messages": [
            {"role":"system","content":judge_prompt},
            {"role":"user","content":user_content},
        ],
        "stream": False,
        "temperature": 0.0,
        "top_p": 1.0,
        "seed": 42,
        "max_tokens": max_output_tokens,
        "cache_prompt": True,
        "response_format": {"type":"json_object","schema":_result_schema()},
    }
    base = _env("PROFILE_RUNTIME_LLAMA_BASE_URL", "http://127.0.0.1:8080").rstrip("/")
    req = urllib.request.Request(
        base + "/v1/chat/completions",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type":"application/json","Accept":"application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=float(_env("PROFILE_RUNTIME_LLAMA_TIMEOUT_SECONDS", "300"))) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError("BOUND_SEMANTIC_MODEL_CALL_FAILED") from exc
    if len(raw) > 4 * 1024 * 1024:
        raise RuntimeError("BOUND_SEMANTIC_MODEL_RESPONSE_TOO_LARGE")
    response = json.loads(raw.decode("utf-8"))
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("BOUND_SEMANTIC_MODEL_RESPONSE_INVALID")
    message = choices[0].get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("BOUND_SEMANTIC_MODEL_CONTENT_EMPTY")
    try:
        result = json.loads(content)
    except json.JSONDecodeError as exc:
        raise RuntimeError("BOUND_SEMANTIC_MODEL_JSON_INVALID") from exc
    if not isinstance(result, dict):
        raise RuntimeError("BOUND_SEMANTIC_MODEL_RESULT_NOT_OBJECT")
    attestation = {
        "provider": PROVIDER,
        "model_id": str(response.get("model") or ""),
        "response_id": str(response.get("id") or ""),
        "finish_reason": str(choices[0].get("finish_reason") or ""),
        "usage": response.get("usage") if isinstance(response.get("usage"), dict) else {},
        "estimated_input_tokens": estimated_input_tokens,
        "semantic_context_tokens": semantic_context_tokens,
    }
    return result, attestation


def _run_exact_validator(
    source: str,
    result: dict[str, Any],
    scope_packet: dict[str, Any],
    expected: dict[str, str],
) -> dict[str, Any]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="semantic-judge-", dir=STATE_DIR) as tmp:
        root = Path(tmp)
        validator_path = root / "validator.py"
        result_path = root / "result.json"
        scope_path = root / "scope.json"
        validator_path.write_text(source, encoding="utf-8")
        result_path.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
        scope_path.write_text(json.dumps(scope_packet, ensure_ascii=False), encoding="utf-8")
        cmd = [
            sys.executable,"-I",str(validator_path),str(result_path),
            "--scope-packet",str(scope_path),
            "--candidate-sha256",expected["candidate_sha256"],
            "--scope-packet-sha256",expected["scope_packet_sha256"],
            "--evidence-manifest-sha256",expected["evidence_manifest_sha256"],
            "--reviewer-execution-id",expected["reviewer_execution_id"],
            "--review-input-sha256",expected["review_input_sha256"],
        ]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        try:
            validated = json.loads(proc.stdout.strip())
        except json.JSONDecodeError as exc:
            raise RuntimeError("BOUND_SEMANTIC_VALIDATOR_OUTPUT_INVALID") from exc
        if not isinstance(validated, dict):
            raise RuntimeError("BOUND_SEMANTIC_VALIDATOR_RESULT_INVALID")
        validated["exit_code"] = proc.returncode
        return validated


def _record(conn: psycopg.Connection, claimed: dict[str, Any], result: dict[str, Any], validation: dict[str, Any], attestation: dict[str, Any], judge_ref: str, validator_ref: str, expected: dict[str, str]) -> None:
    verdict = result.get("verdict")
    clean = verdict == "PASS_INDEPENDENT_SEMANTIC" and validation.get("status") == "PASS" and validation.get("exit_code") == 0
    result = dict(result)
    result["status"] = "PASS" if clean else "BLOCKED"
    unsupported = result.get("unsupported_claims")
    if not isinstance(unsupported, list):
        unsupported = ["SEMANTIC_JUDGE_UNSUPPORTED_CLAIMS_SHAPE_INVALID"]
    payload = {
        "semantic_judge_result": result,
        "unsupported_claims": unsupported,
        "semantic_result_validation": validation,
        "reviewer_runtime_attestation": attestation,
        "reviewer_execution_id": expected["reviewer_execution_id"],
        "reviewer_runtime_provider": PROVIDER,
        "producer_execution_id": claimed["execution_id"],
        "producer_runtime_provider": claimed.get("producer_runtime_provider"),
        "judge_source_ref": judge_ref,
        "validator_source_ref": validator_ref,
        "scope_packet_server_fingerprint": claimed["scope_packet_server_fingerprint"],
        "evidence_manifest_server_fingerprint": claimed["evidence_manifest_server_fingerprint"],
        "blocking_codes": [] if clean else sorted(set(validation.get("blocking_codes") or result.get("blocking_codes") or ["SEMANTIC_JUDGE_NOT_CLEAN"])),
        "source_refs": [judge_ref, validator_ref],
    }
    with conn.cursor() as cur:
        cur.execute(
            "select public.lf_record_profile_semantic_judge_step_v1(%s,%s,%s,%s)",
            (
                claimed["execution_id"],
                f"supabase://public.lf_operation_execution_steps/{claimed['execution_id']}/semantic_judge#bound-independent-review",
                Jsonb(payload),
                expected["reviewer_execution_id"],
            ),
        )
        row = cur.fetchone()
        if row is None or not isinstance(row[0], dict):
            raise RuntimeError("BOUND_SEMANTIC_RECORDER_RESULT_INVALID")
        if clean and row[0].get("outcome") != "STEP_RECORDED":
            raise RuntimeError("BOUND_SEMANTIC_RECORDER_DID_NOT_PASS")
    conn.commit()


def _review(conn: psycopg.Connection, claimed: dict[str, Any]) -> None:
    scope_packet = claimed.get("scope_packet")
    candidate = claimed.get("exact_candidate")
    evidence_manifest = claimed.get("evidence_manifest")
    deterministic = claimed.get("deterministic_result")
    _validate_scope_packet(scope_packet)
    if not isinstance(candidate, dict) or not isinstance(evidence_manifest, dict):
        raise RuntimeError("BOUND_SEMANTIC_REVIEW_INPUT_MISSING")
    if not isinstance(deterministic, dict) or deterministic.get("status") != "PASS":
        raise RuntimeError("BOUND_SEMANTIC_DETERMINISTIC_PREDECESSOR_NOT_PASS")
    candidate_sha = _sha256(candidate)
    declared = str(claimed.get("candidate_digest") or "")
    if declared.startswith("sha256:"):
        declared = declared[7:]
    if not SHA64.fullmatch(declared) or declared != candidate_sha:
        raise RuntimeError("BOUND_SEMANTIC_CANDIDATE_DIGEST_MISMATCH")
    scope_sha = _sha256(scope_packet)
    evidence_sha = _sha256(evidence_manifest)
    reviewer_id = _reviewer_execution_id(claimed["execution_id"], candidate_sha, claimed["profile_source_revision"])
    current_refs = _bounded_authority_refs(evidence_manifest)
    review_input = {
        "scope_authority_packet": scope_packet,
        "exact_candidate": candidate,
        "evidence_manifest": evidence_manifest,
        "current_authority_refs": current_refs,
    }
    review_input_sha = _sha256(review_input)
    expected = {
        "candidate_sha256": candidate_sha,
        "scope_packet_sha256": scope_sha,
        "evidence_manifest_sha256": evidence_sha,
        "reviewer_execution_id": reviewer_id,
        "review_input_sha256": review_input_sha,
    }
    judge_ref, judge_source, validator_ref, validator_source = _runtime_binding(claimed)
    system_prompt = judge_source + "\n\n## Runtime-bound facts\n" + "\n".join([
        f"reviewer_execution_id={reviewer_id}",
        f"reviewer_context_mode={CONTEXT_MODE}",
        f"review_input_classes={'|'.join(INPUT_CLASSES)}",
        f"candidate_sha256={candidate_sha}",
        f"scope_packet_sha256={scope_sha}",
        f"evidence_manifest_sha256={evidence_sha}",
        f"review_input_sha256={review_input_sha}",
        "The deterministic output_validate predecessor is server-recorded clean. Do not infer any context outside the supplied JSON.",
    ])
    result, attestation = _call_model(system_prompt, review_input)
    validation = _run_exact_validator(validator_source, result, scope_packet, expected)
    _record(conn, claimed, result, validation, attestation, judge_ref, validator_ref, expected)


def _server_fingerprints(conn: psycopg.Connection, claimed: dict[str, Any]) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            select encode(extensions.digest(convert_to((%s::jsonb)::text,'UTF8'),'sha256'),'hex'),
                   encode(extensions.digest(convert_to((%s::jsonb)::text,'UTF8'),'sha256'),'hex')
            """,
            (Jsonb(claimed["scope_packet"]), Jsonb(claimed["evidence_manifest"])),
        )
        row = cur.fetchone()
    claimed["scope_packet_server_fingerprint"] = "sha256:" + row[0]
    claimed["evidence_manifest_server_fingerprint"] = "sha256:" + row[1]


def run_once() -> bool:
    conn = _connect()
    try:
        claimed = _claim(conn)
        if claimed is None:
            return False
        _server_fingerprints(conn, claimed)
        _review(conn, claimed)
        print(f"BOUND_SEMANTIC_EXECUTION_ID={claimed['execution_id']}", flush=True)
        return True
    except Exception as exc:
        conn.rollback()
        print(f"BOUND_SEMANTIC_ERROR={type(exc).__name__}:{str(exc)[:500]}", flush=True)
        return True
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--idle-seconds", type=float, default=3.0)
    args = parser.parse_args()
    if not args.daemon:
        return 0 if run_once() else 4
    while True:
        did_work = run_once()
        if not did_work:
            time.sleep(max(0.5, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())

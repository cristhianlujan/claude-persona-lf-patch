#!/usr/bin/env python3
"""Governed GitHub Actions -> PostgreSQL Pooler fallback for LF reconciliation.

This fallback is eligible only when the canonical Supabase Edge Function responds
HTTP 402 with `exceed_egress_quota`. It preserves the existing fail-closed V7
reconciliation/gate functions and their single-use HMAC nonce contract.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import subprocess
from typing import Any, NoReturn

REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
REPOSITORY_ID = "1244397752"
WORKFLOW_REF = f"{REPOSITORY}/.github/workflows/lf-github-reconcile-v3.yml@refs/heads/main"
WORKFLOW_NAME = "LF GitHub Reconciliation V3"
OIDC_AUDIENCE = "lf-supabase-github-reconcile-v3"
WRITER_MODE = "GITHUB_OIDC_HMAC_NONCE_V7"
FALLBACK_MODE = "POOLER_DIRECT_ON_EDGE_402_V1"
PROJECT_ID = "mhwmirqcgxxukpctffuv"
POOLER_HOST = "aws-1-us-east-1.pooler.supabase.com"


def _fail(code: str, detail: str = "") -> NoReturn:
    suffix = f":{detail}" if detail else ""
    raise SystemExit(f"{code}{suffix}")


def is_edge_402_quota(status: int | str, body: str) -> bool:
    try:
        code = int(status)
    except (TypeError, ValueError):
        return False
    return code == 402 and "exceed_egress_quota" in (body or "").lower()


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def repository_path(item: dict[str, Any]) -> str:
    relative = str(item["relative_path"])
    if relative.startswith("skills/"):
        return relative
    return f"skills/{item['skill_code']}/{relative}"


def native_protection_verified(request: dict[str, Any]) -> bool:
    c = ((request.get("branch_protection_details") or {}).get("criteria") or {})
    return bool(
        request.get("branch_protection_status") == "VERIFIED"
        and c.get("active_rules_present") is True
        and c.get("lf_contract_check_required") is True
        and c.get("strict_status_checks") is True
        and c.get("solo_builder_review_policy") is True
        and c.get("non_fast_forward") is True
        and c.get("deletions_blocked") is True
        and c.get("bypass_actors_auditable") is True
        and c.get("bypass_actors_empty") is True
    )


def _decode_jwt_claims_unverified(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        _fail("FAIL_POOLER_FALLBACK_OIDC_FORMAT")
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
    except Exception as exc:
        _fail("FAIL_POOLER_FALLBACK_OIDC_DECODE", type(exc).__name__)
    if not isinstance(claims, dict):
        _fail("FAIL_POOLER_FALLBACK_OIDC_CLAIMS_TYPE")
    return claims


def _verify_oidc_signature_with_node(token: str) -> dict[str, Any]:
    script = r'''
const crypto = require('crypto');
(async () => {
  const token = process.env.LF_OIDC_VERIFY_TOKEN || '';
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('OIDC_FORMAT');
  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
  const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  const conf = await fetch('https://token.actions.githubusercontent.com/.well-known/openid-configuration').then(r => {
    if (!r.ok) throw new Error(`OIDC_DISCOVERY_${r.status}`);
    return r.json();
  });
  const jwks = await fetch(conf.jwks_uri).then(r => {
    if (!r.ok) throw new Error(`OIDC_JWKS_${r.status}`);
    return r.json();
  });
  const jwk = (jwks.keys || []).find(k => k.kid === header.kid && k.kty === 'RSA');
  if (!jwk) throw new Error('OIDC_KID_NOT_FOUND');
  const key = crypto.createPublicKey({key: jwk, format: 'jwk'});
  const ok = crypto.verify(
    'RSA-SHA256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    key,
    Buffer.from(parts[2], 'base64url'),
  );
  if (!ok) throw new Error('OIDC_SIGNATURE_INVALID');
  if (claims.iss !== 'https://token.actions.githubusercontent.com') throw new Error('OIDC_ISSUER_INVALID');
  const now = Math.floor(Date.now()/1000);
  if (!Number.isFinite(Number(claims.exp)) || Number(claims.exp) <= now - 5) throw new Error('OIDC_EXPIRED');
  if (claims.nbf !== undefined && Number(claims.nbf) > now + 5) throw new Error('OIDC_NOT_YET_VALID');
  process.stdout.write(JSON.stringify(claims));
})().catch(err => { console.error(String(err && err.message || err)); process.exit(23); });
'''
    env = os.environ.copy()
    env["LF_OIDC_VERIFY_TOKEN"] = token
    completed = subprocess.run(
        ["node", "-e", script], text=True, capture_output=True, env=env, check=False
    )
    if completed.returncode != 0:
        _fail("FAIL_POOLER_FALLBACK_OIDC_SIGNATURE", completed.stderr.strip()[:300])
    try:
        claims = json.loads(completed.stdout)
    except json.JSONDecodeError:
        _fail("FAIL_POOLER_FALLBACK_OIDC_VERIFIER_OUTPUT")
    return claims


def _validate_claims(claims: dict[str, Any]) -> None:
    expected_run = os.environ.get("GITHUB_RUN_ID", "").strip()
    checks = {
        "aud": claims.get("aud") == OIDC_AUDIENCE,
        "repository": claims.get("repository") == REPOSITORY,
        "repository_id": str(claims.get("repository_id", "")) == REPOSITORY_ID,
        "ref": claims.get("ref") == "refs/heads/main",
        "workflow_ref": claims.get("workflow_ref") == WORKFLOW_REF,
        "workflow": claims.get("workflow") == WORKFLOW_NAME,
        "event_name": claims.get("event_name") == "workflow_run",
        "run_id": bool(expected_run) and str(claims.get("run_id", "")) == expected_run,
        "workflow_sha": isinstance(claims.get("workflow_sha"), str)
        and len(str(claims.get("workflow_sha"))) == 40,
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        _fail("FAIL_POOLER_FALLBACK_OIDC_CLAIMS", ",".join(failed))


def verified_oidc() -> tuple[dict[str, Any], str]:
    token = os.environ.get("OIDC_TOKEN", "").strip()
    if not token:
        _fail("FAIL_POOLER_FALLBACK_OIDC_MISSING")
    _decode_jwt_claims_unverified(token)
    claims = _verify_oidc_signature_with_node(token)
    _validate_claims(claims)
    return claims, sha256_bytes(token.encode("utf-8"))


def _pg_env() -> dict[str, str]:
    password = os.environ.get("PGPASSWORD", "").strip() or os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    if not password:
        _fail("FAIL_POOLER_FALLBACK_DB_PASSWORD_MISSING")
    project = os.environ.get("SUPABASE_PROJECT_ID", PROJECT_ID).strip() or PROJECT_ID
    host = os.environ.get("SUPABASE_POOLER_HOST", POOLER_HOST).strip() or POOLER_HOST
    env = os.environ.copy()
    env.update(
        {
            "PGHOST": host,
            "PGPORT": "5432",
            "PGUSER": f"postgres.{project}",
            "PGPASSWORD": password,
            "PGDATABASE": "postgres",
            "PGSSLMODE": "require",
        }
    )
    return env


def _psql(sql: str) -> str:
    env = _pg_env()
    cmd = [
        "docker", "run", "--rm", "-i",
        "-e", "PGHOST", "-e", "PGPORT", "-e", "PGUSER", "-e", "PGPASSWORD",
        "-e", "PGDATABASE", "-e", "PGSSLMODE",
        "postgres:17.6", "psql", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1",
    ]
    completed = subprocess.run(cmd, input=sql, text=True, capture_output=True, env=env, check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " | ")[:900]
        _fail("FAIL_POOLER_FALLBACK_PSQL", detail)
    return completed.stdout.strip()


def _db_json(sql: str) -> Any:
    raw = _psql(sql)
    if not raw:
        _fail("FAIL_POOLER_FALLBACK_DB_EMPTY_JSON")
    line = raw.splitlines()[-1]
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        _fail("FAIL_POOLER_FALLBACK_DB_INVALID_JSON", line[:300])


def fetch_inventory() -> list[dict[str, Any]]:
    data = _db_json("""
select coalesce(jsonb_agg(to_jsonb(i) order by i.artifact_id),'[]'::jsonb)::text
from public.get_lf_github_reconciliation_inventory_v3() i;
""")
    if not isinstance(data, list) or not data:
        _fail("FAIL_POOLER_FALLBACK_INVENTORY_EMPTY")
    return data


def fetch_governance() -> list[dict[str, Any]]:
    data = _db_json("""
select coalesce(jsonb_agg(to_jsonb(g) order by g.path),'[]'::jsonb)::text
from public.get_lf_repository_governance_bundle_v4() g;
""")
    if not isinstance(data, list) or len(data) < 7:
        _fail("FAIL_POOLER_FALLBACK_GOVERNANCE_INCOMPLETE")
    return data


def _gh_api(path: str) -> Any:
    env = os.environ.copy()
    if not env.get("GH_TOKEN", "").strip():
        _fail("FAIL_POOLER_FALLBACK_GH_TOKEN_MISSING")
    completed = subprocess.run(
        ["gh", "api", f"repos/{REPOSITORY}/{path}"],
        text=True, capture_output=True, env=env, check=False,
    )
    if completed.returncode != 0:
        _fail("FAIL_POOLER_FALLBACK_GITHUB_API", completed.stderr.strip()[:500])
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        _fail("FAIL_POOLER_FALLBACK_GITHUB_JSON")


def verify_source(request: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    source = request.get("source") or {}
    source_id = int(source.get("id", 0))
    run = _gh_api(f"actions/runs/{source_id}")
    expected_sha = source.get("head_sha")
    if not (
        int(run.get("id", 0)) == source_id
        and run.get("name") == "lf-contract-check"
        and run.get("event") == "push"
        and run.get("head_branch") == "main"
        and run.get("head_sha") == expected_sha
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and ((run.get("repository") or {}).get("full_name") == REPOSITORY)
    ):
        _fail("FAIL_POOLER_FALLBACK_SOURCE_WORKFLOW")
    pulls = _gh_api(f"commits/{expected_sha}/pulls")
    merged = next(
        (pr for pr in pulls if pr.get("merged_at") and pr.get("state") == "closed" and pr.get("merge_commit_sha") == expected_sha),
        None,
    )
    if not merged:
        _fail("FAIL_POOLER_FALLBACK_MERGED_PR")
    return (
        {
            "id": source_id, "name": run.get("name"), "event": run.get("event"),
            "head_sha": run.get("head_sha"), "head_branch": run.get("head_branch"),
            "conclusion": run.get("conclusion"), "updated_at": run.get("updated_at"),
            "html_url": run.get("html_url"),
        },
        {"number": int(merged["number"]), "state": "MERGED", "merged": True, "merge_commit_sha": merged["merge_commit_sha"]},
    )


def verify_governance(governance: list[dict[str, Any]]) -> None:
    for expected in governance:
        path = pathlib.Path(str(expected["path"]))
        if path.is_absolute() or ".." in path.parts or not path.is_file():
            _fail("FAIL_POOLER_FALLBACK_GOVERNANCE_FILE_MISSING", str(path))
        data = path.read_bytes()
        if sha256_bytes(data) != expected.get("expected_sha256") or git_blob_sha(data) != expected.get("expected_git_blob"):
            _fail("FAIL_POOLER_FALLBACK_GOVERNANCE_DRIFT", str(path))


def _payload_b64(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def _text_b64(text: str) -> str:
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def _signed_record(payload: dict[str, Any], execution: str, kind: str) -> int:
    if kind == "reconciliation":
        preimage_fn = "private.fn_reconciliation_preimage_v7"
        record_fn = "public.record_external_ci_verification_v7"
    elif kind == "gate":
        preimage_fn = "private.fn_gate_preimage_v7"
        record_fn = "public.record_lf_gate_test_v7"
    else:
        _fail("FAIL_POOLER_FALLBACK_RECORD_KIND", kind)
    payload64 = _payload_b64(payload)
    execution64 = _text_b64(execution)
    sql = f"""
begin;
select set_config('request.jwt.claims','{{\"role\":\"service_role\"}}',true);
with v as (
  select convert_from(decode('{payload64}','base64'),'UTF8')::jsonb as payload,
         convert_from(decode('{execution64}','base64'),'UTF8') as execution
), p as (
  select v.*, {preimage_fn}(v.payload,v.execution) as preimage,
         pg_catalog.gen_random_uuid()::text || '.' ||
           (extract(epoch from clock_timestamp()+interval '4 minutes')::bigint)::text as nonce
  from v
), k as (
  select key_material
  from private.lf_writer_hmac_keys_v7
  where lifecycle_state='ACTIVE' and active and nullif(key_material,'') is not null
), s as (
  select p.payload,p.execution,p.nonce,
         encode(extensions.hmac(
           convert_to(p.preimage||':'||p.nonce,'UTF8'),
           convert_to((select key_material from k),'UTF8'),
           'sha256'
         ),'hex') as signature
  from p
)
select {record_fn}(payload,execution,signature,nonce)::text from s;
commit;
"""
    raw = _psql(sql)
    candidates = [line.strip() for line in raw.splitlines() if line.strip().isdigit()]
    if not candidates:
        _fail("FAIL_POOLER_FALLBACK_RECORD_ID", raw[:400])
    return int(candidates[-1])


def _promote(artifact_id: int, reconciliation_id: int, gate_id: int, execution: str) -> bool:
    execution64 = _text_b64(execution)
    sql = f"""
begin;
select set_config('request.jwt.claims','{{\"role\":\"service_role\"}}',true);
select public.promote_lf_artifact_pass_v3(
  {int(artifact_id)}::bigint,
  {int(reconciliation_id)}::bigint,
  array[{int(gate_id)}::bigint],
  convert_from(decode('{execution64}','base64'),'UTF8')
)::text;
commit;
"""
    try:
        raw = _psql(sql)
    except SystemExit as exc:
        if str(exc).startswith("FAIL_POOLER_FALLBACK_PSQL"):
            return False
        raise
    return any(line.strip() == "true" for line in raw.splitlines())


def _actual_file(item: dict[str, Any]) -> dict[str, Any] | None:
    path = pathlib.Path(repository_path(item))
    if not path.is_file():
        return None
    data = path.read_bytes()
    data.decode("utf-8")
    return {"path": str(path).replace("\\", "/"), "sha256": sha256_bytes(data), "git_blob": git_blob_sha(data)}


def persist(request_path: pathlib.Path, output: pathlib.Path, claims: dict[str, Any], token_sha256: str) -> None:
    request = json.loads(request_path.read_text(encoding="utf-8"))
    if request.get("action") != "reconcile":
        _fail("FAIL_POOLER_FALLBACK_REQUEST_ACTION")
    if str(request.get("reconciliation_workflow_run_id")) != os.environ.get("GITHUB_RUN_ID", ""):
        _fail("FAIL_POOLER_FALLBACK_RUN_BINDING")
    source, merged_pr = verify_source(request)
    head = source["head_sha"]
    current_head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if current_head != head:
        _fail("FAIL_POOLER_FALLBACK_CHECKOUT_BINDING", f"{current_head}!={head}")

    governance = fetch_governance()
    verify_governance(governance)
    inventory = fetch_inventory()
    reported = {int(item["artifact_id"]): item for item in request.get("artifacts") or []}
    native = native_protection_verified(request)
    stored_control = "VERIFIED" if native else "VERIFIED_COMPENSATING_CONTROLS"
    execution = f"GHA-OIDC-{claims['run_id']}-SRC-{source['id']}"
    claims_hash = sha256_bytes(json.dumps(claims, sort_keys=True, separators=(",", ":")).encode("utf-8"))

    results: list[dict[str, Any]] = []
    promotable: list[dict[str, int]] = []
    for item in inventory:
        artifact_id = int(item["artifact_id"])
        actual = _actual_file(item)
        manifest = reported.get(artifact_id)
        failures: list[str] = []
        if not native:
            failures.append("BRANCH_PROTECTION_NOT_VERIFIED")
        if not manifest:
            failures.append("ARTIFACT_NOT_REPORTED")
        if not actual:
            failures.append("ARTIFACT_REPOSITORY_READBACK_MISSING")
        if not bool(item.get("is_current")):
            failures.append("ARTIFACT_NOT_CURRENT")
        if manifest and manifest.get("relative_path") != item.get("relative_path"):
            failures.append("ARTIFACT_PATH_MISMATCH")
        if manifest and manifest.get("repository_path") and manifest.get("repository_path") != repository_path(item):
            failures.append("REPOSITORY_PATH_MISMATCH")
        if not actual or actual.get("sha256") != item.get("current_content_sha256"):
            failures.append("ARTIFACT_SHA256_MISMATCH")
        if not actual or len(str(actual.get("git_blob", ""))) != 40:
            failures.append("ARTIFACT_GIT_BLOB_MISSING")
        if not (manifest or {}).get("audit_covered"):
            failures.append("ARTIFACT_NOT_EXERCISED_BY_WORKFLOW")
        if manifest and actual and (
            manifest.get("sha256") != actual.get("sha256") or manifest.get("git_blob") != actual.get("git_blob")
        ):
            failures.append("MANIFEST_REPOSITORY_MISMATCH")

        reconciliation = {
            "result": "PASS" if not failures else "FAIL",
            "artifact_id": artifact_id,
            "repository": REPOSITORY,
            "target_branch": "main",
            "artifact_path": item["relative_path"],
            "pr_number": merged_pr["number"],
            "pr_state": merged_pr["state"],
            "merged": True,
            "merge_commit_sha": head,
            "workflow_run_id": int(source["id"]),
            "workflow_name": source["name"],
            "workflow_event": source["event"],
            "workflow_head_sha": head,
            "workflow_conclusion": source["conclusion"],
            "artifact_git_blob": (actual or {}).get("git_blob") or (manifest or {}).get("git_blob"),
            "artifact_sha256": (actual or {}).get("sha256") or (manifest or {}).get("sha256"),
            "file_touched_by_merge": bool((manifest or {}).get("file_touched_by_merge")),
            "artifact_exercised_by_workflow": bool((manifest or {}).get("audit_covered")),
            "audit_artifact_name": request["audit_artifact_name"],
            "audit_manifest_sha256": request["audit_manifest_sha256"],
            "branch_protection_status": stored_control,
            "failure_reasons": failures,
            "details": {
                "source_workflow_url": source["html_url"],
                "reconciliation_workflow_run_id": int(claims["run_id"]),
                "reconciliation_workflow_sha": claims.get("workflow_sha"),
                "workflow_ref": claims.get("workflow_ref"),
                "actual_branch_protection_status": request.get("branch_protection_status"),
                "branch_protection": request.get("branch_protection_details") or {},
                "repository_change_control": {
                    "status": request.get("branch_protection_status"),
                    "native_protection_verified": native,
                    "independent_source_run_readback": True,
                    "independent_merged_pr_readback": True,
                    "independent_artifact_content_readback": True,
                    "governance_bundle_verified": True,
                    "governance_file_count": len(governance),
                    "writer_authentication": WRITER_MODE,
                    "transport_fallback": FALLBACK_MODE,
                    "edge_http_status": 402,
                    "edge_error_code": "exceed_egress_quota",
                    "oidc_signature_verified": True,
                    "oidc_token_sha256": token_sha256,
                    "oidc_claims_sha256": claims_hash,
                },
                "baseline_content_sha256": item.get("baseline_content_sha256"),
                "repository_path": (actual or {}).get("path") or (manifest or {}).get("repository_path"),
            },
            "observed_at": source["updated_at"],
            "producer": "github-actions-oidc-pooler-fallback-hmac-v7",
            "purpose": "Persist independently verified fail-closed evidence through governed Pooler fallback after exact Edge 402 egress quota failure",
        }
        reconciliation_id = _signed_record(reconciliation, execution, "reconciliation")

        gate = {
            "test_code": "POST_MERGE-LF-CONTRACT-CHECK-V3",
            "artifact_id": artifact_id,
            "gate_code": "EXTERNAL-CI-V3",
            "test_kind": "INTEGRATION",
            "target_relation": item["relative_path"],
            "probe_preimage": {
                "source_workflow_run_id": int(source["id"]),
                "source_commit_sha": head,
                "artifact_path": item["relative_path"],
                "expected_sha256": item["current_content_sha256"],
                "independent_repository_sha256": (actual or {}).get("sha256"),
                "audit_manifest_sha256": request["audit_manifest_sha256"],
                "repository_change_control_status": request.get("branch_protection_status"),
                "transport_fallback": FALLBACK_MODE,
            },
            "expected_outcome": {
                "workflow_event": "push",
                "workflow_conclusion": "success",
                "artifact_sha256": item["current_content_sha256"],
                "audit_covered": True,
                "independent_readback": True,
                "native_branch_protection": True,
            },
            "observed_outcome": {
                "workflow_event": source["event"],
                "workflow_conclusion": source["conclusion"],
                "artifact_sha256": (actual or {}).get("sha256"),
                "audit_covered": bool((manifest or {}).get("audit_covered")),
                "independent_readback": bool(actual),
                "native_branch_protection": native,
                "failure_reasons": failures,
                "transport_fallback": FALLBACK_MODE,
            },
            "persisted_effects": {
                "rows": 1,
                "github_reconciliation_run_id": reconciliation_id,
                "source_workflow_run_id": int(source["id"]),
            },
            "passed": not failures,
            "runner_type": "GITHUB_ACTIONS_POST_MERGE",
            "runner_identity": WORKFLOW_REF,
            "source_workflow_run_id": int(source["id"]),
            "source_commit_sha": head,
            "executed_at": source["updated_at"],
            "producer": "github-actions-oidc-pooler-fallback-hmac-v7",
            "purpose": "Record reproducible post-merge evidence through governed Pooler fallback after exact Edge 402 egress quota failure",
        }
        gate_id = _signed_record(gate, execution, "gate")
        if not failures:
            promotable.append({"artifact_id": artifact_id, "reconciliation_run_id": reconciliation_id, "gate_test_run_id": gate_id})
        results.append({
            "artifact_id": artifact_id,
            "result": "PASS" if not failures else "FAIL",
            "failures": failures,
            "reconciliation_run_id": reconciliation_id,
            "gate_test_run_id": gate_id,
        })

    pending = list(promotable)
    promoted: list[int] = []
    if native:
        for _ in range(20):
            if not pending:
                break
            progress = False
            for idx in range(len(pending) - 1, -1, -1):
                item = pending[idx]
                if _promote(item["artifact_id"], item["reconciliation_run_id"], item["gate_test_run_id"], execution):
                    promoted.append(item["artifact_id"])
                    pending.pop(idx)
                    progress = True
            if not progress:
                break

    response = {
        "execution_id": execution,
        "source_workflow_run_id": source["id"],
        "source_commit_sha": head,
        "merged_pr_number": merged_pr["number"],
        "actual_branch_protection_status": request.get("branch_protection_status"),
        "native_branch_protection_verified": native,
        "writer_authentication": WRITER_MODE,
        "transport_fallback": FALLBACK_MODE,
        "edge_http_status": 402,
        "edge_error_code": "exceed_egress_quota",
        "governance_files_verified": len(governance),
        "artifacts_expected": len(inventory),
        "artifacts_reported": len(request.get("artifacts") or []),
        "pass_count": sum(1 for item in results if item["result"] == "PASS"),
        "fail_count": sum(1 for item in results if item["result"] == "FAIL"),
        "promoted_artifact_ids": promoted,
        "promotion_pending_artifact_ids": [item["artifact_id"] for item in pending],
        "results": results,
    }
    output.write_text(json.dumps(response, sort_keys=True, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({k: response[k] for k in (
        "execution_id", "source_commit_sha", "pass_count", "fail_count", "transport_fallback",
        "governance_files_verified", "promoted_artifact_ids", "promotion_pending_artifact_ids"
    )}, sort_keys=True))
    if response["fail_count"]:
        _fail("FAIL_POOLER_FALLBACK_RECONCILIATION_ARTIFACTS", str(response["fail_count"]))


def self_test() -> None:
    assert is_edge_402_quota(402, '{"code":"exceed_egress_quota"}')
    assert not is_edge_402_quota(500, '{"code":"exceed_egress_quota"}')
    assert not is_edge_402_quota(402, '{"code":"other"}')
    assert git_blob_sha(b"test\n") == "9daeafb9864cf43055ae93beb0afd6c7d144bfa4"
    item = {"relative_path": "schemas/x.json", "skill_code": "skill-x"}
    assert repository_path(item) == "skills/skill-x/schemas/x.json"
    req = {
        "branch_protection_status": "VERIFIED",
        "branch_protection_details": {"criteria": {
            "active_rules_present": True,
            "lf_contract_check_required": True,
            "strict_status_checks": True,
            "solo_builder_review_policy": True,
            "non_fast_forward": True,
            "deletions_blocked": True,
            "bypass_actors_auditable": True,
            "bypass_actors_empty": True,
        }},
    }
    assert native_protection_verified(req)
    req["branch_protection_details"]["criteria"]["bypass_actors_empty"] = False
    assert not native_protection_verified(req)
    print("PASS_GITHUB_RECONCILIATION_POOLER_FALLBACK_SELFTEST=7/7")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("self-test")
    inv = sub.add_parser("inventory")
    inv.add_argument("--output", type=pathlib.Path, default=pathlib.Path("governed-inventory.json"))
    per = sub.add_parser("persist")
    per.add_argument("--request", type=pathlib.Path, default=pathlib.Path("reconciliation-request.json"))
    per.add_argument("--output", type=pathlib.Path, default=pathlib.Path("reconciliation-response.json"))
    args = parser.parse_args()

    if args.command == "self-test":
        self_test()
        return
    claims, token_hash = verified_oidc()
    if args.command == "inventory":
        inventory = fetch_inventory()
        payload = {
            "repository": REPOSITORY,
            "writer_authentication": WRITER_MODE,
            "transport_fallback": FALLBACK_MODE,
            "inventory": inventory,
        }
        args.output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")), encoding="utf-8")
        print(json.dumps({"repository": REPOSITORY, "artifact_count": len(inventory), "transport_fallback": FALLBACK_MODE}, sort_keys=True))
        return
    persist(args.request, args.output, claims, token_hash)


if __name__ == "__main__":
    main()

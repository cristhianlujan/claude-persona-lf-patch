#!/usr/bin/env python3
"""Generate an inert, guarded LF Migration Train candidate for a documentary VIGENTE change.

This is a source generator, NOT a database writer. It requires exact readback
values and the official ACTUALIZACION_DB_LF Merge Train to perform any effect.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

SCHEMA = "LF_VIGENTE_DOCUMENTARY_MAINTENANCE_REQUEST_V1"
OPERATION = "ACTUALIZACION_DB_LF"
NAME_RE = re.compile(r"lf_[a-z0-9_]+_v[0-9]+\Z")
RULE_RE = re.compile(r"[A-Z0-9][A-Z0-9_-]{3,159}\Z")
HEX32_RE = re.compile(r"[0-9a-f]{32}\Z")
VERSION_RE = re.compile(r"20[0-9]{12}\Z")
MANDATORY_KEYS = {"schema_version", "operation_code", "train", "target", "before", "after", "authority"}


class CandidateError(ValueError):
    pass


def md5_utf8(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def literal(value: str) -> str:
    """Literal via collision-free PostgreSQL dollar quoting; never interpolated as code."""
    if "\x00" in value:
        raise CandidateError("BLOCK_DOCUMENT_NUL")
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    for i in range(32):
        delim = f"$lfdoc{digest[:14]}{i}$"
        if delim not in value:
            return f"{delim}{value}{delim}"
    raise CandidateError("BLOCK_DOCUMENT_DELIMITER_EXHAUSTED")


def check(condition: bool, code: str) -> None:
    if not condition:
        raise CandidateError(code)


def validate(packet: object) -> dict:
    check(isinstance(packet, dict) and set(packet) == MANDATORY_KEYS, "BLOCK_PACKET_SCHEMA")
    p = packet
    check(p["schema_version"] == SCHEMA and p["operation_code"] == OPERATION, "BLOCK_PACKET_CONTRACT")
    check(isinstance(p["train"], dict) and set(p["train"]) == {"pr_number", "migration_version", "migration_name"}, "BLOCK_TRAIN_SCHEMA")
    tr = p["train"]
    check(type(tr["pr_number"]) is int and tr["pr_number"] > 0, "BLOCK_TRAIN_PR_INVALID")
    check(isinstance(tr["migration_version"], str) and VERSION_RE.fullmatch(tr["migration_version"]) is not None, "BLOCK_TRAIN_VERSION_INVALID")
    check(isinstance(tr["migration_name"], str) and NAME_RE.fullmatch(tr["migration_name"]) is not None, "BLOCK_TRAIN_NAME_INVALID")
    check(isinstance(p["target"], dict) and set(p["target"]) == {"rule_id", "rule_code", "state", "column"}, "BLOCK_RULE_TARGET_SCHEMA")
    t = p["target"]
    check(type(t["rule_id"]) is int and t["rule_id"] > 0 and isinstance(t["rule_code"], str) and RULE_RE.fullmatch(t["rule_code"]) is not None, "BLOCK_RULE_IDENTITY")
    check(t["state"] == "VIGENTE" and t["column"] == "pendiente_detalle", "BLOCK_NOT_DOCUMENTARY_ONLY")
    check(isinstance(p["before"], dict) and set(p["before"]) == {"row_md5", "material_md5", "field_text"}, "BLOCK_BEFORE_SCHEMA")
    b = p["before"]
    check(isinstance(b["row_md5"], str) and HEX32_RE.fullmatch(b["row_md5"]) is not None, "BLOCK_BEFORE_ROW_HASH")
    check(isinstance(b["material_md5"], str) and HEX32_RE.fullmatch(b["material_md5"]) is not None, "BLOCK_BEFORE_MATERIAL_HASH")
    check(isinstance(b["field_text"], str), "BLOCK_BEFORE_TEXT_REQUIRED")
    check(isinstance(p["after"], dict) and set(p["after"]) == {"field_text"}, "BLOCK_AFTER_SCHEMA")
    a = p["after"]
    check(isinstance(a["field_text"], str) and len(a["field_text"]) <= 10000, "BLOCK_AFTER_TEXT_INVALID")
    check(a["field_text"] != b["field_text"], "BLOCK_NO_EFFECT_DOCUMENT")
    check(isinstance(p["authority"], dict) and set(p["authority"]) == {"decision_ref", "source_ref"}, "BLOCK_AUTHORITY_SCHEMA")
    auth = p["authority"]
    for ref in ("decision_ref", "source_ref"):
        v = auth[ref]
        check(isinstance(v, str) and 3 <= len(v) <= 512 and "\n" not in v and "\r" not in v and "\x00" not in v, "BLOCK_AUTHORITY_REFERENCE")
    # Authority references are claims to be checked by the Train/reviewer, never proof by themselves.
    return p


def generate(packet: object) -> str:
    p = validate(packet)
    tr, t, b, a, auth = (p[k] for k in ("train", "target", "before", "after", "authority"))
    pr = tr["pr_number"]
    name = tr["migration_name"]
    code = t["rule_code"]
    rid = t["rule_id"]
    before_text = literal(b["field_text"])
    after_text = literal(a["field_text"])
    old_hash = md5_utf8(b["field_text"])
    after_hash = md5_utf8(a["field_text"])
    # Only syntax-safe, whitelisted literals are interpolated as identifiers or patterns.
    return f"""-- LF governed documentary maintenance: {code} (VIGENTE).
-- Source (verify): {auth['source_ref']}
-- Decision (verify): {auth['decision_ref']}
-- Generated candidate; only ACTUALIZACION_DB_LF / official Merge Train can apply.
-- No change to estado, valor_config, policies, implementation, QA, or production.
-- One atomic DO statement: any RAISE rolls back the update in both Train paths.
-- After successful apply: reversal requires a NEW guarded governed migration.
DO $maintenance$
DECLARE
  v_rule lf_ops.reglas%ROWTYPE;
  v_exec_count integer;
  v_changed integer;
BEGIN
  SELECT count(*) INTO v_exec_count
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_execution_steps s
    ON s.execution_id=e.execution_id AND s.step_id='preflight' AND s.status='PASS_CLEAN'
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ '^20[0-9]{{12}}_{name}$'
    AND e.target_path='supabase/migrations/' || e.target_code || '.sql'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.execution_id LIKE 'EXEC-DB-TRAIN-PR{pr}-%'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='{pr}'
    AND e.manifest#>>'{{router_authority_receipt,schema_version}}'='LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
    AND e.manifest#>>'{{router_authority_receipt,target_code}}'=e.target_code
    AND e.manifest#>>'{{router_authority_receipt,operation_code}}'='ACTUALIZACION_DB_LF'
    AND s.evidence_payload->>'producer'='lf-migration-merge-train'
    AND s.evidence_payload#>>'{{exact_target,pr}}'='{pr}'
    AND s.evidence_payload#>>'{{exact_target,target_path}}'=e.target_path
    AND s.evidence_payload#>>'{{trust_validation,valid}}'='true'
    AND e.status='IN_PROGRESS';
  IF v_exec_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_VIGENTE_DOC_TRAIN_AUTHORITY_NOT_BOUND:%',v_exec_count;
  END IF;
  SELECT * INTO v_rule
    FROM lf_ops.reglas WHERE id={rid} AND codigo='{code}' FOR UPDATE;
  IF NOT FOUND
     OR v_rule.estado IS DISTINCT FROM 'VIGENTE'
     OR v_rule.pendiente_decision IS DISTINCT FROM false
     OR md5(to_jsonb(v_rule)::text) IS DISTINCT FROM '{b['row_md5']}'
     OR md5((to_jsonb(v_rule)-'pendiente_detalle'-'updated_at')::text) IS DISTINCT FROM '{b['material_md5']}'
     OR md5(v_rule.pendiente_detalle) IS DISTINCT FROM '{old_hash}'
     OR v_rule.pendiente_detalle IS DISTINCT FROM {before_text}
  THEN
    RAISE EXCEPTION 'BLOCK_VIGENTE_DOC_SOURCE_DRIFT_OR_STATE_CHANGE';
  END IF;
  UPDATE lf_ops.reglas AS r
  SET pendiente_detalle={after_text}, updated_at=clock_timestamp()
  WHERE r.id={rid} AND r.codigo='{code}' AND r.estado='VIGENTE'
    AND r.pendiente_decision=false
    AND md5(to_jsonb(r)::text)='{b['row_md5']}'
    AND r.pendiente_detalle IS NOT DISTINCT FROM {before_text};
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed<>1 THEN
    RAISE EXCEPTION 'BLOCK_VIGENTE_DOC_WRITE_CARDINALITY:%',v_changed;
  END IF;
  IF (SELECT count(*) FROM lf_ops.reglas r
    WHERE r.id={rid} AND r.codigo='{code}' AND r.estado='VIGENTE'
      AND r.pendiente_decision=false
      AND md5((to_jsonb(r)-'pendiente_detalle'-'updated_at')::text)='{b['material_md5']}'
      AND r.pendiente_detalle IS NOT DISTINCT FROM {after_text}
      AND md5(r.pendiente_detalle)='{after_hash}'
  )<>1 THEN
    RAISE EXCEPTION 'BLOCK_VIGENTE_DOC_READBACK_FAILED';
  END IF;
END;
$maintenance$;
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.packet.read_text(encoding="utf-8"))
    sql = generate(data)
    train = data["train"]
    expected_file = f"{train['migration_version']}_{train['migration_name']}.sql"
    check(args.output.as_posix().startswith("supabase/migrations/") and args.output.name == expected_file, "BLOCK_MIGRATION_OUTPUT_PATH")
    check(not args.output.is_symlink() and not args.output.exists(), "BLOCK_MIGRATION_OUTPUT_EXISTS")
    args.output.write_text(sql, encoding="utf-8")
    print(json.dumps({"status": "CANDIDATE_GENERATED_NOT_APPLIED", "path": args.output.as_posix(), "sha256": hashlib.sha256(sql.encode()).hexdigest(), "operation": OPERATION}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CandidateError, ValueError, OSError) as exc:
        print(json.dumps({"status": "BLOCKED", "code": str(exc)}, sort_keys=True))
        raise SystemExit(2)

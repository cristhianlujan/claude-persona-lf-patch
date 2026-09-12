#!/usr/bin/env python3
"""Evaluate the synthetic LF profile execution-strategy A/B corpus.

Reads only ABTEST_* rows from the private runtime queue. Raw outputs are emitted only
for this synthetic corpus so quality can be independently reviewed without exposing
non-test runtime data.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime

import psycopg

TABLE = "private.lf_profile_runtime_queue_v1"
KEY_RE = re.compile(r"^ABTEST_([AB])_CASE([123])(?:_|\.)")
EXPECTED_KEYS = {(v, c) for v in ("A", "B") for c in ("1", "2", "3")}

CASE_REQUIREMENTS = {
    "1": {
        "required_any": [
            ["8000", "8,000"], ["3200", "3,200"], ["4800", "4,800"],
            ["cash", "single", "one-time", "pago único", "contado"],
            ["installment", "cuota"], ["cta", "button", "continuar", "pagar", "aceptar"],
        ],
        "forbidden": ["guaranteed eligibility", "guaranteed approval", "debt cleared now"],
    },
    "2": {
        "required_any": [
            ["3 installment", "3 cuotas", "three installment"],
            ["due date", "fecha de vencimiento", "vencimiento"],
            ["retry", "reintento", "try again"], ["failure", "failed", "fallo", "error"],
            ["receipt", "comprobante"], ["letter", "carta"],
            ["completion", "after completion", "al completar", "after final", "última cuota", "final payment"],
        ],
        "forbidden": ["debt cleared immediately", "letter before completion", "guaranteed payment"],
    },
    "3": {
        "required_any": [
            ["dni"], ["otp"], ["whatsapp"], ["email", "correo"],
            ["consent", "consentimiento", "autoriza"], ["expiry", "expires", "vencimiento", "vigencia"],
            ["eligibility", "elegibilidad", "eligible"], ["document", "documento", "upload", "carga"],
            ["optional", "opcional"],
        ],
        "forbidden": ["pre-checked consent", "consent assumed", "guaranteed eligibility"],
    },
}


def canonical_json_sha256(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def connect() -> psycopg.Connection:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com").strip()
    if not password:
        raise SystemExit("FAIL_AB_DB_PASSWORD_MISSING")
    return psycopg.connect(
        host=host, port=5432, user=f"postgres.{project}", password=password,
        dbname="postgres", sslmode="require", autocommit=True,
    )


def assistant_text(raw_output) -> str:
    if isinstance(raw_output, str):
        text = raw_output
    else:
        text = json.dumps(raw_output, ensure_ascii=False, sort_keys=True)
    marker = "Assistant:"
    return text.split(marker, 1)[1].strip() if marker in text else text.strip()


def requirement_score(case_id: str, text: str) -> tuple[int, int, list[str], list[str]]:
    folded = text.casefold()
    reqs = CASE_REQUIREMENTS[case_id]["required_any"]
    missing: list[str] = []
    hit = 0
    for group in reqs:
        if any(term.casefold() in folded for term in group):
            hit += 1
        else:
            missing.append("|".join(group))
    forbidden_hit = [term for term in CASE_REQUIREMENTS[case_id]["forbidden"] if term.casefold() in folded]
    return hit, len(reqs), missing, forbidden_hit


def main() -> int:
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""
            select request_id::text, input_literal, status, started_at, completed_at,
                   raw_output, receipt, runtime_model_id, runtime_provider, created_at
              from {TABLE}
             where input_literal like 'ABTEST_A_CASE%'
                or input_literal like 'ABTEST_B_CASE%'
             order by created_at desc
            """
        )
        rows = cur.fetchall()

    latest = {}
    for row in rows:
        request_id, literal, status, started_at, completed_at, raw_output, receipt, model_id, provider, created_at = row
        match = KEY_RE.match(literal or "")
        if not match:
            continue
        key = (match.group(1), match.group(2))
        if key not in latest:
            latest[key] = row

    missing_keys = sorted(EXPECTED_KEYS - set(latest))
    if missing_keys:
        raise SystemExit("FAIL_AB_CORPUS_INCOMPLETE:" + json.dumps(missing_keys))

    results = []
    hard_fail = False
    for variant, case_id in sorted(EXPECTED_KEYS, key=lambda x: (int(x[1]), x[0])):
        row = latest[(variant, case_id)]
        request_id, literal, status, started_at, completed_at, raw_output, receipt, model_id, provider, created_at = row
        text = assistant_text(raw_output)
        receipt = receipt if isinstance(receipt, dict) else {}
        claimed_raw_sha = receipt.get("raw_output_sha256")
        actual_raw_sha = canonical_json_sha256(raw_output)
        raw_integrity = bool(claimed_raw_sha and claimed_raw_sha == actual_raw_sha)
        runtime_seconds = None
        if isinstance(started_at, datetime) and isinstance(completed_at, datetime):
            runtime_seconds = round((completed_at - started_at).total_seconds(), 3)
        hits, total, missing, forbidden = requirement_score(case_id, text)
        coverage = round(hits / total, 4) if total else 0.0
        nonempty = bool(text.strip())
        json_object = False
        try:
            parsed = json.loads(text)
            json_object = isinstance(parsed, dict)
        except Exception:
            parsed = None
        status_ok = status == "SUCCEEDED"
        quality_pass = status_ok and raw_integrity and nonempty and coverage >= 0.70 and not forbidden
        if not quality_pass:
            hard_fail = True
        results.append({
            "variant": variant,
            "case_id": case_id,
            "request_id": request_id,
            "status": status,
            "runtime_seconds": runtime_seconds,
            "input_chars": len(literal),
            "input_tokens_est_4char": round(len(literal) / 4),
            "output_chars": len(text),
            "output_tokens_est_4char": round(len(text) / 4),
            "raw_integrity": raw_integrity,
            "json_object": json_object,
            "coverage": coverage,
            "missing_requirements": missing,
            "forbidden_hits": forbidden,
            "quality_pass": quality_pass,
            "runtime_model_id": model_id,
            "runtime_provider": provider,
        })
        print(f"AB_RAW_BEGIN variant={variant} case={case_id} request_id={request_id}")
        print(text)
        print(f"AB_RAW_END variant={variant} case={case_id}")

    by_variant = {}
    for variant in ("A", "B"):
        subset = [r for r in results if r["variant"] == variant]
        by_variant[variant] = {
            "quality_pass_count": sum(1 for r in subset if r["quality_pass"]),
            "avg_coverage": round(sum(r["coverage"] for r in subset) / len(subset), 4),
            "input_tokens_est_total": sum(r["input_tokens_est_4char"] for r in subset),
            "output_tokens_est_total": sum(r["output_tokens_est_4char"] for r in subset),
            "runtime_seconds_avg": round(sum(r["runtime_seconds"] or 0 for r in subset) / len(subset), 3),
            "raw_integrity_all": all(r["raw_integrity"] for r in subset),
        }

    report = {
        "schema": "LF_PROFILE_STRATEGY_AB_REPORT_V1",
        "corpus": "synthetic_only",
        "cases": results,
        "variants": by_variant,
        "gate": "PASS" if not hard_fail else "FAIL",
        "notes": [
            "4-char token estimate is comparative, not provider billing telemetry",
            "quality gate combines raw receipt integrity, successful runtime, requirement coverage and forbidden-claim checks",
            "semantic review of emitted synthetic RAW output remains required before architecture adoption",
        ],
    }
    print("AB_REPORT_JSON=" + json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if not hard_fail else 2


if __name__ == "__main__":
    raise SystemExit(main())

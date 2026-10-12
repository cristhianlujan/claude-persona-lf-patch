"""M9.10 sandbox-only cohort expansion adapter.

Uses existing governed producer + M9.9 canonical evidence verifier. No own
cutover engine, hardcoded cohort IDs, synthetic receipts, or production commits.
A missing verified observation fails closed before any producer call.
The injected verifier must be the existing M9.9 canonical implementation; the
caller, not this adapter, owns binding verification of the Python callable.
"""
from __future__ import annotations

from collections import OrderedDict
from typing import Any, Callable


class EvidencePending(RuntimeError):
    """Canonical evidence is missing; this is NOT a successful expansion."""


def _fetch(conn: Any, sql: str, params: tuple = ()) -> list[tuple]:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def _snapshot(conn: Any) -> tuple:
    """Immutable baseline, including historic rows: compare deltas, not zero rows."""
    targets = (
        "public.lf_capability_current",
        "public.lf_capability_version_registry",
        "programacion.input_governance_cohort_memberships",
        "programacion.input_readiness_runs",
        "programacion.input_family_assessments",
        "programacion.provenance_receipts",
    )
    result = []
    for table in targets:  # fixed authority table identifiers; never user input
        rows = _fetch(conn, f"""SELECT count(*), md5(coalesce(string_agg(
          md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),''))
          FROM {table} t""")
        result.append((table, rows[0]))
    return tuple(result)


def run_sandbox(
    conn: Any,
    governed_producer: Callable[..., Any],
    m99_canonical_readback: Callable[..., dict],
    run_ref: str,
) -> dict:
    """Perform bounded sequential probes; never authorize or publish a cutover.

    Producer must use *conn* and never commit/open external write connections.
    M9.9 readback must verify the canonical DB/Independent Assurance receipts.
    Every candidate transaction is rolled back, including successful probes.
    """
    if conn is None or getattr(conn, "autocommit", True) is not False:
        raise ValueError("M910_TRANSACTIONAL_CONNECTION_REQUIRED")
    if not callable(governed_producer) or not callable(m99_canonical_readback):
        raise ValueError("M910_EXISTING_PRODUCER_AND_VERIFIER_REQUIRED")
    if not isinstance(run_ref, str) or not run_ref.strip():
        raise ValueError("M910_RUN_REF_REQUIRED")

    try:
        rows = _fetch(conn, """SELECT ct.cohort_type_code,cm.pantalla_id,
            cm.authority_ref FROM programacion.input_governance_cohort_types ct
            JOIN programacion.input_governance_cohort_memberships cm
              USING (cohort_type_code)
            WHERE ct.status='ACTIVE' AND cm.status='ACTIVE'
            ORDER BY ct.display_order,cm.representative_rank,cm.pantalla_id""")
        cohorts: dict[str, list[tuple]] = OrderedDict()
        for code, pantalla_id, authority_ref in rows:
            cohorts.setdefault(code, []).append((pantalla_id, authority_ref))
        if not cohorts:
            raise EvidencePending("M910_NO_ACTIVE_GOVERNED_COHORTS")
        current = _fetch(conn, """SELECT capability_code,version,manifest_sha256
            FROM public.lf_capability_current
            WHERE capability_code IN
             ('INPUT_GOVERNANCE','REVERSIBLE_CANDIDATE_VERIFICATION')
            ORDER BY capability_code""")
        if len(current) != 2 or any(not v or not sha for _, v, sha in current):
            raise EvidencePending("M910_GOVERNED_CAPABILITY_CURRENT_MISSING")
        baseline = _snapshot(conn)

        # Read real signed records by the *current* run and cohort. The consumer
        # never constructs evidence; callers must use the canonical M9.9 verifier.
        pending = []
        for code in cohorts:
            stages = _fetch(conn, """SELECT DISTINCT payload->>'stage'
                FROM programacion.provenance_receipts
                WHERE subject_type='IG_CANARY_OBSERVATION'
                  AND subject_ref=%s
                  AND issuer_channel='EVIDENCE_VERIFIER_V1'
                  AND receipt_kind='EVIDENCE_VERIFICATION'
                  AND payload->>'run_ref'=%s
                  AND payload->>'verification_status'='VERIFIED'""",
                  ('IG_CANARY:' + code, run_ref))
            found = {r[0] for r in stages}
            if not {'OBSERVATION','INDEPENDENT_ORACLE','ROLLBACK_ACTION'} <= found:
                pending.append(code)
        if pending:
            raise EvidencePending("M910_CANONICAL_RECEIPTS_REQUIRED:" + ','.join(pending))
    finally:
        conn.rollback()

    verified = []
    for code, members in cohorts.items():
        # Governed producer is supplied by the existing owner capability;
        # candidate effects ALWAYS end inside a rollback before readback.
        try:
            candidate = governed_producer(conn, code, tuple(members), run_ref)
        finally:
            conn.rollback()
        try:
            post = _snapshot(conn)
        finally:
            conn.rollback()
        if post != baseline:
            raise RuntimeError("M910_POSTSTATE_DIFFERS_FROM_BASELINE:" + code)
        evidence = m99_canonical_readback(candidate, {})
        if not isinstance(evidence, dict) or evidence.get('readback_authority') != 'CANONICAL_PROVENANCE_DB':
            raise EvidencePending("M910_CANONICAL_READBACK_NOT_VERIFIED:" + code)
        identity = evidence.get('evidence_identity') or {}
        if identity.get('cohort_type_code') != code or identity.get('run_ref') != run_ref:
            raise EvidencePending("M910_PROVENANCE_IDENTITY_DRIFT:" + code)
        verified.append({'cohort_type_code': code, 'members': len(members),
                         'receipt_ids': identity.get('receipt_ids')})

    # Sandbox-only: no runtime activation and no persistent candidate changes.
    return {'status': 'SANDBOX_PROOF_ONLY', 'verified_cohorts': verified,
            'current_capabilities': current, 'baseline_restored': True,
            'production_cutover_authorized': False}

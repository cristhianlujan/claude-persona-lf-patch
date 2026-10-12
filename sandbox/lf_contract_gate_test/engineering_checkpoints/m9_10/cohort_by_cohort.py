"""M9.10 source-bound sandbox cohort adapter; NEVER a live canary producer.

Only a caller-owned, governed, same-transaction SQL promoter may be injected.
Each ACTIVE cohort is probed once; the candidate is rolled back before the next.
The returned per-cohort matrix is NOT a receipt and cannot admit live cutover.
M9.9's six-case rollback matrix is separately reused, not repeated here.
"""
from __future__ import annotations

from collections import OrderedDict
from typing import Any, Callable


class SandboxProofBlocked(RuntimeError):
    """No sandbox admission without an actual observed SQL state transition."""


def _fetch(conn: Any, sql: str, params: tuple = ()) -> list[tuple]:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def _snapshot(conn: Any) -> tuple:
    """Compare full pre/post states; historical rows may be nonzero."""
    tables = (
        "public.lf_capability_current",
        "public.lf_capability_version_registry",
        "public.lf_capability_binding",
        "programacion.input_readiness_runs",
        "programacion.input_family_assessments",
        "programacion.provenance_receipts",
    )
    result = []
    for table in tables:  # fixed trusted authority identifiers, not caller input
        rows = _fetch(conn, f"""SELECT count(*),md5(coalesce(string_agg(
          md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),'')) 
          FROM {table} AS t""")
        result.append((table, rows[0]))
    return tuple(result)


def run_sandbox(
    conn: Any, governed_producer: Callable[..., Any], run_ref: str
) -> dict[str, Any]:
    """Only a real SQL transaction can qualify a cohort.

    governed_producer(conn, cohort_code, governed_members, run_ref) must call
    the existing versioned promoter through conn without its own COMMIT or a
    second connection. No durable receipt is minted or accepted here.
    """
    if conn is None or getattr(conn, "autocommit", True) is not False:
        raise ValueError("M910_TRANSACTIONAL_CONNECTION_REQUIRED")
    if not callable(governed_producer):
        raise ValueError("M910_EXISTING_GOVERNED_PRODUCER_REQUIRED")
    if not isinstance(run_ref, str) or not run_ref.strip():
        raise ValueError("M910_RUN_REF_REQUIRED")
    try:
        rows = _fetch(conn, """SELECT ct.cohort_type_code,cm.pantalla_id,
            cm.authority_ref FROM programacion.input_governance_cohort_types ct
            JOIN programacion.input_governance_cohort_memberships cm
              USING (cohort_type_code)
            WHERE ct.status='ACTIVE' AND cm.status='ACTIVE'
            ORDER BY ct.display_order,cm.representative_rank,cm.pantalla_id""")
        cohorts = OrderedDict()
        for code, screen_id, authority_ref in rows:
            cohorts.setdefault(code, []).append((screen_id, authority_ref))
        if not cohorts:
            raise SandboxProofBlocked("M910_NO_ACTIVE_GOVERNED_COHORTS")
        baselines = dict(_fetch(conn, """SELECT capability_code,
            (version,manifest_sha256,previous_version)::text
            FROM public.lf_capability_current
            WHERE capability_code IN ('INPUT_GOVERNANCE',
                                      'REVERSIBLE_CANDIDATE_VERIFICATION')"""))
        if set(baselines) != {'INPUT_GOVERNANCE',
                             'REVERSIBLE_CANDIDATE_VERIFICATION'}:
            raise SandboxProofBlocked("M910_REQUIRED_VERSIONED_AUTHORITIES_MISSING")
        before = _snapshot(conn)
    finally:
        conn.rollback()

    proof = []
    for cohort_code, members in cohorts.items():
        try:
            old_row = _fetch(conn, """SELECT version,manifest_sha256,
                 previous_version FROM public.lf_capability_current
                 WHERE capability_code='INPUT_GOVERNANCE'""")
            if len(old_row) != 1:
                raise SandboxProofBlocked("M910_BASELINE_MISSING")
            # The original current/manifest/version pin is verified in SQL.
            governed_producer(conn, cohort_code, tuple(members), run_ref)
            promoted = _fetch(conn, """SELECT version,manifest_sha256,
                 previous_version FROM public.lf_capability_current
                 WHERE capability_code='INPUT_GOVERNANCE'""")
            if len(promoted) != 1 or promoted[0] == old_row[0]:
                raise SandboxProofBlocked("M910_REAL_POINTER_PROMOTION_NOT_OBSERVED")
            if promoted[0][0] == old_row[0][0] or promoted[0][1] == old_row[0][1]:
                raise SandboxProofBlocked("M910_PROMOTION_VERSION_OR_SHA_NOT_CHANGED")
            registry = _fetch(conn, """SELECT count(*) FROM
                public.lf_capability_version_registry
                WHERE capability_code='INPUT_GOVERNANCE'
                  AND version=%s AND manifest_sha256=%s""",
                  (promoted[0][0], promoted[0][1]))
            if registry != [(1,)]:
                raise SandboxProofBlocked("M910_PROMOTED_REGISTRY_MISSING")
            proof.append({
                'cohort_type_code': cohort_code,
                'governed_member_count': len(members),
                'baseline_version': old_row[0][0],
                'candidate_version_observed': promoted[0][0],
                'candidate_manifest_sha256_observed': promoted[0][1],
                'actual_db_promotion_observed': True,
                'rollback_evidence_kind': 'SANDBOX_SQL_NOT_SIGNED_LIVE_CANARY',
            })
        finally:
            conn.rollback()  # ALWAYS before next cohort, even on error
        try:
            post = _snapshot(conn)
        finally:
            conn.rollback()
        if post != before:
            raise SandboxProofBlocked("M910_POST_ROLLBACK_RESIDUE:" + cohort_code)
        proof[-1]['poststate_equals_prestate'] = True

    return {
        'status': 'SANDBOX_DB_PROBE_ONLY_PENDING_INDEPENDENT_CHECKPOINT_ASSERTION',
        'run_ref': run_ref,
        'coverage': len(proof),
        'cohorts': proof,
        'zero_candidate_residue': True,
        'live_signed_canary_receipt': False,
        'operational_release_authorized': False,
        'production_activation': False,
    }

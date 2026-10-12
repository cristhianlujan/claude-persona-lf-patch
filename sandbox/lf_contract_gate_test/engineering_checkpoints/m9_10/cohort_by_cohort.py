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


class _RollbackOnlyConnection:
    """No COMMIT permission on the connection delegated to a producer."""

    def __init__(self, conn: Any):
        self._conn = conn

    @property
    def autocommit(self) -> bool:
        return False

    def cursor(self):
        return self._conn.cursor()

    def commit(self):
        raise SandboxProofBlocked("M910_PRODUCER_COMMIT_FORBIDDEN")


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
            governed_producer(_RollbackOnlyConnection(conn), cohort_code, tuple(members), run_ref)
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


# Source-bound SQL matrix: execute using the governed Supabase SQL transport.
# The SQL itself wraps every real DB action in BEGIN/ROLLBACK and also rolls
# back each cohort's transient version in a PL/pgSQL subtransaction. It does
# not create live receipts, approve a release, or register persistent versions.
SANDBOX_MATRIX_SQL = r'''BEGIN;
CREATE TEMP TABLE m910_source_bound_cohort_proof (
 cohort_type_code text, pantalla_id bigint, authority_ref text,
 promoted boolean, guarded_negative boolean, promoter_reverted boolean,
 exact_rollback boolean, candidate_version_residue bigint,
 historical_runs_delta bigint, historical_assessments_delta bigint,
 binding_delta bigint, live_canary_claim boolean
) ON COMMIT DROP;
DO $m910$
DECLARE c record; v_baseline public.lf_capability_current%rowtype;
 v_current public.lf_capability_current%rowtype;
 v_manifest jsonb; v_candidate_sha text; v_reply jsonb; v_negative jsonb; v_revert jsonb;
 v_expected int; v_count int; v_version_residue bigint;
 v_runs bigint; v_assessments bigint; v_bindings bigint;
 v_runs_post bigint; v_assessments_post bigint; v_bindings_post bigint;
BEGIN
 SELECT * INTO STRICT v_baseline FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE';
 SELECT count(*) INTO v_expected
 FROM programacion.input_governance_cohort_memberships cm
 JOIN programacion.input_governance_cohort_types ct USING(cohort_type_code)
 WHERE cm.status='ACTIVE' AND ct.status='ACTIVE';
 IF v_expected=0 THEN RAISE EXCEPTION 'M910_NO_ACTIVE_GOVERNED_MEMBERSHIPS'; END IF;
 IF v_baseline.version IS DISTINCT FROM '1.0.0' THEN
 RAISE EXCEPTION 'M910_INPUT_GOVERNANCE_BASELINE_DRIFT'; END IF;
 SELECT count(*) INTO v_runs FROM programacion.input_readiness_runs;
 SELECT count(*) INTO v_assessments FROM programacion.input_family_assessments;
 SELECT count(*) INTO v_bindings FROM public.lf_capability_binding;
 FOR c IN
   SELECT ct.cohort_type_code,cm.pantalla_id,cm.authority_ref
   FROM programacion.input_governance_cohort_types ct
   JOIN programacion.input_governance_cohort_memberships cm USING(cohort_type_code)
   WHERE ct.status='ACTIVE' AND cm.status='ACTIVE'
   ORDER BY ct.display_order,cm.representative_rank,cm.pantalla_id
 LOOP
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1') THEN
    RAISE EXCEPTION 'M910_UNEXPECTED_REAL_CANDIDATE_PRESENT'; END IF;
  BEGIN
   SELECT manifest INTO STRICT v_manifest
   FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE'
   AND version=v_baseline.version;
   v_manifest:=jsonb_set(v_manifest,'{version}',to_jsonb('1.0.1'::text),false);
   v_manifest:=jsonb_set(v_manifest,'{sandbox_cohort_qualification_v1}',
     jsonb_build_object('cohort_type_code',c.cohort_type_code,
      'pantalla_id',c.pantalla_id,'authority_ref',c.authority_ref,
      'test_source','github://cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_10/cohort_by_cohort.py',
      'candidate_scope','TRANSIENT_TRANSACTION_LOCAL',
      'no_operational_release',true,'no_runtime_activation',true),true);
   v_candidate_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.lf_capability_version_registry (
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,source_ref,
    docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',
    v_manifest,v_candidate_sha,source_ref,docs_ref,validator_ref,
    'M910_TRANSIENT_SANDBOX_NO_OPERATIONAL_RELEASE'
   FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   IF NOT FOUND THEN RAISE EXCEPTION 'M910_GOVERNED_SOURCE_MISSING'; END IF;
   v_reply:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',
      v_baseline.manifest_sha256,'M910_TRANSIENT_SANDBOX','per-cohort sandbox qualification');
   SELECT * INTO STRICT v_current FROM public.lf_capability_current
      WHERE capability_code='INPUT_GOVERNANCE';
   IF v_reply->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT'
      OR v_current.version IS DISTINCT FROM '1.0.1'
      OR v_current.manifest_sha256 IS DISTINCT FROM v_candidate_sha THEN
      RAISE EXCEPTION 'M910_REAL_GOVERNED_PROMOTION_NOT_OBSERVED'; END IF;
   v_negative:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',
       v_baseline.manifest_sha256,'M910_TRANSIENT_SANDBOX','stale currentness negative');
   IF v_negative->>'decision' IS DISTINCT FROM 'BLOCK_CURRENTNESS_MISMATCH'
     OR NOT EXISTS (SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1'
         AND manifest_sha256=v_candidate_sha) THEN
     RAISE EXCEPTION 'M910_NEGATIVE_STALE_MANIFEST_FAILED'; END IF;
   v_revert:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',
       v_candidate_sha,'M910_TRANSIENT_SANDBOX','per-cohort promoter revert');
   IF v_revert->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT'
     OR NOT EXISTS (SELECT 1 FROM public.lf_capability_current
        WHERE capability_code='INPUT_GOVERNANCE' AND version=v_baseline.version
          AND manifest_sha256=v_baseline.manifest_sha256) THEN
     RAISE EXCEPTION 'M910_VERSIONED_REVERT_FAILED'; END IF;
   RAISE EXCEPTION 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK' THEN RAISE; END IF;
  END;
  SELECT * INTO STRICT v_current FROM public.lf_capability_current
  WHERE capability_code='INPUT_GOVERNANCE';
  SELECT count(*) INTO v_version_residue FROM public.lf_capability_version_registry
     WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1';
  SELECT count(*) INTO v_runs_post FROM programacion.input_readiness_runs;
  SELECT count(*) INTO v_assessments_post FROM programacion.input_family_assessments;
  SELECT count(*) INTO v_bindings_post FROM public.lf_capability_binding;
  IF to_jsonb(v_current) IS DISTINCT FROM to_jsonb(v_baseline)
    OR v_version_residue<>0 OR v_runs_post<>v_runs
    OR v_assessments_post<>v_assessments OR v_bindings_post<>v_bindings THEN
    RAISE EXCEPTION 'M910_POSTSTATE_MISMATCH_FOR_COHORT:%',c.cohort_type_code; END IF;
  INSERT INTO m910_source_bound_cohort_proof VALUES
    (c.cohort_type_code,c.pantalla_id,c.authority_ref,true,true,true,true,
     v_version_residue,v_runs_post-v_runs,v_assessments_post-v_assessments,
     v_bindings_post-v_bindings,false);
 END LOOP;
 SELECT count(*) INTO v_count FROM m910_source_bound_cohort_proof;
 IF v_count<>v_expected THEN RAISE EXCEPTION 'M910_COHORT_COVERAGE_MISMATCH'; END IF;
END $m910$;
SELECT cohort_type_code,pantalla_id,authority_ref,promoted,guarded_negative,
 promoter_reverted,exact_rollback,candidate_version_residue,historical_runs_delta,
 historical_assessments_delta,binding_delta,live_canary_claim
FROM m910_source_bound_cohort_proof ORDER BY cohort_type_code,pantalla_id;
ROLLBACK;'''

def source_bound_sandbox_matrix_sql() -> str:
    """Return the exact SQL source to be executed by a governed DB connector."""
    return SANDBOX_MATRIX_SQL

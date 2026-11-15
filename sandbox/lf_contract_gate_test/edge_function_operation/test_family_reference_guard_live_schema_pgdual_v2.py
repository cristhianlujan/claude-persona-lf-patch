"""Five exact trigger / STALE cases on PG17.6 and PG18.7.

Builds the schema by applying the unmodified 20261114224412 migration against
the same source-preimage fixtures as PR #3951, then runs five checks inside a
separate transaction and rolls them back. This is isolated PG, NOT a live
Supabase transaction and NOT a Curator or production acceptance receipt.
"""
from __future__ import annotations

import shutil
import subprocess
import time
import unittest
import uuid

from test_family_reference_inheritance_pgdual_v1 import BASE, IDS, M, SRC


CASES_SQL = r"""
BEGIN;
DO $family_ref_guard$
DECLARE
  v_message text;
  v_state text;
  v_row bigint;
  v_n integer;
  v_hash_before text;
  v_hash_after text;
  v_freshness text;
BEGIN
  IF (SELECT count(*) FROM programacion.input_family_inheritable_sources_v1) <> 12
  THEN RAISE EXCEPTION 'PRECHECK_CATALOG_NOT_12'; END IF;

  -- Negative 1: valid hash but source is CANDIDATO.
  BEGIN
    INSERT INTO programacion.input_family_inheritable_sources_v1
      (family_code,source_kind,rule_id,scope_kind,source_hash,
       semantic_equivalence,semantic_transferability,
       semantic_evidence_ref,semantic_reason_code)
    SELECT 'PROBE_CANDIDATO','RULE',r.id,'GLOBAL',
      encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
      'PARTIAL_BASE','TRANSFERABLE','fixture://candidate/reference','TEST_CANDIDATE'
    FROM lf_ops.reglas r WHERE r.id=390;
    RAISE EXCEPTION 'CANDIDATE_FALSE_ACCEPT';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    IF v_state <> 'P0001' OR
       v_message <> 'LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:PROBE_CANDIDATO,RULE'
    THEN RAISE EXCEPTION 'CANDIDATE_WRONG_ERROR:%,%',v_state,v_message; END IF;
    RAISE NOTICE 'CASE_CANDIDATO|SQLSTATE=%|ERROR=%',v_state,v_message;
  END;

  -- Negative 2: status VIGENTE but not transversal; hash matches.
  BEGIN
    INSERT INTO programacion.input_family_inheritable_sources_v1
      (family_code,source_kind,rule_id,scope_kind,source_hash,
       semantic_equivalence,semantic_transferability,
       semantic_evidence_ref,semantic_reason_code)
    SELECT 'PROBE_NONTRANSVERSAL','RULE',r.id,'GLOBAL',
      encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
      'PARTIAL_BASE','TRANSFERABLE','fixture://nontrans/reference','TEST_NONTRANS'
    FROM lf_ops.reglas r WHERE r.id=6;
    RAISE EXCEPTION 'NONTRANS_FALSE_ACCEPT';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    IF v_state <> 'P0001' OR
       v_message <> 'LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:PROBE_NONTRANSVERSAL,RULE'
    THEN RAISE EXCEPTION 'NONTRANS_WRONG_ERROR:%,%',v_state,v_message; END IF;
    RAISE NOTICE 'CASE_NONTRANSVERSAL|SQLSTATE=%|ERROR=%',v_state,v_message;
  END;

  -- Negative 3: source VIGENTE transversal but stale supplied SHA.
  BEGIN
    INSERT INTO programacion.input_family_inheritable_sources_v1
      (family_code,source_kind,rule_id,scope_kind,source_hash,
       semantic_equivalence,semantic_transferability,
       semantic_evidence_ref,semantic_reason_code)
    SELECT 'PROBE_SHA','RULE',r.id,'GLOBAL',repeat('0',64),
      'PARTIAL_BASE','TRANSFERABLE','fixture://sha/reference','TEST_SHA'
    FROM lf_ops.reglas r WHERE r.id=179;
    RAISE EXCEPTION 'SHA_FALSE_ACCEPT';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    IF v_state <> 'P0001' OR
       v_message <> 'LF_FAMILY_REFERENCE_SOURCE_SHA_MISMATCH:PROBE_SHA'
    THEN RAISE EXCEPTION 'SHA_WRONG_ERROR:%,%',v_state,v_message; END IF;
    RAISE NOTICE 'CASE_SHA_MISMATCH|SQLSTATE=%|ERROR=%',v_state,v_message;
  END;

  -- Positive 4: VIGENTE + transversal + correct SHA; only transaction-local.
  INSERT INTO programacion.input_family_inheritable_sources_v1
    (family_code,source_kind,rule_id,scope_kind,source_hash,
     semantic_equivalence,semantic_transferability,
     semantic_evidence_ref,semantic_reason_code)
  SELECT 'PROBE_VALID_TRANSVERSAL','RULE',r.id,'GLOBAL',
    encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
    'EQUIVALENT_COMPONENT','TRANSFERABLE',
    'fixture://valid-transversal/reference','TEST_VALID_TRANSVERSAL'
  FROM lf_ops.reglas r WHERE r.id=21
  RETURNING source_id INTO v_row;
  IF v_row IS NULL THEN RAISE EXCEPTION 'VALID_TRANSVERSAL_NO_ROW'; END IF;
  SELECT count(*) INTO v_n FROM programacion.input_family_inheritable_sources_v1;
  IF v_n <> 13 THEN RAISE EXCEPTION 'VALID_TRANSVERSAL_EXPECTED_13:%',v_n; END IF;
  RAISE NOTICE 'CASE_VALID_TRANSVERSAL|SQLSTATE=00000|ERROR=NONE|ROWS_INSIDE=13';

  -- Positive 5: change an ordinary field on VIGENTE rule source 416.
  -- STALE must come from read-time hash comparison, not an UPDATE to catalog.
  SELECT source_hash INTO v_hash_before
  FROM programacion.input_family_inheritable_sources_v1 WHERE rule_id=416;
  SELECT freshness INTO v_freshness
  FROM public.v_lf_input_family_coverage_by_screen_v1
  WHERE pantalla_id=51 AND family_code='AUDIT';
  IF v_freshness <> 'CURRENT' THEN
    RAISE EXCEPTION 'STALE_PRECONDITION_NOT_CURRENT:%',v_freshness;
  END IF;
  UPDATE lf_ops.reglas SET descripcion=coalesce(descripcion,'')||':guard-rollback'
  WHERE id=416;
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'STALE_RULE_UPDATE_COUNT:%',v_n; END IF;
  SELECT freshness,current_source_hash INTO v_freshness,v_hash_after
  FROM public.v_lf_input_family_coverage_by_screen_v1
  WHERE pantalla_id=51 AND family_code='AUDIT';
  IF v_freshness <> 'STALE' OR v_hash_before = v_hash_after THEN
    RAISE EXCEPTION 'STALE_READTIME_FAILED:%:%',v_freshness,(v_hash_before=v_hash_after);
  END IF;
  IF (SELECT source_hash FROM programacion.input_family_inheritable_sources_v1
      WHERE rule_id=416) <> v_hash_before THEN
    RAISE EXCEPTION 'STALE_CATALOG_HASH_MUTATED';
  END IF;
  RAISE NOTICE 'CASE_STALE_ON_SOURCE_CHANGE|SQLSTATE=00000|ERROR=NONE|FRESHNESS=STALE';
END $family_ref_guard$;
ROLLBACK;
SELECT 'READBACK_CATALOG='||count(*) FROM programacion.input_family_inheritable_sources_v1;
SELECT 'READBACK_ACTIVE='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE estado='ACTIVE';
SELECT 'READBACK_RULES='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='RULE';
SELECT 'READBACK_POLICY='||count(*) FROM programacion.input_family_inheritable_sources_v1 WHERE source_kind='POLICY';
SELECT 'READBACK_PROBES='||count(*) FROM programacion.input_family_inheritable_sources_v1
 WHERE family_code LIKE 'PROBE_%';
SELECT 'READBACK_SOURCE_UNCHANGED='||(descripcion IS NULL)::text FROM lf_ops.reglas WHERE id=416;
SELECT 'READBACK_FRESHNESS='||freshness FROM public.v_lf_input_family_coverage_by_screen_v1
 WHERE pantalla_id=51 AND family_code='AUDIT';
"""


class FamilyReferenceGuardPgDual(unittest.TestCase):
    def test_live_schema_five_cases_rollback(self):
        self.assertEqual(len(M), 1, "EXACT_MIGRATION_MUST_BE_UNIQUE")
        self.assertEqual(M[0].name, "20261114224412_lf_input_family_inheritance_reference_v1.sql")
        self.assertTrue(SRC.is_file(), "SOURCE_PREIMAGES_MISSING")
        self.assertIsNotNone(shutil.which("docker"), "DOCKER_REQUIRED_FOR_DUAL_PG")

        seed = BASE
        for family, rule_id in IDS:
            seed += (
                "INSERT INTO lf_ops.reglas(id,codigo,estado,es_transversal,titulo) "
                f"VALUES ({rule_id},'SOURCE_{rule_id}','VIGENTE',true,'{family}');\n"
            )
            seed += (
                "INSERT INTO programacion.input_family_reuse_map_v1 "
                f"VALUES (956,'HEREDAR',{rule_id},NULL,NULL);\n"
            )
        seed += (
            "INSERT INTO lf_ops.reglas(id,codigo,estado,es_transversal,titulo) VALUES "
            "(390,'THEME-002','CANDIDATO',true,'Candidate probe'),"
            "(6,'NONTRANS-006','VIGENTE',false,'Nontrans probe'),"
            "(21,'TRANS-021','VIGENTE',true,'Transversal probe');\n"
        )
        for kind, policy_code in (
            ("SECURITY", "SEC-B2B-IDEMPOTENCY"),
            ("RATE_LIMIT", "RATE-B2B-UPLOAD"),
            ("SESSION", "SESSION-B2B-DEFAULT"),
            ("TIMEOUT", "TIMEOUT-B2B-UPLOAD"),
        ):
            seed += (
                "INSERT INTO programacion.input_family_reuse_map_v1 "
                f"VALUES (956,'ATAR_POLITICA',NULL,'{kind}','{policy_code}');\n"
            )

        for image in ("17.6", "18.7"):
            with self.subTest(postgres=image):
                container = "lf-family-ref-guard-" + uuid.uuid4().hex[:10]
                started = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", container,
                     "-e", "POSTGRES_PASSWORD=fixture-only", "postgres:" + image],
                    capture_output=True, text=True, timeout=180,
                )
                self.assertEqual(started.returncode, 0, started.stderr)
                try:
                    for attempt in range(120):
                        ready = subprocess.run(
                            ["docker", "exec", container, "pg_isready", "-U", "postgres"],
                            capture_output=True, text=True, timeout=8,
                        )
                        if ready.returncode == 0:
                            break
                        time.sleep(0.7)
                    self.assertEqual(ready.returncode, 0, "POSTGRES_NOT_READY")

                    def psql(sql: str):
                        return subprocess.run(
                            ["docker", "exec", "-i", container, "psql", "-X", "-Atq",
                             "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
                            input=sql, capture_output=True, text=True, timeout=180,
                        )

                    prepared = psql(seed + "\nSET check_function_bodies=off;\n" +
                                    SRC.read_text(encoding="utf-8"))
                    self.assertEqual(prepared.returncode, 0, prepared.stderr[-5000:])
                    applied = psql(M[0].read_text(encoding="utf-8"))
                    self.assertEqual(applied.returncode, 0, applied.stderr[-6000:])

                    result = psql(CASES_SQL)
                    self.assertEqual(result.returncode, 0, result.stderr[-7000:])
                    expected_errors = (
                        "CASE_CANDIDATO|SQLSTATE=P0001|ERROR=LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:PROBE_CANDIDATO,RULE",
                        "CASE_NONTRANSVERSAL|SQLSTATE=P0001|ERROR=LF_FAMILY_REFERENCE_SOURCE_NOT_VIGENTE:PROBE_NONTRANSVERSAL,RULE",
                        "CASE_SHA_MISMATCH|SQLSTATE=P0001|ERROR=LF_FAMILY_REFERENCE_SOURCE_SHA_MISMATCH:PROBE_SHA",
                        "CASE_VALID_TRANSVERSAL|SQLSTATE=00000|ERROR=NONE|ROWS_INSIDE=13",
                        "CASE_STALE_ON_SOURCE_CHANGE|SQLSTATE=00000|ERROR=NONE|FRESHNESS=STALE",
                    )
                    for check in expected_errors:
                        self.assertIn(check, result.stderr, check + "\n" + result.stderr)
                    for check in (
                        "READBACK_CATALOG=12", "READBACK_ACTIVE=12",
                        "READBACK_RULES=11", "READBACK_POLICY=1",
                        "READBACK_PROBES=0",
                        "READBACK_SOURCE_UNCHANGED=true",
                        "READBACK_FRESHNESS=CURRENT",
                    ):
                        self.assertIn(check, result.stdout, check + "\n" + result.stdout)
                    print("PG_" + image + "_EXACT_ERRORS_AND_ROLLBACK")
                    for check in expected_errors:
                        print(check)
                    print(result.stdout)
                finally:
                    subprocess.run(
                        ["docker", "rm", "-f", container],
                        capture_output=True, text=True, timeout=30,
                    )

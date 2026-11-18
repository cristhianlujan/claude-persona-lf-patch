"""LF-AUD-UI-02 negative replay: V6 context versus legacy traceability.
Both PostgreSQL images execute BEGIN / ROLLBACK; no persistent fixture writes.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261118154500_lf_aud_ui02_versioned_open_work_envelope_v2.sql"


class Ui02OpenWorkVersionedPgDual(unittest.TestCase):
    def test_live_bridge_source_patch_contract(self):
        source = MIGRATION.read_text(encoding="utf-8")
        self.assertIn("073fbfea36ac02553f5c7338905b23a1", source)
        self.assertIn("6f138a2cb789f6fbf71d73e855d54c85", source)
        self.assertIn("d1e007a427b5a6003b996733970cf80d", source)
        for name in ("lf_profile_native_bridge_prepare_v1",
                     "lf_profile_native_bridge_record_output_v1",
                     "lf_profile_native_bridge_record_report_v1"):
            self.assertIn(name, source)
        self.assertIn("LF_AUD_UI02_BRIDGE_READBACK_FAILED", source)
        self.assertEqual(source.count("COMMIT;"), 1)

    def test_v6_and_legacy_negative_replay_begin_rollback_pg17_pg18(self):
        self.assertIsNotNone(shutil.which("docker"), "CI_REQUIRES_DOCKER")
        source = MIGRATION.read_text(encoding="utf-8")
        helpers = source.split("-- UI02_HELPERS_BEGIN", 1)[1].split("-- UI02_HELPERS_END", 1)[0]
        check = r"""
BEGIN;
""" + helpers + r"""
DO $test$
DECLARE v6 jsonb; legacy jsonb; result jsonb;
BEGIN
  v6:=jsonb_build_object(
    'output_contract_version','UI_PRODUCTION_SPEC_V6',
    'governance_envelope',jsonb_build_object(
      'schema','LF_UI_GOVERNANCE_ENVELOPE_V1',
      'render_policy','NON_RENDER',
      'context',jsonb_build_object('ig_open_work_resolution',
        jsonb_build_array(jsonb_build_object('family_code','SECURITY','status','DEPENDENCIA',
        'reason','Await security decision','next_action','Review source')))));
  -- PREPATCH NEGATIVE: traceability was absent for a legitimate V6 response.
  IF v6#>'{traceability,ig_open_work_resolution}' IS NOT NULL
  THEN RAISE EXCEPTION 'PREPATCH_NEGATIVE_NOT_REPRODUCED'; END IF;
  result:=public.lf_profile_ig_open_work_resolution_for_output_v2('PERFIL-UI-ARCHITECT',v6);
  IF jsonb_typeof(result)<>'array' OR jsonb_array_length(result)<>1
  THEN RAISE EXCEPTION 'V6_CONTEXT_VALID_RESPONSE_REJECTED'; END IF;
  IF public.lf_profile_ig_open_work_output_field_v2('PERFIL-UI-ARCHITECT',NULL)
      <>'governance_envelope.context.ig_open_work_resolution'
  THEN RAISE EXCEPTION 'PREPARE_V6_CONTRACT_MISMATCH'; END IF;
  -- V6 schema is mandatory; never downgrade a forged envelope to traceability.
  IF public.lf_profile_ig_open_work_resolution_for_output_v2('PERFIL-UI-ARCHITECT',
     jsonb_set(v6,'{governance_envelope,schema}','"FORGED"'::jsonb))
     IS NOT NULL
  THEN RAISE EXCEPTION 'V6_WRONG_ENVELOPE_FALSE_PASS'; END IF;
  legacy:=jsonb_build_object('output_contract_version','UI_PRODUCTION_SPEC_V5',
    'traceability',jsonb_build_object('ig_open_work_resolution',
    jsonb_build_array(jsonb_build_object('family_code','AUDIT','status','NO_CORRESPONDE'))));
  IF jsonb_array_length(public.lf_profile_ig_open_work_resolution_for_output_v2(
    'PERFIL-UI-ARCHITECT',legacy))<>1
  THEN RAISE EXCEPTION 'LEGACY_UI_TRACEABILITY_BROKEN'; END IF;
  IF jsonb_array_length(public.lf_profile_ig_open_work_resolution_for_output_v2(
    'PERFIL-PRODUCT-DIRECTOR-LF',legacy))<>1
  THEN RAISE EXCEPTION 'OTHER_PROFILE_TRACEABILITY_BROKEN'; END IF;
  IF public.lf_profile_ig_open_work_output_field_v2('PERFIL-PRODUCT-DIRECTOR-LF',NULL)
      <>'traceability.ig_open_work_resolution'
  THEN RAISE EXCEPTION 'OTHER_PROFILE_PREPARE_BROKEN'; END IF;
  RAISE NOTICE 'LF_AUD_UI02_NEGATIVE_REPLAY_V6_LEGACY_OTHERS_PASS';
END $test$;
ROLLBACK;
SELECT 'ROLLED_BACK='||
  (to_regprocedure('public.lf_profile_ig_open_work_resolution_for_output_v2(text,jsonb)')
  IS NULL)::text;
"""
        for image in ("17.6", "18.7"):
            with self.subTest(postgres=image):
                name = "lf-ui02-" + uuid.uuid4().hex[:9]
                started = subprocess.run(
                    ["docker", "run", "-d", "--rm", "--name", name,
                     "-e", "POSTGRES_PASSWORD=fixture-only", "postgres:" + image],
                    text=True, capture_output=True, timeout=180)
                self.assertEqual(started.returncode, 0, started.stderr)
                try:
                    for _ in range(100):
                        ready = subprocess.run(
                            ["docker", "exec", name, "pg_isready", "-U", "postgres"],
                            text=True, capture_output=True, timeout=10)
                        if ready.returncode == 0:
                            break
                        time.sleep(0.7)
                    self.assertEqual(ready.returncode, 0, "POSTGRES_NOT_READY")
                    ran = subprocess.run(
                        ["docker", "exec", "-i", name, "psql", "-X", "-Atq",
                         "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
                        input=check, text=True, capture_output=True, timeout=140)
                    self.assertEqual(ran.returncode, 0, ran.stderr[-4500:])
                    self.assertIn("LF_AUD_UI02_NEGATIVE_REPLAY_V6_LEGACY_OTHERS_PASS",
                                  ran.stderr)
                    self.assertIn("ROLLED_BACK=true", ran.stdout)
                finally:
                    subprocess.run(["docker", "rm", "-f", name],
                                   capture_output=True, timeout=30)


if __name__ == "__main__":
    unittest.main()

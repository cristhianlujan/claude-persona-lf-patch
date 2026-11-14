"""Owner policy-activation regression: PG17.6/18.7, exact migration, rollback.

Synthetic source-complete fixture tests positive behavior, while the initial
fixture reproduces the real live catalog/descriptor blockers. No live writes.
"""
from __future__ import annotations

import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / (
    "supabase/migrations/"
    "20261114092500_lf_skill_selector_owner_decision_enable18_v1.sql"
)
SELECTOR = ROOT / (
    "supabase/migrations/"
    "20261114035000_lf_profile_skill_zero_enabled_compat_v1.sql"
)

PROFILES = (
    "ACT-0051",
    "PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING",
    "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531",
    "PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF",
    "PERFIL-GAMIFICATION-SYSTEM-ARCHITECT",
    "PERFIL-PRODUCT-DIRECTOR-LF",
    "PERFIL-QUALITY-PACK",
    "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
    "PERFIL-UI-ARCHITECT",
    "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531",
)
SCREEN_PROFILES = (
    "PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING",
    "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531",
    "PERFIL-GAMIFICATION-SYSTEM-ARCHITECT",
    "PERFIL-PRODUCT-DIRECTOR-LF",
    "PERFIL-QUALITY-PACK",
    "PERFIL-UI-ARCHITECT",
    "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531",
)
OWNER_REF = (
    "owner-decision://lf/2026-11-14T04:20:00-05:00/"
    "lf_skill_selector_policy_v1/enable-18"
)


def sql_list(values):
    return ",".join("('" + v.replace("'", "''") + "')" for v in values)


SCHEMA = r"""
CREATE TABLE public.lf_profile_selection_registry_v1(
  profile_code text PRIMARY KEY, descriptor_status text NOT NULL);
CREATE TABLE public.lf_profile_selector_policy_v1(
  profile_code text PRIMARY KEY, channels text[] NOT NULL);
CREATE TABLE public.lf_skill_catalog_v1(
  skill_code text PRIMARY KEY, status text NOT NULL, required_operation text NOT NULL,
  effect text NOT NULL, handler_fn text NOT NULL, input_required text[] NOT NULL);
CREATE TABLE public.lf_skill_selection_registry_v1(
  skill_code text PRIMARY KEY, descriptor jsonb NOT NULL, source_ref text NOT NULL,
  source_revision text NOT NULL, descriptor_status text NOT NULL);
CREATE TABLE public.lf_profile_write_authority_v1(
  profile_code text, operation_code text, status text);
CREATE TABLE public.lf_skill_selector_policy_v1(
  profile_code text NOT NULL, skill_code text NOT NULL, channels text[] NOT NULL,
  required_operation text NOT NULL, allowed_effects text[] NOT NULL,
  selection_mode text NOT NULL, enabled boolean NOT NULL,
  policy_evidence_ref text, owner_decision_required boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(profile_code,skill_code,required_operation));
CREATE TABLE public.lf_operation_execution_steps(
  execution_id text,step_order integer,step_id text,status text,
  evidence_payload jsonb);
INSERT INTO public.lf_operation_execution_steps VALUES
  ('TEST-STEP40',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
   '{"input_governance":{"status":"BLOCKED","blocking_code":"BLOCK_PROFILE_INPUT_GOVERNANCE"}}');
INSERT INTO public.lf_skill_catalog_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK','DRAFT','EJECUCION_PERFIL_LF',
  'READ_ONLY','lf_skill_h_input_governance_context_pack_v1',
  ARRAY['request_text','profile_code','scope','consumer']),
 ('SCREEN_RULES_SNAPSHOT','READY','EJECUCION_PERFIL_LF',
  'READ_ONLY','lf_skill_h_screen_rules_snapshot_v1',ARRAY['pantalla_codigo']),
 ('PROFILE_UPDATE_APPLY','READY','ACTUALIZACION_PERFIL_LF',
  'WRITE_GOVERNED','lf_skill_h_profile_update_propose_v1',ARRAY[]::text[]);
INSERT INTO public.lf_skill_selection_registry_v1 VALUES
 ('INPUT_GOVERNANCE_CONTEXT_PACK',
  '{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1"}',
  'supabase://public.lf_activos/INPUT_GOVERNANCE_EXECUTION_CONTRACT',
  'CANDIDATE_SOURCE_NOT_ATTESTED','STALE_SOURCE_CHANGED');
INSERT INTO public.lf_profile_write_authority_v1 VALUES
 ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','ACTUALIZACION_PERFIL_LF','ACTIVE');
"""

SOURCE_COMPLETE = r"""
UPDATE public.lf_skill_catalog_v1 SET status='READY'
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
UPDATE public.lf_skill_selection_registry_v1
   SET descriptor_status='CURRENT',source_revision='sha256:source-attested-fixture-1'
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
INSERT INTO public.lf_skill_selection_registry_v1 VALUES
 ('SCREEN_RULES_SNAPSHOT','{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1"}',
  'github://fixture/SCREEN_RULES_SNAPSHOT','sha256:source-attested-fixture-2','CURRENT'),
 ('PROFILE_UPDATE_APPLY','{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1"}',
  'github://fixture/PROFILE_UPDATE_APPLY','sha256:source-attested-fixture-3','CURRENT');
CREATE FUNCTION public.lf_skill_h_input_governance_context_pack_v1(p_input jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
"""


class _PGSkillOwnerLab:
    IMAGE = ""

    def exec_sql(self, sql: str, expect_failure: bool = False):
        proc = subprocess.run(
            ["docker", "exec", "-i", self.container, "psql", "-U", "postgres",
             "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-A", "-t"],
            input=sql, text=True, capture_output=True, timeout=90,
        )
        if expect_failure:
            self.assertNotEqual(proc.returncode, 0, proc.stdout)
        else:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout.strip(), proc.stderr.strip()

    def test_activation_and_transactional_rollback(self):
        if shutil.which("docker") is None:
            self.skipTest("Docker unavailable; PG17/18 test NOT_EXECUTED")
        self.container = "lf-skills-18-" + uuid.uuid4().hex[:12]
        subprocess.run(
            ["docker", "run", "-d", "--rm", "--name", self.container,
             "-e", "POSTGRES_PASSWORD=lf-skill-pg-lab", self.IMAGE],
            check=True, capture_output=True, text=True, timeout=120,
        )
        try:
            for _ in range(60):
                probe = subprocess.run(
                    ["docker", "exec", self.container, "pg_isready",
                     "-U", "postgres"], capture_output=True, timeout=5,
                )
                if probe.returncode == 0:
                    break
                time.sleep(.5)
            else:
                self.fail("POSTGRES_NOT_READY_" + self.IMAGE)

            profile_values = sql_list(PROFILES)
            screen_values = sql_list(SCREEN_PROFILES)
            fixture = SCHEMA + f"""
INSERT INTO public.lf_profile_selection_registry_v1
 SELECT column1,'CURRENT' FROM (VALUES {profile_values}) AS x(column1);
INSERT INTO public.lf_profile_selector_policy_v1
 SELECT column1,ARRAY['PRODUCTO'] FROM (VALUES {profile_values}) AS x(column1);
INSERT INTO public.lf_skill_selector_policy_v1
 (profile_code,skill_code,channels,required_operation,allowed_effects,
  selection_mode,enabled,policy_evidence_ref,owner_decision_required)
 SELECT column1,'INPUT_GOVERNANCE_CONTEXT_PACK',ARRAY['PRODUCTO'],
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY'],'DETERMINISTIC_REQUIRED',false,
 'supabase://preimage',true FROM (VALUES {profile_values}) AS x(column1);
INSERT INTO public.lf_skill_selector_policy_v1
 (profile_code,skill_code,channels,required_operation,allowed_effects,
  selection_mode,enabled,policy_evidence_ref,owner_decision_required)
 SELECT column1,'SCREEN_RULES_SNAPSHOT',ARRAY['PRODUCTO'],
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY'],'SEMANTIC_OPTIONAL',false,
 'supabase://preimage',true FROM (VALUES {screen_values}) AS x(column1);
INSERT INTO public.lf_skill_selector_policy_v1
 (profile_code,skill_code,channels,required_operation,allowed_effects,
  selection_mode,enabled,policy_evidence_ref,owner_decision_required)
 VALUES('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PROFILE_UPDATE_APPLY',
 ARRAY['PRODUCTO'],'ACTUALIZACION_PERFIL_LF',ARRAY['WRITE_GOVERNED'],
 'SEMANTIC_OPTIONAL',false,'supabase://preimage',true);
"""
            self.exec_sql(fixture)
            self.exec_sql(SELECTOR.read_text(encoding="utf-8"))

            # Real-source-like state: catalog DRAFT and stale/missing descriptors.
            # Atomic migration must fail BEFORE enabling any of the 18 policies.
            migration = MIGRATION.read_text(encoding="utf-8")
            _, err = self.exec_sql(migration, expect_failure=True)
            self.assertIn("LF_SKILL_OWNER_POLICY_DEPENDENCY_NOT_READY", err)
            out, _ = self.exec_sql(
                "SELECT count(*) FROM public.lf_skill_selector_policy_v1 "
                "WHERE enabled OR NOT owner_decision_required;"
            )
            self.assertEqual(out, "0")

            # Positive logic only after a source-complete synthetic fixture.
            # This does not attest live LF source readiness.
            self.exec_sql(SOURCE_COMPLETE)
            out, _ = self.exec_sql("SELECT "
                "public.lf_profile_skill_selection_prepare_v1("
                "'PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',NULL)->>'status';")
            self.assertEqual(out, "READY")  # zero-enabled Step40 compatibility

            # Migration in explicit transaction, followed by ROLLBACK of
            # all 18 changes. No promotion or RUN mutation.
            out, _ = self.exec_sql(
                "BEGIN;\n" + migration + "\n"
                "SELECT 'POST='||count(*) FROM public.lf_skill_selector_policy_v1 "
                f"WHERE enabled AND NOT owner_decision_required AND policy_evidence_ref='{OWNER_REF}';"
                "\nSELECT 'STEP40='||status||':'||"
                "evidence_payload#>>'{input_governance,status}' "
                "FROM public.lf_operation_execution_steps WHERE execution_id='TEST-STEP40';"
                "\nSELECT 'PREPARE='||"
                "public.lf_profile_skill_selection_prepare_v1("
                "'PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',"
                "'{\"selected_skill_code\":\"SCREEN_RULES_SNAPSHOT\","
                "\"reason\":\"lab source-bound choice\","
                "\"review_mode\":\"CURRENT_CONTEXT_REVIEW\","
                "\"descriptor_revision\":\"sha256:source-attested-fixture-2\","
                "\"evidence_refs\":[\"supabase://lab\"]}'::jsonb)->>'status';"
                "\nROLLBACK;\n"
                "SELECT 'POST_ROLLBACK='||count(*) "
                "FROM public.lf_skill_selector_policy_v1 WHERE enabled;"
            )
            for expected in ("POST=18", "STEP40=STEP_PASS_WITH_EVIDENCE:BLOCKED",
                             "PREPARE=READY", "POST_ROLLBACK=0"):
                self.assertIn(expected, out, out)
        finally:
            subprocess.run(
                ["docker", "rm", "-f", self.container],
                capture_output=True, text=True, timeout=90,
            )


class TestOwnerPG176(_PGSkillOwnerLab, unittest.TestCase):
    IMAGE = "postgres:17.6"


class TestOwnerPG187(_PGSkillOwnerLab, unittest.TestCase):
    IMAGE = "postgres:18.7"


if __name__ == "__main__":
    unittest.main(verbosity=2)

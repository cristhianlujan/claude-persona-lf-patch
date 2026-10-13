-- M10.11 only. Contract + unit governance. No REVOKE, DROP, checkpoint status,
-- blocker status, capability version, external unit or runtime mutation.
-- EKB IG-M1011-REMOVE-READY-EMPTY-001 / ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001.
DO $p$
DECLARE n bigint; ready_count bigint;
BEGIN
 IF (SELECT w.status FROM programacion.engineering_plan_units u
     JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
     IS DISTINCT FROM 'IN_PROGRESS' THEN
   RAISE EXCEPTION 'M1011_PRESTATE_DRIFT';
 END IF;
 IF (SELECT u.unit_metadata#>>'{action_specs_v1,REVOKE_MIGRATION,status}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
     IS DISTINCT FROM 'READY' THEN
   RAISE EXCEPTION 'M1011_ACTION_DRIFT';
 END IF;
 IF (SELECT max(id) FROM public.lf_eventos
     WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160')
     IS DISTINCT FROM 20193 THEN
   RAISE EXCEPTION 'M1011_CLASSIFICATION_DRIFT';
 END IF;
 SELECT count(*),count(*) FILTER (WHERE x->>'class'='REMOVE_READY')
   INTO n,ready_count
   FROM public.lf_eventos e
   CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x
   WHERE e.id=20193;
 IF n IS DISTINCT FROM 147 OR ready_count IS DISTINCT FROM 0 THEN
   RAISE EXCEPTION 'M1011_MATRIX_DRIFT';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_capability_registry r
   JOIN public.lf_capability_current c USING(capability_code)
   JOIN public.lf_capability_version_registry v
     ON v.capability_code=c.capability_code AND v.version=c.version
   WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE'
     AND r.status='ACTIVE' AND c.version='1.0.0'
     AND v.release_state='RELEASED'
     AND v.manifest_sha256='5ae32390ee2743f74cf00b0fd4fdbfcea17162f637024e2856bdc6fd261fa9e6'
 ) THEN RAISE EXCEPTION 'M1011_GOVERNANCE_CURRENTNESS_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND
       ((checkpoint_code='REVOKE_MIGRATION' AND status='IN_PROGRESS')
       OR (checkpoint_code IN ('NEG_CALLER_DENIED','REVOKE_READBACK') AND status='PENDING')))
     IS DISTINCT FROM 3 THEN
   RAISE EXCEPTION 'M1011_CHECKPOINT_DRIFT';
 END IF;
END;
$p$;

-- Conditional exit rule, with evidence obligations even when no target exists.
UPDATE programacion.engineering_plan_units
SET exit_criterion =
  'M10.11 CONDITIONAL: With CURRENT approved REMOVE_READY exact signatures, revoke EXECUTE only by Git migration after current multi-source callers=0, ACL baseline, reversible positive and negative tests, and observation/readback. With CURRENT verified zero REMOVE_READY, do not REVOKE: CP3 and CP4 may be NOT_APPLICABLE only with signed current classification and independent multi-source zero-target/no-ACL-change proof; CP5 terminal readback always required. Historic zero is NOT currentness. Unknown or contradicted caller => BLOCK. No DROP/CASCADE, synthetic PASS or production activation.',
    unit_metadata=jsonb_set(unit_metadata,'{m1011_retirement_governance_v1}',
      $j$ {
        "schema_version":"IG_M1011_RETIREMENT_GOVERNANCE_V1",
        "scope":"IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11_ONLY",
        "transversal_governance":{"capability":"ASSET_RETIREMENT_GOVERNANCE","current_version":"1.0.0","change":"NOT_APPLICABLE_NO_GLOBAL_GOVERNANCE_EDIT"},
        "historical_classification":{"event_id":20193,"classified":147,"remove_ready":0,"currentness":"NOT_PROVEN"},
        "counterexample":{"caller":"programacion.fn_input_gov_gold_b_prepare_review_v1","callee":"programacion.fn_input_readiness_run_is_current_cached_v2","rule":"RECLASSIFY_BEFORE_RETIREMENT"},
        "sources":["SQL","EDGE","ROUTER","GIT","REGISTRY","CONTRACTS"],
        "outcomes":{"NONZERO":"EXACT_ALLOWLIST_ROLLBACK_TEST_THEN_REVOKE","ZERO":"NO_REVOKE_CP3_CP4_NA_ONLY_WITH_CURRENT_SIGNED_EVIDENCE_CP5_READBACK","STALE":"BLOCK_REFRESH_CLASSIFIER"},
        "not_applicable_requires":["fresh_classification","signed_zero_target_receipt","cross_source_caller_check","current_governance","unchanged_acl","independent_readback"],
        "forbidden":["REVOKE_IF_ZERO","REVOKE_BY_PREFIX","SYNTHETIC_PASS","NA_FROM_HISTORICAL_MATRIX","DROP_CASCADE","PRODUCTION_ACTIVATION"]
      } $j$::jsonb,true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

-- More restrictive material action: never run REVOKE against zero or stale
-- classifications, even if the generic migration packet compiles.
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,REVOKE_MIGRATION}',
  coalesce(unit_metadata#>'{action_specs_v1,REVOKE_MIGRATION}','{}'::jsonb) ||
    $j$ {
      "status":"BLOCK_NO_CURRENT_REMOVE_READY",
      "expected":"No REVOKE while there is no fresh eligible target. Recheck current M10.10 and callers. Exact signed zero permits evidence-backed NOT_APPLICABLE, never a fake material PASS.",
      "revoke_admission":{"source":"M10.10_CURRENT_SIGNED_CLASSIFICATION","exact_signatures":true,"zero_active_callers":true,"multi_source_currentness":true,"acl_baseline":true,"rollback_exact":true,"no_prefix_revoke":true},
      "not_applicable_contract":{"mode":"ONLY_FRESH_ZERO_WITH_INDEPENDENT_READBACK","required":["fresh_signed_classification","remove_ready_zero","caller_sources_checked","acl_unchanged","governance_current","real_assertion_receipt"]},
      "assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"git_merged":true,"readback_passed":true,"implementation_written":true,"classification_current":true,"exact_targets_nonempty":true,"zero_active_callers_verified":true,"exact_acl_rollback_verified":true,"negative_test_passed":true}},
      "forbidden":["REVOKE_BY_PREFIX","REVOKE_WITH_ZERO_TARGETS","REVOKE_UNLISTED_SIGNATURE","SYNTHETIC_PASS","SKIP_ROLLBACK"]
    } $j$::jsonb,true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,NEG_CALLER_DENIED}',
  coalesce(unit_metadata#>'{action_specs_v1,NEG_CALLER_DENIED}','{}'::jsonb) ||
    $j$ {
      "zero_targets_policy":"NOT_APPLICABLE_ONLY_WITH_SAME_FRESH_SIGNED_ZERO_RECEIPT_AS_REVOKE_MIGRATION",
      "positive_targets_policy":"REAL_DENIAL_TEST_WITH_AUTHORIZED_EXACT_TARGET_AND_CALLER_READBACK",
      "forbidden":["TEST_AN_UNAPPROVED_LIVE_FUNCTION","REUSE_STALE_ZERO","SYNTHETIC_DENIAL_AS_REAL_PASS"]
    } $j$::jsonb,true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

-- Replace irrelevant migration-history preflight with the target-classification
-- authority; the historical result must be refreshed before NA or REVOKE.
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,
  '{source_pack_v1,checkpoint_inputs,REVOKE_MIGRATION,inputs,queries}',
  to_jsonb(ARRAY[
    'SELECT e.id,e.created_at,count(*) classified_count,count(*) FILTER (WHERE x->>''class''=''REMOVE_READY'') ready_count FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->''matrix'') x WHERE e.entidad_codigo=''IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160'' GROUP BY e.id,e.created_at ORDER BY e.id DESC LIMIT 1'
  ]::text[]),true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

-- Keep CP5 mandatory and machine-readable in both branches.
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,REVOKE_READBACK}',
    $j$ {
      "status":"READY",
      "checkpoint_code":"REVOKE_READBACK",
      "schema_version":"ENGINEERING_ACTION_SPEC_V3",
      "action_kind":"READBACK_ONCE",
      "recipe_mode":"READBACK_EXACT",
      "contract_source":"IG_M1011_RETIREMENT_GOVERNANCE_V1",
      "requires_material_execution":false,
      "expected":"Check fresh signed M10.10 classification, exact ACL no-mutation/revoke evidence, source-bound caller scope, current retirement governance; historical zero does not pass.",
      "target":{"declared_assets":["ASSET_RETIREMENT_GOVERNANCE"],"declared_events":[],"declared_objects":["information_schema.routine_privileges","pg_catalog.pg_proc","public.lf_eventos"],"declared_artifacts":[]},
      "assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"classification_current":true,"governance_current":true,"signed_evidence":true,"readback_passed":true,"no_unauthorized_revoke":true}},
      "forbidden":["SYNTHETIC_PASS","REUSE_STALE_CLASSIFICATION"]
    } $j$::jsonb,true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.11';

UPDATE programacion.engineering_work_checkpoints
SET title=CASE checkpoint_code
    WHEN 'REVOKE_MIGRATION' THEN 'REVOKE solo sobre REMOVE_READY vigente; si 0, N/A firmado'
    WHEN 'NEG_CALLER_DENIED' THEN 'Negativo sobre REVOKE real; si 0, N/A con la misma evidencia'
    WHEN 'REVOKE_READBACK' THEN 'Readback terminal obligatorio ACL, clasificación y callers'
    ELSE title END
WHERE work_item_id=197 AND checkpoint_code IN
  ('REVOKE_MIGRATION','NEG_CALLER_DENIED','REVOKE_READBACK');

DO $verify$
BEGIN
 IF (SELECT u.unit_metadata#>>'{m1011_retirement_governance_v1,scope}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
     IS DISTINCT FROM 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11_ONLY'
 THEN RAISE EXCEPTION 'M1011_GOVERNANCE_READBACK_FAILED'; END IF;
 IF (SELECT u.unit_metadata#>>'{action_specs_v1,REVOKE_MIGRATION,status}'
     FROM programacion.engineering_plan_units u
     WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11')
     IS DISTINCT FROM 'BLOCK_NO_CURRENT_REMOVE_READY'
 THEN RAISE EXCEPTION 'M1011_ACTION_READBACK_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND ((checkpoint_code='REVOKE_MIGRATION' AND status='IN_PROGRESS')
       OR (checkpoint_code IN ('NEG_CALLER_DENIED','REVOKE_READBACK') AND status='PENDING')))
     IS DISTINCT FROM 3
 THEN RAISE EXCEPTION 'M1011_CHECKPOINT_STATUS_WAS_MUTATED'; END IF;
END;
$verify$;

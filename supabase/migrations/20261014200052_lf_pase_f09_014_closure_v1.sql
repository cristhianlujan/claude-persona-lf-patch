-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- Close PASE-ATOM-F09-014 with exact-head case evidence and preserve the
-- provider-bound VERIFIED-receipt gap as an explicit blocking out-of-scope finding.
DO $f09_014$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-014';
  c_exec constant text := 'CLAUDE-PASE-F09-014-CLOSE-20261014-001';
  v_status text;
  v_evt boolean;
  v_payload jsonb := $payload${
  "evidence_schema_version": "operational-event/v2",
  "purpose": "Record F09-014 source-bound case evidence and out-of-scope assurance finding",
  "producer": "CLAUDE:PASE_GLOBAL09",
  "execution_id": "CLAUDE-PASE-F09-014-CLOSE-20261014-001",
  "work_code": "PASE-ATOM-F09-014",
  "owner_instruction": "PASE owner Paulo, 2026-10-14",
  "source_pack_event_ids": [
    19827,
    19806,
    19786
  ],
  "fixture_source": {
    "manifest_path": "sandbox/lf_contract_gate_test/pase_evaluation_quality/f09_014_quality_cases_v1.json",
    "manifest_blob_sha": "39a5dd37a250852229221cf607bdb81db7de1dcd",
    "judge_test_path": "sandbox/lf_contract_gate_test/pase_evaluation_quality/test_f09_014_quality_cases_v1.py",
    "judge_test_blob_sha": "d618051e23896ea359d98964ad6a9a5e9222a0e0"
  },
  "applied_pr": {
    "number": 2631,
    "merge_sha": "5f95fa69ae227c174f47da915c16887b7025f670"
  },
  "case_evidence": {
    "exact_execution_head_sha": "d51c1ec988c818ca919b904cba5f72b65ee452cb",
    "checkpoint_ids": [
      "C2",
      "C3"
    ],
    "cases": [
      {
        "case_id": "GOLDEN-SCENARIO-MATRIX",
        "producer": "F04 scenario profiles and deterministic scenario suite",
        "judge": "Independent F09-014 case runner",
        "expected_code": "PASS",
        "observed_code": "PASS"
      },
      {
        "case_id": "BLOCK-STALE-F06-INVENTORY",
        "producer": "F06 control-binding inventory fixture",
        "judge": "Independent exact-main currentness assertion",
        "expected_code": "BLOCK_STALE_CURRENTNESS",
        "observed_code": "BLOCK_STALE_CURRENTNESS"
      },
      {
        "case_id": "BLOCK-UNKNOWN-SELECTED-SCENARIO",
        "producer": "PASE scenario qualifier selection",
        "judge": "Independent F09-014 case runner",
        "expected_code": "BLOCK_SCENARIO_SELECTED_UNKNOWN",
        "observed_code": "BLOCK_SCENARIO_SELECTED_UNKNOWN"
      },
      {
        "case_id": "DIFFICULT-PROVIDER-BOUND-RECEIPT",
        "producer": "Provider-bound VERIFIED receipt fixture",
        "judge": "Independent assurance evaluator boundary test",
        "expected_code": "UNPROVEN_AND_BLOCKED",
        "observed_code": "UNPROVEN_AND_BLOCKED"
      }
    ],
    "cases_evaluated_count": 4,
    "false_pass_count": 0,
    "false_fail_count": 0,
    "replay_run_count": 2,
    "replay_identical": true,
    "replay_sha256": "04182fdf0b75bab1cd3788866f839750177d4a110389acdeb51f1062325ecd96",
    "producer_not_equal_judge_count": 4,
    "judge_disagreement_count": 0
  },
  "out_of_scope_finding": {
    "finding_code": "ASSURANCE-VERIFIED-RECEIPT-PROVIDER-BINDING-NOT-CONSUMED-001",
    "scope_code": "OUT_OF_SCOPE_FOR_F09_014",
    "severity_code": "BLOCKING",
    "evidence_code": "UNPROVEN_BLOCK",
    "detail": "The assurance core does not consume a provider-bound VERIFIED receipt; the claim remains unproven and blocking."
  },
  "ekb_entry_proposal": "Assurance evaluator does not consume a provider-bound VERIFIED receipt. Treat the claim as UNPROVEN/BLOCK until the canonical Evidence Ledger provider readback is bound and independently consumed by the assurance core. Do not infer verification from a VERIFIED label or receipt-shaped fields.",
  "acceptance_declared": false,
  "router_resolution": {
    "router": "ACT-0001",
    "target_hint": "DB",
    "action_hint": "UPDATE",
    "asset_type_hint": "MIGRATION",
    "distribution_mode": "ROUTER",
    "route_status": "READY_TO_EXECUTE",
    "operation_code": "ACTUALIZACION_DB_LF",
    "required_policy_count": 5,
    "resolved_policy_count": 5,
    "missing_or_non_english_action_hint_block_code": "BLOCK_OPERATION_NOT_REGISTERED",
    "ekb_evidence_note": "Router ACT-0001 exige action_hint en inglés (UPDATE); 'ACTUALIZAR' o vacío → BLOCK_OPERATION_NOT_REGISTERED."
  },
  "ekb_router_entry_proposal": "Router ACT-0001 requires an English action_hint (UPDATE); ACTUALIZAR or an empty action_hint returns BLOCK_OPERATION_NOT_REGISTERED."
}$payload$::jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
     WHERE u.plan_code = c_plan
       AND u.unit_code = c_unit
       AND u.disposition = 'ASSIGNED'
       AND w.work_code = u.unit_code
  ) THEN
    RAISE EXCEPTION 'F09_014_CLOSE_PLAN_UNIT_DRIFT';
  END IF;

  SELECT w.status
    INTO v_status
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
   WHERE u.plan_code = c_plan
     AND u.unit_code = c_unit
     AND u.disposition = 'ASSIGNED'
     AND w.work_code = u.unit_code
   FOR UPDATE OF w;

  v_evt := EXISTS (
    SELECT 1
      FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
  );

  IF v_status = 'DONE' AND v_evt THEN
    RETURN;
  END IF;
  IF v_status IS NULL OR v_status NOT IN ('BACKLOG', 'IN_PROGRESS') OR v_evt THEN
    RAISE EXCEPTION 'F09_014_CLOSE_PRESTATE_DRIFT status=% event=%', v_status, v_evt;
  END IF;

  IF v_payload->>'execution_id' IS DISTINCT FROM c_exec
     OR jsonb_typeof(v_payload->'acceptance_declared') IS DISTINCT FROM 'boolean'
     OR coalesce((v_payload->>'acceptance_declared')::boolean, true) THEN
    RAISE EXCEPTION 'F09_014_CLOSE_EVENT_ENVELOPE_DRIFT';
  END IF;

  v_payload := jsonb_set(
    v_payload,
    '{occurred_at}',
    to_jsonb(to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
    true
  );

  UPDATE programacion.engineering_work_items
     SET status = 'DONE',
         started_at = coalesce(started_at, clock_timestamp()),
         completed_at = clock_timestamp(),
         updated_by_execution_id = c_exec
   WHERE id = (
     SELECT w.id
       FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
      WHERE u.plan_code = c_plan
        AND u.unit_code = c_unit
        AND u.disposition = 'ASSIGNED'
        AND w.work_code = u.unit_code
   );

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'F09-014 case evidence and assurance finding recorded from source-bound runs and Train merge 5f95fa69.',
    'INFO',
    v_payload,
    'CLAUDE:PASE_GLOBAL09',
    c_exec
  );
END
$f09_014$;

-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- 1) Close PASE-ATOM-F07-X02 under owner decision D6 (lf_eventos 20583).
-- 2) Record four owner decisions for PASE-ATOM-F07-X01 and move it to IN_PROGRESS.
-- Does not close X01, does not touch R02-R05, does not activate PASE,
-- does not change workflows, rulesets or migration ledger.
-- Idempotent per section: a section already applied is skipped; any other
-- pre-state aborts the whole migration without writes.
DO $f07$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_x02_exec constant text := 'GPT-PASE-F07-X02-CLOSE-D6-20261013';
  c_x01_exec constant text := 'GPT-PASE-F07-X01-OWNER-DECISIONS-20261013';
  v_x02_status text;
  v_x01_status text;
  v_x02_done_evt boolean;
  v_x01_evt boolean;
BEGIN
  -- Common pre-state -------------------------------------------------------
  IF (SELECT count(*) FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
      WHERE u.plan_code = c_plan
        AND u.unit_code IN ('PASE-ATOM-F07-X01','PASE-ATOM-F07-X02')
        AND u.disposition = 'ASSIGNED'
        AND w.work_code = u.unit_code) <> 2
  THEN RAISE EXCEPTION 'F07_CLOSE_PLAN_UNIT_PRESTATE_DRIFT'; END IF;

  IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_items
                  WHERE work_code = 'PASE-ATOM-F07-X02-R01' AND status = 'DONE')
  THEN RAISE EXCEPTION 'F07_CLOSE_R01_NOT_DONE'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
       WHERE id IN (20574, 20575, 20580, 20583)
         AND entidad_codigo = 'PASE-ATOM-F07-X02') <> 4
  THEN RAISE EXCEPTION 'F07_CLOSE_EVIDENCE_EVENTS_MISSING'; END IF;

  SELECT status INTO v_x02_status FROM programacion.engineering_work_items
   WHERE work_code = 'PASE-ATOM-F07-X02' FOR UPDATE;
  SELECT status INTO v_x01_status FROM programacion.engineering_work_items
   WHERE work_code = 'PASE-ATOM-F07-X01' FOR UPDATE;
  v_x02_done_evt := EXISTS (SELECT 1 FROM public.lf_eventos
                             WHERE created_by_execution_id = c_x02_exec
                               AND entidad_codigo = 'PASE-ATOM-F07-X02');
  v_x01_evt := EXISTS (SELECT 1 FROM public.lf_eventos
                        WHERE created_by_execution_id = c_x01_exec
                          AND entidad_codigo = 'PASE-ATOM-F07-X01');

  -- Classify both sections before any write --------------------------------
  IF NOT ((v_x02_status = 'IN_PROGRESS' AND NOT v_x02_done_evt)
       OR (v_x02_status = 'DONE' AND v_x02_done_evt))
  THEN RAISE EXCEPTION 'F07_CLOSE_X02_PRESTATE_DRIFT status=% event=%', v_x02_status, v_x02_done_evt; END IF;

  IF NOT ((v_x01_status = 'BACKLOG' AND NOT v_x01_evt)
       OR (v_x01_status = 'IN_PROGRESS' AND v_x01_evt))
  THEN RAISE EXCEPTION 'F07_CLOSE_X01_PRESTATE_DRIFT status=% event=%', v_x01_status, v_x01_evt; END IF;

  -- Section A: X02 closure under D6 ----------------------------------------
  IF v_x02_status = 'IN_PROGRESS' THEN
    UPDATE programacion.engineering_work_items
       SET status = 'DONE',
           completed_at = now(),
           updated_by_execution_id = c_x02_exec
     WHERE work_code = 'PASE-ATOM-F07-X02';

    INSERT INTO public.lf_eventos(
      evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
      payload, origen, created_by_execution_id
    ) VALUES (
      'PLAN_SNAPSHOT_DETALLADO', 'ENGINEERING_WORK_ITEM', 'PASE-ATOM-F07-X02',
      'X02 closed under owner D6: PASE-disabled window reviewed (20575, 20580), findings declared as owned debt (R02-R05), R01 done. Per-merge manifest criterion superseded by D5/D6.',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version', 'operational-event/v2',
        'purpose', 'Record closure of PASE-ATOM-F07-X02 under owner decision D6 with its evidence references',
        'producer', 'GPT:PASE_GLOBAL07',
        'execution_id', c_x02_exec,
        'work_code', 'PASE-ATOM-F07-X02',
        'closure_basis', 'OWNER_D6',
        'decision_event_ids', jsonb_build_array(20574, 20583),
        'window_review_event_ids', jsonb_build_array(20575, 20580),
        'r01_status', 'DONE',
        'declared_debt_open', jsonb_build_array('R02', 'R03', 'R05'),
        'declared_debt_done', jsonb_build_array('R04'),
        'debt_outside_global07_critical_path', true,
        'migration_source_parity_pass_moved_to', 'PASE-ATOM-F09-X16',
        'superseded_exit_criterion', 'PER_MERGE_MANIFEST',
        'pase_ran_claimed', false,
        'acceptance_declared', false,
        'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ),
      'GPT:PASE_GLOBAL07', c_x02_exec
    );
  END IF;

  -- Section B: X01 owner decisions (X01 stays open) ------------------------
  IF v_x01_status = 'BACKLOG' THEN
    UPDATE programacion.engineering_work_items
       SET status = 'IN_PROGRESS',
           started_at = coalesce(started_at, now()),
           updated_by_execution_id = c_x01_exec
     WHERE work_code = 'PASE-ATOM-F07-X01';

    INSERT INTO public.lf_eventos(
      evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
      payload, origen, created_by_execution_id
    ) VALUES (
      'PLAN_SNAPSHOT_DETALLADO', 'ENGINEERING_WORK_ITEM', 'PASE-ATOM-F07-X01',
      'Owner decisions for X01: authorization order, force-with-lease exception, canonical lock scope, Train ownership. X01 remains open.',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version', 'operational-event/v2',
        'purpose', 'Record four owner decisions required by PASE-ATOM-F07-X01 acceptance criteria',
        'producer', 'GPT:PASE_GLOBAL07',
        'execution_id', c_x01_exec,
        'work_code', 'PASE-ATOM-F07-X01',
        'decided_by', 'PAULO (owner PASE/POST-PASE), chat 2026-10-13',
        'owner_decisions', jsonb_build_array(
          jsonb_build_object(
            'id', 'X01-D1-AUTH_ORDER',
            'choice', 'KEEP_CURRENT_ORDER',
            'order', 'HUMAN_LABEL -> TRAIN_SYNC_RETIMESTAMP -> APPLY -> MERGE',
            'condition', 'Receipt must record authorized_head and final_head; the diff between them may only be main sync plus version retimestamp'),
          jsonb_build_object(
            'id', 'X01-D2-FORCE_WITH_LEASE',
            'choice', 'FORMAL_EXCEPTION',
            'scope', 'PR branch only, never main',
            'rationale', 'New commit has the expected head as parent (no history rewrite); the lease is a safety guard'),
          jsonb_build_object(
            'id', 'X01-D3-LOCK_SCOPE',
            'choice', 'MIGRATION:<version>',
            'other_scopes', 'historical/compat only'),
          jsonb_build_object(
            'id', 'X01-D4-OWNERSHIP',
            'train_code_owner', 'cristhianlujan',
            'train_operation_owner', 'paulozterra (ready-to-merge label = human authorization)')
        ),
        'remaining_for_x01', jsonb_build_array(
          'TYPED_DURABLE_RECEIPT_IN_LF_EVENTOS_OR_EVIDENCE_LEDGER',
          'RECEIPT_FIELDS: human_authorization_ref, main_before, authorized_head, final_head',
          'FAIL_CLOSED_PRE_APPLY_CHECKS without skipped/neutral (workflow change, Cristhian)',
          'POST_PASE_RECEIPT_VERIFIER (owner decision pending: move to F09-X16)'
        ),
        'acceptance_declared', false,
        'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ),
      'GPT:PASE_GLOBAL07', c_x01_exec
    );
  END IF;
END
$f07$;

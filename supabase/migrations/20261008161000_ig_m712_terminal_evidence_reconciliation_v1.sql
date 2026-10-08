-- IG M7.12: repair a false terminal event reference, retaining historical provenance.
-- R16 Git-first. Do not change checkpoint status, suite promotion, or execution semantics.
-- Root cause: prior DONE terminal readback cited V1 PLANNED event instead of V2 closure.
DO $m712_evidence$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M7.12';
 v_checkpoint constant text := 'SUITE_READBACK_TERMINAL';
 v_actor constant text := 'ENGINEERING_M712_CLOSURE_REF_RECONCILIATION_V1';
 v_cp_id bigint;
 v_work_id bigint;
 v_old text;
 v_new text;
 v_part text;
 v_parts text[] := ARRAY[]::text[];
 v_removed text[] := ARRAY[]::text[];
 v_event_id bigint;
 v_event public.lf_eventos%ROWTYPE;
 v_handoff public.lf_eventos%ROWTYPE;
 v_independent public.lf_eventos%ROWTYPE;
 v_updated int;
 v_audit_id bigint;
BEGIN
 -- Concurrency protection and exact declared terminal target, no other units.
 PERFORM pg_advisory_xact_lock(hashtext(v_plan||'|'||v_unit||'|'||v_checkpoint));
 SELECT u.work_item_id,c.id,c.evidence_ref INTO v_work_id,v_cp_id,v_old
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND u.disposition='ASSIGNED'
   AND c.checkpoint_code=v_checkpoint AND c.status='DONE'
   AND c.sequence_no=(SELECT max(z.sequence_no)
                      FROM programacion.engineering_work_checkpoints z
                      WHERE z.work_item_id=c.work_item_id)
 FOR UPDATE OF c;
 IF v_cp_id IS NULL OR nullif(btrim(v_old),'') IS NULL THEN
   RAISE EXCEPTION 'M712_TERMINAL_DONE_AND_EVIDENCE_REQUIRED';
 END IF;
 IF (programacion.fn_engineering_terminal_acceptance_assert_v1(v_plan,v_unit,v_checkpoint)->>'status')<>'PASS' THEN
   RAISE EXCEPTION 'M712_TERMINAL_GATE_NOT_PASS';
 END IF;
 SELECT e.* INTO v_handoff FROM public.lf_eventos e
 WHERE e.entidad_codigo=v_plan||'.'||v_unit||'.CLOSE.HANDOFF'
   AND e.evento_tipo='HANDOFF_DEEP_CONTEXT'
 ORDER BY e.id DESC LIMIT 1;
 SELECT e.* INTO v_independent FROM public.lf_eventos e
 WHERE e.entidad_codigo=v_plan||'.'||v_unit||'.CLOSE.INDEPENDENT_READBACK'
   AND e.evento_tipo='READBACK_VERIFICADO'
 ORDER BY e.id DESC LIMIT 1;
 IF v_handoff.id IS NULL OR v_independent.id IS NULL
    OR v_handoff.payload->>'plan_code'<>v_plan
    OR v_independent.payload->>'plan_code'<>v_plan
    OR v_handoff.payload->>'unit_code'<>v_unit
    OR v_independent.payload->>'unit_code'<>v_unit
    OR v_handoff.payload->>'all_dependencies_done'<>'true'
    OR v_independent.payload->>'all_dependencies_done'<>'true'
    OR v_independent.payload->>'handoff_event_ref'<>'event://'||v_handoff.id THEN
   RAISE EXCEPTION 'M712_V2_GUARDED_CLOSURE_PROOF_REQUIRED';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_test_suite_runs r
   JOIN public.lf_test_suites s ON s.suite_code=r.suite_code
   WHERE r.suite_code='INPUT_GOV_REMEDIATION_QUALITY_V1'
     AND r.status='PASSED' AND r.tests_passed>=1 AND r.tests_failed=0
     AND r.commit_sha ~ '^[0-9a-f]{40}$'
     AND s.status='CANDIDATO' AND s.execution_policy->>'mode'='READ_ONLY'
     AND r.metadata->>'semantic_e2e'='false'
 ) THEN
   RAISE EXCEPTION 'M712_CANDIDATE_STRUCTURAL_FIRST_RUN_NOT_VERIFIED';
 END IF;
 -- Keep real evidence, remove only terminal event pointers that do not
 -- belong to this exact plan/unit's verified closure pair.
 FOREACH v_part IN ARRAY string_to_array(v_old,';') LOOP
   v_part:=btrim(v_part);
   IF v_part='' THEN CONTINUE; END IF;
   IF v_part ~ '^supabase://public[.]lf_eventos/[0-9]+$' THEN
     v_event_id:=split_part(v_part,'/',4)::bigint;
     SELECT e.* INTO v_event FROM public.lf_eventos e WHERE e.id=v_event_id;
     IF v_event.id IS NULL
        OR v_event.entidad_codigo NOT IN (
          v_plan||'.'||v_unit||'.CLOSE.HANDOFF',
          v_plan||'.'||v_unit||'.CLOSE.INDEPENDENT_READBACK'
        )
        OR v_event.payload->>'plan_code' IS DISTINCT FROM v_plan
        OR v_event.payload->>'unit_code' IS DISTINCT FROM v_unit THEN
       v_removed:=array_append(v_removed,v_part);
       CONTINUE;
     END IF;
   END IF;
   IF NOT v_part=ANY(v_parts) THEN v_parts:=array_append(v_parts,v_part); END IF;
 END LOOP;
 v_part:='supabase://public.lf_eventos/'||v_handoff.id;
 IF NOT v_part=ANY(v_parts) THEN v_parts:=array_append(v_parts,v_part); END IF;
 v_part:='supabase://public.lf_eventos/'||v_independent.id;
 IF NOT v_part=ANY(v_parts) THEN v_parts:=array_append(v_parts,v_part); END IF;
 v_new:=array_to_string(v_parts,';');
 IF v_new IS DISTINCT FROM v_old THEN
   UPDATE programacion.engineering_work_checkpoints
      SET evidence_ref=v_new,updated_at=now(),updated_by_execution_id=v_actor
   WHERE id=v_cp_id AND status='DONE' AND evidence_ref IS NOT DISTINCT FROM v_old;
   GET DIAGNOSTICS v_updated=ROW_COUNT;
   IF v_updated<>1 THEN RAISE EXCEPTION 'M712_CONCURRENT_EVIDENCE_CHANGE'; END IF;
 END IF;
 -- Append-only audit: the invalid historical pointer is retained here, not as proof.
 SELECT id INTO v_audit_id FROM public.lf_eventos
 WHERE entidad_codigo=v_plan||'.'||v_unit||'.CLOSE.EVIDENCE_RECONCILIATION'
 ORDER BY id DESC LIMIT 1;
 IF v_audit_id IS NULL THEN
   INSERT INTO public.lf_eventos
     (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,
      origen,created_by_execution_id)
   VALUES
     ('READBACK_VERIFICADO','ENGINEERING_PLAN_UNIT',
      v_plan||'.'||v_unit||'.CLOSE.EVIDENCE_RECONCILIATION',
      'Verified replacement of historical planning-event pointer in M7.12 terminal evidence',
      'INFO',
      jsonb_build_object(
       'evidence_schema_version','operational-event/v2',
       'plan_code',v_plan,'unit_code',v_unit,'checkpoint_code',v_checkpoint,
       'root_cause_code','IG-M712-V1-PLANNED-EVENT-INCORRECT-CLOSURE-REF-001',
       'old_evidence_ref',v_old,'new_evidence_ref',v_new,
       'superseded_nonclosure_refs',to_jsonb(v_removed),
       'handoff_event_ref','event://'||v_handoff.id,
       'independent_readback_event_ref','event://'||v_independent.id,
       'readback_only',true,'suite_activation_authorized',false,
       'semantic_e2e_claimed',false,'checkpoint_state_unchanged','DONE',
       'occurred_at',clock_timestamp()
      ),
      'EXECUTION:'||v_actor,v_actor)
   RETURNING id INTO v_audit_id;
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM programacion.engineering_work_checkpoints c
   WHERE c.id=v_cp_id AND c.status='DONE'
     AND c.evidence_ref LIKE '%supabase://public.lf_eventos/'||v_handoff.id||'%'
     AND c.evidence_ref LIKE '%supabase://public.lf_eventos/'||v_independent.id||'%'
 ) THEN RAISE EXCEPTION 'M712_TERMINAL_EVIDENCE_READBACK_FAILED'; END IF;
END
$m712_evidence$;

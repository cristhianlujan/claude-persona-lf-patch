-- Contract/gov paired repair: M9.8 technical completion is not runtime release activation.
-- Reuse canonical dependency graph and signed checkpoint evidence; no pointer/receipt writes.
DO $fix$
DECLARE m jsonb;s jsonb;pack jsonb;v_q jsonb;v_w bigint;affected int;
BEGIN
 SELECT work_item_id,unit_metadata INTO v_w,m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12'
 FOR UPDATE;
 IF v_w IS NULL OR m#>>'{cutover_readiness_governance_v1,require_m98_live_pass}'<>'true'
 OR m#>>'{action_specs_v1,CLOSURE_GATE_CONSUME,capability_execution_contract,require_m98_current_pass}'<>'true'
 THEN RAISE EXCEPTION 'M912_CONTRACT_PRESTATE_CHANGED'; END IF;
 IF (SELECT count(*) FROM programacion.fn_engineering_effective_dependencies_v1(v_w) WHERE is_unmet)<>1
 OR NOT EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(v_w)
   WHERE effective_work_code='PAULO-150' AND is_unmet)
 THEN RAISE EXCEPTION 'M912_GRAPH_PRESTATE_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.8'
 AND w.status='DONE' AND c.checkpoint_code='GATE_VERDICT_READBACK' AND c.status='DONE'
 AND c.evidence_ref LIKE '%fn_ig_m98_engineering_assurance_v7%'
 AND u.unit_metadata#>>'{m9_8_gate_contract_v2,technical_positive_state}'='TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED')
 THEN RAISE EXCEPTION 'M98_TECHNICAL_PROOF_ABSENT'; END IF;
 v_q:=jsonb_build_array('select u.unit_code,w.status as unit_status,count(*) as checkpoint_total,
count(*) filter(where c.status=''DONE'' and nullif(c.evidence_ref,'''') is not null) as done_attested,
bool_or(u.unit_code=''M9.8'' and c.checkpoint_code=''GATE_VERDICT_READBACK'' and c.status=''DONE''
 and c.evidence_ref like ''%fn_ig_m98_engineering_assurance_v7%''
 and u.unit_metadata#>>''{m9_8_gate_contract_v2,technical_positive_state}''=''TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED'') as m98_technical_verified
from programacion.engineering_plan_units owner
cross join lateral programacion.fn_engineering_effective_dependencies_v1(owner.work_item_id) d
join programacion.engineering_work_items w on w.id=d.effective_work_item_id
join programacion.engineering_plan_units u on u.work_item_id=w.id and u.plan_code=owner.plan_code
join programacion.engineering_work_checkpoints c on c.work_item_id=w.id
where owner.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' and owner.unit_code=''M9.12''
group by u.unit_code,w.status order by u.unit_code');
 pack:=m->'source_pack_v1';
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,inputs,queries}',v_q,true);
 pack:=jsonb_set(pack,'{checkpoint_inputs,PREREQ_RECEIPTS,inputs,db_objects}',
 jsonb_build_array('programacion.engineering_work_items','programacion.engineering_work_checkpoints',
 'programacion.engineering_plan_units'),true);
 m:=jsonb_set(m,'{source_pack_v1}',pack,true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,require_m98_live_pass}','false'::jsonb,true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,require_m98_technical_completion}','true'::jsonb,true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,m98_stage}',to_jsonb('TECHNICAL_VERIFIED_NOT_RELEASED'::text),true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,m98_source}',to_jsonb('CANONICAL_GRAPH_AND_SIGNED_ENGINEERING_CHECKPOINT'::text),true);
 s:=m#>'{action_specs_v1,CLOSURE_GATE_CONSUME}';
 s:=jsonb_set(s,'{capability_execution_contract}',
 ((s->'capability_execution_contract')-'require_m98_current_pass')||
 jsonb_build_object('require_m98_technical_checkpoint_done',true,'m98_release_binding_required',false),true);
 s:=s||jsonb_build_object('expected',
 'Require M9.8 completed technical checkpoint and attested evidence from canonical graph. Runtime-bound M9.8 release function is NOT a prerequisite; M9.10 drill and M9.0 signed bundle remain mandatory for CUTOVER_READY.');
 m:=jsonb_set(m,'{action_specs_v1,CLOSURE_GATE_CONSUME}',s,true);
 IF m IS NULL THEN RAISE EXCEPTION 'M912_NULL_JSON'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12';
 UPDATE public.lf_error_knowledge
 SET estado='RESUELTO',
 causa_raiz='M9.12 incorrectly consumed M9.8 release-bound readback requiring evidence_binding (NULL by design) despite M9.8 technical DONE and signed v7 checkpoint.',
 prevencion='Consume M9.8 technical DONE + signed checkpoint from canonical graph; reserve runtime evidence_binding for later release admission only. M9.10, bundle currentness, and signed CUTOVER_READY remain required.',
 validacion='PASS when M9.8 is DONE 5/5 and technical gate evidence attested, M9.12 WAIT_DEPENDENCIES solely for M9.10, no new readiness receipt, and negative tampering with technical proof fails.'
 WHERE codigo='IG-M912-M98-LIVE-READBACK-BLOCKED-001' AND estado='ACTIVO';
 GET DIAGNOSTICS affected=ROW_COUNT;
 IF affected<>1 THEN RAISE EXCEPTION 'M912_EKB_PRESTATE_CHANGED'; END IF;
END $fix$;
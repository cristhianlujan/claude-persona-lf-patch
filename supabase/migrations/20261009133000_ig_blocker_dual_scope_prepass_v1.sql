-- Cross-unit governance: repair unit contract and transversal governance in the SAME micro-lot.
-- Extend the existing prepass V2. This is NOT a new gate and does not make incompatibility PASS.
CREATE OR REPLACE FUNCTION programacion.fn_engineering_plan_blocker_repair_prepass_v2(p_plan_code text)
RETURNS jsonb LANGUAGE plpgsql
SET search_path TO 'programacion','public','pg_catalog'
AS $function$
DECLARE
 r record; v_cp text; v_spec jsonb; v_drifts jsonb; v_result jsonb; v_pair jsonb;
 v_rows jsonb:='[]'::jsonb; v_attempted int:=0; v_changed int:=0;
 v_git boolean; v_admission_drift boolean;
BEGIN
 WITH pinned AS (
   SELECT c.capability_code consumer,upper(d.key) provider,
          d.value->>'version' pinned_version,d.value->>'manifest_sha256' pinned_sha
   FROM public.lf_capability_current c
   JOIN public.lf_capability_version_registry v
     ON v.capability_code=c.capability_code AND v.version=c.version
    AND v.manifest_sha256=c.manifest_sha256
   CROSS JOIN LATERAL jsonb_each(coalesce(v.manifest->'dependencies','{}'::jsonb)) d
   WHERE jsonb_typeof(d.value)='object'
     AND d.value ? 'version' AND d.value ? 'manifest_sha256'
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'consumer',p.consumer,'provider',p.provider,
   'pinned_version',p.pinned_version,'current_version',c.version,
   'pinned_sha256',p.pinned_sha,'current_sha256',c.manifest_sha256,
   'state',CASE WHEN c.capability_code IS NULL THEN 'MISSING' ELSE 'DRIFT' END
 )),'[]'::jsonb)
 INTO v_drifts
 FROM pinned p LEFT JOIN public.lf_capability_current c ON upper(c.capability_code)=p.provider
 WHERE c.capability_code IS NULL OR c.version IS DISTINCT FROM p.pinned_version
    OR c.manifest_sha256 IS DISTINCT FROM p.pinned_sha;
 FOR r IN
   SELECT pu.unit_code,pu.work_item_id FROM programacion.engineering_plan_units pu
   JOIN programacion.engineering_work_items w ON w.id=pu.work_item_id
   WHERE pu.plan_code=p_plan_code AND pu.disposition='ASSIGNED'
     AND w.status IN ('BACKLOG','READY','IN_PROGRESS','BLOCKED')
     AND programacion.fn_engineering_effective_open_blocker_count_v1(w.id)>0
   ORDER BY pu.id
 LOOP
   SELECT c.checkpoint_code INTO v_cp FROM programacion.engineering_work_checkpoints c
   WHERE c.work_item_id=r.work_item_id AND c.status NOT IN ('DONE','NOT_APPLICABLE')
   ORDER BY c.sequence_no LIMIT 1;
   IF v_cp IS NULL THEN CONTINUE; END IF;
   v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,r.unit_code,v_cp);
   v_git:=coalesce(v_spec#>>'{authoring_contract,git_route}'='SCOPED_BRANCH_PR_MERGE',false)
          OR coalesce(v_spec->>'action_kind'='WRITE_GIT',false);
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(v_drifts) d
     WHERE d->>'consumer'='SAFE_CHANGE_ADMISSION') INTO v_admission_drift;
   v_pair:=jsonb_build_object(
     'schema_version','ENGINEERING_BLOCKER_DUAL_SCOPE_REPAIR_V1',
     'unit_code',r.unit_code,'checkpoint_code',v_cp,
     'unit_contract',jsonb_build_object(
       'action_spec_status',v_spec->>'status','action_kind',v_spec->>'action_kind',
       'allowed_db_targets',coalesce(v_spec#>'{authoring_contract,db_targets_exact}','[]'::jsonb),
       'resolution','REPAIR_AND_READBACK_OR_PROVE_NO_CHANGE'),
     'governance',jsonb_build_object(
       'current_capability_pin_drifts',v_drifts,'admission_relevant',v_git,
       'resolution','RECONCILE_COMPATIBILITY_WITH_EVIDENCE_OR_PROVE_NOT_APPLICABLE',
       'no_blind_major_version_rebind',true),
     'required_tracks',jsonb_build_array('UNIT_CONTRACT','TRANSVERSAL_GOVERNANCE'),
     'closure_rule','BOTH_TRACKS_EVIDENCED_OR_GOVERNANCE_PROVEN_NOT_APPLICABLE',
     'no_new_gate',true);
   IF v_git AND v_admission_drift THEN
     v_result:=jsonb_build_object(
       'status','TRANSVERSAL_ADMISSION_DRIFT','state_changed',false,
       'repair_family','GOVERNANCE_CURRENTNESS',
       'error_code','CAPABILITY_PIN_DRIFT_REQUIRES_COMPATIBILITY_PROOF');
   ELSE
     v_result:=programacion.fn_engineering_blocker_family_dispatch_v1(
       p_plan_code,r.unit_code,v_cp,true);
   END IF;
   v_attempted:=v_attempted+1;
   IF coalesce((v_result->>'state_changed')::boolean,false) THEN
     v_changed:=v_changed+1;
   END IF;
   v_rows:=v_rows||jsonb_build_array(jsonb_build_object(
     'unit_code',r.unit_code,'checkpoint_code',v_cp,
     'result',v_result,'repair_pair',v_pair));
 END LOOP;
 RETURN jsonb_build_object(
   'schema_version','ENGINEERING_PLAN_BLOCKER_REPAIR_PREPASS_V2',
   'plan_code',p_plan_code,'attempted',v_attempted,'changed',v_changed,
   'dual_scope_protocol','ENGINEERING_BLOCKER_DUAL_SCOPE_REPAIR_V1',
   'governance_pin_drifts',v_drifts,'results',v_rows);
END;
$function$;

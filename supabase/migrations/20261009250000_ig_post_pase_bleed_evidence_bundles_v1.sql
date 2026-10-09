-- IG scope correction (recurrence of IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001).
-- M7.14 / M8.12 / M9.13 *_EVIDENCE_BUNDLE still routed to FINAL_EVIDENCE (disabled POST_PASE workstream, needs a Router AUTHORIZED_PLAN).
-- The checkpoint is kept (traceability + closure evidence) but its mechanism becomes IG-owned: a deterministic manifest derived from the
-- engineering ledger (unit status + checkpoint evidence_refs of the macrolot units), hashed with SHA-256, no own store, no FINAL_EVIDENCE.
do $preflight$
declare v_n int;
begin
  select count(*) into v_n from programacion.engineering_plan_units pu
   join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and (pu.unit_code,c.checkpoint_code) in (('M7.14','M7_EVIDENCE_BUNDLE'),('M8.12','M8_EVIDENCE_BUNDLE'),('M9.13','M9_EVIDENCE_BUNDLE'));
  if v_n<>3 then raise exception 'IG_EVIDENCE_BUNDLE_SCOPE_PREFLIGHT_FAILED n=%',v_n; end if;
end
$preflight$;

do $apply$
declare
  r record;
  v_q text;
  v_spec jsonb;
begin
  for r in select * from (values ('M7.14','M7_EVIDENCE_BUNDLE','M7','M7'),('M8.12','M8_EVIDENCE_BUNDLE','M8','M8'),('M9.13','M9_EVIDENCE_BUNDLE','M9','M9')) t(unit_code,cp,macro,pfx) loop
    v_q := format($q$select u.unit_code, w.status unit_status, count(c.*) checkpoints, count(c.*) filter (where c.status in ('DONE','NOT_APPLICABLE')) closed, count(c.*) filter (where c.status in ('DONE','NOT_APPLICABLE') and nullif(btrim(coalesce(c.evidence_ref,'')),'') is null) closed_without_evidence, encode(extensions.digest(convert_to(string_agg(u.unit_code||'|'||c.checkpoint_code||'|'||c.status||'|'||coalesce(c.evidence_ref,''),E'\n' order by u.unit_code,c.sequence_no),'UTF8'),'sha256'),'hex') unit_manifest_sha256 from programacion.engineering_plan_units u join programacion.engineering_work_items w on w.id=u.work_item_id join programacion.engineering_work_checkpoints c on c.work_item_id=w.id where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code ~ '^%s\.[0-9]+$' and u.unit_code<>%L group by u.unit_code,w.status order by u.unit_code$q$, r.pfx, r.unit_code);
    v_spec := jsonb_build_object(
      'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3','checkpoint_code',r.cp,
      'contract_source','EXPLICIT_ACTION_SPEC','contract_family','READ_ONLY_EVIDENCE',
      'precision','IG_LEDGER_DERIVED_MANIFEST_V1','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
      'mutation_policy','NO_DOMAIN_MUTATION','requires_material_execution',false,
      'expected','Per-unit ledger manifest of the '||r.macro||' units (status, checkpoint closure, evidence_ref presence, SHA-256 of unit|checkpoint|status|evidence_ref lines). No FINAL_EVIDENCE, no own store; the manifest sha is persisted in the checkpoint evidence_ref.',
      'target',jsonb_build_object('checkpoint',r.cp,'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
        'declared_objects',jsonb_build_array('programacion.engineering_plan_units','programacion.engineering_work_items','programacion.engineering_work_checkpoints'),'declared_artifacts','[]'::jsonb),
      'verification_queries',jsonb_build_array(v_q),
      'forbidden',jsonb_build_array('USE_FINAL_EVIDENCE_FROM_DISABLED_POST_PASE','CREATE_OWN_EVIDENCE_STORE','SYNTHETIC_PASS_WITHOUT_READBACK'));
    update programacion.engineering_plan_units pu
       set unit_metadata = jsonb_set(jsonb_set(pu.unit_metadata, array['action_specs_v1',r.cp], v_spec, true),
                                     array['transversal_execution_v1',r.cp,'activation'], '"DECLARED_ONLY"'::jsonb, false)
     where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code=r.unit_code;
    update programacion.engineering_work_checkpoints c
       set title='Evidencia de cierre '||r.macro||' derivada del ledger (manifest SHA-256 determinista de las unidades '||r.macro||'; sin FINAL_EVIDENCE ni store propio)',
           updated_at=now(), updated_by_execution_id='IG_POST_PASE_SCOPE_CORRECTION_V2'
      from programacion.engineering_plan_units pu
     where pu.work_item_id=c.work_item_id and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
       and pu.unit_code=r.unit_code and c.checkpoint_code=r.cp;
  end loop;
end
$apply$;

update public.lf_error_knowledge
   set frecuencia=coalesce(frecuencia,1)+1, ultima_vez=now(), updated_at=now(),
       evidencia=evidencia||';supabase://programacion.engineering_plan_units/M7.14,M8.12,M9.13',
       validacion=validacion||' RECURRENCE 2026-10-09: M7.14/M8.12/M9.13 *_EVIDENCE_BUNDLE also routed to FINAL_EVIDENCE; corrected to ledger-derived READBACK_ONCE with activation DECLARED_ONLY.'
 where codigo='IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001';

do $selftest$
declare v_bad int; s jsonb; u text; cp text;
begin
  for u,cp in select * from (values ('M7.14','M7_EVIDENCE_BUNDLE'),('M8.12','M8_EVIDENCE_BUNDLE'),('M9.13','M9_EVIDENCE_BUNDLE')) t(a,b) loop
    s:=programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2',u,cp);
    if s->>'status' is distinct from 'READY' or s->>'action_kind' is distinct from 'READBACK_ONCE'
       or s::text ilike '%TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION%' then
      raise exception 'IG_EVIDENCE_BUNDLE_SELFTEST_FAILED:%:%',u,left(s::text,300);
    end if;
  end loop;
  select count(*) into v_bad from programacion.engineering_plan_units pu, jsonb_each(pu.unit_metadata->'transversal_execution_v1') e
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code in ('M7.14','M8.12','M9.13') and e.value->>'activation'='ACTIVE' and e.value::text ~ 'FINAL_EVIDENCE';
  if v_bad<>0 then raise exception 'IG_EVIDENCE_BUNDLE_SELFTEST_ACTIVE_POST_PASE:%',v_bad; end if;
end
$selftest$;

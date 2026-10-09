-- Keep POST_PASE capabilities declared for traceability, but inactive inside IG.
-- POST_PASE is owned by a separate workstream and must not be executed by
-- IG macrolot closure units until that workstream is explicitly activated.

do $preflight$
declare
  v_total int;
  v_active int;
begin
  select count(*),
         count(*) filter (
           where pu.unit_metadata#>>'{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation}'='ACTIVE'
         )
    into v_total,v_active
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code in ('M5.10','M6.13')
    and (pu.unit_metadata#>'{transversal_execution_v1,FINAL_EVIDENCE_SADM}')::text ilike '%POST_PASE_ROUTER%'
    and (pu.unit_metadata#>'{transversal_execution_v1,FINAL_EVIDENCE_SADM}')::text ilike '%POST_PASE_ORCHESTRATOR%';

  if v_total<>2 or v_active<>2 then
    raise exception 'IG_POST_PASE_DEACTIVATION_PREFLIGHT_FAILED total=% active=%',v_total,v_active;
  end if;
end
$preflight$;

update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        unit_metadata,
        '{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation}',
        '"DECLARED_ONLY"'::jsonb,
        false
      ),
      '{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation_reason}',
      '"OUT_OF_SCOPE_POST_PASE_WORKSTREAM_NOT_ACTIVE_FOR_IG"'::jsonb,
      true
    ),
    '{transversal_execution_v1,FINAL_EVIDENCE_SADM,scope_boundary}',
    '"IG_MACROLOT_CLOSURE_DOES_NOT_EXECUTE_POST_PASE"'::jsonb,
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code in ('M5.10','M6.13');

update public.lf_error_knowledge
set validacion =
  'PASS when complete repository capability input references resolve only through the canonical resolver; unknown resolution codes fail closed; external facts are never synthesized; declared-only or out-of-scope transversals do not compile to execution packets.',
    prevencion =
  'Use fn_engineering_repository_capability_input_resolve_v1 only for ACTIVE repository-capability execution. Keep cross-workstream capability references DECLARED_ONLY until their owning workstream is explicitly activated. Unknown resolution codes fail closed and external authority facts are never synthesized.',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-REPOSITORY-CAPABILITY-INPUT-RESOLVER-001';

update public.lf_error_knowledge
set validacion =
  'PASS when supported ACTIVE transversal handlers compile to READ|WRITE_DB|WRITE_GIT|RUN_TEST using exact capability-owned entrypoints; incomplete inputs remain fail-closed; DECLARED_ONLY cross-workstream handlers remain non-executable and do not affect the current unit.',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-TRANSVERSAL-ADAPTER-COMPILATION-GAP-001';

do $selftest$
declare
  v_declared_only int;
  v_bad int;
begin
  select count(*)
    into v_declared_only
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code in ('M5.10','M6.13')
    and pu.unit_metadata#>>'{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation}'='DECLARED_ONLY'
    and pu.unit_metadata#>>'{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation_reason}'
        ='OUT_OF_SCOPE_POST_PASE_WORKSTREAM_NOT_ACTIVE_FOR_IG'
    and (pu.unit_metadata#>'{transversal_execution_v1,FINAL_EVIDENCE_SADM}')::text ilike '%POST_PASE_ROUTER%'
    and (pu.unit_metadata#>'{transversal_execution_v1,FINAL_EVIDENCE_SADM}')::text ilike '%POST_PASE_ORCHESTRATOR%';

  if v_declared_only<>2 then
    raise exception 'IG_POST_PASE_DEACTIVATION_SELFTEST_FAILED declared_only=%',v_declared_only;
  end if;

  select count(*)
    into v_bad
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code in ('M5.10','M6.13')
    and pu.unit_metadata#>>'{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation}'='ACTIVE';

  if v_bad<>0 then
    raise exception 'IG_POST_PASE_STILL_ACTIVE:%',v_bad;
  end if;
end
$selftest$;

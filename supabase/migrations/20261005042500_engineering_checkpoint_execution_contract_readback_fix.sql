-- Readback fixes for ENGINEERING_CHECKPOINT_EXECUTION_CONTRACT_V1.

create or replace function programacion.fn_engineering_checkpoint_recipe_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with u as (
  select pu.plan_code, pu.unit_code, pu.work_item_id, pu.exit_criterion, pu.unit_metadata
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
), cp as (
  select c.checkpoint_code,c.title,c.sequence_no,c.status
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id=c.work_item_id
  where c.checkpoint_code=coalesce(p_checkpoint_code,(select c2.checkpoint_code from programacion.engineering_work_checkpoints c2 where c2.work_item_id=u.work_item_id and c2.status not in ('DONE','NOT_APPLICABLE') order by c2.sequence_no limit 1))
  limit 1
), inp as (
  select case
    when cp.checkpoint_code is null then null
    when u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code] is not null then u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code] is not null then u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' is not null and u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' <> 'null'::jsonb then u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'
    else null end execution_input
  from u cross join cp
), miss as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind',m.value->>'kind','text',m.value->>'text','blocking',coalesce((m.value->>'blocking')::boolean,false),
    'resolver',coalesce(nullif(m.value->>'resolver',''),case
      when m.value->>'text' ilike '%M8.11%' then 'UPSTREAM:M8.11'
      when m.value->>'text' ilike '%M8.1%' then 'UPSTREAM:M8.1'
      when m.value->>'text' ilike '%M2.8%' then 'UPSTREAM:M2.8'
      when m.value->>'kind'='DELIVERABLE' then 'SELF:'||p_unit_code||'/'||cp.checkpoint_code
      else null end)
  )) filter(where m.value is not null),'[]'::jsonb) resolved
  from cp cross join inp
  left join lateral jsonb_array_elements(coalesce(inp.execution_input->'missing_typed','[]'::jsonb)) m(value) on true
), classified as (
  select cp.*,u.exit_criterion,inp.execution_input,miss.resolved,
    case
      when cp.checkpoint_code ~* '(^TERMINAL$|HANDOFF|FINAL_HANDOFF|INDEPENDENT_READBACK|CLOSURE)' then 'TERMINAL_RECONCILE'
      when cp.checkpoint_code ~* '(READBACK|RECEIPT_READBACK|GATE_READBACK)' then 'READBACK_EXACT'
      when cp.checkpoint_code ~* '(ASIS|INVENTORY|BASELINE|SOURCE_MAP|AUTHORITY_MAP)' then 'OBSERVE_AND_PERSIST'
      when cp.checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)' then 'VERIFY_EXPECTED'
      when cp.checkpoint_code ~* '(DECISION|ADR|ADJUDICAT|AUTHORITY|GATE|CUTOVER_READY|EXPIRY)' then 'DECISION_OR_GATE'
      else 'EXECUTE_DECLARED_DELIVERABLE' end recipe_mode
  from u cross join cp cross join inp cross join miss
)
select jsonb_build_object(
  'schema_version','ENGINEERING_CHECKPOINT_RECIPE_V1','checkpoint_code',checkpoint_code,'checkpoint_title',title,'checkpoint_sequence_no',sequence_no,
  'recipe_mode',recipe_mode,'execution_input_present',execution_input is not null,'missing_resolution',resolved,
  'decision_rule',case recipe_mode
    when 'OBSERVE_AND_PERSIST' then 'EXECUTE_CANONICAL_INPUT_ONCE; IF checkpoint_title observation is confirmed THEN persist DONE immediately; do not design later checkpoints.'
    when 'READBACK_EXACT' then 'READ exact declared authority once; IF exact state matches checkpoint_title THEN persist DONE; historical reconfirmation forbidden.'
    when 'VERIFY_EXPECTED' then 'RUN only the declared negative/parity/test for this checkpoint; compare to checkpoint_title/expected result; persist immediately on PASS.'
    when 'DECISION_OR_GATE' then 'USE only declared authority/evidence; persist the decision/gate and exact readback; do not broaden scope.'
    when 'TERMINAL_RECONCILE' then 'VERIFY prior required checkpoints are terminal and closure evidence exists; reconcile ledger only; no material redesign.'
    else 'MATERIALIZE only the deliverable named by current checkpoint, verify it exactly, then persist; no cross-checkpoint design.' end,
  'steps',jsonb_build_array('EXECUTE_CURRENT_INPUT_ONCE','EVALUATE_CURRENT_CHECKPOINT_ONLY','PERSIST_VIA_FN_ENGINEERING_CHECKPOINT_TRANSITION_V1','USE_RETURNED_BOOTSTRAP_AS_ONLY_NEXT_STATE'),
  'close_when',case recipe_mode
    when 'OBSERVE_AND_PERSIST' then 'CANONICAL_LIVE_OBSERVATION_MATCHES_CHECKPOINT_TITLE'
    when 'READBACK_EXACT' then 'EXACT_READBACK_MATCHES_DECLARED_CHECKPOINT'
    when 'VERIFY_EXPECTED' then 'DECLARED_EXPECTED_RESULT_VERIFIED'
    when 'DECISION_OR_GATE' then 'DECISION_OR_GATE_PERSISTED_AND_READ_BACK'
    when 'TERMINAL_RECONCILE' then 'ALL_REQUIRED_PRIOR_CHECKPOINTS_TERMINAL_AND_CLOSURE_EVIDENCE_PRESENT'
    else 'DECLARED_DELIVERABLE_MATERIALIZED_AND_CURRENT_CHECKPOINT_VERIFICATION_PASS' end,
  'unit_exit_criterion',exit_criterion,
  'fallback_only_on',jsonb_build_array('MISSING_CANONICAL_OBJECT','CONTRADICTION','STALE_CURRENTNESS','DEMONSTRATED_DRIFT','MATERIAL_FINGERPRINT_CHANGE'),
  'forbidden',jsonb_build_array('CROSS_CHECKPOINT_DESIGN','REPEATED_SOLUTION_REDESIGN','HISTORICAL_RECONFIRMATION_AFTER_LIVE_PASS','NARRATIVE_PROGRESS_PERCENT','UNTRIGGERED_DISCOVERY')
) from classified;
$function$;

-- Reconcile checkpoint text with RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1 without reducing material scopes.
update programacion.engineering_work_checkpoints c
set title='Reproducibilidad: 2 ejecuciones frescas sobre exactamente 3 pantallas representativas ×47 producen el mismo SHA; negativo: entrada con fuente semántica => rechazo; baseline histórico 13×47 solo para paridad/readback',updated_at=now(),updated_by_execution_id='ENGINEERING_CHECKPOINT_EXECUTION_CONTRACT_V1'
from programacion.engineering_plan_units pu
where pu.work_item_id=c.work_item_id and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M2.8' and c.checkpoint_code='REPRODUCIBILITY_NEGATIVE' and c.status not in ('DONE','NOT_APPLICABLE');

update programacion.engineering_work_checkpoints c
set title=case pu.unit_code
  when 'M5.3' then 'Paridad contra golden histórico 13×47 por reuse/readback; validación fresca, si aplica, usa muestra estándar de 3 pantallas; readback y estado terminal único'
  when 'M5.4' then 'Paridad contra golden histórico 13×47 por reuse/readback; validación fresca, si aplica, usa muestra estándar de 3 pantallas; readback y estado terminal único'
  when 'M8.5' then '0 resolvers ejecutados sin necesidad; paridad contra golden histórico 13×47 por reuse/readback; validación fresca estándar=3; estado terminal único'
  when 'M8.6' then 'Negativo: lectura en lote no cambia resultados; validar muestra fresca estándar de 3 pantallas y usar baseline histórico 13×47 para paridad/readback'
  else c.title end,
  updated_at=now(),updated_by_execution_id='ENGINEERING_CHECKPOINT_EXECUTION_CONTRACT_V1'
from programacion.engineering_plan_units pu
where pu.work_item_id=c.work_item_id and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code in ('M5.3','M5.4','M8.5','M8.6') and c.status not in ('DONE','NOT_APPLICABLE') and c.checkpoint_code in ('TERMINAL','NEGATIVE_PARITY');

-- M10.5 is preserved as an explicit post-cutover integral exception rather than silently sampled.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(coalesce(unit_metadata,'{}'::jsonb),'{validation_scope_class_v1}','"EXPLICIT_INTEGRAL_POST_CUTOVER_E2E"'::jsonb,true)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.5';

-- Ensure the active execution-contract EKB is returned by V1 core and therefore by bootstrap V2.
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{canonical_bootstrap_v1,ekb_codes}',
  case
    when jsonb_typeof(unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}')='array' and (unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}') @> '["ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001"]'::jsonb then unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}'
    when jsonb_typeof(unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}')='array' then (unit_metadata#>'{canonical_bootstrap_v1,ekb_codes}') || '["ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001"]'::jsonb
    else '["ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001"]'::jsonb end,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and disposition<>'FUSED';

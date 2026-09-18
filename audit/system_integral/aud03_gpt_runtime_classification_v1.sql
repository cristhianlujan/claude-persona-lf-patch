-- AUD-3 GPT_RUNTIME full-population classifier v1
-- Read-only. Classification is signal-based and auditable; MIXED/UNCLASSIFIED are not coerced.
with population as (
  select c.operation_code,c.step_id,c.contract_code,c.status,c.purpose,c.resolver_ref,
         c.execution_sql,c.required_evidence_keys,c.input_required,c.output_payload,c.notes,
         exists(
           select 1 from public.lf_operation_step_judge_bindings b
           where b.operation_code=c.operation_code and b.step_id=c.step_id and b.status='ACTIVE_ENFORCEMENT'
         ) has_active_judge,
         lower(concat_ws(' ',c.step_id,coalesce(c.purpose,''),coalesce(c.notes,''))) txt
  from public.lf_operation_step_contracts c
  where c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
    and c.resolver_ref like 'GPT_RUNTIME%'
),
signals as (
  select *,
    ((execution_sql is not null and btrim(execution_sql)<>'')
      or txt ~ '(determin|validat|schema|currentness|readback|parity|duplicate|hash|fingerprint|idempot|integrity|exact-head|exact head|contract|permission|state transition|rollback|scope check)')
      as deterministic_signal,
    (has_active_judge
      or txt ~ '(semantic|expertise|quality|judge|review|risk|interpret|classif|narrative|research|design|human|hitl|recommend|analysis|analisis)')
      as semantic_signal
  from population
),
classified as (
  select *,
    case
      when deterministic_signal and semantic_signal then 'MIXED'
      when deterministic_signal then 'DETERMINISTIC_SIGNAL_ONLY'
      when semantic_signal then 'SEMANTIC_SIGNAL_ONLY'
      else 'UNCLASSIFIED'
    end classification
  from signals
)
select jsonb_build_object(
 'active_gpt_runtime_population',(select count(*) from classified),
 'classification_counts',jsonb_build_object(
   'deterministic_signal_only',(select count(*) from classified where classification='DETERMINISTIC_SIGNAL_ONLY'),
   'semantic_signal_only',(select count(*) from classified where classification='SEMANTIC_SIGNAL_ONLY'),
   'mixed',(select count(*) from classified where classification='MIXED'),
   'unclassified',(select count(*) from classified where classification='UNCLASSIFIED')
 ),
 'rows',coalesce((
   select jsonb_agg(jsonb_build_object(
     'operation_code',operation_code,'step_id',step_id,'contract_code',contract_code,
     'status',status,'purpose',purpose,'resolver_ref',resolver_ref,
     'has_execution_sql',(execution_sql is not null and btrim(execution_sql)<>''),
     'has_active_judge',has_active_judge,
     'deterministic_signal',deterministic_signal,'semantic_signal',semantic_signal,
     'classification',classification
   ) order by operation_code,step_id)
   from classified
 ),'[]'::jsonb),
 'interpretation','Signal-based triage only. MIXED and UNCLASSIFIED require AUD-5 assurance review; no system repair is implied.'
) as aud03_gpt_runtime_classification;

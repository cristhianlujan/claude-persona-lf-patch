-- INPUT_GOVERNANCE actionable remediation derived layer v1.
-- Derived read-only summary; does not mutate classifier outcomes, run state, Story Gate, promotion, or product sources.
create or replace function programacion.fn_input_actionable_remediation_summary_v1(p_run_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
with rc as (
  select r.id run_id,r.pantalla_id,p.codigo screen_code
  from programacion.input_readiness_runs r
  join lf_ops.pantallas p on p.id=r.pantalla_id
  where r.id=p_run_id
),
field_refs as (
  select rg.codigo rule_code,rg.estado rule_status,e.key ref_key,e.value field_code,
         f.id field_id,f.estado field_status,
         coalesce((select jsonb_agg(v.codigo order by v.validation_order nulls last,v.id)
                   from lf_ops.campos_validaciones v
                   where v.campo_id=f.id and v.estado='ACTIVO'),'[]'::jsonb) active_validations
  from rc
  join lf_ops.reglas_pantallas rp on rp.pantalla_id=rc.pantalla_id
  join lf_ops.reglas rg on rg.id=rp.regla_id and rg.estado='VIGENTE'
  cross join lateral jsonb_each_text(rg.valor_config) e
  left join lf_ops.campos f on f.codigo=e.value
  where e.key like '%\_field\_code' escape '\'
),
fr as (
  select count(*) filter(where field_status='ACTIVO') active_ref_count,
         coalesce(string_agg(rule_code||' ('||rule_status||') -> '||ref_key||' -> '||field_code||' ('||coalesce(field_status,'ABSENT')||')','; ' order by rule_code,ref_key),'') chain_text,
         coalesce(jsonb_agg(jsonb_build_object('rule_code',rule_code,'rule_status',rule_status,'reference_key',ref_key,'field_code',field_code,'field_status',coalesce(field_status,'ABSENT'),'active_validations',active_validations) order by rule_code,ref_key),'[]'::jsonb) refs,
         coalesce((select jsonb_agg(distinct v) from field_refs x cross join lateral jsonb_array_elements_text(x.active_validations) v),'[]'::jsonb) validation_codes
  from field_refs
),
outcomes as (
  select coalesce(jsonb_agg(distinct k.outcome order by k.outcome),'[]'::jsonb) codes
  from rc
  join lf_ops.reglas_pantallas rp on rp.pantalla_id=rc.pantalla_id
  join lf_ops.reglas rg on rg.id=rp.regla_id and rg.estado='VIGENTE'
  cross join lateral jsonb_object_keys(case when jsonb_typeof(rg.valor_config->'outcomes')='object' then rg.valor_config->'outcomes' else '{}'::jsonb end) k(outcome)
),
q as (
  select p.id proposal_id,a.family_code,p.gap_code,p.proposal_kind,p.proposed_payload,p.canonical_target,p.source_refs proposal_source_refs,
         a.source_refs,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,a.curator_evidence,a.validator_evidence,p.stage_impact,
         coalesce(p.proposed_payload->>'gap_classification','') gap_classification,
         coalesce(a.blockers->0->>'bootstrap_level','') bootstrap_level,
         coalesce(a.curator_evidence->'bootstrap_probe','{}'::jsonb) bootstrap_probe,
         coalesce((a.source_refs->0)::text,(p.source_refs->0)::text,'{}') source_ref_text
  from programacion.input_family_assessments a
  join programacion.input_gap_proposals p on p.assessment_id=a.id and p.run_id=a.run_id
  where a.run_id=p_run_id and a.story_ready_status='BLOCKED' and a.validator_outcome='PASS'
    and p.status='VALIDATED' and p.validator_outcome='PASS'
),
items as (
 select q.family_code,
 jsonb_build_object(
   'evaluation_outcome','NEGATIVE_CONFIRMED',
   'evidence_examined',jsonb_build_array(
      jsonb_build_object('source_ref',q.source_ref_text,'authority_status','CURRENT_VALIDATED_READBACK','observed_fact',q.rationale),
      jsonb_build_object('source_ref','CURATOR_BOOTSTRAP_PROBE:'||q.family_code,'authority_status','CURRENT_VALIDATED_READBACK','observed_fact',q.bootstrap_probe::text)
   ),
   'evidence_found',case
      when q.family_code in ('FIELDS','VALIDATIONS') and fr.active_ref_count>0 then fr.refs
      when q.bootstrap_level='PARTIAL' then jsonb_build_array('Validated partial bootstrap evidence: '||q.bootstrap_probe::text)
      else '[]'::jsonb end,
   'exact_gap',case
      when q.family_code='FIELDS' and fr.active_ref_count>0 then 'FIELDS resolver reports no field while scoped current rules expose active explicit field references: '||fr.chain_text||'. The missing dimension is traversal and semantic sufficiency evaluation of those references.'
      when q.family_code='VALIDATIONS' and fr.active_ref_count>0 then 'VALIDATIONS resolver starts from an empty field set although the scoped rule-to-field chain resolves: '||fr.chain_text||'; active validations='||fr.validation_codes::text||'. The missing dimension is traversal through the resolved field into its active validations and scope verification.'
      when q.family_code='UI_MESSAGES' then 'No current canonical message registry entry is resolved for the screen recovery outcomes '||outcomes.codes::text||'; validated probe='||q.bootstrap_probe::text||'.'
      else q.family_code||' remains Story BLOCKED by '||q.gap_code||' on source '||q.source_ref_text||'; validated bootstrap probe='||q.bootstrap_probe::text||'. The unresolved required dimension is the specific canonical source/definition represented by this blocker.' end,
   'cause_type',case
      when q.family_code in ('FIELDS','VALIDATIONS') and fr.active_ref_count>0 then 'RESOLVER_MISSED_EXPLICIT_REFERENCE'
      when q.proposal_kind='SOURCE_CONFLICT' then 'SOURCE_CONFLICT'
      when q.family_code='UI_MESSAGES' and coalesce((q.bootstrap_probe->>'message_registry_count')::int,0)=0 then 'CANONICAL_SOURCE_ABSENT'
      when q.gap_classification='APPLICABILITY_AUTHORITY_GAP' then 'APPLICABILITY_AUTHORITY_MISSING'
      when q.gap_classification='FUNCTIONAL_DEFINITION_GAP' then 'FUNCTIONAL_DEFINITION_MISSING'
      else 'GOVERNANCE_EVIDENCE_MISSING' end,
   'remediation_action',case
      when q.family_code='FIELDS' and fr.active_ref_count>0 then jsonb_build_array('Traverse each scoped VIGENTE rule explicit *_field_code reference into lf_ops.campos, resolve the ACTIVO field, and reevaluate every required FIELDS dimension before changing the evaluation outcome.')
      when q.family_code='VALIDATIONS' and fr.active_ref_count>0 then jsonb_build_array('Traverse the scoped VIGENTE rule -> explicit field reference -> ACTIVO field chain into lf_ops.campos_validaciones, verify the active validations apply to the recovery scope, and reevaluate every required VALIDATIONS dimension.')
      when q.family_code='UI_MESSAGES' then jsonb_build_array('Resolve Client message/error catalogs for pantalla_id='||(select pantalla_id from rc)||' and explicit current recovery outcomes '||outcomes.codes::text||'; reuse only current scope-matched entries and, only if exhaustive canonical lookup remains empty, prepare the minimal UX_PRODUCT source definition per unresolved outcome.')
      else jsonb_build_array('Resolve blocker '||q.gap_code||' for family '||q.family_code||' by re-reading the exact current source '||q.source_ref_text||', exhausting explicit VIGENTE/ACTIVO references, reuse rules, named canonical entities, current evidence and contradictions for this pantalla_id; record the resolved authority/status and rerun Curator then independent Validator.') end,
   'do_not_do',case
      when q.family_code='FIELDS' then jsonb_build_array('Do not create a new field while an explicit current field reference remains unresolved.','Do not mark FIELDS POSITIVE until all required FIELDS dimensions are reevaluated.','Do not request Human Decision for a resolver traversal defect.')
      when q.family_code='VALIDATIONS' then jsonb_build_array('Do not create new validations before evaluating the active validations already linked to the resolved field.','Do not copy validation semantics from another screen solely because codes look similar.','Do not request Human Decision for a resolver traversal defect.')
      when q.family_code='UI_MESSAGES' then jsonb_build_array('Do not invent final copy.','Do not reuse B2B or cross-screen messages by textual similarity without explicit scope.','Do not convert an empty message catalog into NOT_APPLICABLE.')
      else jsonb_build_array('Do not treat absence or count=0 as NOT_APPLICABLE without positive authority.','Do not create or canonicalize a replacement source before exhausting explicit current references and reusable canonical entities for the exact scope.','Do not escalate to Human Decision while internal resolution remains permitted and no positive owner escalation authority is present.') end,
   'close_when',case
      when q.family_code='FIELDS' then jsonb_build_array('Every scoped explicit field reference is resolved with current authority/status and the FIELDS resolver demonstrates that no required FIELDS dimension remains unresolved; Curator and independent Validator then reevaluate the family.')
      when q.family_code='VALIDATIONS' then jsonb_build_array('The scoped rule -> field -> active-validation chain is resolved, each validation is verified for the recovery scope, and no required VALIDATIONS dimension remains unresolved after Curator and independent Validator reevaluation.')
      when q.family_code='UI_MESSAGES' then jsonb_build_array('Each required recovery outcome has a current canonical Client message/error reference applicable to the screen, or a minimal explicit UX_PRODUCT authority decision/source request remains for only the unresolved copy property.')
      else jsonb_build_array('A fresh direct readback resolves blocker '||q.gap_code||' for the exact source/scope, records the current authority and evidence, and an independent Validator reevaluation confirms no unresolved required Story dimension remains for '||q.family_code||'.') end,
   'next_owner',case when q.proposal_kind='SOURCE_CONFLICT' then 'CURATOR' when q.family_code='UI_MESSAGES' then 'UX_PRODUCT' when q.family_code='SECURITY' then 'SECURITY' else 'INTERNAL_RESOLVER' end,
   'human_decision_required',false,
   'unsupported_invention',false,
   'candidate_or_stale_used_as_current_authority',false,
   'cross_scope_authority_leakage',false,
   'keyword_or_category_used_as_sufficiency_authority',false,
   'proposal_id',q.proposal_id,'family_code',q.family_code,'gap_code',q.gap_code
 ) item
 from q cross join fr cross join outcomes
)
select jsonb_build_object(
  'schema_version',1,
  'run_id',p_run_id,
  'run_is_current',programacion.fn_input_readiness_run_is_current(p_run_id),
  'evaluation_boundary','DERIVED_ACTIONABLE_REMEDIATION_NO_CLASSIFIER_CHANGE',
  'negative_confirmed_count',count(*),
  'owner_interruption_required',false,
  'automatic_canonicalization','DENY',
  'items',coalesce(jsonb_agg(item order by family_code),'[]'::jsonb)
)
from items;
$function$;

revoke all on function programacion.fn_input_actionable_remediation_summary_v1(bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_actionable_remediation_summary_v1(bigint) to service_role;

-- ENGINEERING_CHECKPOINT_EXECUTION_CONTRACT_V1
-- Transversal execution contract for engineering-plan checkpoints.
-- Goal: eliminate repeated deliberation between canonical bootstrap and material action.

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
  where pu.plan_code = p_plan_code
    and pu.unit_code = p_unit_code
), cp as (
  select c.checkpoint_code, c.title, c.sequence_no, c.status
  from programacion.engineering_work_checkpoints c
  join u on u.work_item_id = c.work_item_id
  where c.checkpoint_code = coalesce(
    p_checkpoint_code,
    (
      select c2.checkpoint_code
      from programacion.engineering_work_checkpoints c2
      where c2.work_item_id = u.work_item_id
        and c2.status not in ('DONE','NOT_APPLICABLE')
      order by c2.sequence_no
      limit 1
    )
  )
  limit 1
), inp as (
  select case
    when cp.checkpoint_code is null then null
    when u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code] is not null
      then u.unit_metadata#>array['source_pack_v2','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code] is not null
      then u.unit_metadata#>array['source_pack_v1','checkpoint_inputs',cp.checkpoint_code]
    when u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' is not null
      and u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}' <> 'null'::jsonb
      then u.unit_metadata#>'{canonical_bootstrap_v1,semantic_source_input}'
    else null
  end execution_input
  from u cross join cp
), miss as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'kind', m.value->>'kind',
      'text', m.value->>'text',
      'blocking', coalesce((m.value->>'blocking')::boolean,false),
      'resolver', coalesce(
        nullif(m.value->>'resolver',''),
        case
          when m.value->>'text' ilike '%M8.11%' then 'UPSTREAM:M8.11'
          when m.value->>'text' ilike '%M8.1%' then 'UPSTREAM:M8.1'
          when m.value->>'text' ilike '%M2.8%' then 'UPSTREAM:M2.8'
          when m.value->>'kind' = 'DELIVERABLE' then 'SELF:' || p_unit_code || '/' || cp.checkpoint_code
          else null
        end
      )
    )
  ), '[]'::jsonb) as resolved
  from cp
  cross join inp
  left join lateral jsonb_array_elements(coalesce(inp.execution_input->'missing_typed','[]'::jsonb)) m(value) on true
), classified as (
  select
    cp.*,
    u.exit_criterion,
    inp.execution_input,
    miss.resolved,
    case
      when cp.checkpoint_code ~* '(^TERMINAL$|HANDOFF|FINAL_HANDOFF|INDEPENDENT_READBACK|CLOSURE)' then 'TERMINAL_RECONCILE'
      when cp.checkpoint_code ~* '(READBACK|RECEIPT_READBACK|GATE_READBACK)' then 'READBACK_EXACT'
      when cp.checkpoint_code ~* '(ASIS|INVENTORY|BASELINE|SOURCE_MAP|AUTHORITY_MAP)' then 'OBSERVE_AND_PERSIST'
      when cp.checkpoint_code ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)' then 'VERIFY_EXPECTED'
      when cp.checkpoint_code ~* '(DECISION|ADR|ADJUDICAT|AUTHORITY|GATE|CUTOVER_READY|EXPIRY)' then 'DECISION_OR_GATE'
      else 'EXECUTE_DECLARED_DELIVERABLE'
    end as recipe_mode
  from u cross join cp cross join inp cross join miss
)
select jsonb_build_object(
  'schema_version','ENGINEERING_CHECKPOINT_RECIPE_V1',
  'checkpoint_code', checkpoint_code,
  'checkpoint_title', title,
  'checkpoint_sequence_no', sequence_no,
  'recipe_mode', recipe_mode,
  'execution_input_present', execution_input is not null,
  'missing_resolution', resolved,
  'decision_rule', case recipe_mode
    when 'OBSERVE_AND_PERSIST' then 'EXECUTE_CANONICAL_INPUT_ONCE; IF checkpoint_title observation is confirmed THEN persist DONE immediately; do not design later checkpoints.'
    when 'READBACK_EXACT' then 'READ exact declared authority once; IF exact state matches checkpoint_title THEN persist DONE; historical reconfirmation forbidden.'
    when 'VERIFY_EXPECTED' then 'RUN only the declared negative/parity/test for this checkpoint; compare to checkpoint_title/expected result; persist immediately on PASS.'
    when 'DECISION_OR_GATE' then 'USE only declared authority/evidence; persist the decision/gate and exact readback; do not broaden scope.'
    when 'TERMINAL_RECONCILE' then 'VERIFY prior required checkpoints are terminal and closure evidence exists; reconcile ledger only; no material redesign.'
    else 'MATERIALIZE only the deliverable named by current checkpoint, verify it exactly, then persist; no cross-checkpoint design.'
  end,
  'steps', jsonb_build_array(
    'EXECUTE_CURRENT_INPUT_ONCE',
    'EVALUATE_CURRENT_CHECKPOINT_ONLY',
    'PERSIST_VIA_FN_ENGINEERING_CHECKPOINT_TRANSITION_V1',
    'USE_RETURNED_BOOTSTRAP_AS_ONLY_NEXT_STATE'
  ),
  'close_when', case recipe_mode
    when 'OBSERVE_AND_PERSIST' then 'CANONICAL_LIVE_OBSERVATION_MATCHES_CHECKPOINT_TITLE'
    when 'READBACK_EXACT' then 'EXACT_READBACK_MATCHES_DECLARED_CHECKPOINT'
    when 'VERIFY_EXPECTED' then 'DECLARED_EXPECTED_RESULT_VERIFIED'
    when 'DECISION_OR_GATE' then 'DECISION_OR_GATE_PERSISTED_AND_READ_BACK'
    when 'TERMINAL_RECONCILE' then 'ALL_REQUIRED_PRIOR_CHECKPOINTS_TERMINAL_AND_CLOSURE_EVIDENCE_PRESENT'
    else 'DECLARED_DELIVERABLE_MATERIALIZED_AND_CURRENT_CHECKPOINT_VERIFICATION_PASS'
  end,
  'unit_exit_criterion', exit_criterion,
  'fallback_only_on', jsonb_build_array('MISSING_CANONICAL_OBJECT','CONTRADICTION','STALE_CURRENTNESS','DEMONSTRATED_DRIFT','MATERIAL_FINGERPRINT_CHANGE'),
  'forbidden', jsonb_build_array('CROSS_CHECKPOINT_DESIGN','REPEATED_SOLUTION_REDESIGN','HISTORICAL_RECONFIRMATION_AFTER_LIVE_PASS','NARRATIVE_PROGRESS_PERCENT','UNTRIGGERED_DISCOVERY')
)
from classified;
$function$;

create or replace function programacion.fn_engineering_unit_bootstrap_v2(
  p_plan_code text,
  p_unit_code text
) returns jsonb
language sql
stable
set search_path = programacion, public, pg_catalog
as $function$
with b as (
  select programacion.fn_engineering_unit_bootstrap_v1(p_plan_code,p_unit_code) payload
)
select payload || jsonb_build_object(
  'schema_version','ENGINEERING_UNIT_BOOTSTRAP_V2',
  'decision_recipe', case
    when payload->'current_checkpoint' is null then null
    else programacion.fn_engineering_checkpoint_recipe_v1(
      p_plan_code,
      p_unit_code,
      payload#>>'{current_checkpoint,checkpoint_code}'
    )
  end,
  'ledger_sync', jsonb_build_object(
    'transition_entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
    'progress_source','programacion.engineering_work_checkpoints',
    'progress_rule','LEDGER_DERIVED_ONLY',
    'checkpoint_transition','PERSIST_THEN_RETURN_REBOOTSTRAP'
  )
)
from b;
$function$;

create or replace function programacion.fn_engineering_checkpoint_transition_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_new_status text,
  p_evidence_ref text,
  p_actor text,
  p_detail text default null
) returns jsonb
language plpgsql
volatile
set search_path = programacion, public, pg_catalog
as $function$
declare
  v_work_item_id bigint;
  v_current_code text;
  v_existing_status text;
  v_remaining int;
  v_open_blockers int;
  v_unmet_deps int;
  v_result jsonb;
  v_progress text;
  v_next text;
begin
  if p_new_status not in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then
    raise exception 'Unsupported checkpoint transition status: %', p_new_status;
  end if;

  select pu.work_item_id
    into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    raise exception 'Canonical unit not found: %/%', p_plan_code,p_unit_code;
  end if;

  select c.status
    into v_existing_status
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code;

  if v_existing_status in ('DONE','NOT_APPLICABLE') then
    return programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code)
      || jsonb_build_object('transition',jsonb_build_object('status','NOOP_ALREADY_TERMINAL','checkpoint_code',p_checkpoint_code));
  end if;

  select c.checkpoint_code
    into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current_code is distinct from p_checkpoint_code then
    raise exception 'Checkpoint % is not current; current=%', p_checkpoint_code,v_current_code;
  end if;

  if p_new_status in ('DONE','NOT_APPLICABLE') and coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'Terminal checkpoint transition requires evidence_ref or detail';
  end if;

  update programacion.engineering_work_checkpoints
  set status=p_new_status,
      evidence_ref=coalesce(nullif(p_evidence_ref,''),evidence_ref),
      completed_at=case when p_new_status='DONE' then now() else completed_at end,
      updated_at=now(),
      updated_by_execution_id=coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
  where work_item_id=v_work_item_id and checkpoint_code=p_checkpoint_code;

  if p_new_status='IN_PROGRESS' then
    update programacion.engineering_work_items
    set status='IN_PROGRESS',
        started_at=coalesce(started_at,now()),
        updated_at=now()
    where id=v_work_item_id and status not in ('DONE','CANCELLED');
  else
    select count(*) into v_remaining
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id
      and c.required
      and c.status not in ('DONE','NOT_APPLICABLE');

    select count(*) into v_open_blockers
    from programacion.engineering_work_blockers b
    where b.work_item_id=v_work_item_id and b.status='OPEN';

    select count(*) into v_unmet_deps
    from programacion.engineering_work_dependencies d
    join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
    where d.work_item_id=v_work_item_id
      and d.relation_type='REQUIRES'
      and coalesce(dw.status,'BACKLOG')<>'DONE';

    if v_remaining=0 and v_open_blockers=0 and v_unmet_deps=0 then
      update programacion.engineering_work_items
      set status='DONE',
          completed_at=coalesce(completed_at,now()),
          started_at=coalesce(started_at,now()),
          updated_at=now()
      where id=v_work_item_id and status<>'CANCELLED';
    else
      update programacion.engineering_work_items
      set status='IN_PROGRESS',
          started_at=coalesce(started_at,now()),
          completed_at=null,
          updated_at=now()
      where id=v_work_item_id and status not in ('DONE','CANCELLED');
    end if;
  end if;

  v_result := programacion.fn_engineering_unit_bootstrap_v2(p_plan_code,p_unit_code);
  v_progress := coalesce(v_result#>>'{state,progress_pct}','0');
  v_next := coalesce(v_result#>>'{terminal_action}','UNKNOWN');

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,
    'PROGRESS',
    'Checkpoint '||p_checkpoint_code||' -> '||p_new_status||'; ledger_progress='||v_progress||'%',
    p_detail,
    v_next || coalesce(' / '||(v_result#>>'{current_checkpoint,checkpoint_code}'),''),
    case when nullif(p_evidence_ref,'') is null then '[]'::jsonb else jsonb_build_array(p_evidence_ref) end,
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'),
    now(),
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
  );

  return v_result || jsonb_build_object(
    'transition',jsonb_build_object(
      'status','APPLIED',
      'checkpoint_code',p_checkpoint_code,
      'new_status',p_new_status,
      'ledger_progress_pct',v_progress,
      'next_terminal_action',v_next
    )
  );
end;
$function$;

-- Evolve the plan-wide canonical entrypoint without deleting V1 history.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  jsonb_set(
    coalesce(unit_metadata,'{}'::jsonb),
    '{canonical_bootstrap_v2}',
    jsonb_build_object(
      'contract','ENGINEERING_UNIT_BOOTSTRAP_V2',
      'entrypoint','programacion.fn_engineering_unit_bootstrap_v2',
      'identity',jsonb_build_array('plan_code','unit_code'),
      'decision_recipe','programacion.fn_engineering_checkpoint_recipe_v1',
      'transition_entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'progress_rule','LEDGER_DERIVED_ONLY',
      'checkpoint_loop','BOOTSTRAP_EXECUTE_EVALUATE_PERSIST_REBOOTSTRAP',
      'effective_at',now()
    ),
    true
  ),
  '{canonical_bootstrap_v1,status}',
  '"COMPATIBILITY_ONLY"'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

-- Keep preferred-input contracts pointed at the current canonical bootstrap.
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{source_pack_v1,lookup_strategy_v2,preferred_input}',
  jsonb_build_object(
    'mode','CANONICAL_ENGINEERING_UNIT_BOOTSTRAP',
    'entrypoint','programacion.fn_engineering_unit_bootstrap_v2',
    'args',jsonb_build_object('plan_code',plan_code,'unit_code',unit_code),
    'rule','CALL_DIRECTLY_BEFORE_SOURCE_PACK_OR_WORK_CODE_LOOKUP'
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_metadata ? 'source_pack_v1';

update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{source_pack_v2,preferred_input}',
  jsonb_build_object(
    'mode','CANONICAL_ENGINEERING_UNIT_BOOTSTRAP',
    'entrypoint','programacion.fn_engineering_unit_bootstrap_v2',
    'args',jsonb_build_object('plan_code',plan_code,'unit_code',unit_code),
    'rule','CALL_DIRECTLY_BEFORE_SOURCE_PACK_OR_WORK_CODE_LOOKUP'
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_metadata ? 'source_pack_v2';

-- Prevent the old rule from remaining the visible authority.
update public.lf_error_knowledge
set estado='SUPERSEDED',
    prevencion='SUPERSEDED by ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001. Use fn_engineering_unit_bootstrap_v2 + checkpoint recipe + atomic transition.',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-CHECKPOINT-MICROLOOP-001';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,lifecycle_phase,consumer_role,
  root_cause_family,detectability,source_context,source_ref
)
select
  'ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001',
  'ENGINEERING_GOVERNANCE',
  'Checkpoint execution must be recipe-driven and ledger-synchronized',
  'Canonical source lookup alone does not remove execution latency when the agent must reinterpret evidence and narrate progress before persisting the checkpoint.',
  'Checkpoint inputs described what to inspect but did not provide a deterministic result-to-action transition or atomic persist+rebootstrap operation.',
  'Repeated deliberation after sufficient live evidence; narrative progress diverges from engineering_work_checkpoints.',
  'Use ENGINEERING_UNIT_BOOTSTRAP_V2. It returns a decision_recipe for the current checkpoint. Persist via fn_engineering_checkpoint_transition_v1, which writes the checkpoint, derives progress from ledger and returns the next bootstrap. Never reason across checkpoints before current persistence.',
  'PASS when every IG unit points to bootstrap V2; current pending checkpoints receive a non-null decision_recipe; transition updates ledger and returns the next state; narrative progress is not an authority.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_unit_bootstrap_v2|programacion.fn_engineering_checkpoint_recipe_v1|programacion.fn_engineering_checkpoint_transition_v1',
  now(),now(),'EXECUTION','{IG,ENGINEERING_AGENT}'::text[],
  'CONTRACT_DRIFT','HIGH','IG checkpoint execution latency','supabase://programacion.fn_engineering_unit_bootstrap_v2'
where not exists (select 1 from public.lf_error_knowledge where codigo='ENGINEERING-CHECKPOINT-EXECUTION-CONTRACT-001');

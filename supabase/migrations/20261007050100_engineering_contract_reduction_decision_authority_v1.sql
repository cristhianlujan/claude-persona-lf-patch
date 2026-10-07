-- ENGINEERING contract reduction: decision authority normalization v1
-- Reclassifies temporary DECISION_AUTHORITY_REQUIRED family blockers to their
-- actual authority: current ADR/capability readback, owner decision, upstream
-- receipt/cutover, adjudication execution, or verification/materialization.

create or replace function programacion.fn_engineering_current_adr_assert_v1(
  p_adr text
)
returns jsonb
language plpgsql
stable
set search_path to 'transversal','programacion','public','pg_catalog'
as $function$
declare
  v_estado text;
  v_created_at timestamptz;
begin
  select d.estado,d.created_at
    into v_estado,v_created_at
  from transversal.decision_log d
  where d.adr=p_adr
  order by d.created_at desc
  limit 1;

  if lower(coalesce(v_estado,''))<>'vigente' then
    raise exception 'ENGINEERING_ADR_NOT_CURRENT:% estado=%',p_adr,coalesce(v_estado,'<missing>');
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CURRENT_ADR_ASSERT_V1',
    'status','PASS',
    'adr',p_adr,
    'estado',v_estado,
    'created_at',v_created_at
  );
end;
$function$;

create or replace function programacion.fn_engineering_current_capability_set_assert_v1(
  p_capability_codes text[]
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_requested int := coalesce(array_length(p_capability_codes,1),0);
  v_current int := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  if v_requested=0 then
    raise exception 'ENGINEERING_CAPABILITY_SET_EMPTY';
  end if;

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'capability_code',r.capability_code,
           'registry_status',r.status,
           'version',c.version,
           'release_state',v.release_state,
           'manifest_sha256',v.manifest_sha256
         ) order by r.capability_code),'[]'::jsonb)
    into v_current,v_rows
  from unnest(p_capability_codes) q(capability_code)
  join public.lf_capability_registry r
    on r.capability_code=q.capability_code
   and r.status='ACTIVE'
  join public.lf_capability_current c
    on c.capability_code=r.capability_code
  join public.lf_capability_version_registry v
    on v.capability_code=c.capability_code
   and v.version=c.version
   and v.release_state='RELEASED';

  if v_current<>v_requested then
    raise exception 'ENGINEERING_CAPABILITY_SET_NOT_CURRENT requested=% current=% codes=%',
      v_requested,v_current,p_capability_codes;
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_CURRENT_CAPABILITY_SET_ASSERT_V1',
    'status','PASS',
    'requested',v_requested,
    'current',v_current,
    'capabilities',v_rows
  );
end;
$function$;

comment on function programacion.fn_engineering_current_adr_assert_v1(text)
is 'Fail-closed read-only assertion that an exact ADR exists in transversal.decision_log with estado VIGENTE.';
comment on function programacion.fn_engineering_current_capability_set_assert_v1(text[])
is 'Fail-closed read-only assertion that every exact capability is ACTIVE and has CURRENT RELEASED version authority.';

do $normalize$
declare
  v_spec jsonb;
  v_queries jsonb;
  v_new jsonb;
  v_q text;
begin
  -- M9.2 release-binding ADR is already VIGENTE.
  select unit_metadata#>'{action_specs_v1,ADR_M17_PRESENT}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.2';

  v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb);
  v_q:='select programacion.fn_engineering_current_adr_assert_v1(''DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001'') as result';
  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_CURRENT_ADR_BOUND_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','CURRENT_ADR_ASSERT_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','CURRENT_ADR_BOUND',
      'verification_queries',v_queries||jsonb_build_array(v_q),
      'decision_authority_contract',jsonb_build_object(
        'authority_ref','transversal.decision_log:DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001',
        'required_state','VIGENTE',
        'assert_entrypoint','programacion.fn_engineering_current_adr_assert_v1'
      ),
      'expected','Exact release-binding ADR must be current; stale historical missing claims do not block.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    jsonb_set(
      jsonb_set(
        unit_metadata,
        '{source_pack_v1,checkpoint_inputs,ADR_M17_PRESENT,missing}',
        '[]'::jsonb,true
      ),
      '{source_pack_v1,checkpoint_inputs,ADR_M17_PRESENT,missing_typed}',
      '[]'::jsonb,true
    ),
    '{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('ADR_M17_PRESENT',v_new),
    true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.2';

  -- M9.6 adjudication ADR + WAIVER_AUTHORITY are current.
  select unit_metadata#>'{action_specs_v1,AUTHORITY_M17}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.6';

  v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb);
  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_ADJUDICATION_AUTHORITY_BOUND_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','CURRENT_ADR_AND_CAPABILITY_ASSERT_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','CURRENT_ADJUDICATION_AUTHORITY_BOUND',
      'verification_queries',v_queries||jsonb_build_array(
        'select programacion.fn_engineering_current_adr_assert_v1(''DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'') as result',
        'select programacion.fn_engineering_current_capability_set_assert_v1(array[''WAIVER_AUTHORITY'']::text[]) as result'
      ),
      'decision_authority_contract',jsonb_build_object(
        'authority_adr','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
        'waiver_capability','WAIVER_AUTHORITY',
        'local_override','FORBIDDEN'
      )
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    jsonb_set(
      jsonb_set(
        unit_metadata,
        '{source_pack_v1,checkpoint_inputs,AUTHORITY_M17,missing}',
        '[]'::jsonb,true
      ),
      '{source_pack_v1,checkpoint_inputs,AUTHORITY_M17,missing_typed}',
      '[]'::jsonb,true
    ),
    '{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('AUTHORITY_M17',v_new),
    true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.6';

  -- M10.0 consumes existing Super Admin authorities; no local promotion authority.
  select unit_metadata#>'{action_specs_v1,REUSE_SADM_AUTHORITY}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  v_queries:=coalesce(v_spec->'verification_queries','[]'::jsonb);
  v_new:=(
    v_spec||jsonb_build_object(
      'status','READY',
      'precision','EXPLICIT_SADM_AUTHORITY_REUSE_BOUND_V1',
      'action_kind','READBACK_ONCE',
      'recipe_mode','CURRENT_CAPABILITY_SET_ASSERT_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','CURRENT_CAPABILITY_AUTHORITY_BOUND',
      'verification_queries',v_queries||jsonb_build_array(
        'select programacion.fn_engineering_current_capability_set_assert_v1(array[''AUTHORITY_READBACK'',''PLAN_AUTHORITY_DRIFT_GUARD'',''WAIVER_AUTHORITY'']::text[]) as result'
      ),
      'decision_authority_contract',jsonb_build_object(
        'authority_owner','SUPER_ADMIN',
        'capabilities',jsonb_build_array('AUTHORITY_READBACK','PLAN_AUTHORITY_DRIFT_GUARD','WAIVER_AUTHORITY'),
        'ig_local_authority','FORBIDDEN'
      )
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('REUSE_SADM_AUTHORITY',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  -- True owner decision: exact CUTOVER_AUTHORIZED record, but do not create it here.
  select unit_metadata#>'{action_specs_v1,HUMAN_DECISION_RECORD}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  v_new:=(
    v_spec||jsonb_build_object(
      'status','BLOCK_OWNER_DECISION_REQUIRED',
      'precision','EXPLICIT_OWNER_DECISION_CONTRACT_V1',
      'action_kind','DECISION_GATE',
      'recipe_mode','OWNER_DECISION_RECORD_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','OWNER_DECISION_PENDING',
      'decision_authority_contract',jsonb_build_object(
        'owner','SUPER_ADMIN',
        'record_table','programacion.human_decisions',
        'decision','CUTOVER_AUTHORIZED',
        'required_fields',jsonb_build_array('head_sha','decision','actor_identity','approval_ref'),
        'head_sha_binding','M9.0_FROZEN_BUNDLE_SHA',
        'precondition_receipt','CUTOVER_READY',
        'automatic_decision','FORBIDDEN'
      ),
      'expected','Owner decision record is the remaining gate; contract authoring is complete and no automatic CUTOVER_AUTHORIZED decision is permitted.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('HUMAN_DECISION_RECORD',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  -- Upstream receipt dependency: contract is complete; receipt does not exist yet.
  select unit_metadata#>'{action_specs_v1,CUTOVER_READY_PRECONDITION}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  v_new:=(
    v_spec||jsonb_build_object(
      'status','BLOCK_UPSTREAM_RECEIPT_PENDING',
      'precision','EXPLICIT_UPSTREAM_RECEIPT_CONTRACT_V1',
      'action_kind','DECISION_GATE',
      'recipe_mode','UPSTREAM_RECEIPT_GATE_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','UPSTREAM_RECEIPT_PENDING',
      'upstream_receipt_contract',jsonb_build_object(
        'producer_unit','M9.12',
        'receipt_kind','CUTOVER_READY',
        'receipt_table','programacion.provenance_receipts',
        'head_sha_binding','M9.0_FROZEN_BUNDLE_SHA',
        'must_be_current',true
      ),
      'expected','Wait for the exact M9.12 CUTOVER_READY receipt bound to the M9.0 frozen bundle; no local substitute is allowed.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('CUTOVER_READY_PRECONDITION',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M10.0';

  -- Owner decision N-6: exact ADR identity is known and currently absent.
  select unit_metadata#>'{action_specs_v1,ADR_APPROVED}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='N-6';

  v_new:=(
    v_spec||jsonb_build_object(
      'status','BLOCK_OWNER_DECISION_REQUIRED',
      'precision','EXPLICIT_OWNER_ADR_CONTRACT_V1',
      'action_kind','DECISION_GATE',
      'recipe_mode','OWNER_ADR_GATE_V1',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'contract_family','OWNER_DECISION_PENDING',
      'decision_authority_contract',jsonb_build_object(
        'owner','SUPER_ADMIN',
        'record_table','transversal.decision_log',
        'adr','DEC-INPUT-GOV-SAFE-AUTOFIX-002',
        'required_state','VIGENTE',
        'automatic_approval','FORBIDDEN'
      ),
      'verification_queries',coalesce(v_spec->'verification_queries','[]'::jsonb)||jsonb_build_array(
        'select programacion.fn_engineering_current_adr_assert_v1(''DEC-INPUT-GOV-SAFE-AUTOFIX-002'') as result'
      ),
      'expected','Exact owner ADR DEC-INPUT-GOV-SAFE-AUTOFIX-002 is the remaining gate; the technical contract is complete.'
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('ADR_APPROVED',v_new),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='N-6';

  -- Adjudication checkpoints: bind exact existing authority, leave only the
  -- actual divergence-specific execution as the gate.
  for v_new in
    select jsonb_build_object('unit_code',u,'checkpoint_code',c)
    from (values
      ('M4.10','ADJUDICATE_DIVERGENCES'),
      ('M9.6','ADJUDICATE_EACH')
    ) x(u,c)
  loop
    select unit_metadata#>array['action_specs_v1',v_new->>'checkpoint_code']
      into v_spec
    from programacion.engineering_plan_units
    where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and unit_code=v_new->>'unit_code';

    v_spec:=(
      v_spec||jsonb_build_object(
        'status','BLOCK_ADJUDICATION_EXECUTION_REQUIRED',
        'precision','EXPLICIT_ADJUDICATION_AUTHORITY_CONTRACT_V1',
        'action_kind','DECISION_GATE',
        'recipe_mode','PLAN_AUTHORITY_ADJUDICATION_V1',
        'requires_material_execution',false,
        'mutation_policy','NO_IMPLICIT_MUTATION',
        'contract_family','ADJUDICATION_EXECUTION_PENDING',
        'adjudication_contract',jsonb_build_object(
          'authority_adr','DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
          'plan_authority_capability','PLAN_AUTHORITY_DRIFT_GUARD',
          'waiver_capability','WAIVER_AUTHORITY',
          'evidence_ledger','EVIDENCE_LEDGER',
          'local_override','FORBIDDEN',
          'per_divergence_receipt_required',true
        ),
        'expected','Authority is bound. Remaining work is exact per-divergence adjudication with current PLAN_AUTHORITY/WAIVER receipts.'
      )
    )-'required_contract';

    update programacion.engineering_plan_units pu
    set unit_metadata=jsonb_set(
      pu.unit_metadata,'{action_specs_v1}',
      coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
        ||jsonb_build_object(v_new->>'checkpoint_code',v_spec),true
    )
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code=v_new->>'unit_code';
  end loop;

  -- M4.11 is not an owner decision: it waits for the release-binding mechanism.
  select unit_metadata#>'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE}'
    into v_spec
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M4.11';

  v_spec:=(
    v_spec||jsonb_build_object(
      'status','BLOCK_UPSTREAM_CAPABILITY_CUTOVER_PENDING',
      'precision','EXPLICIT_RELEASE_BINDING_DEPENDENCY_V1',
      'action_kind','DECISION_GATE',
      'recipe_mode','UPSTREAM_RELEASE_BINDING_GATE_V1',
      'requires_material_execution',false,
      'contract_family','UPSTREAM_RELEASE_BINDING_PENDING',
      'release_binding_contract',jsonb_build_object(
        'authority_adr','DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001',
        'version_registry','public.lf_capability_version_registry',
        'current_pointer','public.lf_capability_current',
        'cutover_owner','CAPABILITY_CUTOVER',
        'producer_unit','M9.2',
        'validator_function_rewrite','FORBIDDEN'
      )
    )
  )-'required_contract';

  update programacion.engineering_plan_units
  set unit_metadata=jsonb_set(
    unit_metadata,'{action_specs_v1}',
    coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)||jsonb_build_object('DECISIONAL_BINDING_VIA_RELEASE',v_spec),true
  )
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M4.11';

  -- These were semantically misclassified as decisions; retain fail-closed but
  -- move them to their actual contract families.
  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'STRUCTURAL_GATE_CONTROLS',
        (pu.unit_metadata#>'{action_specs_v1,STRUCTURAL_GATE_CONTROLS}')
          || jsonb_build_object(
            'status','BLOCK_VERIFICATION_ASSERTION_REQUIRED',
            'precision','RECLASSIFIED_VERIFICATION_CONTRACT_V1',
            'action_kind','VERIFY_QUERY_ONCE',
            'contract_family','VERIFY_ASSERTION_REQUIRED'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M4.3';

  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'JUDGE_NON_DECISIONAL',
        (pu.unit_metadata#>'{action_specs_v1,JUDGE_NON_DECISIONAL}')
          || jsonb_build_object(
            'status','BLOCK_VERIFICATION_ASSERTION_REQUIRED',
            'precision','RECLASSIFIED_VERIFICATION_CONTRACT_V1',
            'action_kind','VERIFY_QUERY_ONCE',
            'contract_family','VERIFY_ASSERTION_REQUIRED'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M7.12';

  update programacion.engineering_plan_units pu
  set unit_metadata=jsonb_set(
    pu.unit_metadata,'{action_specs_v1}',
    coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      || jsonb_build_object(
        'DECISION_TABLE',
        (pu.unit_metadata#>'{action_specs_v1,DECISION_TABLE}')
          || jsonb_build_object(
            'status','BLOCK_MATERIALIZATION_CONTRACT_REQUIRED',
            'precision','RECLASSIFIED_MATERIALIZATION_CONTRACT_V1',
            'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
            'contract_family','MATERIALIZATION_CONTRACT_REQUIRED'
          )
      ),true
  )
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M5.2';
end;
$normalize$;

do $selftest$
declare
  v_generic_decision_blocks int;
  v_ready_bound int;
begin
  with open_cp as (
    select pu.unit_code,c.checkpoint_code,
      programacion.fn_engineering_checkpoint_action_spec_v3(
        'IG_CURATOR_VALIDATOR_REFACTOR_V2',pu.unit_code,c.checkpoint_code
      ) s
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.disposition='ASSIGNED'
      and c.required
      and c.status not in ('DONE','NOT_APPLICABLE')
  )
  select count(*) filter(where s->>'status'='BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED'),
         count(*) filter(where (unit_code,checkpoint_code) in (
           ('M9.2','ADR_M17_PRESENT'),
           ('M9.6','AUTHORITY_M17'),
           ('M10.0','REUSE_SADM_AUTHORITY')
         ) and s->>'status'='READY')
    into v_generic_decision_blocks,v_ready_bound
  from open_cp;

  if v_generic_decision_blocks<>0 then
    raise exception 'ENGINEERING_DECISION_NORMALIZATION_GENERIC_BLOCKS_REMAIN:%',v_generic_decision_blocks;
  end if;

  if v_ready_bound<>3 then
    raise exception 'ENGINEERING_DECISION_NORMALIZATION_READY_BOUND_MISMATCH:%',v_ready_bound;
  end if;

  perform programacion.fn_engineering_current_adr_assert_v1(
    'DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001'
  );
  perform programacion.fn_engineering_current_adr_assert_v1(
    'DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'
  );
  perform programacion.fn_engineering_current_capability_set_assert_v1(
    array['AUTHORITY_READBACK','PLAN_AUTHORITY_DRIFT_GUARD','WAIVER_AUTHORITY']::text[]
  );
end;
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-CONTRACT-REDUCTION-DECISION-AUTHORITY-001',
  'ENGINEERING_ORCHESTRATION',
  'Decision-family sanitation must bind existing authority and expose the real remaining gate',
  'Sixteen checkpoints were temporarily grouped as DECISION_AUTHORITY_REQUIRED although several already had current ADR/capability authority, several were ordinary verification/materialization gates, and others were true owner/upstream/adjudication gates.',
  'Family sanitation preserved fail-closed behavior but flattened materially different decision semantics into one generic contract blocker.',
  'GENERIC_DECISION_BLOCK_HIDES_CURRENT_AUTHORITY_AND_REAL_GATE',
  'Bind exact current ADR/capability authority by identifier, clear stale missing claims, represent true owner decisions and upstream receipts explicitly, and reclassify verification/materialization checkpoints to their actual family. Never auto-create owner decisions.',
  'PASS when open plan has 0 BLOCK_DECISION_AUTHORITY_CONTRACT_REQUIRED; M9.2 ADR_M17_PRESENT, M9.6 AUTHORITY_M17 and M10.0 REUSE_SADM_AUTHORITY compile READY; owner/upstream/adjudication gates remain fail-closed with specific reasons.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_current_adr_assert_v1; supabase://programacion.fn_engineering_current_capability_set_assert_v1; supabase://programacion.engineering_plan_units',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','ENGINEERING_EXECUTOR','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Plan-wide normalization of decision authority contract family',
  'supabase://programacion.fn_engineering_current_adr_assert_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

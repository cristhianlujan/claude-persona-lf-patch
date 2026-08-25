-- Story Agent Product + Quality R1
-- Product semantics + append-only functional contract + effective sizing revision.

insert into public.lf_decision_log(adr,titulo,decision,razon,impacto,estado,created_at)
select
  'DEC-HMO-STATE-DIMENSIONS-001',
  'Separar disponibilidad de oferta y configuración del usuario',
  'La disponibilidad de una oferta y la configuración elegida por el usuario son dimensiones independientes. La disponibilidad autorizada por backend se representa como offer_availability_status (por ejemplo ACTIVA). La configuración de la oferta en Home se representa como offer_configuration_state y sólo admite SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA. ACTIVA no es una modalidad ni un configuration_state.',
  'Las reglas R-HMO-003 y R-HMO-004/R-HMO-005 usan dominios incompatibles si se interpretan como un único campo. El runtime filtra disponibilidad con offer_data.status activa/active, mientras la selección del usuario tiene otro dominio.',
  'Story Agent, Agent Task y frontend deben mantener ambas dimensiones separadas.',
  'VIGENTE',now()
where not exists(select 1 from public.lf_decision_log where adr='DEC-HMO-STATE-DIMENSIONS-001');

update public.lf_product_rules
set rule_statement='Cada oferta mantiene un offer_configuration_state independiente, limitado a SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA.',
    expected_behavior=jsonb_build_object('field','offer_configuration_state','states',jsonb_build_array('SIN_CONFIGURAR','PAGO_UNICO','CUOTAS','VENCIDA','MODIFICADA','INACTIVA')),
    validation_rules=jsonb_build_array('solo un offer_configuration_state vigente por offer_id','offer_availability_status no debe colapsarse con offer_configuration_state'),
    traceability=coalesce(traceability,'{}'::jsonb)||jsonb_build_object('decision_ref','DEC-HMO-STATE-DIMENSIONS-001'),
    updated_at=now(),updated_by_execution_id='STORY_PRODUCT_QUALITY_20260824'
where rule_code='R-HMO-003';

update public.lf_product_rules
set preconditions=jsonb_build_array('offer_availability_status = ACTIVA'),
    traceability=coalesce(traceability,'{}'::jsonb)||jsonb_build_object('decision_ref','DEC-HMO-STATE-DIMENSIONS-001'),
    updated_at=now(),updated_by_execution_id='STORY_PRODUCT_QUALITY_20260824'
where rule_code in ('R-HMO-004','R-HMO-005');

update public.lf_user_stories
set acceptance_criteria=jsonb_build_array(
  jsonb_build_object('code','AC-HMO-001-001','given','Home cargado','when','no existe selección','then','CTA deshabilitado y contador 0 de N','source','HU-HMO-001.acceptance_criteria[0]','source_rule_codes',jsonb_build_array('R-HMO-001')),
  jsonb_build_object('code','AC-HMO-001-002','given','una oferta válida configurada','when','se actualiza la selección','then','CTA habilitado con texto Continuar con 1 oferta','source','HU-HMO-001.acceptance_criteria[1]','source_rule_codes',jsonb_build_array('R-HMO-002')),
  jsonb_build_object('code','AC-HMO-001-003','given','dos o más ofertas válidas','when','se actualiza la selección','then','CTA muestra la cantidad exacta de selecciones válidas y no exige configurar las demás ofertas','source','HU-HMO-001.acceptance_criteria[2]','source_rule_codes',jsonb_build_array('R-HMO-002')),
  jsonb_build_object('code','AC-HMO-001-004','given','una oferta con configuración vigente','when','se intenta una transición a un estado fuera de SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA','then','la transición se rechaza y la selección válida previa permanece sin cambios','source','R-HMO-003','source_rule_codes',jsonb_build_array('R-HMO-003')),
  jsonb_build_object('code','AC-HMO-001-005','given','una oferta ACTIVA con un plan en cuotas previamente seleccionado','when','el usuario selecciona pago único','then','la modalidad queda en PAGO_UNICO y selected_plan_id queda vacío para esa oferta','source','R-HMO-004','source_rule_codes',jsonb_build_array('R-HMO-004')),
  jsonb_build_object('code','AC-HMO-001-006','given','una oferta ACTIVA con planes en cuotas disponibles','when','el usuario abre el selector y elige un plan vigente perteneciente a esa oferta','then','solo ese plan queda seleccionado y Aplicar plan se habilita; cancelar sin aplicar conserva la selección previa','source','R-HMO-005','source_rule_codes',jsonb_build_array('R-HMO-005'))
),updated_at=now()
where story_code='HU-HMO-001' and status='CANDIDATO';

do $$
declare
  v_old public.lf_functional_versions%rowtype;
  v_story public.lf_user_stories%rowtype;
  v_new_id bigint;
begin
  if exists(select 1 from public.lf_functional_versions where artifact_code='HU-HMO-001' and version_no=2) then return; end if;
  select * into v_old from public.lf_functional_versions where artifact_code='HU-HMO-001' and version_no=1 and status='SEALED' order by id desc limit 1;
  if not found then raise exception 'HU-HMO-001 v1 SEALED source not found'; end if;
  select * into v_story from public.lf_user_stories where story_code='HU-HMO-001' and status='CANDIDATO';
  if not found then raise exception 'HU-HMO-001 candidate Story not found'; end if;
  insert into public.lf_functional_versions(
    artifact_code,artifact_type,story_code,parent_spec_version_id,version_no,objective,
    acceptance_criteria,invariants,negative_controls,source_rule_codes,
    supersedes_version_id,amendment_reason_code,amendment_ref,status,
    content_sha256,sealed_at,created_by_execution_id
  ) values (
    v_old.artifact_code,v_old.artifact_type,v_old.story_code,v_old.parent_spec_version_id,2,v_old.objective,
    v_story.acceptance_criteria,v_old.invariants,v_old.negative_controls,v_old.source_rule_codes,
    v_old.id,'STORY_AC_RULE_COVERAGE','STORY-001/DEC-HMO-STATE-DIMENSIONS-001','DRAFT',
    null,null,'STORY_PRODUCT_QUALITY_20260824'
  ) returning id into v_new_id;
  update public.lf_functional_versions set status='SEALED' where id=v_new_id and status='DRAFT';
end $$;

-- Effective gate rows are immutable. Create an agent-version successor and place the
-- recalibrated G_TASK_SIZING_MIN revision there; all other gates remain inherited.
insert into programacion.versiones_agente(
  agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas
)
select
  v.agente_id,
  'v0.9.1-story-product-quality-budget-r1',
  v.objetivo,
  'draft',
  v.id,
  'PRODUCT_QUALITY_R1: sizing calibrated from candidate 3b9c7676; hidden authority/hardening remains separate; no production promotion.'
from programacion.versiones_agente v
where v.agente_id=1
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.9.1-story-product-quality-budget-r1')
order by v.id desc
limit 1;

do $$
declare
  v_new_version_id bigint;
  v_parent_version_id bigint;
  v_old programacion.gates%rowtype;
  v_new_config jsonb;
begin
  select id,supersedes_version_id into v_new_version_id,v_parent_version_id
  from programacion.versiones_agente
  where version_codigo='v0.9.1-story-product-quality-budget-r1';
  if v_new_version_id is null then raise exception 'PRODUCT_QUALITY_AGENT_VERSION_MISSING'; end if;
  if exists(select 1 from programacion.gates where version_id=v_new_version_id and gate_codigo='G_TASK_SIZING_MIN') then return; end if;

  with recursive version_chain as (
    select v.id,v.supersedes_version_id,0 as depth from programacion.versiones_agente v where v.id=v_parent_version_id
    union all
    select p.id,p.supersedes_version_id,vc.depth+1
    from programacion.versiones_agente p join version_chain vc on p.id=vc.supersedes_version_id
  )
  select g.* into v_old
  from version_chain vc join programacion.gates g on g.version_id=vc.id
  where g.gate_codigo='G_TASK_SIZING_MIN' and g.estado in ('defined','active')
  order by vc.depth asc,g.id desc limit 1;
  if v_old.id is null then raise exception 'G_TASK_SIZING_MIN_PARENT_MISSING'; end if;

  select jsonb_set(
    v_old.configuracion,'{profiles}',
    coalesce((
      select jsonb_agg(
        case when p.value->>'profile_code'='HMO_LIBERTAD_FINANCIERA_PILOT_V1' then
          p.value||jsonb_build_object(
            'calibration_status','PRODUCT_CANDIDATE_CALIBRATED_R1',
            'confidence','MEDIUM_PRODUCT_EVIDENCE',
            'max_files_expected',5,
            'max_changed_files',5,
            'max_patch_bytes',65536,
            'max_context_bytes',65536,
            'provenance',coalesce(p.value->'provenance','{}'::jsonb)||jsonb_build_object(
              'candidate_base_head_sha','27c1e7feaf63952d7fe6122c5b4e93cf0c1c3cc3',
              'candidate_head_sha','3b9c76769775fdd96bbdff27cc2e9ca80f9082c6',
              'candidate_changed_files',5,
              'candidate_changed_file_total_bytes',33181,
              'measured_worker_spec_bytes',16279,
              'measured_selected_context_bytes',39172,
              'measured_active_context_bytes',55451,
              'context_budget_cap_bytes',65536,
              'context_budget_headroom_bytes',10085,
              'context_budget_policy','WorkerTaskSpec canonical JSON + files resolved by context_path_patterns; unreferenced artifacts excluded',
              'reference_artifact_budgeting','RETIRED_UNLESS_DECLARED_IN_CONTEXT_PATH_PATTERNS',
              'recalibration_trigger','CONTEXT_PATH_CHANGE_OR_SUCCESSOR_TASK_OR_PROFILE_DRIFT'
            )
          )
        else p.value end order by p.ord
      )
      from jsonb_array_elements(coalesce(v_old.configuracion->'profiles','[]'::jsonb)) with ordinality p(value,ord)
    ),'[]'::jsonb),false
  ) into v_new_config;

  insert into programacion.gates(
    version_id,gate_codigo,fase,tipo,nombre,descripcion,ejecutor_componente_id,
    modo_verificacion,reintentos_max,bloqueante,evidencia_requerida,configuracion,estado
  ) values (
    v_new_version_id,v_old.gate_codigo,v_old.fase,v_old.tipo,v_old.nombre,
    'Fail-closed sizing policy calibrated from the observed product candidate. Context budget includes WorkerTaskSpec plus only declared context paths.',
    v_old.ejecutor_componente_id,v_old.modo_verificacion,v_old.reintentos_max,
    v_old.bloqueante,v_old.evidencia_requerida,v_new_config,'defined'
  );
end $$;

create or replace function programacion.fn_task_sizing_profile(p_task_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  v_functional_id bigint;
  v_module_code text;
  v_repo_full_name text;
  v_gate jsonb;
  v_profile jsonb;
begin
  select t.functional_version_id,s.module_code into v_functional_id,v_module_code
  from programacion.agent_tasks t
  join public.lf_functional_versions f on f.id=t.functional_version_id
  join public.lf_user_stories s on s.story_code=f.story_code
  where t.id=p_task_id;
  if v_functional_id is null then return null; end if;

  v_repo_full_name:=programacion.fn_functional_preparation_readiness(v_functional_id)->'repository_resolution'->>'repo_full_name';
  if v_repo_full_name is null then return null; end if;

  with recursive version_chain as (
    (select v.id,v.supersedes_version_id,0 as depth
     from programacion.versiones_agente v
     where v.agente_id=1
     order by v.id desc limit 1)
    union all
    select p.id,p.supersedes_version_id,vc.depth+1
    from programacion.versiones_agente p join version_chain vc on p.id=vc.supersedes_version_id
  )
  select g.configuracion into v_gate
  from version_chain vc join programacion.gates g on g.version_id=vc.id
  where g.gate_codigo='G_TASK_SIZING_MIN' and g.estado in ('defined','active')
  order by vc.depth asc,g.id desc limit 1;

  if v_gate is null or v_gate->>'threshold_status'<>'CALIBRATED_BY_PROFILE' then return null; end if;
  select p.value into v_profile
  from jsonb_array_elements(coalesce(v_gate->'profiles','[]'::jsonb)) with ordinality p(value,ord)
  where p.value->>'module_code'=v_module_code
    and p.value->>'repo_full_name'=v_repo_full_name
    and p.value->>'threshold_status'='CALIBRATED'
  order by p.ord desc limit 1;
  return v_profile;
end;
$$;

revoke all on function programacion.fn_task_sizing_profile(bigint) from public;
grant execute on function programacion.fn_task_sizing_profile(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_human_authority;

-- Story Agent Product + Quality R1
-- Scope: canonicalize HMO state dimensions, complete HU-HMO-001 rule->AC coverage,
-- preserve append-only Functional Version history, and recalibrate the HMO Agent Task
-- sizing profile from the observed product candidate rather than an unrelated prototype.

insert into public.lf_decision_log(adr,titulo,decision,razon,impacto,estado,created_at)
select
  'DEC-HMO-STATE-DIMENSIONS-001',
  'Separar disponibilidad de oferta y configuración del usuario',
  'La disponibilidad de una oferta y la configuración elegida por el usuario son dimensiones independientes. La disponibilidad autorizada por backend se representa como offer_availability_status (por ejemplo ACTIVA). La configuración de la oferta en Home se representa como offer_configuration_state y sólo admite SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA. ACTIVA no es una modalidad ni un configuration_state.',
  'Las reglas R-HMO-003 y R-HMO-004/R-HMO-005 usan dominios incompatibles si se interpretan como un único campo. El runtime de ofertas filtra disponibilidad con offer_data.status activa/active, mientras la configuración de selección tiene un dominio distinto.',
  'Story Agent, Agent Task y frontend deben mantener ambos campos separados y rechazar cualquier colapso de los dos dominios.',
  'VIGENTE',
  now()
where not exists (
  select 1 from public.lf_decision_log where adr='DEC-HMO-STATE-DIMENSIONS-001'
);

update public.lf_product_rules
set rule_statement='Cada oferta mantiene un offer_configuration_state independiente, limitado a SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA.',
    expected_behavior=jsonb_build_object(
      'field','offer_configuration_state',
      'states',jsonb_build_array('SIN_CONFIGURAR','PAGO_UNICO','CUOTAS','VENCIDA','MODIFICADA','INACTIVA')
    ),
    validation_rules=jsonb_build_array(
      'solo un offer_configuration_state vigente por offer_id',
      'offer_availability_status no debe colapsarse con offer_configuration_state'
    ),
    traceability=coalesce(traceability,'{}'::jsonb)||jsonb_build_object('decision_ref','DEC-HMO-STATE-DIMENSIONS-001'),
    updated_at=now(),
    updated_by_execution_id='STORY_PRODUCT_QUALITY_20260824'
where rule_code='R-HMO-003';

update public.lf_product_rules
set preconditions=jsonb_build_array('offer_availability_status = ACTIVA'),
    traceability=coalesce(traceability,'{}'::jsonb)||jsonb_build_object('decision_ref','DEC-HMO-STATE-DIMENSIONS-001'),
    updated_at=now(),
    updated_by_execution_id='STORY_PRODUCT_QUALITY_20260824'
where rule_code in ('R-HMO-004','R-HMO-005');

update public.lf_user_stories
set acceptance_criteria=jsonb_build_array(
  jsonb_build_object('code','AC-HMO-001-001','given','Home cargado','when','no existe selección','then','CTA deshabilitado y contador 0 de N','source','HU-HMO-001.acceptance_criteria[0]','source_rule_codes',jsonb_build_array('R-HMO-001')),
  jsonb_build_object('code','AC-HMO-001-002','given','una oferta válida configurada','when','se actualiza la selección','then','CTA habilitado con texto Continuar con 1 oferta','source','HU-HMO-001.acceptance_criteria[1]','source_rule_codes',jsonb_build_array('R-HMO-002')),
  jsonb_build_object('code','AC-HMO-001-003','given','dos o más ofertas válidas','when','se actualiza la selección','then','CTA muestra la cantidad exacta de selecciones válidas y no exige configurar las demás ofertas','source','HU-HMO-001.acceptance_criteria[2]','source_rule_codes',jsonb_build_array('R-HMO-002')),
  jsonb_build_object('code','AC-HMO-001-004','given','una oferta con configuración vigente','when','se intenta una transición a un estado fuera de SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA','then','la transición se rechaza y la selección válida previa permanece sin cambios','source','R-HMO-003','source_rule_codes',jsonb_build_array('R-HMO-003')),
  jsonb_build_object('code','AC-HMO-001-005','given','una oferta ACTIVA con un plan en cuotas previamente seleccionado','when','el usuario selecciona pago único','then','la modalidad queda en PAGO_UNICO y selected_plan_id queda vacío para esa oferta','source','R-HMO-004','source_rule_codes',jsonb_build_array('R-HMO-004')),
  jsonb_build_object('code','AC-HMO-001-006','given','una oferta ACTIVA con planes en cuotas disponibles','when','el usuario abre el selector y elige un plan vigente perteneciente a esa oferta','then','solo ese plan queda seleccionado y Aplicar plan se habilita; cancelar sin aplicar conserva la selección previa','source','R-HMO-005','source_rule_codes',jsonb_build_array('R-HMO-005'))
),
updated_at=now()
where story_code='HU-HMO-001' and status='CANDIDATO';

do $$
declare
  v_old public.lf_functional_versions%rowtype;
  v_story public.lf_user_stories%rowtype;
  v_new_id bigint;
begin
  if exists(select 1 from public.lf_functional_versions where artifact_code='HU-HMO-001' and version_no=2) then
    return;
  end if;

  select * into v_old
  from public.lf_functional_versions
  where artifact_code='HU-HMO-001' and version_no=1 and status='SEALED'
  order by id desc limit 1;
  if not found then raise exception 'HU-HMO-001 v1 SEALED source not found'; end if;

  select * into v_story
  from public.lf_user_stories
  where story_code='HU-HMO-001' and status='CANDIDATO';
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

-- Recalibrate only the exact HMO/libertad-financiera profile. 64 KiB is a bounded
-- pilot envelope above the measured 55,451 bytes (WorkerTaskSpec + selected context)
-- and below the former 490,709-byte prototype-derived allowance.
update programacion.gates g
set configuracion = jsonb_set(
  g.configuracion,
  '{profiles}',
  coalesce((
    select jsonb_agg(
      case
        when p.value->>'profile_code'='HMO_LIBERTAD_FINANCIERA_PILOT_V1' then
          p.value || jsonb_build_object(
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
        else p.value
      end
      order by p.ord
    )
    from jsonb_array_elements(coalesce(g.configuracion->'profiles','[]'::jsonb)) with ordinality p(value,ord)
  ),'[]'::jsonb),
  false
)
from programacion.versiones_agente v
where g.version_id=v.id
  and v.version_codigo='v0.9-roadmap-complete'
  and g.gate_codigo='G_TASK_SIZING_MIN'
  and g.estado in ('defined','active');

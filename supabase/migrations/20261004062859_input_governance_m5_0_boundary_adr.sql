-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.0 / PAULO-132
-- ADR-only boundary freeze. No runtime function, trigger, contract revision, promotion or production change.

begin;

do $m5_0_preflight$
declare
  v_n_done integer;
  v_runtime_links integer;
  v_parallel_adr integer;
begin
  if (select count(*) from transversal.decision_log where adr='DEC-INPUT-GOV-RUNTIME-001') <> 1 then
    raise exception 'M5_0_RUNTIME_ADR_NOT_EXACTLY_ONE';
  end if;

  select count(*) into v_parallel_adr
  from transversal.decision_log
  where adr <> 'DEC-INPUT-GOV-RUNTIME-001'
    and upper(coalesce(estado,'')) in ('VIGENTE','ACTIVE','ACTIVO')
    and coalesce(titulo,'') ilike '%Agent%Curator%Validator%';
  if v_parallel_adr <> 0 then
    raise exception 'M5_0_PARALLEL_BOUNDARY_ADR_EXISTS:%',v_parallel_adr;
  end if;

  select count(*) into v_n_done
  from programacion.engineering_plan_units u
  join programacion.engineering_work_items w on w.id=u.work_item_id
  where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and u.unit_code in ('N-10','N-11','N-12','N-13','N-15')
    and w.status='DONE';
  if v_n_done <> 5 then
    raise exception 'M5_0_REQUIRED_RECONCILIATION_UNITS_NOT_DONE:%',v_n_done;
  end if;

  if not exists (
    select 1 from programacion.contratos c
    where c.id=42
      and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and c.estado='defined'
      and c.fail_closed
      and c.especificacion->>'contract_revision'='1.5'
      and c.especificacion->>'runtime_orchestrator'='SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
      and c.especificacion->>'curator_runtime'='SUPABASE_EDGE_FUNCTION:input-governance-curator-v1'
      and c.especificacion->>'validator_runtime'='SUPABASE_EDGE_FUNCTION:input-governance-validator-v1'
  ) then
    raise exception 'M5_0_EXECUTION_CONTRACT_BOUNDARY_DRIFT';
  end if;

  if not exists (
    select 1 from programacion.contratos c
    where c.contrato_codigo='INPUT_READINESS_CONTRACT'
      and c.estado='defined'
      and c.fail_closed
      and c.especificacion->>'contract_revision'='5.13'
  ) then
    raise exception 'M5_0_READINESS_5_13_NOT_AVAILABLE';
  end if;

  select count(*) into v_runtime_links
  from public.lf_activo_relaciones
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo in ('EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1','EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1')
    and relacion_tipo='DEPENDE_DE';
  if v_runtime_links <> 2 then
    raise exception 'M5_0_AGENT_RUNTIME_RELATIONS_NOT_EXACTLY_TWO:%',v_runtime_links;
  end if;

  if exists (
    select 1 from pg_proc p
    where p.pronamespace='programacion'::regnamespace
      and p.proname in (
        'fn_input_governance_curator_materialize_v1',
        'fn_input_governance_curator_rebind_v1',
        'fn_input_governance_recurate_v2',
        'fn_input_governance_recurate_source_stale_v1',
        'fn_input_governance_bootstrap_materialize_v2'
      )
      and p.prosrc ilike '%fn_input_v58_build_assertions(%'
  ) then
    raise exception 'M5_0_LIVE_CURATOR_CALLS_VALIDATOR_ASSERTION_BUILDER';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.pronamespace='programacion'::regnamespace
      and p.proname='fn_input_governance_validator_rebind_v1'
      and p.prosrc ilike '%fn_input_v58_build_assertions(%'
  ) then
    raise exception 'M5_0_VALIDATOR_REBIND_DOES_NOT_OWN_ASSERTION_BUILDER';
  end if;
end
$m5_0_preflight$;

update transversal.decision_log
set titulo='Frontera Agent / Curator / Validator de Input Governance',
    decision='M5.0 / PAULO-132 AMPLIA DEC-INPUT-GOV-RUNTIME-001 sin crear una ADR paralela. Frontera unica: (1) INPUT_GOVERNANCE_AGENT orquesta y secuencia Curator y Validator como fases/runtimes separados; (2) Curator produce, rematerializa, rebind y recuratea, pero MUST NOT invocar al Validator, MUST NOT decidir aceptacion/rechazo y MUST NOT contener conocimiento semantico especifico por familia que pertenezca a registry/resolver; puede consumir autoridades/resolvers/classifiers gobernados sin duplicar sus reglas; (3) Validator acepta/rechaza mediante evidencia y oracles independientes, relee/resuelve autoridad actual y no puede tratar una conclusion del Curator como autoridad; DEC-INPUT-GOV-VALIDATOR-CLAIMS-NOT-CONCLUSIONS-001 sigue siendo la decision especializada para esa independencia; (4) rebind y recuration respetan exactamente la misma frontera; (5) el universo/propiedades por familia permanecen bajo sus autoridades gobernadas, incluida DEC-INPUT-GOV-D-M1.4 para el universo de 47 familias; (6) INPUT_READINESS_CONTRACT 5.13 e INPUT_GOVERNANCE_EXECUTION_CONTRACT 1.5 no cambian por esta ADR. No autoriza promocion, produccion ni refactor runtime.',
    razon='Congela una sola frontera contractual despues de reconciliar el estado live posterior a N-10/N-11/N-12/N-13/N-15. N-10 elimino el cruce historico Curator rebind -> fn_input_v58_build_assertions; N-11 retiro component IDs fijos; N-12 retiro allowlists temporales; N-13 reforzo currentness en continuations; N-15 ato consumers a capability/version/currentness. El call graph live acotado del SOURCE_PACK confirma que Curator ya no invoca el assertion builder del Validator y que Validator rebind conserva esa responsabilidad.',
    impacto='ADR-only. Amplia la decision existente en el mismo ADR DEC-INPUT-GOV-RUNTIME-001; no crea motor, registry, resolver ni ADR de frontera paralelos. Cruces historicos corregidos quedan como evidencia, no como deuda viva. Las unidades M5.x posteriores deben implementar o verificar comportamiento respetando esta frontera. INPUT_READINESS_CONTRACT 5.13 permanece sin cambio y promotion_authorized/production_authorized siguen fuera de alcance.',
    estado='vigente'
where adr='DEC-INPUT-GOV-RUNTIME-001';

insert into public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref
) values (
  gen_random_uuid(),
  'IG-M5-BOUNDARY-ADR-001',
  'INPUT_GOVERNANCE',
  'La frontera Agent / Curator / Validator debe vivir en una sola ADR y reutilizar autoridades existentes',
  'M5.0 reconcilio cruces historicos y estado live: Agent orquesta; Curator materializa/rebind/recurate sin invocar Validator; Validator conserva acceptance y assertion builder; reglas/propiedades por familia se delegan a registry/resolver/autoridad y las conclusiones del Curator no son autoridad del Validator.',
  'La separacion original de runtimes en DEC-INPUT-GOV-RUNTIME-001 no congelaba con suficiente precision ownership de orquestacion, produccion, acceptance, semantica por familia y rebind/recuration, lo que permitio cruces historicos como el assertion builder dentro de Curator rebind.',
  'Cuando la frontera se describe en multiples ADRs o se replica semantica de familia dentro de Curator/Validator, aparece acoplamiento y falsa independencia aunque existan runtimes separados.',
  'Ampliar la ADR existente; Agent=orquestacion, Curator=produccion/materializacion, Validator=acceptance con oracle independiente, family semantics=registry/resolver/authority. Prohibir Curator->Validator y tratar conclusions del Curator como no autoritativas.',
  'Readback debe mostrar exactamente un DEC-INPUT-GOV-RUNTIME-001 ampliado, 0 ADR paralela de frontera, Agent->Curator y Agent->Validator como relaciones separadas, 0 Curator call a fn_input_v58_build_assertions y Validator rebind manteniendo ese builder.',
  'MEDIUM',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
  'M5.0 / PAULO-132; SOURCE_PACK_LOOKUP_V2 preferred_input + current crossings. N-10 PR#1546 merged; N-11 PR#1547; N-12 PR#1548; N-13 y N-15 DONE con readbacks. ADR extendida in-place para evitar duplicacion.',
  now(),now(),'BOUNDARY_GOVERNANCE',array['INPUT_GOVERNANCE','AGENT','CURATOR','VALIDATOR','AUDITOR'],
  'ARCHITECTURE_BOUNDARY_DRIFT','STRUCTURAL',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2 M5.0 / PAULO-132',
  'supabase://transversal.decision_log/DEC-INPUT-GOV-RUNTIME-001|supabase://programacion.engineering_plan_units/M5.0|github://cristhianlujan/claude-persona-lf-patch/pull/1546|github://cristhianlujan/claude-persona-lf-patch/pull/1547|github://cristhianlujan/claude-persona-lf-patch/pull/1548'
);

do $m5_0_post$
declare
  v_parallel_adr integer;
begin
  if (select count(*) from transversal.decision_log where adr='DEC-INPUT-GOV-RUNTIME-001' and titulo='Frontera Agent / Curator / Validator de Input Governance' and decision ilike '%M5.0 / PAULO-132 AMPLIA%' and estado='vigente') <> 1 then
    raise exception 'M5_0_ADR_READBACK_FAILED';
  end if;

  select count(*) into v_parallel_adr
  from transversal.decision_log
  where adr <> 'DEC-INPUT-GOV-RUNTIME-001'
    and upper(coalesce(estado,'')) in ('VIGENTE','ACTIVE','ACTIVO')
    and coalesce(titulo,'') ilike '%Agent%Curator%Validator%';
  if v_parallel_adr <> 0 then
    raise exception 'M5_0_DUPLICATE_ADR_NEGATIVE_FAILED:%',v_parallel_adr;
  end if;

  if (select count(*) from public.lf_error_knowledge where codigo='IG-M5-BOUNDARY-ADR-001' and estado='ACTIVO') <> 1 then
    raise exception 'M5_0_EKB_POST_FAILED';
  end if;
end
$m5_0_post$;

commit;

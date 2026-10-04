-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M1.7 / PAULO-121
-- R16 Git-first migration.
-- Registers three ADRs only. No runtime mutation, cutover, deploy, registry creation,
-- authority creation, or parallel mechanism is performed here.

do $$
declare
  v_count integer;
begin
  -- Fail closed: M1.7 ADRs must be absent before this migration.
  select count(*) into v_count
  from transversal.decision_log
  where adr in (
    'DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001',
    'DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
    'DEC-INPUT-GOV-M1.7-COMPONENT-PROPERTIES-001'
  );
  if v_count <> 0 then
    raise exception 'BLOCK_M1_7_ADR_PREEXISTING_COUNT:%', v_count;
  end if;

  -- Reuse-first precondition: canonical transversal authorities are already active/current.
  select count(*) into v_count
  from public.lf_capability_registry r
  join public.lf_capability_version_registry v
    on v.capability_code = r.capability_code
  join public.lf_capability_current c
    on c.capability_code = r.capability_code
   and c.version = v.version
  where r.capability_code in (
    'PLAN_AUTHORITY_DRIFT_GUARD',
    'WAIVER_AUTHORITY',
    'RUNTIME_DEPLOY_VERIFICATION'
  )
    and r.status = 'ACTIVE'
    and r.owner_scope = 'LF_GOVERNANCE'
    and v.version = '1.0.0'
    and v.release_state = 'RELEASED';
  if v_count <> 3 then
    raise exception 'BLOCK_M1_7_TRANSVERSAL_AUTHORITY_CURRENT_COUNT:%', v_count;
  end if;

  -- CAPABILITY_CUTOVER must already be delivered by Super Admin; M1.7 only references it.
  select count(*) into v_count
  from programacion.engineering_plan_units u
  join programacion.engineering_work_items w on w.id = u.work_item_id
  where u.plan_code = 'LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1'
    and u.unit_code = 'SADM-PP-L5-022'
    and u.capability_ref = 'CAPABILITY_CUTOVER'
    and w.status = 'DONE';
  if v_count <> 1 then
    raise exception 'BLOCK_M1_7_CAPABILITY_CUTOVER_NOT_DONE:%', v_count;
  end if;

  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values
  (
    'DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001',
    'Input Governance release binding reutiliza CURRENT/CANDIDATE transversal',
    'Input Governance debe resolver releases reutilizando public.lf_capability_version_registry como autoridad de versiones/candidatos y public.lf_capability_current como único puntero CURRENT. Toda promoción o reversión consume CAPABILITY_CUTOVER; M1.7 no ejecuta switch ni crea binding propio.',
    'Separar identidad de versión, selección CURRENT y efecto de cutover evita punteros paralelos y permite reversión bajo la autoridad transversal existente.',
    'M9.2/M10.2 y cualquier release posterior de Input Governance deben consumir esta decisión. Queda prohibido crear tabla, registry, pointer o mecanismo CURRENT/CANDIDATE específico de IG.',
    'VIGENTE'
  ),
  (
    'DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001',
    'Input Governance adjudica divergencias mediante autoridades transversales existentes',
    'Una divergencia de plan/currentness no se resuelve con estado local de Input Governance: se consume la familia PLAN_AUTHORITY, materializada por PLAN_AUTHORITY_DRIFT_GUARD para detectar MATCH/AUTHORIZED_DELTA/UNREGISTERED_DRIFT. Una excepción aceptada requiere WAIVER_AUTHORITY vigente, exact-scope y verificable. Sin autoridad válida, el efecto dependiente queda HOLD/BLOCK.',
    'La adjudicación debe provenir de una autoridad independiente del consumidor; permitir overrides locales produciría auto-autorización y false-green.',
    'No se crea adjudicador paralelo. PLAN_AUTHORITY gobierna divergencia del plan y WAIVER_AUTHORITY gobierna excepciones explícitas; Input Governance solo consume sus receipts/veredictos.',
    'VIGENTE'
  ),
  (
    'DEC-INPUT-GOV-M1.7-COMPONENT-PROPERTIES-001',
    'Propiedades declaradas de componentes requieren verificación runtime independiente',
    'Las propiedades runtime/semánticas declaradas por contratos, assets o configuración son claims hasta ser demostradas. Cuando exista efecto de deploy, la verificación consume RUNTIME_DEPLOY_VERIFICATION vigente sobre receipt y fuente exacta; la verificación es read-only y no puede desplegar ni promover.',
    'Una propiedad declarada no prueba por sí sola que el componente desplegado la cumpla. Separar declaración de verificación evita certificar configuración stale o no materializada.',
    'M1.7 no modifica runtime. Los consumidores deben exigir evidencia de RUNTIME_DEPLOY_VERIFICATION cuando la propiedad dependa del runtime y bloquear la afirmación material ante receipt ausente, stale o mismatch.',
    'VIGENTE'
  );

  get diagnostics v_count = row_count;
  if v_count <> 3 then
    raise exception 'BLOCK_M1_7_ADR_INSERT_COUNT:%', v_count;
  end if;

  -- Exact postcondition: all three ADRs are present and explicitly reuse the expected authorities.
  select count(*) into v_count
  from transversal.decision_log
  where (
    adr = 'DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001'
    and estado = 'VIGENTE'
    and decision like '%lf_capability_version_registry%'
    and decision like '%lf_capability_current%'
    and decision like '%CAPABILITY_CUTOVER%'
  ) or (
    adr = 'DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001'
    and estado = 'VIGENTE'
    and decision like '%PLAN_AUTHORITY%'
    and decision like '%WAIVER_AUTHORITY%'
  ) or (
    adr = 'DEC-INPUT-GOV-M1.7-COMPONENT-PROPERTIES-001'
    and estado = 'VIGENTE'
    and decision like '%RUNTIME_DEPLOY_VERIFICATION%'
  );
  if v_count <> 3 then
    raise exception 'BLOCK_M1_7_ADR_POST_READBACK_COUNT:%', v_count;
  end if;
end $$;

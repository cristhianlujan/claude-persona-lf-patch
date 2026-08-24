do $block$
declare
  v_batch uuid:=gen_random_uuid();
  v_decision_number bigint;
begin
  if not exists(
    select 1 from public.lf_decisiones_gov
    where id_decision='DEC-HMO-STATE-DIMENSIONS-001'
  ) then
    select coalesce(max(decision_number),0)+1 into v_decision_number
    from public.lf_decisiones_gov;

    insert into public.lf_decisiones_gov(
      id_decision,fecha,decision,contexto,impacto,estado_original,estado_normalizado,
      documento_relacionado,observaciones,source_sheet_name,migration_batch_id,raw_payload,
      decision_number,created_by_execution_id,updated_by_execution_id,updated_at
    ) values (
      'DEC-HMO-STATE-DIMENSIONS-001',
      '2026-08-24',
      'Separar explícitamente la disponibilidad server-side de una oferta de su estado de configuración en Home Multi Oferta. offer_availability_status=ACTIVA significa que backend autoriza presentar/configurar la oferta; offer_configuration_state pertenece al conjunto SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA. PAGO_UNICO y CUOTAS son configuraciones mutuamente excluyentes y no reemplazan el estado de disponibilidad backend.',
      'R-HMO-004 y R-HMO-005 usan offer.status = ACTIVA como precondición, mientras R-HMO-003 enumera estados de configuración. El runtime canónico public.fn_lf_my_active_offers filtra offer_data.status en activa/active y devuelve por separado estado, offer_data e installment_plans. Los datos lf_proto.proto_offers conservan offer_data.status=activa y modalidad_seleccionada=pago_unico|cuotas como dimensiones distintas.',
      'Cierra AMB-HMO-001-STATE-01 sin inventar una nueva máquina de estados ni una capa nueva. El Agent Task debe tratar disponibilidad backend y configuración UI como dimensiones distintas y preservar la exclusividad de modalidad.',
      'VIGENTE','VIGENTE',
      'supabase://mhwmirqcgxxukpctffuv/public/v_lf_product_rules_current#R-HMO-003..005',
      'Readback causal: public.fn_lf_my_active_offers -> lf_proto.fn_lf_my_active_offers_internal filtra offer_data.status=activa/active. Esta decisión aclara vocabulario existente; no altera precios, vigencias ni comportamiento comercial.',
      'STORY_AGENT',v_batch,
      jsonb_build_object(
        'source_rules',jsonb_build_array('R-HMO-003','R-HMO-004','R-HMO-005'),
        'runtime_ref','SUPABASE:public.fn_lf_my_active_offers',
        'ambiguity_code','AMB-HMO-001-STATE-01'
      ),
      v_decision_number,'STORY-AGENT-GAP-CLOSURE-20260824','STORY-AGENT-GAP-CLOSURE-20260824',now()
    );
  end if;
end
$block$;

update programacion.agent_task_delivery_contracts
set in_scope = in_scope || jsonb_build_array(
      'Interpretar offer_availability_status=ACTIVA como disponibilidad autorizada por backend, separada de offer_configuration_state.',
      'Mantener offer_configuration_state únicamente en SIN_CONFIGURAR, PAGO_UNICO, CUOTAS, VENCIDA, MODIFICADA o INACTIVA conforme DEC-HMO-STATE-DIMENSIONS-001.'
    ),
    must_not_change = must_not_change || jsonb_build_array(
      'No colapsar offer_availability_status y offer_configuration_state en un único enum ni inferir ACTIVA como modalidad de pago.'
    ),
    blocked_if = (
      select coalesce(jsonb_agg(e order by ord),'[]'::jsonb)
      from jsonb_array_elements(blocked_if) with ordinality q(e,ord)
      where e->>'code' not in ('BLOCK-CLIENT-AUTH','BLOCK-PLAN-CATALOG','BLOCK-STATE-DOMAIN')
    ),
    semantic_ambiguities='[]'::jsonb
where task_id=21 and status='DRAFT';

update programacion.task_blockers
set status='RESOLVED',
    resolved_by='STORY-AGENT-GAP-CLOSURE-20260824',
    resolution_ref='decision://DEC-CLIENT-AUTH-SESSION-RUNTIME-001'
where task_id=21
  and blocker_code='CLIENT_AUTH_SESSION_RUNTIME_REQUIRED'
  and status='OPEN';

update programacion.agent_task_delivery_contracts
set status='SEALED'
where task_id=21 and status='DRAFT';

with src as (
  select
    t.id as task_id,
    t.task_code,
    t.objective,
    t.task_sha256,
    t.protected_path_patterns,
    f.acceptance_criteria,
    f.invariants,
    f.negative_controls,
    f.source_rule_codes,
    f.content_sha256,
    s.dependencies,
    programacion.fn_p0_json_codes(f.acceptance_criteria,'AC') as ac_codes,
    programacion.fn_p0_json_codes(f.invariants,'INV') as inv_codes,
    programacion.fn_p0_json_codes(f.negative_controls,'NEG') as neg_codes
  from programacion.agent_tasks t
  join public.lf_functional_versions f on f.id=t.functional_version_id
  join public.lf_user_stories s on s.story_code=f.story_code
  where t.id in (23,24,25,26)
), materialized as (
  select src.*,
    (
      select jsonb_agg(
        jsonb_build_object(
          'code','POS-'||(ac->>'code'),
          'statement','Dado '||coalesce(ac->>'given','el contexto sellado')||', cuando '||coalesce(ac->>'when','ocurre la acción definida')||', entonces '||coalesce(ac->>'then','se cumple el resultado esperado')||'.',
          'source_refs',jsonb_build_array(ac->>'code')
        ) order by ac->>'code'
      )
      from jsonb_array_elements(src.acceptance_criteria) ac
    ) as positive_cases,
    (
      select jsonb_agg(
        jsonb_build_object(
          'code','EDGE-'||(inv->>'code'),
          'statement',inv->>'statement',
          'source_refs',
            case when nullif(inv->>'source_rule_code','') is null
              then jsonb_build_array(inv->>'code')
              else jsonb_build_array(inv->>'code',inv->>'source_rule_code')
            end
        ) order by inv->>'code'
      )
      from jsonb_array_elements(src.invariants) inv
    ) as edge_cases,
    (
      select jsonb_agg(
        jsonb_build_object(
          'code','REG-'||(neg->>'code'),
          'statement','Debe rechazarse o impedirse: '||(neg->>'prohibited'),
          'source_refs',
            case when nullif(neg->>'source_rule_code','') is null
              then jsonb_build_array(neg->>'code')
              else jsonb_build_array(neg->>'code',neg->>'source_rule_code')
            end
        ) order by neg->>'code'
      )
      from jsonb_array_elements(src.negative_controls) neg
    ) as regression_cases
  from src
)
insert into programacion.agent_task_delivery_contracts(
  task_id,schema_version,expected_change,in_scope,out_of_scope,must_not_change,
  positive_cases,edge_cases,regression_cases,dependency_resolution,
  required_tests,required_evidence,blocked_if,semantic_ambiguities,
  generated_from_functional_sha256,generated_from_task_sha256,status
)
select
  m.task_id,
  2,
  m.objective||' El cambio debe respetar literalmente la Functional Version sellada y no completar dependencias con supuestos.',
  jsonb_build_array(
    m.objective,
    'Implementar únicamente el alcance descrito por AC/INV/NEG sellados de la Functional Version.',
    'Consumir únicamente interfaces y dependencias ya declaradas por el Agent Task.'
  ),
  jsonb_build_array(
    'No ampliar el cambio fuera de write_path_patterns y files_expected del Agent Task.',
    'No resolver decisiones de negocio, credenciales, pricing o arquitectura externa que permanezcan bloqueadas.',
    'No crear endpoints, tablas, estados o contratos no presentes en autoridad canónica.'
  ),
  jsonb_build_array(
    'No modificar rutas protegidas del Agent Task: '||array_to_string(m.protected_path_patterns,', '),
    'No alterar reglas, precios, vigencias o decisiones de negocio recibidas desde backend.',
    'No reducir AC, invariantes, negativos ni controles de accesibilidad/seguridad de la Functional Version.'
  ),
  m.positive_cases,
  m.edge_cases,
  m.regression_cases,
  case m.task_id
    when 23 then jsonb_build_array(
      jsonb_build_object(
        'source_dependency','componente modal accesible',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','UI:PASO3_MODAL_CUOTAS',
        'reason','El Agent Task declara UI:PASO3_MODAL_CUOTAS como interfaz canónica del selector modal accesible.'
      )
    )
    when 24 then jsonb_build_array(
      jsonb_build_object(
        'source_dependency','almacenamiento de selección',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','SUPABASE:public.lf_user_offer_selections',
        'reason','El Agent Task declara public.lf_user_offer_selections como almacenamiento canónico de selección por usuario/oferta/versión.'
      ),
      jsonb_build_object(
        'source_dependency','sesión autenticada',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','SUPABASE:public.fn_lf_my_active_offers',
        'reason','La RPC declarada por el Agent Task es auth-bound, exige auth.uid() y resuelve ofertas del cliente autenticado.'
      )
    )
    when 25 then jsonb_build_array(
      jsonb_build_object(
        'source_dependency','servicio de pricing',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','SUPABASE:public.fn_lf_my_checkout_pricing_quote',
        'reason','La RPC declarada por el Agent Task es la interfaz canónica para obtener el quote de pricing del checkout.'
      ),
      jsonb_build_object(
        'source_dependency','contrato de montos',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','SUPABASE:public.fn_lf_my_checkout_pricing_quote',
        'reason','El mismo quote backend constituye el contrato de montos; el frontend no debe inferir importes ni comisiones.'
      )
    )
    when 26 then jsonb_build_array(
      jsonb_build_object(
        'source_dependency','servicio de vigencia',
        'resolution_type','UNRESOLVED',
        'resolution_ref',null,
        'reason','No existe todavía una interfaz canónica declarada en el Agent Task que revalide vigencia de oferta antes del checkout; no se inventa una.'
      ),
      jsonb_build_object(
        'source_dependency','idempotencia de pagos',
        'resolution_type','INTERFACE_REF',
        'resolution_ref','SUPABASE:public.fn_lf_checkout_reserve_operation',
        'reason','La RPC declarada por el Agent Task reserva la operación por user/idempotency_key y rechaza reutilización con request distinto.'
      )
    )
  end,
  jsonb_build_array(
    jsonb_build_object(
      'test_ref','VISIBLE:build',
      'purpose','Demostrar que el cambio compila en el proyecto exacto y HEAD pineado.',
      'covers_refs',to_jsonb(m.source_rule_codes)
    ),
    jsonb_build_object(
      'test_ref','VISIBLE:lint',
      'purpose','Detectar defectos estáticos en el cambio dentro del alcance permitido.',
      'covers_refs',to_jsonb(m.source_rule_codes)
    ),
    jsonb_build_object(
      'test_ref','SEMANTIC:'||m.task_code,
      'purpose','Demostrar conductualmente el universo completo de criterios, invariantes y negativos de la Functional Version.',
      'covers_refs',to_jsonb(coalesce(m.ac_codes,'{}'::text[])||coalesce(m.inv_codes,'{}'::text[])||coalesce(m.neg_codes,'{}'::text[]))
    ),
    jsonb_build_object(
      'test_ref','MUTATION:'||m.task_code,
      'purpose','Demostrar que mutaciones de los comportamientos materiales producen FAIL y no un falso verde.',
      'covers_refs',to_jsonb(coalesce(m.ac_codes,'{}'::text[])||coalesce(m.inv_codes,'{}'::text[])||coalesce(m.neg_codes,'{}'::text[]))
    )
  ),
  jsonb_build_array(
    jsonb_build_object(
      'evidence_type','WORKER_CONTEXT_RECEIPT',
      'source_ref','runtime://agent-task-worker-context',
      'covers_refs',to_jsonb(m.source_rule_codes)
    ),
    jsonb_build_object(
      'evidence_type','EXACT_HEAD_TEST_RECEIPTS',
      'source_ref','github-actions://exact-head',
      'covers_refs',to_jsonb(coalesce(m.ac_codes,'{}'::text[])||coalesce(m.inv_codes,'{}'::text[])||coalesce(m.neg_codes,'{}'::text[]))
    ),
    jsonb_build_object(
      'evidence_type','SEMANTIC_MUTATION_RECEIPT',
      'source_ref','quality://semantic-mutation/'||lower(m.task_code),
      'covers_refs',to_jsonb(coalesce(m.ac_codes,'{}'::text[])||coalesce(m.inv_codes,'{}'::text[])||coalesce(m.neg_codes,'{}'::text[]))
    )
  ),
  case m.task_id
    when 23 then jsonb_build_array(
      jsonb_build_object('code','DEPENDENCY_INTEGRATION_REQUIRED','condition','HU-HMO-001 debe tener PASS verificado e integrarse al HEAD antes de ejecutar este Agent Task.')
    )
    when 24 then jsonb_build_array(
      jsonb_build_object('code','DEPENDENCY_INTEGRATION_REQUIRED','condition','HU-HMO-001 debe tener PASS verificado e integrarse al HEAD antes de ejecutar persistencia/recuperación.')
    )
    when 25 then jsonb_build_array(
      jsonb_build_object('code','B2B_PRICING_CONFIG_NUMERIC_VALUES_REQUIRED','condition','La configuración B2B debe tener valores numéricos aprobados; el Agent Task no puede inventarlos.'),
      jsonb_build_object('code','DEPENDENCY_INTEGRATION_REQUIRED','condition','HU-HMO-001 debe tener PASS verificado e integrarse al HEAD antes de ejecutar el resumen consolidado.')
    )
    when 26 then jsonb_build_array(
      jsonb_build_object('code','SERVICE_VALIDITY_INTERFACE_REQUIRED','condition','Debe existir una interfaz canónica verificable para revalidar vigencia de la oferta antes del checkout.'),
      jsonb_build_object('code','DEPENDENCY_INTEGRATION_REQUIRED','condition','HU-HMO-002 debe tener PASS verificado e integrarse al HEAD antes de ejecutar la revalidación final.')
    )
  end,
  '[]'::jsonb,
  m.content_sha256,
  m.task_sha256,
  'DRAFT'
from materialized m
where not exists(
  select 1 from programacion.agent_task_delivery_contracts dc where dc.task_id=m.task_id
);

update programacion.agent_task_delivery_contracts
set status='SEALED'
where task_id in (23,24,25)
  and status='DRAFT';

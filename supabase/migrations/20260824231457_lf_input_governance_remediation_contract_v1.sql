-- LF Input Governance internal remediation contract v1
-- Owner-approved 2026-08-24: remediation must occur inside INPUT_GOVERNANCE_AGENT.
-- Readiness contract 5.12 remains unchanged. Canonical auto-write remains DENY.

insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
values(
  'DEC-INPUT-GOV-SELF-REMEDIATE-001',
  'Input Governance debe intentar remediación interna antes de escalar al owner',
  'INPUT_GOVERNANCE_AGENT debe corregir automáticamente defectos determinísticos de su propio análisis/gate, materializar propuestas trazables para gaps restantes y exigir validación independiente. Solo propuestas validadas HUMAN_DECISION_REQUIRED se escalan al owner. Las propuestas no son fuente canónica y la escritura canónica automática permanece DENY.',
  'El run 194 de ONB_002 produjo 26 bloqueos y 0 propuestas; además DESIGN_SYSTEM mezcló 9 elementos NOT_APPLICABLE con component bindings realmente pendientes.',
  'Añade analysis_revision 1.3 al execution contract y corrige la semántica de análisis sin merge, promotion ni producción.',
  'vigente'
)
on conflict (adr) do update
set decision=excluded.decision,razon=excluded.razon,impacto=excluded.impacto,estado='vigente';

update programacion.contratos
set especificacion =
    jsonb_set(
      jsonb_set(especificacion,'{contract_revision}','"1.3"'::jsonb,true),
      '{analysis_revision}','"INPUT_GOV_REMEDIATION_1_3"'::jsonb,true
    )
    || jsonb_build_object(
      'remediation_loop',
      jsonb_build_object(
        'decision','DEC-INPUT-GOV-SELF-REMEDIATE-001',
        'self_analysis_correction','AUTO',
        'gap_proposals','CURATOR_PROPOSE_VALIDATOR_VERIFY',
        'owner_escalation','VALIDATED_HUMAN_DECISION_REQUIRED_ONLY',
        'proposal_is_canonical_source',false,
        'automatic_canonicalization','DENY',
        'safe_canonical_write_allowlist',jsonb_build_array()
      )
    )
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

create or replace function programacion.fn_input_governance_bootstrap_classify_v2(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,programacion,lf_ops
as $function$
declare
  v jsonb;
  v_blockers jsonb;
  v_b jsonb;
  v_new_blockers jsonb:='[]'::jsonb;
  v_required int:=0;
  v_resolved int:=0;
  v_na int:=0;
  v_pending int:=0;
  v_unresolved int:=0;
begin
  v:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,p_family_code,p_version_id);

  if p_family_code='DESIGN_SYSTEM' then
    select
      count(*) filter(where required_for_implementation),
      count(*) filter(where required_for_implementation and semantic_binding_status='RESOLVED_ID' and component_token_id is not null),
      count(*) filter(where required_for_implementation and semantic_binding_status='NOT_APPLICABLE'),
      count(*) filter(where required_for_implementation and semantic_binding_status='PENDING_SEMANTIC_COMPONENT'),
      count(*) filter(
        where required_for_implementation
          and (
            semantic_binding_status='PENDING_SEMANTIC_COMPONENT'
            or semantic_binding_status not in ('RESOLVED_ID','NOT_APPLICABLE')
            or (semantic_binding_status='RESOLVED_ID' and component_token_id is null)
          )
      )
    into v_required,v_resolved,v_na,v_pending,v_unresolved
    from lf_ops.pantalla_elementos
    where pantalla_id=p_pantalla_id and status<>'DEPRECATED';

    v:=jsonb_set(
      v,
      '{probe,summary}',
      coalesce(v->'probe'->'summary','{}'::jsonb)
      || jsonb_build_object(
        'element_required_semantic_resolved_count',v_resolved,
        'element_required_semantic_not_applicable_count',v_na,
        'element_required_semantic_pending_count',v_pending,
        'element_required_semantic_unresolved_count',v_unresolved,
        'element_required_count',v_required,
        'semantic_gap_contract','DESIGN_ELEMENT_BINDING_SEMANTICS_V1'
      ),
      true
    );

    v_blockers:=coalesce(v->'blockers','[]'::jsonb);
    for v_b in select value from jsonb_array_elements(v_blockers)
    loop
      if v_b->>'code' <> 'ELEMENT_REQUIRED_COMPONENT_BINDING_MISSING' then
        v_new_blockers:=v_new_blockers||jsonb_build_array(v_b);
      end if;
    end loop;
    if v_unresolved>0 then
      v_new_blockers:=v_new_blockers||jsonb_build_array(
        jsonb_build_object(
          'code','ELEMENT_REQUIRED_SEMANTIC_COMPONENT_UNRESOLVED',
          'count',v_unresolved,
          'not_applicable_count',v_na,
          'pending_semantic_component_count',v_pending
        )
      );
    end if;
    v:=jsonb_set(v,'{blockers}',v_new_blockers,true);
  end if;

  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));
end;
$function$;

revoke all on function programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint) to service_role;

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_run record;
  v_current_manifest jsonb;
  v_current_sha text;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_payload jsonb;
  v_contract_sha text;
  v_has_terminal_successor boolean;
  v_analysis_revision text;
begin
  select r.status,r.version_id,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,
         r.source_manifest,r.source_snapshot_sha256,r.invalidated_at,r.scope
    into v_run
  from programacion.input_readiness_runs r where r.id=p_run_id;
  if not found then return false; end if;
  if v_run.status<>'COMPLETED' or v_run.source_snapshot_sha256 is null or v_run.invalidated_at is not null then return false; end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
    into v_contract_schema,v_contract_revision,v_contract_payload
  from programacion.contratos c
  where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if v_contract_schema is null or v_contract_revision is null then return false; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run.contract_version<>v_contract_schema
     or v_run.contract_revision is distinct from v_contract_revision
     or v_run.contract_snapshot_sha256 is distinct from v_contract_sha then return false; end if;

  if coalesce(v_run.scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then
    select especificacion->>'analysis_revision' into v_analysis_revision
    from programacion.contratos
    where version_id=v_run.version_id and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed;
    if v_analysis_revision is null or v_run.scope->>'analysis_revision' is distinct from v_analysis_revision then return false; end if;
  end if;

  select exists(
    select 1 from programacion.input_readiness_runs n
    where n.supersedes_run_id=p_run_id and n.status in ('COMPLETED','BLOCKED')
  ) into v_has_terminal_successor;
  if v_has_terminal_successor then return false; end if;

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_run.source_snapshot_sha256 and v_current_manifest=v_run.source_manifest;
end;
$function$;

-- Pure regression: ONB_002 Design System semantic component gap must be 2, not raw 11.
do $block$
declare
  v jsonb;
  v_count int;
  v_na int;
begin
  v:=programacion.fn_input_governance_bootstrap_classify_v2(2,'DESIGN_SYSTEM',19);
  select coalesce((x->>'count')::int,0)
    into v_count
  from jsonb_array_elements(v->'blockers') x
  where x->>'code'='ELEMENT_REQUIRED_SEMANTIC_COMPONENT_UNRESOLVED';
  v_na:=coalesce((v->'probe'->'summary'->>'element_required_semantic_not_applicable_count')::int,0);
  if v_count<>2 or v_na<>9 then
    raise exception 'INPUT_REMEDIATION_DESIGN_REGRESSION_FAILED unresolved=% na=%',v_count,v_na;
  end if;
end;
$block$;
create or replace function programacion.fn_agent_task_materialize_verified_machine_gates_v1(
  p_task_id bigint,
  p_verifier_identity text,
  p_verifier_run_id text,
  p_workflow_sha text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','vault','extensions'
as $function$
declare
  v_ex programacion.ejecuciones%rowtype;
  v_source_ev programacion.evidencias%rowtype;
  v_source_verification_id bigint;
  v_source_authority_receipt_id bigint;
  v_source_subject_sha text;
  v_tests jsonb;
  v_mapping jsonb;
  v_gate_code text;
  v_proof_key text;
  v_proof_value text;
  v_obj_id bigint;
  v_independence boolean;
  v_existing_id bigint;
  v_existing_result text;
  v_eval_id bigint;
  v_evidence_id bigint;
  v_evidence_sha text;
  v_manifest jsonb;
  v_verification_payload jsonb;
  v_subject_payload jsonb;
  v_subject_sha text;
  v_token text;
  v_channel_hash text;
  v_token_hash text;
  v_receipt_id bigint;
  v_receipt_sha text;
  v_verification_id bigint;
  v_verification_sha text;
  v_results jsonb := '[]'::jsonb;
  v_materialized integer := 0;
  v_skipped integer := 0;
  v_source_ref text;
  v_worker_receipt jsonb;
begin
  if p_task_id is null or p_task_id < 1 then raise exception 'MACHINE_GATE_TASK_ID_INVALID'; end if;
  if p_verifier_identity !~ '^github-actions://cristhianlujan/claude-persona-lf-patch/[.]github/workflows/story-agent-evidence-verifier[.]yml@refs/heads/main#run-[0-9]+$' then
    raise exception 'MACHINE_GATE_VERIFIER_IDENTITY_INVALID';
  end if;
  if coalesce(p_verifier_run_id,'') !~ '^[0-9]+$' or p_verifier_identity not like '%#run-'||p_verifier_run_id then
    raise exception 'MACHINE_GATE_VERIFIER_RUN_ID_MISMATCH';
  end if;
  if coalesce(p_workflow_sha,'') !~ '^[0-9a-f]{40}$' then raise exception 'MACHINE_GATE_WORKFLOW_SHA_INVALID'; end if;

  select e.* into v_ex
  from programacion.ejecuciones e
  where e.request_ref='agent-task://'||p_task_id::text and e.estado='RUNNING'
  order by e.id desc limit 1;
  if v_ex.id is null then raise exception 'MACHINE_GATE_RUNNING_EXECUTION_NOT_FOUND:%',p_task_id; end if;
  if programacion.fn_agent_task_worker_context_receipt_ok(v_ex.id) is not true then
    raise exception 'MACHINE_GATE_CONTEXT_BOUND_WORKER_RECEIPT_REQUIRED:%',v_ex.id;
  end if;

  select ev.* into v_source_ev
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id
  join programacion.objetivos_ejecucion oe on oe.id=eva.objetivo_id and oe.execution_id=v_ex.id
  where ev.tipo='VERIFIED_WORKER_RECEIPT'
    and ev.source_system='PROGRAMMING_AGENT_WORKER'
    and ev.metadata#>>'{worker_receipt,status}'='PASS'
    and exists(
      select 1 from programacion.evidence_verifications vv
      where vv.evidence_id=ev.id and vv.verification_status='VERIFIED'
        and vv.evidence_sha256=ev.sha256 and vv.source_system=ev.source_system and vv.source_ref=ev.source_ref
        and vv.authority_receipt_id is not null
    )
  order by ev.id desc limit 1;
  if v_source_ev.id is null then raise exception 'MACHINE_GATE_VERIFIED_WORKER_SOURCE_NOT_FOUND:%',v_ex.id; end if;

  select vv.id,vv.authority_receipt_id,pr.subject_sha256
    into v_source_verification_id,v_source_authority_receipt_id,v_source_subject_sha
  from programacion.evidence_verifications vv
  join programacion.provenance_receipts pr on pr.id=vv.authority_receipt_id
  where vv.evidence_id=v_source_ev.id and vv.verification_status='VERIFIED'
    and vv.evidence_sha256=v_source_ev.sha256 and vv.source_system=v_source_ev.source_system and vv.source_ref=v_source_ev.source_ref
  order by vv.id desc limit 1;
  if v_source_verification_id is null then raise exception 'MACHINE_GATE_SOURCE_VERIFICATION_NOT_FOUND:%',v_source_ev.id; end if;
  perform programacion.fn_assert_provenance_receipt(
    v_source_authority_receipt_id,'EVIDENCE_VERIFICATION',v_ex.id,v_ex.head_sha,
    'evidence_verification','evidence:'||v_source_ev.id::text,v_source_subject_sha
  );

  v_worker_receipt:=v_source_ev.metadata->'worker_receipt';
  v_tests:=coalesce(v_worker_receipt->'tests','{}'::jsonb);
  v_source_ref:=v_source_ev.source_ref;

  select decrypted_secret into v_token from vault.decrypted_secrets
  where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
  if length(coalesce(v_token,''))<32 then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_SECRET_MISSING'; end if;
  v_token_hash:=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex');
  select secret_sha256 into v_channel_hash from programacion.provenance_channels where channel_code='EVIDENCE_VERIFIER_V1';
  if v_channel_hash is distinct from v_token_hash then raise exception 'EVIDENCE_VERIFIER_V1_VAULT_CHANNEL_HASH_MISMATCH'; end if;

  for v_mapping in
    select value from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('gate_code','G_BUILD_TYPECHECK','proof_key','build','proof_kind','exact_pass'),
      jsonb_build_object('gate_code','G_LINT_FORMAT','proof_key','lint','proof_kind','exact_pass'),
      jsonb_build_object('gate_code','G_TEST_POSITIVE','proof_key','semantic','proof_kind','count_pass'),
      jsonb_build_object('gate_code','G_TEST_NEGATIVE','proof_key','mutation','proof_kind','count_pass')
    ))
  loop
    v_gate_code:=v_mapping->>'gate_code';
    v_proof_key:=v_mapping->>'proof_key';
    v_proof_value:=v_tests->>v_proof_key;

    if v_mapping->>'proof_kind'='exact_pass' then
      if v_proof_value is distinct from 'PASS' then
        v_results:=v_results||jsonb_build_array(jsonb_build_object('gate_code',v_gate_code,'status','NOT_MATERIALIZED','reason','SOURCE_PROOF_NOT_PASS','proof',v_proof_value));
        v_skipped:=v_skipped+1; continue;
      end if;
    else
      if coalesce(v_proof_value,'') !~ '^[1-9][0-9]*/[1-9][0-9]* PASS$'
         or split_part(split_part(v_proof_value,' ',1),'/',1) <> split_part(split_part(v_proof_value,' ',1),'/',2) then
        v_results:=v_results||jsonb_build_array(jsonb_build_object('gate_code',v_gate_code,'status','NOT_MATERIALIZED','reason','SOURCE_COUNT_PROOF_NOT_FULL_PASS','proof',v_proof_value));
        v_skipped:=v_skipped+1; continue;
      end if;
    end if;

    select oe.id,coalesce(c.independencia_requerida,false)
      into v_obj_id,v_independence
    from programacion.objetivos_ejecucion oe
    join programacion.gates g on g.id=oe.gate_id
    left join programacion.componentes c on c.id=g.ejecutor_componente_id
    where oe.execution_id=v_ex.id and oe.aplicabilidad='REQUIRED' and g.gate_codigo=v_gate_code
    order by g.version_id desc,g.id desc limit 1;
    if v_obj_id is null then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('gate_code',v_gate_code,'status','NOT_MATERIALIZED','reason','EFFECTIVE_OBJECTIVE_NOT_FOUND'));
      v_skipped:=v_skipped+1; continue;
    end if;
    if v_independence then raise exception 'MACHINE_GATE_INDEPENDENT_OBJECTIVE_FORBIDDEN:%',v_gate_code; end if;

    v_existing_id:=null; v_existing_result:=null;
    select ev.id,ev.resultado into v_existing_id,v_existing_result
    from programacion.evaluaciones ev where ev.objetivo_id=v_obj_id
    order by ev.intento desc,ev.id desc limit 1;
    if v_existing_id is not null then
      if v_existing_result='PASS' then
        v_results:=v_results||jsonb_build_array(jsonb_build_object('gate_code',v_gate_code,'status','ALREADY_PASS','evaluation_id',v_existing_id));
        v_skipped:=v_skipped+1; continue;
      end if;
      raise exception 'MACHINE_GATE_EXISTING_EVALUATION_REQUIRES_SEPARATE_REMEDIATION:%:%:%',v_gate_code,v_existing_id,v_existing_result;
    end if;

    insert into programacion.evaluaciones(
      objetivo_id,intento,evaluador_identidad,evaluador_tipo,evaluador_canal,
      independencia_declarada,resultado,resumen,detalles,head_sha
    ) values(
      v_obj_id,1,'STORY_AGENT_MACHINE_EVIDENCE_CONSUMER_V1','oracle','EVIDENCE_VERIFIER_V1',false,'PENDING',
      'Pending exact evidence verification for '||v_gate_code,
      jsonb_build_object('schema_version',1,'consumer','STORY_AGENT_MACHINE_EVIDENCE_CONSUMER_V1',
        'derived_from_evidence_id',v_source_ev.id,'derived_from_verification_id',v_source_verification_id,
        'proof_key',v_proof_key,'proof_value',v_proof_value,'verifier_identity',p_verifier_identity),
      v_ex.head_sha
    ) returning id into v_eval_id;

    v_manifest:=jsonb_build_object(
      'schema_version',1,'evidence_kind','MACHINE_GATE_DERIVED_RECEIPT','execution_id',v_ex.id,'task_id',p_task_id,
      'gate_code',v_gate_code,'base_head_sha',v_ex.head_sha,'source_snapshot_sha256',v_ex.source_snapshot_sha256,
      'source_worker_evidence_id',v_source_ev.id,'source_worker_evidence_sha256',v_source_ev.sha256,
      'source_worker_verification_id',v_source_verification_id,'source_worker_authority_receipt_id',v_source_authority_receipt_id,
      'source_ref',v_source_ref,'proof_key',v_proof_key,'proof_value',v_proof_value,
      'delivered_head_sha',v_worker_receipt->>'delivered_head_sha','merged_head_sha',v_worker_receipt->>'merged_head_sha',
      'github_actions_run_id',v_worker_receipt->>'github_actions_run_id'
    );
    v_evidence_sha:=programacion.fn_v09_sha256_jsonb(v_manifest);

    insert into programacion.evidencias(evaluacion_id,tipo,source_system,source_ref,sha256,head_sha,resumen,metadata)
    values(v_eval_id,'MACHINE_GATE_DERIVED_RECEIPT','VERIFIED_WORKER_RECEIPT_DERIVATION_V1',
      v_source_ref||'#gate='||v_gate_code,v_evidence_sha,v_ex.head_sha,
      'Gate-specific machine evidence derived from externally verified context-bound Worker receipt.',v_manifest)
    returning id into v_evidence_id;

    v_verification_payload:=jsonb_build_object(
      'schema_version',1,'execution_id',v_ex.id::text,'task_id',p_task_id::text,'gate_code',v_gate_code,
      'evidence_id',v_evidence_id::text,'head_sha',v_ex.head_sha,'evidence_sha256',v_evidence_sha,
      'source_system','VERIFIED_WORKER_RECEIPT_DERIVATION_V1','source_ref',v_source_ref||'#gate='||v_gate_code,
      'verification_status','VERIFIED','verifier_identity',p_verifier_identity,
      'github_repository','cristhianlujan/claude-persona-lf-patch',
      'github_workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/story-agent-evidence-verifier.yml@refs/heads/main',
      'github_run_id',p_verifier_run_id,'github_workflow_sha',p_workflow_sha,
      'source_worker_evidence_id',v_source_ev.id::text,'source_worker_verification_id',v_source_verification_id::text
    );
    v_subject_payload:=jsonb_build_object(
      'evidence_id',v_evidence_id,'evidence_sha256',v_evidence_sha,'source_system','VERIFIED_WORKER_RECEIPT_DERIVATION_V1',
      'source_ref',v_source_ref||'#gate='||v_gate_code,'verification_status','VERIFIED',
      'verification_method','GITHUB_ACTIONS_OIDC_MACHINE_GATE_DERIVATION_V1','verifier_identity',p_verifier_identity,
      'verification_payload',v_verification_payload
    );
    v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject_payload);

    select id,receipt_sha256 into v_receipt_id,v_receipt_sha
    from programacion.issue_provenance_receipt(
      'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',v_ex.id,v_ex.head_sha,'evidence_verification',
      'evidence:'||v_evidence_id::text,v_subject_sha,p_verifier_identity,
      'github-actions://run/'||p_verifier_run_id||'/machine-gate/'||v_gate_code||'/evidence/'||v_evidence_id::text,
      v_verification_payload||jsonb_build_object('subject_type','evidence_verification','subject_ref','evidence:'||v_evidence_id::text,'subject_sha256',v_subject_sha)
    );

    insert into programacion.evidence_verifications(
      evidence_id,evidence_sha256,source_system,source_ref,verification_status,verification_method,
      verifier_identity,verification_payload,authority_receipt_id
    ) values(
      v_evidence_id,v_evidence_sha,'VERIFIED_WORKER_RECEIPT_DERIVATION_V1',v_source_ref||'#gate='||v_gate_code,
      'VERIFIED','GITHUB_ACTIONS_OIDC_MACHINE_GATE_DERIVATION_V1',p_verifier_identity,v_verification_payload,v_receipt_id
    ) returning id,verification_sha256 into v_verification_id,v_verification_sha;

    update programacion.evaluaciones
    set resultado='PASS',finished_at=now(),
        resumen='PASS from gate-specific proof in externally verified context-bound Worker receipt.',
        detalles=detalles||jsonb_build_object('evidence_id',v_evidence_id,'evidence_sha256',v_evidence_sha,
          'evidence_verification_id',v_verification_id,'evidence_verification_sha256',v_verification_sha,
          'authority_receipt_id',v_receipt_id,'authority_receipt_sha256',v_receipt_sha)
    where id=v_eval_id;

    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'gate_code',v_gate_code,'status','PASS','evaluation_id',v_eval_id,'evidence_id',v_evidence_id,
      'evidence_verification_id',v_verification_id,'authority_receipt_id',v_receipt_id,'proof',v_proof_value));
    v_materialized:=v_materialized+1;
  end loop;

  return jsonb_build_object('status','MATERIALIZED','execution_id',v_ex.id,'task_id',p_task_id,
    'source_worker_evidence_id',v_source_ev.id,'source_worker_verification_id',v_source_verification_id,
    'materialized_count',v_materialized,'skipped_count',v_skipped,'results',v_results);
end;
$function$;

revoke all on function programacion.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text) to postgres;

create or replace function public.fn_agent_task_materialize_verified_machine_gates_v1(
  p_task_id bigint,p_verifier_identity text,p_verifier_run_id text,p_workflow_sha text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_agent_task_materialize_verified_machine_gates_v1(p_task_id,p_verifier_identity,p_verifier_run_id,p_workflow_sha);
$function$;
revoke all on function public.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text) to service_role;

comment on function programacion.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text)
is 'PROG-024 canonical machine-gate consumer. Materializes only explicit build/lint/semantic/mutation PASS proofs from an externally VERIFIED, execution/context-bound Worker receipt. Independent/human/unsupported gates are never inferred.';
comment on function public.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text)
is 'Service-role transport wrapper for the OIDC-authenticated Story Agent Evidence Verifier; no public/anon/authenticated execution.';

do $selftest$
declare v_acl text; v_def text;
begin
  select pg_get_functiondef('programacion.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text)'::regprocedure) into v_def;
  if position('G_BUILD_TYPECHECK' in v_def)=0 or position('G_TEST_NEGATIVE' in v_def)=0 or position('MACHINE_GATE_INDEPENDENT_OBJECTIVE_FORBIDDEN' in v_def)=0 then
    raise exception 'SELFTEST_MACHINE_GATE_CONSUMER_DEFINITION_INCOMPLETE';
  end if;
  select coalesce(p.proacl::text,'') into v_acl from pg_proc p where p.oid='public.fn_agent_task_materialize_verified_machine_gates_v1(bigint,text,text,text)'::regprocedure;
  if v_acl not like '%service_role=X/%' or v_acl like '%anon=%' or v_acl like '%authenticated=%' then
    raise exception 'SELFTEST_MACHINE_GATE_PUBLIC_WRAPPER_ACL_INVALID:%',v_acl;
  end if;
end;
$selftest$;
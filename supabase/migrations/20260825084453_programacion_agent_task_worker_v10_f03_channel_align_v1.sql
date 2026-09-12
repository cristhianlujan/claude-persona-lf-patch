do $align$
declare
  vdef text;
begin
  select pg_get_functiondef('programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)'::regprocedure)
    into vdef;
  if position('INDEPENDENT_AUDITOR_V1' in vdef)=0 then
    raise exception 'WORKER_V10_F03_ALIGN_LEGACY_CHANNEL_MARKER_MISSING';
  end if;
  vdef:=replace(vdef,
    'pr.issuer_channel=''INDEPENDENT_AUDITOR_V1''',
    'pr.issuer_channel=''F03_OIDC_AUDITOR_V1''');
  vdef:=replace(vdef,
    '(pr.payload->>''receipt_contract_version'')::integer>=3',
    '(pr.payload->>''receipt_contract_version'')::integer>=4
        and coalesce((pr.payload->>''mutation_count'')::integer,0)>=8
        and (pr.payload->>''killed_count'')::integer=(pr.payload->>''mutation_count'')::integer
        and pr.payload->>''hidden_output''=''HASH_ONLY''');
  execute vdef;
end;
$align$;

do $selftest$
declare
  vdef text;
begin
  select pg_get_functiondef('programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)'::regprocedure)
    into vdef;
  if position('INDEPENDENT_AUDITOR_V1' in vdef)>0 then
    raise exception 'SELFTEST_WORKER_V10_LEGACY_F03_CHANNEL_REMAINS';
  end if;
  if position('F03_OIDC_AUDITOR_V1' in vdef)=0
     or position('receipt_contract_version' in vdef)=0
     or position('mutation_count' in vdef)=0
     or position('killed_count' in vdef)=0
     or position('HASH_ONLY' in vdef)=0 then
    raise exception 'SELFTEST_WORKER_V10_F03_V4_BINDING_INCOMPLETE';
  end if;
end;
$selftest$;

comment on function programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)
is 'Worker v10 authority context aligned to the AUD24-F03 GitHub OIDC mutation authority receipt v4. Legacy INDEPENDENT_AUDITOR_V1 receipts are not accepted for hidden_ok.';

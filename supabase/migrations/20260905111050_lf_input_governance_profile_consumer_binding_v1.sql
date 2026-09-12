-- Strategy 26 / MC-06 + MC-07
-- Reuse the existing INPUT_GOVERNANCE_EXECUTION_CONTRACT allowlist.
-- Profile execution consumes CONTEXT_PACK; invalid consumer identities fail closed.
-- Preserve the legacy contract_snapshot_hash receipt field while adding the
-- canonical contract_snapshot_sha256 + consumer fields required for readback.

do $$
declare
  v_def text;
  v_old text := E'    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(p_request_text,v_adapters,''STORY_CREATOR'');';
  v_new text := E'    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1(\n      p_request_text,\n      v_adapters,\n      case when v_operation.operation_code = ''EJECUCION_PERFIL_LF'' then ''CONTEXT_PACK'' else ''STORY_CREATOR'' end\n    );';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;

  if position('then ''CONTEXT_PACK'' else ''STORY_CREATOR'' end' in v_def) = 0 then
    if position(v_old in v_def) = 0 then
      raise exception 'S26_INPUT_GOV_ROUTER_CONSUMER_ANCHOR_NOT_FOUND';
    end if;
    v_def := replace(v_def, v_old, v_new);
    execute v_def;
  end if;
end;
$$;

do $$
declare
  v_def text;
  v_anchor text := E'  if v_required_count = 0 then\n    return jsonb_build_object(\n      ''applicable'', false,\n      ''status'', ''NOT_REQUIRED'',\n      ''blocking_code'', null,\n      ''decision'', ''N/A'',\n      ''continuation_allowed'', true,\n      ''required_by_adapters'', ''[]''::jsonb\n    );\n  end if;\n';
  v_guard text := E'\n  -- Consumer identity is authority-bearing. Resolve the current allowlist from\n  -- INPUT_GOVERNANCE_EXECUTION_CONTRACT and fail closed on unknown callers.\n  if not coalesce((\n    select (c.especificacion->''allowed_consumers'') ? btrim(coalesce(p_consumer, ''''))\n    from programacion.contratos c\n    where c.contrato_codigo = ''INPUT_GOVERNANCE_EXECUTION_CONTRACT''\n      and c.estado = ''defined''\n    order by c.id desc\n    limit 1\n  ), false) then\n    return jsonb_build_object(\n      ''applicable'', true,\n      ''status'', ''BLOCKED'',\n      ''blocking_code'', ''BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED'',\n      ''decision'', ''BLOCKED'',\n      ''continuation_allowed'', false,\n      ''consumer'', p_consumer,\n      ''required_by_adapters'', v_required_adapters\n    );\n  end if;\n';
begin
  select pg_get_functiondef('programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure)
    into v_def;

  if position('BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED' in v_def) = 0 then
    if position(v_anchor in v_def) = 0 then
      raise exception 'S26_INPUT_GOV_CONSUMER_ALLOWLIST_ANCHOR_NOT_FOUND';
    end if;
    v_def := replace(v_def, v_anchor, v_anchor || v_guard);
  end if;

  if position('''consumer'', p_consumer' in v_def) = 0 then
    if position(E'      ''governance_version'', v_contract_revision,\n' in v_def) = 0 then
      raise exception 'S26_INPUT_GOV_RECEIPT_CONSUMER_ANCHOR_NOT_FOUND';
    end if;
    v_def := replace(
      v_def,
      E'      ''governance_version'', v_contract_revision,\n',
      E'      ''governance_version'', v_contract_revision,\n      ''consumer'', p_consumer,\n'
    );
  end if;

  if position('''contract_snapshot_sha256'', v_contract_snapshot_sha256' in v_def) = 0 then
    if position(E'      ''contract_snapshot_hash'', v_contract_snapshot_sha256,\n' in v_def) = 0 then
      raise exception 'S26_INPUT_GOV_RECEIPT_CONTRACT_SHA_ANCHOR_NOT_FOUND';
    end if;
    v_def := replace(
      v_def,
      E'      ''contract_snapshot_hash'', v_contract_snapshot_sha256,\n',
      E'      ''contract_snapshot_hash'', v_contract_snapshot_sha256,\n      ''contract_snapshot_sha256'', v_contract_snapshot_sha256,\n'
    );
  end if;

  execute v_def;
end;
$$;

comment on function programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text) is
  'Internal ACT-0001 Input Governance resolver. Strategy26 hardening: applicable consumer identity must exist in current INPUT_GOVERNANCE_EXECUTION_CONTRACT.allowed_consumers; profile execution is bound by Router to CONTEXT_PACK. Receipt includes consumer and contract_snapshot_sha256. No new gate or agent.';

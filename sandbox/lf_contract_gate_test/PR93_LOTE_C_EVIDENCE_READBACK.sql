-- PR #93 / LOTE-C structural readback. SELECT-only.

select jsonb_build_object(
  'functions',jsonb_build_object(
    'gate_binder',to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is not null,
    'gate_validator',to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is not null,
    'separation',to_regprocedure('private.fn_writer_key_separation_v7_valid()') is not null
  ),
  'postgres_helper_execute',jsonb_build_object(
    'scope_parser',has_function_privilege('postgres','private.fn_writer_preimage_scope_v7(text)','EXECUTE'),
    'reconciliation_preimage',has_function_privilege('postgres','private.fn_reconciliation_preimage_v7(jsonb,text)','EXECUTE'),
    'gate_preimage',has_function_privilege('postgres','private.fn_gate_preimage_v7(jsonb,text)','EXECUTE'),
    'canonical_json',has_function_privilege('postgres','private.fn_canonical_json_v7(jsonb)','EXECUTE'),
    'payload_sha256',has_function_privilege('postgres','private.fn_payload_sha256_v7(jsonb)','EXECUTE')
  ),
  'api_helper_denial',jsonb_build_object(
    'service_scope_parser',not has_function_privilege('service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'),
    'service_gate_binder',not has_function_privilege('service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'),
    'anon_scope_parser',not has_function_privilege('anon','private.fn_writer_preimage_scope_v7(text)','EXECUTE'),
    'authenticated_scope_parser',not has_function_privilege('authenticated','private.fn_writer_preimage_scope_v7(text)','EXECUTE')
  ),
  'gate_trigger',(
    select jsonb_build_object(
      'present',count(*)=1,
      'enabled_always',bool_and(t.tgenabled='A'),
      'before_insert',bool_and((t.tgtype & 2)=2 and (t.tgtype & 4)=4)
    )
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private'
      and c.relname='lf_gate_test_runs_v3'
      and t.tgname='trg_05_bind_gate_writer_nonce_v7'
      and not t.tgisinternal
  ),
  'definition_checks',jsonb_build_object(
    'gate_validator_private_nonce',position(
      't.persisted_effects->>''writer_nonce_sha256'''
      in pg_get_functiondef('private.fn_gate_nonce_v7_valid(bigint)'::regprocedure)
    )>0,
    'gate_validator_event_crosscheck',position(
      'e.payload->>''writer_nonce_sha256'''
      in pg_get_functiondef('private.fn_gate_nonce_v7_valid(bigint)'::regprocedure)
    )>0,
    'separation_covers_parser',position(
      'fn_writer_preimage_scope_v7'
      in pg_get_functiondef('private.fn_writer_key_separation_v7_valid()'::regprocedure)
    )>0,
    'separation_covers_binder',position(
      'fn_bind_gate_writer_nonce_v7'
      in pg_get_functiondef('private.fn_writer_key_separation_v7_valid()'::regprocedure)
    )>0
  ),
  'temporary_membership_residual',(
    select count(*)
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in ('lf_writer_verifier_v7','lf_governance_owner_v3')
  )
) as pr93_lote_c_evidence_readback;

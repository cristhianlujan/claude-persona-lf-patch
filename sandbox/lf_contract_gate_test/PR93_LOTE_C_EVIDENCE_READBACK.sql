-- PR #93 / LOTE-E structural readback. SELECT-only.

select jsonb_build_object(
  'functions',jsonb_build_object(
    'gate_binder',to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is not null,
    'gate_validator',to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is not null,
    'separation',to_regprocedure('private.fn_writer_key_separation_v7_valid()') is not null
  ),
  'owners',(
    select jsonb_object_agg(p.proname,pg_get_userbyid(p.proowner))
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname in (
        'fn_bind_gate_writer_nonce_v7',
        'fn_gate_nonce_v7_valid',
        'fn_writer_key_separation_v7_valid'
      )
  ),
  'gate_table',jsonb_build_object(
    'owner',(
      select pg_get_userbyid(c.relowner)
      from pg_class c
      where c.oid='private.lf_gate_test_runs_v3'::regclass
    ),
    'nonce_column',exists(
      select 1
      from information_schema.columns
      where table_schema='private'
        and table_name='lf_gate_test_runs_v3'
        and column_name='writer_nonce_sha256'
    ),
    'nonce_constraint',exists(
      select 1
      from pg_constraint c
      where c.conrelid='private.lf_gate_test_runs_v3'::regclass
        and c.conname='lf_gate_test_runs_v3_writer_nonce_v7_ck'
    ),
    'v7_missing_private_nonce',(
      select count(*)
      from private.lf_gate_test_runs_v3 t
      where t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
        and coalesce(t.writer_nonce_sha256,'') !~ '^[0-9a-f]{64}$'
    )
  ),
  'postgres_helper_execute',jsonb_build_object(
    'scope_parser',has_function_privilege(
      'postgres','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    ),
    'reconciliation_preimage',has_function_privilege(
      'postgres','private.fn_reconciliation_preimage_v7(jsonb,text)','EXECUTE'
    ),
    'gate_preimage',has_function_privilege(
      'postgres','private.fn_gate_preimage_v7(jsonb,text)','EXECUTE'
    ),
    'canonical_json',has_function_privilege(
      'postgres','private.fn_canonical_json_v7(jsonb)','EXECUTE'
    ),
    'payload_sha256',has_function_privilege(
      'postgres','private.fn_payload_sha256_v7(jsonb)','EXECUTE'
    ),
    'frame_component',has_function_privilege(
      'postgres','private.fn_frame_component_v7(text)','EXECUTE'
    )
  ),
  'temporary_creator_acl_removed',not has_function_privilege(
    'postgres','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
  ),
  'api_helper_denial',jsonb_build_object(
    'service_scope_parser',not has_function_privilege(
      'service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    ),
    'service_gate_binder',not has_function_privilege(
      'service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
    ),
    'anon_scope_parser',not has_function_privilege(
      'anon','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    ),
    'authenticated_scope_parser',not has_function_privilege(
      'authenticated','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    )
  ),
  'gate_trigger',(
    select jsonb_build_object(
      'present',count(*)=1,
      'enabled_always',bool_and(t.tgenabled='A'),
      'before_insert_update',bool_and(
        (t.tgtype & 2)=2
        and (t.tgtype & 4)=4
        and (t.tgtype & 16)=16
      ),
      'function_owner',min(pg_get_userbyid(p.proowner))
    )
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    join pg_proc p on p.oid=t.tgfoid
    where n.nspname='private'
      and c.relname='lf_gate_test_runs_v3'
      and t.tgname='trg_05_bind_gate_writer_nonce_v7'
      and not t.tgisinternal
  ),
  'definition_checks',jsonb_build_object(
    'gate_validator_private_nonce_column',position(
      't.writer_nonce_sha256'
      in regexp_replace(
        pg_get_functiondef('private.fn_gate_nonce_v7_valid(bigint)'::regprocedure),
        '\s','','g'
      )
    )>0,
    'gate_validator_event_crosscheck',position(
      'e.payload->>''writer_nonce_sha256'''
      in regexp_replace(
        pg_get_functiondef('private.fn_gate_nonce_v7_valid(bigint)'::regprocedure),
        '\s','','g'
      )
    )>0,
    'gate_validator_effects_crosscheck',position(
      'e.payload->''persisted_effects''=t.persisted_effects'
      in regexp_replace(
        pg_get_functiondef('private.fn_gate_nonce_v7_valid(bigint)'::regprocedure),
        '\s','','g'
      )
    )>0,
    'binder_preserves_persisted_effects',(
      position(
        'new.persisted_effects:='
        in regexp_replace(
pg_get_functiondef('private.fn_bind_gate_writer_nonce_v7()'::regprocedure),
'\s','','g'
        )
      )=0
      and position(
        'new.persisted_effects_sha256:='
        in regexp_replace(
pg_get_functiondef('private.fn_bind_gate_writer_nonce_v7()'::regprocedure),
'\s','','g'
        )
      )=0
    ),
    'binder_blocks_authentication_downgrade',(
      position(
        'old.writer_authentication=''GITHUB_OIDC_HMAC_NONCE_V7'''
        in regexp_replace(
pg_get_functiondef('private.fn_bind_gate_writer_nonce_v7()'::regprocedure),
'\s','','g'
        )
      )>0
      and position(
        'V7gateauthenticationcannotbedowngraded'
        in regexp_replace(
pg_get_functiondef('private.fn_bind_gate_writer_nonce_v7()'::regprocedure),
'\s','','g'
        )
      )>0
    ),
    'separation_covers_parser',position(
      'fn_writer_preimage_scope_v7'
      in regexp_replace(
        pg_get_functiondef('private.fn_writer_key_separation_v7_valid()'::regprocedure),
        '\s','','g'
      )
    )>0,
    'separation_covers_binder',position(
      'fn_bind_gate_writer_nonce_v7'
      in regexp_replace(
        pg_get_functiondef('private.fn_writer_key_separation_v7_valid()'::regprocedure),
        '\s','','g'
      )
    )>0
  ),
  'gate_event_alignment_gaps',(
    select count(*)
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e on e.id=t.evidence_event_id
    where t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and (
        e.payload->>'writer_nonce_sha256' is distinct from t.writer_nonce_sha256
        or e.payload->'persisted_effects' is distinct from t.persisted_effects
        or e.payload->>'persisted_effects_sha256'
           is distinct from t.persisted_effects_sha256
      )
  ),
  'temporary_membership_residual',(
    select count(*)
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in (
        'lf_writer_verifier_v7','lf_governance_owner_v3'
      )
  ),
  'private_create_residual',jsonb_build_object(
    'verifier',has_schema_privilege(
      'lf_writer_verifier_v7','private','CREATE'
    ),
    'governance_owner',has_schema_privilege(
      'lf_governance_owner_v3','private','CREATE'
    )
  )
) as pr93_lote_d_evidence_readback;

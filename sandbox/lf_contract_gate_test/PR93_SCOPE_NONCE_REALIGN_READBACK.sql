-- PR #93 / CA-N39..CA-N42 supplemental readback.
-- SELECT-only. Structural evidence does not replace runtime execution.

select jsonb_build_object(
  'functions',jsonb_build_object(
    'scope_parser',to_regprocedure(
      'private.fn_writer_preimage_scope_v7(text)'
    ) is not null,
    'proof_consumer',to_regprocedure(
      'private.fn_consume_writer_proof_v7(text,text,text)'
    ) is not null,
    'reconciliation_nonce_validator',to_regprocedure(
      'private.fn_reconciliation_nonce_v7_valid(bigint)'
    ) is not null,
    'gate_nonce_validator',to_regprocedure(
      'private.fn_gate_nonce_v7_valid(bigint)'
    ) is not null
  ),
  'scope_vectors',jsonb_build_object(
    'reconciliation',private.fn_writer_preimage_scope_v7(
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object('artifact_id',1,'workflow_run_id',2),
        'READBACK'
      )
    ),
    'gate',private.fn_writer_preimage_scope_v7(
      private.fn_gate_preimage_v7(
        jsonb_build_object('artifact_id',1,'test_code','T'),
        'READBACK'
      )
    ),
    'legacy_rejected',private.fn_writer_preimage_scope_v7(
      'reconciliation-v7:READBACK'
    ) is null,
    'malformed_rejected',private.fn_writer_preimage_scope_v7(
      '17#reconciliation-v7garbage'
    ) is null
  ),
  'active_definition_checks',jsonb_build_object(
    'consumer_uses_scope_parser',position(
      'fn_writer_preimage_scope_v7'
      in pg_get_functiondef(
        'private.fn_consume_writer_proof_v7(text,text,text)'::regprocedure
      )
    )>0,
    'consumer_uses_legacy_scope_like',position(
      'reconciliation-v7:%'
      in pg_get_functiondef(
        'private.fn_consume_writer_proof_v7(text,text,text)'::regprocedure
      )
    )>0,
    'reconciliation_uses_persisted_preimage',position(
      'signed_preimage_sha256'
      in pg_get_functiondef(
        'private.fn_reconciliation_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0,
    'reconciliation_uses_persisted_nonce',position(
      'writer_nonce_sha256'
      in pg_get_functiondef(
        'private.fn_reconciliation_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0,
    'reconciliation_reconstructs_legacy_preimage',position(
      'array_to_string'
      in pg_get_functiondef(
        'private.fn_reconciliation_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0,
    'gate_uses_persisted_preimage',position(
      'signed_preimage_sha256'
      in pg_get_functiondef(
        'private.fn_gate_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0,
    'gate_uses_event_nonce',position(
      'writer_nonce_sha256'
      in pg_get_functiondef(
        'private.fn_gate_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0,
    'gate_reconstructs_legacy_preimage',position(
      'array_to_string'
      in pg_get_functiondef(
        'private.fn_gate_nonce_v7_valid(bigint)'::regprocedure
      )
    )>0
  ),
  'acl',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'function',p.oid::regprocedure::text,
      'owner',pg_get_userbyid(p.proowner),
      'security_definer',p.prosecdef,
      'service_role_execute',has_function_privilege('service_role',p.oid,'EXECUTE'),
      'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
      'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')
    ) order by p.oid::regprocedure::text),'[]'::jsonb)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname in (
        'fn_writer_preimage_scope_v7',
        'fn_consume_writer_proof_v7',
        'fn_reconciliation_nonce_v7_valid',
        'fn_gate_nonce_v7_valid'
      )
  ),
  'temporary_membership_residual',(
    select count(*)
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in (
        'lf_writer_verifier_v7',
        'lf_governance_owner_v3'
      )
  )
) as pr93_v7_scope_nonce_realign_readback;

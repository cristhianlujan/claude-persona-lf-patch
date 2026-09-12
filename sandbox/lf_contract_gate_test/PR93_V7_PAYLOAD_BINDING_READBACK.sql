-- PR #93 / CA-N36..CA-N38 supplemental readback.
-- SELECT-only. Structural evidence does not replace runtime execution.

select jsonb_build_object(
  'helpers',jsonb_build_object(
    'canonical_json',to_regprocedure('private.fn_canonical_json_v7(jsonb)') is not null,
    'payload_sha256',to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is not null,
    'frame_component',to_regprocedure('private.fn_frame_component_v7(text)') is not null,
    'reconciliation_preimage',to_regprocedure(
      'private.fn_reconciliation_preimage_v7(jsonb,text)'
    ) is not null,
    'gate_preimage',to_regprocedure(
      'private.fn_gate_preimage_v7(jsonb,text)'
    ) is not null
  ),
  'owners_and_acl',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'function',p.oid::regprocedure::text,
      'owner',pg_get_userbyid(p.proowner),
      'security_definer',p.prosecdef,
      'volatility',p.provolatile,
      'search_path',p.proconfig,
      'service_role_execute',has_function_privilege('service_role',p.oid,'EXECUTE'),
      'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
      'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')
    ) order by p.oid::regprocedure::text),'[]'::jsonb)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname in (
        'fn_canonical_json_v7',
        'fn_payload_sha256_v7',
        'fn_frame_component_v7',
        'fn_reconciliation_preimage_v7',
        'fn_gate_preimage_v7'
      )
  ),
  'active_definition_checks',jsonb_build_object(
    'reconciliation_uses_payload_hash',position(
      'fn_payload_sha256_v7'
      in pg_get_functiondef(
        'private.fn_reconciliation_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0,
    'gate_uses_payload_hash',position(
      'fn_payload_sha256_v7'
      in pg_get_functiondef(
        'private.fn_gate_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0,
    'reconciliation_uses_length_frame',position(
      'fn_frame_component_v7'
      in pg_get_functiondef(
        'private.fn_reconciliation_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0,
    'gate_uses_length_frame',position(
      'fn_frame_component_v7'
      in pg_get_functiondef(
        'private.fn_gate_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0,
    'reconciliation_uses_raw_delimiter_join',position(
      'array_to_string'
      in pg_get_functiondef(
        'private.fn_reconciliation_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0,
    'gate_uses_raw_delimiter_join',position(
      'array_to_string'
      in pg_get_functiondef(
        'private.fn_gate_preimage_v7(jsonb,text)'::regprocedure
      )
    )>0
  ),
  'shared_vector',jsonb_build_object(
    'canonical',private.fn_canonical_json_v7(jsonb_build_object(
      'z','a:b',
      'a',jsonb_build_array(1,true,null,jsonb_build_object('k','ñ')),
      'n',1.0
    )),
    'sha256',private.fn_payload_sha256_v7(jsonb_build_object(
      'z','a:b',
      'a',jsonb_build_array(1,true,null,jsonb_build_object('k','ñ')),
      'n',1.0
    )),
    'expected_sha256','e6dbf00ab828cd67089efa5d25a5a66011ac7cea845179f9bf997187af77029b'
  ),
  'collision_guards',jsonb_build_object(
    'frame_distribution_distinct',(
      private.fn_frame_component_v7('a:b')||private.fn_frame_component_v7('c')
      is distinct from
      private.fn_frame_component_v7('a')||private.fn_frame_component_v7('b:c')
    ),
    'artifact_path_mutation_distinct',(
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object('artifact_id',1,'artifact_path','skills/a.md'),
        'READBACK'
      )
      is distinct from
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object('artifact_id',1,'artifact_path','skills/b.md'),
        'READBACK'
      )
    ),
    'nested_detail_mutation_distinct',(
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object(
          'artifact_id',1,
          'details',jsonb_build_object('actual_branch_protection_status','VERIFIED')
        ),
        'READBACK'
      )
      is distinct from
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object(
          'artifact_id',1,
          'details',jsonb_build_object('actual_branch_protection_status','FAILED')
        ),
        'READBACK'
      )
    )
  ),
  'temporary_membership_residual',(
    select count(*)
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname='lf_governance_owner_v3'
  )
) as pr93_v7_payload_binding_readback;

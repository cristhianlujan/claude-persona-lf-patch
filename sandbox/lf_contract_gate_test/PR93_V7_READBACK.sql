-- PR #93 V7 readback. SELECT-only. Safe for preview and post-merge production.

select jsonb_build_object(
  'roles',jsonb_build_object(
    'postgres_application_memberships',(
      select count(*)
      from pg_auth_members m
      join pg_roles member_role on member_role.oid=m.member
      join pg_roles granted_role on granted_role.oid=m.roleid
      where member_role.rolname='postgres'
        and granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
    ),
    'application_role_flags',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'role',r.rolname,
        'login',r.rolcanlogin,
        'inherit',r.rolinherit,
        'bypass_rls',r.rolbypassrls
      ) order by r.rolname),'[]'::jsonb)
      from pg_roles r
      where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
    ),
    'governance_public_create',has_schema_privilege('lf_governance_owner_v3','public','CREATE'),
    'governance_private_create',has_schema_privilege('lf_governance_owner_v3','private','CREATE')
  ),
  'writer_key',jsonb_build_object(
    'owner',(
      select pg_get_userbyid(c.relowner)
      from pg_class c
      where c.oid='private.lf_writer_hmac_keys_v7'::regclass
    ),
    'rls',(
      select c.relrowsecurity
      from pg_class c
      where c.oid='private.lf_writer_hmac_keys_v7'::regclass
    ),
    'force_rls',(
      select c.relforcerowsecurity
      from pg_class c
      where c.oid='private.lf_writer_hmac_keys_v7'::regclass
    ),
    'api_roles_can_select',jsonb_build_object(
      'anon',has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT'),
      'authenticated',has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT'),
      'service_role',has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    ),
    'key_ready',private.fn_writer_key_ready_v7()
  ),
  'nonce_registry',jsonb_build_object(
    'owner',(
      select pg_get_userbyid(c.relowner)
      from pg_class c
      where c.oid='private.lf_reconciliation_writer_nonces_v7'::regclass
    ),
    'rls',(
      select c.relrowsecurity
      from pg_class c
      where c.oid='private.lf_reconciliation_writer_nonces_v7'::regclass
    ),
    'force_rls',(
      select c.relforcerowsecurity
      from pg_class c
      where c.oid='private.lf_reconciliation_writer_nonces_v7'::regclass
    ),
    'api_select',jsonb_build_object(
      'anon',has_table_privilege('anon','private.lf_reconciliation_writer_nonces_v7','SELECT'),
      'authenticated',has_table_privilege('authenticated','private.lf_reconciliation_writer_nonces_v7','SELECT'),
      'service_role',has_table_privilege('service_role','private.lf_reconciliation_writer_nonces_v7','SELECT')
    )
  ),
  'writers',jsonb_build_object(
    'v7',jsonb_build_object(
      'reconciliation_service_execute',has_function_privilege(
        'service_role','public.record_external_ci_verification_v7(jsonb,text,text,text)','EXECUTE'
      ),
      'gate_service_execute',has_function_privilege(
        'service_role','public.record_lf_gate_test_v7(jsonb,text,text,text)','EXECUTE'
      ),
      'anon_reconciliation_execute',has_function_privilege(
        'anon','public.record_external_ci_verification_v7(jsonb,text,text,text)','EXECUTE'
      ),
      'authenticated_reconciliation_execute',has_function_privilege(
        'authenticated','public.record_external_ci_verification_v7(jsonb,text,text,text)','EXECUTE'
      )
    ),
    'legacy_service_execute',jsonb_build_object(
      'reconciliation_v5',has_function_privilege(
        'service_role','public.record_external_ci_verification_v5(jsonb,text,text,text)','EXECUTE'
      ),
      'gate_v5',has_function_privilege(
        'service_role','public.record_lf_gate_test_v5(jsonb,text,text,text)','EXECUTE'
      ),
      'reconciliation_v6',has_function_privilege(
        'service_role','public.record_external_ci_verification_v6(jsonb,text,text,text)','EXECUTE'
      ),
      'gate_v6',has_function_privilege(
        'service_role','public.record_lf_gate_test_v6(jsonb,text,text,text)','EXECUTE'
      )
    )
  ),
  'triggers',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'table',c.oid::regclass::text,
      'trigger',t.tgname,
      'enabled',t.tgenabled,
      'definition',pg_get_triggerdef(t.oid,true)
    ) order by c.oid::regclass::text,t.tgname),'[]'::jsonb)
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    where not t.tgisinternal
      and t.tgname in (
        'trg_10_guard_v7_reconciliation_row',
        'trg_10_guard_v7_gate_row',
        'trg_00_guard_lf_github_reconciliation_quarantine_v7'
      )
  ),
  'quarantine',jsonb_build_object(
    'quarantined_rows',(
      select count(*) from private.lf_github_reconciliation_quarantine_v7
    ),
    'unquarantined_legacy_rows',(
      select count(*)
      from private.lf_github_reconciliation_runs_v3 g
      where (
        g.branch_protection_status='VERIFIED_COMPENSATING_CONTROLS'
        or (
          g.result='PASS'
          and g.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
        )
      )
      and not exists (
        select 1
        from private.lf_github_reconciliation_quarantine_v7 q
        where q.reconciliation_run_id=g.id
      )
    )
  ),
  'closure',(
    select to_jsonb(c)
    from public.v_lf_architecture_closure_current c
  ),
  'closure_definition_checks',jsonb_build_object(
    'contains_v7_writer',position(
      'GITHUB_OIDC_HMAC_NONCE_V7'
      in pg_get_viewdef('public.v_lf_architecture_closure_v8'::regclass,true)
    )>0,
    'inherits_token_control_ready',position(
      'token_control_ready'
      in pg_get_viewdef('public.v_lf_architecture_closure_v8'::regclass,true)
    )>0
  ),
  'net_api_exposure_count',private.fn_net_api_exposure_v7_count()
) as pr93_v7_readback;

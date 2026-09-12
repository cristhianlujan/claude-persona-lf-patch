-- PR #93 V7 readback. SELECT-only. It does not prove runtime behavior by itself.

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
    )
  ),
  'writer_key_relation',jsonb_build_object(
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
    'api_access',jsonb_build_object(
      'anon_select',has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT'),
      'authenticated_select',has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT'),
      'service_select',has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT'),
      'service_insert',has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT'),
      'service_update',has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE'),
      'service_delete',has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    ),
    'lifecycle_counts',(
      select jsonb_build_object(
        'prepared',count(*) filter (where lifecycle_state='PREPARED'),
        'active',count(*) filter (where lifecycle_state='ACTIVE'),
        'retiring',count(*) filter (where lifecycle_state='RETIRING'),
        'retired',count(*) filter (where lifecycle_state='RETIRED'),
        'active_flag_mismatches',count(*) filter (
          where active is distinct from (lifecycle_state='ACTIVE')
        ),
        'stale_retiring',count(*) filter (
          where lifecycle_state='RETIRING' and retiring_until<=clock_timestamp()
        ),
        'total',count(*)
      )
      from private.lf_writer_hmac_keys_v7
    ),
    'non_secret_generations',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'key_id',key_id,
        'key_name',key_name,
        'lifecycle_state',lifecycle_state,
        'created_at',created_at,
        'activated_at',activated_at,
        'retiring_at',retiring_at,
        'retiring_until',retiring_until,
        'retired_at',retired_at,
        'installed_by_execution_id',installed_by_execution_id,
        'last_transition_execution_id',last_transition_execution_id
      ) order by created_at,key_id),'[]'::jsonb)
      from private.lf_writer_hmac_keys_v7
    ),
    'key_ready',private.fn_writer_key_ready_v7(),
    'key_separation',private.fn_writer_key_separation_v7_valid()
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
    ),
    'counts',(
      select jsonb_build_object(
        'total',count(*),
        'distinct_nonces',count(distinct nonce_sha256),
        'with_key_id',count(*) filter (where key_id is not null),
        'without_key_id',count(*) filter (where key_id is null),
        'expired_after_consumption',count(*) filter (where expires_at<consumed_at-interval '5 seconds'),
        'beyond_six_minutes',count(*) filter (where expires_at>consumed_at+interval '6 minutes')
      )
      from private.lf_reconciliation_writer_nonces_v7
    )
  ),
  'private_functions',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'function',p.oid::regprocedure::text,
      'owner',pg_get_userbyid(p.proowner),
      'security_definer',p.prosecdef,
      'volatility',p.provolatile,
      'config',p.proconfig,
      'source_md5',md5(p.prosrc),
      'service_role_execute',has_function_privilege('service_role',p.oid,'EXECUTE'),
      'governance_execute',has_function_privilege('lf_governance_owner_v3',p.oid,'EXECUTE')
    ) order by p.oid::regprocedure::text),'[]'::jsonb)
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private'
      and p.proname in (
        'fn_writer_hmac_v7_match_key',
        'fn_writer_hmac_v7_valid',
        'fn_consume_writer_proof_v7',
        'fn_install_writer_hmac_key_v7',
        'fn_writer_hmac_challenge_v7',
        'fn_promote_writer_hmac_key_v7',
        'fn_retire_writer_hmac_key_v7',
        'fn_guard_lf_writer_hmac_keys_v7'
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
        'trg_guard_lf_writer_hmac_keys_v7',
        'trg_10_guard_v7_reconciliation_row',
        'trg_10_guard_v7_gate_row',
        'trg_00_guard_lf_github_reconciliation_quarantine_v7'
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

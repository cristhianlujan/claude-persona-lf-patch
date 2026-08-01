-- PR #93 / CA-N30..CA-N35 supplemental readback.
-- SELECT-only. It validates structure and metadata, not runtime behavior.

select jsonb_build_object(
  'canonicalization',jsonb_build_object(
    'reconciliation_helper',to_regprocedure(
      'private.fn_reconciliation_preimage_v7(jsonb,text)'
    ) is not null,
    'gate_helper',to_regprocedure(
      'private.fn_gate_preimage_v7(jsonb,text)'
    ) is not null,
    'reconciliation_writer_uses_helper',position(
      'fn_reconciliation_preimage_v7'
      in pg_get_functiondef(
        'public.record_external_ci_verification_v7(jsonb,text,text,text)'::regprocedure
      )
    )>0,
    'gate_writer_uses_helper',position(
      'fn_gate_preimage_v7'
      in pg_get_functiondef(
        'public.record_lf_gate_test_v7(jsonb,text,text,text)'::regprocedure
      )
    )>0,
    'reconciliation_writer_uses_concat_ws',position(
      'concat_ws'
      in pg_get_functiondef(
        'public.record_external_ci_verification_v7(jsonb,text,text,text)'::regprocedure
      )
    )>0,
    'gate_writer_uses_concat_ws',position(
      'concat_ws'
      in pg_get_functiondef(
        'public.record_lf_gate_test_v7(jsonb,text,text,text)'::regprocedure
      )
    )>0,
    'position_collision_rejected',(
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object(
          'artifact_id',1,
          'workflow_run_id',2,
          'merge_commit_sha',repeat('a',40),
          'artifact_sha256',null,
          'branch_protection_status','VERIFIED',
          'result','FAIL',
          'audit_manifest_sha256',repeat('b',64)
        ),
        'READBACK'
      )
      is distinct from
      private.fn_reconciliation_preimage_v7(
        jsonb_build_object(
          'artifact_id',1,
          'workflow_run_id',2,
          'merge_commit_sha',repeat('a',40),
          'artifact_sha256','VERIFIED',
          'branch_protection_status',null,
          'result','FAIL',
          'audit_manifest_sha256',repeat('b',64)
        ),
        'READBACK'
      )
    )
  ),
  'keystore_rls',jsonb_build_object(
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
    'postgres_policy',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'policy',p.policyname,
        'cmd',p.cmd,
        'roles',p.roles,
        'qual',p.qual,
        'with_check',p.with_check
      )),'[]'::jsonb)
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
    ),
    'separation_valid',private.fn_writer_key_separation_v7_valid(),
    'rotation_status',private.fn_writer_key_rotation_status_v7()
  ),
  'nonce_insert_policy',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'policy',p.policyname,
      'cmd',p.cmd,
      'roles',p.roles,
      'with_check',p.with_check,
      'requires_key_id',position('KEY_ID IS NOT NULL' in upper(coalesce(p.with_check,'')))>0
    )),'[]'::jsonb)
    from pg_policies p
    where p.schemaname='private'
      and p.tablename='lf_reconciliation_writer_nonces_v7'
      and p.policyname='pol_lf_writer_nonce_v7_insert'
  ),
  'state_time_constraint',(
    select jsonb_build_object(
      'name',c.conname,
      'definition',pg_get_constraintdef(c.oid,true),
      'retired_overlap_order_checked',position(
        'retiring_until >= retiring_at'
        in pg_get_constraintdef(c.oid,true)
      )>0
    )
    from pg_constraint c
    where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and c.conname='lf_writer_hmac_keys_v7_state_times_ck'
  ),
  'truncate_guards',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'relation',t.tgrelid::regclass::text,
      'trigger',t.tgname,
      'enabled',t.tgenabled,
      'definition',pg_get_triggerdef(t.oid,true)
    ) order by t.tgrelid::regclass::text,t.tgname),'[]'::jsonb)
    from pg_trigger t
    where not t.tgisinternal
      and t.tgname in (
        'trg_block_lf_writer_hmac_keys_v7_truncate',
        'trg_block_lf_writer_nonces_v7_truncate'
      )
  ),
  'private_api_exposure',jsonb_build_object(
    'service_reconciliation_helper',has_function_privilege(
      'service_role','private.fn_reconciliation_preimage_v7(jsonb,text)','EXECUTE'
    ),
    'service_gate_helper',has_function_privilege(
      'service_role','private.fn_gate_preimage_v7(jsonb,text)','EXECUTE'
    ),
    'service_rotation_status',has_function_privilege(
      'service_role','private.fn_writer_key_rotation_status_v7()','EXECUTE'
    ),
    'service_truncate_guard',has_function_privilege(
      'service_role','private.fn_block_writer_security_truncate_v7()','EXECUTE'
    )
  )
) as pr93_v7_hardening_readback;

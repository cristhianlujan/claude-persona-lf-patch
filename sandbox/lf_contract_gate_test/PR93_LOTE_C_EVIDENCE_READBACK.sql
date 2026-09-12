-- PR #93 / LOTE-E structural readback. SELECT-only.
-- LOTE-E.4: repair INTO matching, pin trigger-to-function linkage,
-- cover quoted identifiers and retain exact fail-closed binder body pinning.

with mutation_patterns as (
  select
    '(^|;|\mbegin\M|\mthen\M|\melse\M|\mloop\M)\s*new\M\s*\.\s*"?persisted_effects(_sha256)?\M"?\s*(:=|=)'::text
      as direct_field_assignment,
    '(^|;|\mbegin\M|\mthen\M|\melse\M|\mloop\M)\s*new\M\s*(:=|=)'::text
      as whole_record_assignment,
    '\m[a-z]*?(?:select|execute|returning|fetch)\M[^;]*?\minto\M\s+(?:strict\s+)?([^;]*?)(?:\mfrom\M|\musing\M|;)'::text
      as into_assignment_statement,
    '(^|,)\s*new\M(?:\s*\.\s*"?persisted_effects(_sha256)?\M"?)?\s*(,|$)'::text
      as into_assignment_target,
    '/\*([^*]|\*+[^*/])*\*+/'::text
      as block_comment,
    E'--[^\\r\\n]*'::text
      as line_comment
),
binder_source as (
  select coalesce((
    select p.prosrc
    from pg_proc p
    where p.oid=to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
  ),'') as source_text
),
mutation_vectors(vector_name,source_text,expected_mutation) as (
  values
    ('direct_colon_equals',
     'begin new.persisted_effects := ''{}''::jsonb; end',true),
    ('direct_equals_with_spaced_dot',
     'begin new . persisted_effects_sha256 = ''x''; end',true),
    ('direct_after_line_comment',
     E'BEGIN\n -- normalise\n NEW.persisted_effects := ''{}''::jsonb;\nEND',true),
    ('direct_after_block_comment',
     'BEGIN /* normalise */ NEW.persisted_effects_sha256 := ''x''; END',true),
    ('direct_quoted_identifier',
     'begin new."persisted_effects" := ''{}''::jsonb; end',true),
    ('select_into_first_target',
     'begin select payload into new.persisted_effects from t; end',true),
    ('select_into_later_target',
     'begin select payload,hash into v_other, new . persisted_effects_sha256 from t; end',true),
    ('execute_into_first_target',
     'begin execute v_sql into new.persisted_effects using p_id; end',true),
    ('execute_into_later_target',
     'begin execute v_sql into v_other,new.persisted_effects_sha256 using p_id; end',true),
    ('returning_into_first_target',
     'begin insert into t values(1) returning payload into new.persisted_effects; end',true),
    ('returning_into_later_target',
     'begin update t set x=1 returning payload,hash into v_other,new.persisted_effects_sha256; end',true),
    ('fetch_into_target',
     'begin fetch c into new.persisted_effects; end',true),
    ('whole_record_direct',
     'begin new := old; end',true),
    ('whole_record_select_into',
     'begin select row(payload,hash) into new from t; end',true),
    ('select_into_quoted_target',
     'begin select payload into new."persisted_effects_sha256" from t; end',true),
    ('read_json_operator',
     'begin perform new.persisted_effects->>''x''; end',false),
    ('read_cast',
     'begin v := new.persisted_effects::text; end',false),
    ('comparison_is_distinct',
     'begin if new.persisted_effects is distinct from old.persisted_effects then null; end if; end',false),
    ('comparison_equals',
     'begin if new.persisted_effects = old.persisted_effects then null; end if; end',false),
    ('select_into_other_then_read',
     'begin select x into v from t where y=new.persisted_effects; end',false),
    ('execute_without_into_read',
     'begin execute v_sql using new.persisted_effects; end',false),
    ('returning_into_other_then_read',
     'begin insert into t values(new.persisted_effects) returning payload into v_other; end',false),
    ('insert_into_read',
     'begin insert into log(payload) values(new.persisted_effects); end',false),
    ('line_comment_only',
     E'begin\n-- new.persisted_effects := ''{}''::jsonb;\nperform 1;\nend',false),
    ('block_comment_only',
     'begin /* new.persisted_effects_sha256 := ''x''; */ perform 1; end',false)
),
sources(source_kind,vector_name,source_text,expected_mutation) as (
  select 'binder'::text,null::text,binder_source.source_text,null::boolean
  from binder_source
  union all
  select 'vector',vector_name,source_text,expected_mutation
  from mutation_vectors
),
normalized_sources as (
  select
    sources.source_kind,
    sources.vector_name,
    sources.expected_mutation,
    sources.source_text as raw_source,
    lower(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            sources.source_text,
            mutation_patterns.block_comment,
            '',
            'g'
          ),
          mutation_patterns.line_comment,
          '',
          'g'
        ),
        '\s+',
        ' ',
        'g'
      )
    ) as spaced,
    regexp_replace(
      regexp_replace(
        regexp_replace(
          sources.source_text,
          mutation_patterns.block_comment,
          '',
          'g'
        ),
        mutation_patterns.line_comment,
        '',
        'g'
      ),
      '\s',
      '',
      'g'
    ) as stripped
  from sources
  cross join mutation_patterns
),
binder_def as (
  select
    normalized_sources.spaced,
    normalized_sources.stripped,
    encode(
      extensions.digest(
        convert_to(normalized_sources.raw_source,'UTF8'),
        'sha256'
      ),
      'hex'
    ) as prosrc_sha256
  from normalized_sources
  where normalized_sources.source_kind='binder'
),
expected_binder as (
  select '3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293'::text
    as prosrc_sha256
),
binder_mutation_check as (
  select
    binder_def.spaced ~ mutation_patterns.direct_field_assignment
    or binder_def.spaced ~ mutation_patterns.whole_record_assignment
    or exists(
      select 1
      from regexp_matches(
        binder_def.spaced,
        mutation_patterns.into_assignment_statement,
        'g'
      ) as matched(captures)
      where (matched.captures)[1] ~ mutation_patterns.into_assignment_target
    ) as mutates_signed_effects
  from binder_def
  cross join mutation_patterns
),
mutation_vector_results as (
  select
    normalized_sources.vector_name,
    normalized_sources.expected_mutation,
    normalized_sources.spaced ~ mutation_patterns.direct_field_assignment
    or normalized_sources.spaced ~ mutation_patterns.whole_record_assignment
    or exists(
      select 1
      from regexp_matches(
        normalized_sources.spaced,
        mutation_patterns.into_assignment_statement,
        'g'
      ) as matched(captures)
      where (matched.captures)[1] ~ mutation_patterns.into_assignment_target
    ) as detected_mutation
  from normalized_sources
  cross join mutation_patterns
  where normalized_sources.source_kind='vector'
),
mutation_pattern_controls as (
  select
    bool_and(detected_mutation=expected_mutation) as all_pass,
    jsonb_object_agg(
      vector_name,
      jsonb_build_object(
        'expected',expected_mutation,
        'detected',detected_mutation,
        'pass',detected_mutation=expected_mutation
      )
      order by vector_name
    ) as cases
  from mutation_vector_results
)
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
  'temporary_creator_acl_removed',coalesce((
    select p.proacl is not null
       and not exists(
         select 1
         from aclexplode(p.proacl) acl
         where acl.grantee=(select r.oid from pg_roles r where r.rolname='postgres')
           and acl.privilege_type='EXECUTE'
       )
    from pg_proc p
    where p.oid='private.fn_bind_gate_writer_nonce_v7()'::regprocedure
  ),false),
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
      'binds_pinned_function',coalesce(bool_and(
        t.tgfoid=to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
      ),false),
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
      binder_def.prosrc_sha256=expected_binder.prosrc_sha256
      and not binder_mutation_check.mutates_signed_effects
      and mutation_pattern_controls.all_pass
    ),
    'binder_definition_digest',jsonb_build_object(
      'expected',expected_binder.prosrc_sha256,
      'actual',binder_def.prosrc_sha256,
      'matches',binder_def.prosrc_sha256=expected_binder.prosrc_sha256
    ),
    'binder_mutation_pattern_controls',jsonb_build_object(
      'all_pass',mutation_pattern_controls.all_pass,
      'cases',mutation_pattern_controls.cases
    ),
    'binder_blocks_authentication_downgrade',(
      position(
        'old.writer_authentication=''GITHUB_OIDC_HMAC_NONCE_V7'''
        in binder_def.stripped
      )>0
      and position(
        'V7gateauthenticationcannotbedowngraded'
        in binder_def.stripped
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
    )>0,
    'verifier_definition_excludes_expired_retiring_keys_definition_only',position(
      'retiring_until>clock_timestamp()'
      in regexp_replace(
        pg_get_functiondef(
          'private.fn_writer_hmac_v7_match_key(text,text,text)'::regprocedure
        ),
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
) as pr93_lote_e_evidence_readback
from binder_def
cross join expected_binder
cross join binder_mutation_check
cross join mutation_pattern_controls;

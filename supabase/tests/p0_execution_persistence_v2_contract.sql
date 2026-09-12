-- P0 execution persistence V2 transactional/adversarial contract.
-- Verified against Supabase project mhwmirqcgxxukpctffuv on 2026-08-12.
-- Expected: 20/20 PASS and ROLLBACK; this script must leave no rows behind.

begin;

create or replace function pg_temp.p0_bundle_v2(
  p_execution_id text,
  p_loop_version text default 'p0-test-valid-loop-v2',
  p_terminal_state text default 'COMPLETE',
  p_verdict text default 'PASS',
  p_supersedes_execution_id text default null
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'execution', jsonb_build_object(
      'execution_id', p_execution_id,
      'started_at', '2026-08-12T12:30:00Z',
      'completed_at', '2026-08-12T12:31:00Z',
      'terminal_state', p_terminal_state,
      'verdict', p_verdict,
      'source_ref', 'test://source.png',
      'source_sha256', repeat('a', 64),
      'source_width', 1536,
      'source_height', 1024,
      'source_mime_type', 'image/png',
      'code_head_sha', repeat('b', 40),
      'loop_version', p_loop_version,
      'configuration_id', 'P0-TEST-V2',
      'configuration_sha256', repeat('c', 64),
      'languages', jsonb_build_array('spa', 'eng'),
      'dependencies', jsonb_build_object('tesseract', '5.3.4', 'opencv', '4.13.0.92'),
      'acceptance_declared', false,
      'autonomous_system_ready', false,
      'p0_5_authorized', false,
      'production_authorized', false,
      'unresolved_critical', 0,
      'unresolved_high', 0,
      'unresolved_medium', 0,
      'mutation_escapes', 0,
      'supersedes_execution_id', p_supersedes_execution_id,
      'supersession_reason', case when p_supersedes_execution_id is null then null else 'TEST_SUPERSESSION' end
    ),
    'elements', jsonb_build_array(
      jsonb_build_object(
        'element_id', 'ROOT', 'parent_element_id', null, 'element_type', 'ROOT', 'visible_text', null,
        'bbox', jsonb_build_object('x', 0, 'y', 0, 'width', 1536, 'height', 1024),
        'cardinality', 1, 'confidence', 1, 'modality', 'SOURCE', 'payload', '{}'::jsonb
      ),
      jsonb_build_object(
        'element_id', 'FIELD-1', 'parent_element_id', 'ROOT', 'element_type', 'TEXT',
        'visible_text', 'Nombre completo',
        'bbox', jsonb_build_object('x', 600, 'y', 311, 'width', 131, 'height', 20),
        'cardinality', 1, 'confidence', 0.95, 'modality', 'OCR', 'payload', '{}'::jsonb
      )
    ),
    'evidence_units', jsonb_build_array(
      jsonb_build_object(
        'evidence_unit_id', 'EV-ROOT', 'evidence_kind', 'SOURCE_REGION',
        'evidence_ref', 'p0://test/evidence/root', 'content_sha256', repeat('2', 64),
        'bbox', jsonb_build_object('x', 0, 'y', 0, 'width', 1536, 'height', 1024),
        'modality', 'SOURCE', 'payload', '{}'::jsonb
      ),
      jsonb_build_object(
        'evidence_unit_id', 'EV-1', 'evidence_kind', 'TEXT_CROP',
        'evidence_ref', 'p0://test/evidence/ev-1', 'content_sha256', repeat('d', 64),
        'bbox', jsonb_build_object('x', 600, 'y', 311, 'width', 131, 'height', 20),
        'modality', 'OCR', 'payload', '{}'::jsonb
      )
    ),
    'element_evidence', jsonb_build_array(
      jsonb_build_object('element_id', 'ROOT', 'evidence_unit_id', 'EV-ROOT', 'relationship', 'SUPPORTS'),
      jsonb_build_object('element_id', 'FIELD-1', 'evidence_unit_id', 'EV-1', 'relationship', 'TEXT_TOKEN')
    ),
    'records', jsonb_build_array(
      jsonb_build_object('record_kind', 'RULE', 'record_id', 'INV-1', 'stage', 'P-01', 'rule_version', 'v2', 'severity', 'INFO', 'status', 'APPLIED', 'payload', '{}'::jsonb),
      jsonb_build_object('record_kind', 'VALIDATION', 'record_id', 'VAL-1', 'stage', 'P-02', 'rule_version', 'v2', 'severity', 'INFO', 'status', 'PASS', 'payload', '{}'::jsonb),
      jsonb_build_object('record_kind', 'PASS_RESULT', 'record_id', 'P-03', 'stage', 'P-03', 'rule_version', 'v2', 'severity', 'INFO', 'status', p_verdict, 'payload', '{}'::jsonb)
    ),
    'artifacts', jsonb_build_array(
      jsonb_build_object('artifact_id', 'SOURCE-1', 'artifact_role', 'SOURCE', 'artifact_ref', 'git://test/source.png', 'content_sha256', repeat('a', 64), 'content_bytes', 2048, 'external_evidence_ref', null, 'payload', '{}'::jsonb),
      jsonb_build_object('artifact_id', 'CONFIG-1', 'artifact_role', 'CONFIGURATION', 'artifact_ref', 'git://test/config.json', 'content_sha256', repeat('c', 64), 'content_bytes', 512, 'external_evidence_ref', null, 'payload', '{}'::jsonb),
      jsonb_build_object('artifact_id', 'RECEIPT-1', 'artifact_role', 'RECEIPT', 'artifact_ref', 'git://test/receipt.json', 'content_sha256', repeat('e', 64), 'content_bytes', 1024, 'external_evidence_ref', null, 'payload', '{}'::jsonb),
      jsonb_build_object('artifact_id', 'MANIFEST-1', 'artifact_role', 'MANIFEST', 'artifact_ref', 'git://test/manifest.json', 'content_sha256', repeat('f', 64), 'content_bytes', 768, 'external_evidence_ref', null, 'payload', '{}'::jsonb),
      jsonb_build_object('artifact_id', 'AUDIT-1', 'artifact_role', 'AUDIT', 'artifact_ref', 'git://test/audit.json', 'content_sha256', repeat('1', 64), 'content_bytes', 640, 'external_evidence_ref', null, 'payload', '{}'::jsonb)
    ),
    'transitions', jsonb_build_array(
      jsonb_build_object('transition_ordinal', 0, 'from_state', null, 'to_state', 'P-01', 'occurred_at', '2026-08-12T12:30:00Z', 'reason', 'START', 'payload', '{}'::jsonb),
      jsonb_build_object('transition_ordinal', 1, 'from_state', 'P-01', 'to_state', 'COMPLETE', 'occurred_at', '2026-08-12T12:31:00Z', 'reason', 'VALIDATED', 'payload', '{}'::jsonb)
    )
  );
$$;

create temporary table _p0_v2_contract_results(
  check_code text primary key,
  outcome text not null
) on commit drop;

do $suite$
declare
  v_bundle jsonb;
  v_result jsonb;
  v_reconstructed jsonb;
  v_failed boolean;
begin
  -- C01: complete atomic insert + reconstruction.
  v_bundle := pg_temp.p0_bundle_v2('P0-CONTRACT-V2-BASE');
  v_result := private.fn_persist_lf_p0_execution_v1(v_bundle);
  if v_result->>'outcome' <> 'INSERTED' then raise exception 'C01_INSERT_FAILED'; end if;
  v_reconstructed := private.fn_reconstruct_lf_p0_execution_v1('P0-CONTRACT-V2-BASE');
  if v_reconstructed->'execution'->>'execution_id' <> 'P0-CONTRACT-V2-BASE'
     or jsonb_array_length(v_reconstructed->'elements') <> 2
     or jsonb_array_length(v_reconstructed->'evidence_units') <> 2
     or jsonb_array_length(v_reconstructed->'element_evidence') <> 2
     or jsonb_array_length(v_reconstructed->'records') <> 3
     or jsonb_array_length(v_reconstructed->'artifacts') <> 5
     or jsonb_array_length(v_reconstructed->'transitions') <> 2 then
    raise exception 'C01_RECONSTRUCTION_INCOMPLETE';
  end if;
  insert into _p0_v2_contract_results values ('C01', 'PASS');

  -- C02: exact retry is idempotent and traceable.
  v_result := private.fn_persist_lf_p0_execution_v1(v_bundle);
  if v_result->>'outcome' <> 'IDEMPOTENT_REPLAY'
     or (select count(*) from private.lf_p0_execution_persist_attempts_v1 where execution_id='P0-CONTRACT-V2-BASE') <> 2 then
    raise exception 'C02_IDEMPOTENCY_FAILED';
  end if;
  insert into _p0_v2_contract_results values ('C02', 'PASS');

  -- C03: same execution_id with changed content conflicts.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(jsonb_set(v_bundle, '{execution,source_ref}', '"test://changed.png"'));
  exception when unique_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C03_CONFLICT_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C03', 'PASS');

  -- C04: bad child/evidence reference rejects the complete attempt and leaves no run.
  -- V2 may fail earlier on LF_P0_ORPHAN_EVIDENCE_UNIT, so check_violation is accepted
  -- as the stronger fail-closed outcome in addition to FK rejection.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-ATOMIC'), '{element_evidence,1,evidence_unit_id}', '"EV-MISSING"')
    );
  exception when check_violation or foreign_key_violation then v_failed := true;
  end;
  if not v_failed or exists(select 1 from private.lf_p0_execution_runs_v1 where execution_id='P0-CONTRACT-V2-ATOMIC') then
    raise exception 'C04_PARTIAL_WRITE_SURVIVED';
  end if;
  insert into _p0_v2_contract_results values ('C04', 'PASS');

  -- C05: one evidence unit cannot own/support two material elements in PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(
        pg_temp.p0_bundle_v2('P0-CONTRACT-V2-EXCLUSIVE'),
        '{element_evidence}',
        jsonb_build_array(
          jsonb_build_object('element_id','ROOT','evidence_unit_id','EV-1','relationship','SUPPORTS'),
          jsonb_build_object('element_id','FIELD-1','evidence_unit_id','EV-1','relationship','TEXT_TOKEN')
        )
      )
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C05_EVIDENCE_CONTAMINATION_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C05', 'PASS');

  -- C06: incomplete terminal state cannot emit PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-INCOMPLETE', 'p0-test-valid-loop-v2', 'BLOCKED', 'PASS'));
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C06_INCOMPLETE_PASS_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C06', 'PASS');

  -- C07: invalidated loop cannot emit a new PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-INVALIDATED', 'p0-v4-r2-pre-atomicity'));
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C07_INVALIDATED_PASS_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C07', 'PASS');

  -- C08: execution graphs are isolated.
  perform private.fn_persist_lf_p0_execution_v1(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-ISOLATED'));
  if (select count(*) from private.lf_p0_execution_elements_v1 where execution_id='P0-CONTRACT-V2-BASE') <> 2
     or (select count(*) from private.lf_p0_execution_elements_v1 where execution_id='P0-CONTRACT-V2-ISOLATED') <> 2 then
    raise exception 'C08_EXECUTION_ISOLATION_FAILED';
  end if;
  insert into _p0_v2_contract_results values ('C08', 'PASS');

  -- C09: supersession is append-only lineage, not mutation.
  perform private.fn_persist_lf_p0_execution_v1(
    pg_temp.p0_bundle_v2('P0-CONTRACT-V2-SUPERSEDING', 'p0-test-valid-loop-v2', 'COMPLETE', 'PASS', 'P0-CONTRACT-V2-BASE')
  );
  if private.fn_reconstruct_lf_p0_execution_v1('P0-CONTRACT-V2-SUPERSEDING')->'execution'->>'supersedes_execution_id' <> 'P0-CONTRACT-V2-BASE' then
    raise exception 'C09_SUPERSESSION_LINEAGE_MISSING';
  end if;
  insert into _p0_v2_contract_results values ('C09', 'PASS');

  -- C10: persisted rows are immutable.
  v_failed := false;
  begin
    update private.lf_p0_execution_runs_v1 set verdict='BLOCKED' where execution_id='P0-CONTRACT-V2-BASE';
  exception when object_not_in_prerequisite_state then v_failed := true;
  end;
  if not v_failed then raise exception 'C10_APPEND_ONLY_UPDATE_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C10', 'PASS');

  -- C11: private tables/RPCs are inaccessible to API users; service_role uses RPC only.
  if has_table_privilege('anon','private.lf_p0_execution_runs_v1','select')
     or has_table_privilege('authenticated','private.lf_p0_execution_elements_v1','select')
     or has_function_privilege('anon','private.fn_persist_lf_p0_execution_v1(jsonb)','execute')
     or has_function_privilege('authenticated','private.fn_reconstruct_lf_p0_execution_v1(text)','execute')
     or has_table_privilege('service_role','private.lf_p0_execution_runs_v1','select')
     or not has_function_privilege('service_role','private.fn_persist_lf_p0_execution_v1(jsonb)','execute') then
    raise exception 'C11_ACL_CONTRACT_FAILED';
  end if;
  insert into _p0_v2_contract_results values ('C11', 'PASS');

  -- C12: every PASS element needs evidence.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(
        pg_temp.p0_bundle_v2('P0-CONTRACT-V2-UNLINKED-ELEMENT'),
        '{element_evidence}',
        jsonb_build_array(jsonb_build_object('element_id','FIELD-1','evidence_unit_id','EV-1','relationship','TEXT_TOKEN'))
      )
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C12_UNLINKED_ELEMENT_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C12', 'PASS');

  -- C13: failed validation blocks PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-VALIDATION-FAIL'), '{records,1,status}', '"FAIL"')
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C13_FAILED_VALIDATION_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C13', 'PASS');

  -- C14: SOURCE/CONFIGURATION/RECEIPT/MANIFEST/AUDIT are mandatory for PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-NO-MANIFEST'), '{artifacts,3,artifact_role}', '"AUDIT"')
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C14_MISSING_ARTIFACT_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C14', 'PASS');

  -- C15: final ordered transition must be COMPLETE.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-BAD-FINAL'), '{transitions,1,to_state}', '"P-03"')
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C15_BAD_FINAL_TRANSITION_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C15', 'PASS');

  -- C16: PASS requires dependency provenance.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-NO-DEPS'), '{execution,dependencies}', '{}'::jsonb)
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C16_EMPTY_DEPENDENCIES_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C16', 'PASS');

  -- C17: orphan evidence is rejected.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(
        pg_temp.p0_bundle_v2('P0-CONTRACT-V2-ORPHAN-EVIDENCE'),
        '{evidence_units}',
        (pg_temp.p0_bundle_v2('X')->'evidence_units') || jsonb_build_array(
          jsonb_build_object(
            'evidence_unit_id','EV-ORPHAN','evidence_kind','TEXT_CROP',
            'evidence_ref','p0://test/evidence/orphan','content_sha256',repeat('3',64),
            'bbox',jsonb_build_object('x',10,'y',10,'width',10,'height',10),
            'modality','OCR','payload','{}'::jsonb
          )
        )
      )
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C17_ORPHAN_EVIDENCE_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C17', 'PASS');

  -- C18: SOURCE artifact hash must bind execution source hash.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-SOURCE-HASH'), '{artifacts,0,content_sha256}', to_jsonb(repeat('4',64)))
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C18_SOURCE_HASH_MISMATCH_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C18', 'PASS');

  -- C19: CONFIGURATION artifact hash must bind execution configuration hash.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(pg_temp.p0_bundle_v2('P0-CONTRACT-V2-CONFIG-HASH'), '{artifacts,1,content_sha256}', to_jsonb(repeat('5',64)))
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C19_CONFIG_HASH_MISMATCH_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C19', 'PASS');

  -- C20: unresolved blocking record cannot coexist with PASS.
  v_failed := false;
  begin
    perform private.fn_persist_lf_p0_execution_v1(
      jsonb_set(
        pg_temp.p0_bundle_v2('P0-CONTRACT-V2-BLOCKING-RECORD'),
        '{records}',
        (pg_temp.p0_bundle_v2('X')->'records') || jsonb_build_array(
          jsonb_build_object('record_kind','OMISSION','record_id','OM-1','stage','P-02','rule_version','v2','severity','MEDIUM','status','OPEN','payload','{}'::jsonb)
        )
      )
    );
  exception when check_violation then v_failed := true;
  end;
  if not v_failed then raise exception 'C20_BLOCKING_RECORD_ACCEPTED'; end if;
  insert into _p0_v2_contract_results values ('C20', 'PASS');
end;
$suite$;

select jsonb_build_object(
  'suite', 'P0_EXECUTION_PERSISTENCE_V2_CONTRACT',
  'status', case when count(*)=20 and bool_and(outcome='PASS') then 'PASS' else 'FAIL' end,
  'checks', count(*),
  'check_codes', jsonb_agg(check_code order by check_code),
  'committed_rows', 0
) as result
from _p0_v2_contract_results;

rollback;

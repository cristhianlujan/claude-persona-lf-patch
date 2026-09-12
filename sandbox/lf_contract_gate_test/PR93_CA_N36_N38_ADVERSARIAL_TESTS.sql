-- PR #93 / CA-N36..CA-N38 adversarial tests.
-- Isolated environment only. No persisted effects are expected.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_canonical_json_v7(jsonb)') is null
     or to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null then
    raise exception 'CA-N36..CA-N38 helpers are missing';
  end if;
end
$preflight$;

-- Shared Edge/PostgreSQL test vector. Object keys are sorted, arrays preserve order,
-- strings retain Unicode and colon characters, and 1.0 canonicalizes to integer 1.
do $canonical_vector$
declare
  v_payload jsonb:=jsonb_build_object(
    'z','a:b',
    'a',jsonb_build_array(1,true,null,jsonb_build_object('k','ñ')),
    'n',1.0
  );
  v_canonical text;
  v_hash text;
begin
  v_canonical:=private.fn_canonical_json_v7(v_payload);
  v_hash:=private.fn_payload_sha256_v7(v_payload);

  if v_canonical is distinct from '{"a":[1,true,null,{"k":"ñ"}],"n":1,"z":"a:b"}' then
    raise exception 'CANONICAL_VECTOR_FAILED: %',v_canonical;
  end if;
  if v_hash is distinct from 'e6dbf00ab828cd67089efa5d25a5a66011ac7cea845179f9bf997187af77029b' then
    raise exception 'CANONICAL_HASH_FAILED: %',v_hash;
  end if;
end
$canonical_vector$;

-- Key insertion order must not change the signed payload digest.
do $key_order$
declare
  v_left jsonb:='{"b":2,"a":1}'::jsonb;
  v_right jsonb:='{"a":1,"b":2}'::jsonb;
begin
  if private.fn_payload_sha256_v7(v_left)
     is distinct from private.fn_payload_sha256_v7(v_right) then
    raise exception 'KEY_ORDER_FAILED: equivalent objects produced different hashes';
  end if;
end
$key_order$;

-- CA-N36: length framing must distinguish different distributions of ':' characters.
do $separator_injection$
declare
  v_left text;
  v_right text;
  v_gate_left text;
  v_gate_right text;
begin
  v_left:=private.fn_frame_component_v7('a:b')||private.fn_frame_component_v7('c');
  v_right:=private.fn_frame_component_v7('a')||private.fn_frame_component_v7('b:c');
  if v_left=v_right then
    raise exception 'FRAME_COLLISION_FAILED: length framing collided';
  end if;

  v_gate_left:=private.fn_gate_preimage_v7(
    jsonb_build_object('test_code','a:b','source_workflow_run_id',3),
    'EXEC:1'
  );
  v_gate_right:=private.fn_gate_preimage_v7(
    jsonb_build_object('test_code','a','source_workflow_run_id','b:3'),
    'EXEC:1'
  );
  if v_gate_left=v_gate_right then
    raise exception 'PAYLOAD_SEPARATOR_COLLISION_FAILED';
  end if;
end
$separator_injection$;

-- CA-N37: every payload mutation, including formerly unsigned authorization fields,
-- must change the signed preimage.
do $full_payload_binding$
declare
  v_base jsonb:=jsonb_build_object(
    'result','PASS',
    'artifact_id',1,
    'repository','cristhianlujan/claude-persona-lf-patch',
    'target_branch','main',
    'artifact_path','skills/a.md',
    'merged',true,
    'merge_commit_sha',repeat('a',40),
    'workflow_run_id',123,
    'workflow_conclusion','success',
    'file_touched_by_merge',true,
    'artifact_exercised_by_workflow',true,
    'audit_manifest_sha256',repeat('b',64),
    'branch_protection_status','VERIFIED',
    'failure_reasons',jsonb_build_array(),
    'details',jsonb_build_object('actual_branch_protection_status','VERIFIED')
  );
  v_original text;
begin
  v_original:=private.fn_reconciliation_preimage_v7(v_base,'EXEC-BIND');

  if v_original=private.fn_reconciliation_preimage_v7(
    jsonb_set(v_base,'{artifact_path}','"skills/other.md"'::jsonb),
    'EXEC-BIND'
  ) then
    raise exception 'FULL_BINDING_FAILED: artifact_path mutation was not signed';
  end if;

  if v_original=private.fn_reconciliation_preimage_v7(
    jsonb_set(v_base,'{details,actual_branch_protection_status}','"FAILED"'::jsonb),
    'EXEC-BIND'
  ) then
    raise exception 'FULL_BINDING_FAILED: branch protection detail mutation was not signed';
  end if;

  if v_original=private.fn_reconciliation_preimage_v7(
    jsonb_set(v_base,'{failure_reasons}',jsonb_build_array('MUTATED')),
    'EXEC-BIND'
  ) then
    raise exception 'FULL_BINDING_FAILED: failure_reasons mutation was not signed';
  end if;

  if v_original=private.fn_reconciliation_preimage_v7(
    jsonb_set(v_base,'{merged}','false'::jsonb),
    'EXEC-BIND'
  ) then
    raise exception 'FULL_BINDING_FAILED: merged mutation was not signed';
  end if;
end
$full_payload_binding$;

-- CA-N38: integers are normalized; fractions and unsafe integers fail closed.
do $numeric_contract$
declare
  v_fraction_rejected boolean:=false;
  v_unsafe_rejected boolean:=false;
begin
  if private.fn_canonical_json_v7('1'::jsonb)
     is distinct from private.fn_canonical_json_v7('1.0'::jsonb) then
    raise exception 'INTEGER_NORMALIZATION_FAILED';
  end if;

  begin
    perform private.fn_canonical_json_v7('1.5'::jsonb);
  exception
    when sqlstate '22023' then
      v_fraction_rejected:=true;
  end;

  begin
    perform private.fn_canonical_json_v7('9007199254740992'::jsonb);
  exception
    when sqlstate '22023' then
      v_unsafe_rejected:=true;
  end;

  if not v_fraction_rejected then
    raise exception 'FRACTION_REJECTION_FAILED';
  end if;
  if not v_unsafe_rejected then
    raise exception 'UNSAFE_INTEGER_REJECTION_FAILED';
  end if;
end
$numeric_contract$;

-- Non-ASCII object keys are rejected so Edge and PostgreSQL use the same sort order.
do $key_domain$
declare
  v_rejected boolean:=false;
begin
  begin
    perform private.fn_canonical_json_v7('{"ñ":1}'::jsonb);
  exception
    when sqlstate '22023' then
      v_rejected:=true;
  end;

  if not v_rejected then
    raise exception 'NON_ASCII_KEY_REJECTION_FAILED';
  end if;
end
$key_domain$;

rollback;

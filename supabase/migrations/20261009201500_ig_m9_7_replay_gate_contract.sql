begin;
-- M9.7 replay gate reads canonical EVIDENCE_LEDGER plus signed release-bundle receipts.
create or replace function programacion.fn_input_governance_shadow_receipt_gate_v1(p_current_bundle_sha text,p_candidate_bundle_sha text,p_snapshot_sha text)
returns jsonb language plpgsql stable security invoker
set search_path to 'pg_catalog','programacion','private','public'
as $gate$
declare r private.lf_evidence_ledger_v1%rowtype;
 c programacion.provenance_receipts%rowtype;
 n programacion.provenance_receipts%rowtype;
 e jsonb; snapshot text;
begin
 if coalesce(p_current_bundle_sha,'') !~ '^[0-9a-f]{64}$'
 or coalesce(p_candidate_bundle_sha,'') !~ '^[0-9a-f]{64}$'
 or coalesce(p_snapshot_sha,'') !~ '^[0-9a-f]{64}$' then
 return jsonb_build_object('status','BLOCKED','code','SHADOW_SELECTOR_INVALID');end if;
 select * into r from private.lf_evidence_ledger_v1
 where receipt_kind='IG_SHADOW_COMPARISON' and capability_code='INPUT_GOVERNANCE'
 and verification_state in ('ANCHORED','VERIFIED')
 and verification_payload->>'comparison_scope'='BUNDLE_DIGEST_ONLY'
 and receipt_payload#>>'{typed_evidence,current_release_sha256}'=p_current_bundle_sha
 and receipt_payload#>>'{typed_evidence,candidate_release_sha256}'=p_candidate_bundle_sha
 and receipt_payload#>>'{typed_evidence,source_snapshot_sha256}'=p_snapshot_sha
 order by created_at desc limit 1;
 if not found then return jsonb_build_object('status','BLOCKED','code','SHADOW_RECEIPT_MISSING_OR_UNBOUND');end if;
 e:=r.receipt_payload->'typed_evidence';
 if r.receipt_payload->>'typed_evidence_schema_version'<>'ig-shadow-receipt/v1'
 or private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',e) is not true
 or r.receipt_payload->>'plan_digest' is distinct from p_snapshot_sha
 or coalesce(r.verification_payload->>'current_release_bundle_receipt_id','') !~ '^[0-9]+$'
 or coalesce(r.verification_payload->>'candidate_release_bundle_receipt_id','') !~ '^[0-9]+$' then
 return jsonb_build_object('status','BLOCKED','code','SHADOW_RECEIPT_CONTRACT_INVALID');end if;
 select * into c from programacion.provenance_receipts
 where id=(r.verification_payload->>'current_release_bundle_receipt_id')::bigint
 and subject_type='input_governance_release_bundle' and subject_sha256=p_current_bundle_sha;
 select * into n from programacion.provenance_receipts
 where id=(r.verification_payload->>'candidate_release_bundle_receipt_id')::bigint
 and subject_type='input_governance_release_bundle' and subject_sha256=p_candidate_bundle_sha;
 if c.id is null or n.id is null then return jsonb_build_object('status','BLOCKED','code','SHADOW_SOURCE_MISSING');end if;
 snapshot:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('current_id',c.id,
 'current_receipt_sha256',c.receipt_sha256,'candidate_id',n.id,
 'candidate_receipt_sha256',n.receipt_sha256));
 if snapshot is distinct from p_snapshot_sha
 or e->>'current_release_ref' is distinct from c.head_sha
 or e->>'candidate_release_ref' is distinct from n.head_sha
 or e#>>'{comparison,current_output_sha256}' is distinct from c.subject_sha256
 or e#>>'{comparison,candidate_output_sha256}' is distinct from n.subject_sha256
 or e#>>'{comparison,method_version}'<>'IG_RELEASE_BUNDLE_MANIFEST_DIGEST_V1'
 or e#>>'{comparison,result}' is distinct from (case when c.subject_sha256=n.subject_sha256 then 'MATCH' else 'MISMATCH' end)
 or (e#>>'{comparison,difference_count}')::numeric is distinct from
 (case when c.subject_sha256=n.subject_sha256 then 0 else 1 end) then
 return jsonb_build_object('status','BLOCKED','code','SHADOW_REPLAY_COMPARISON_DIVERGENCE');end if;
 begin
 perform programacion.fn_assert_provenance_receipt(c.id,'EVIDENCE_VERIFICATION',null,c.head_sha,
 'input_governance_release_bundle','input-governance-release-bundle',c.subject_sha256);
 perform programacion.fn_assert_provenance_receipt(n.id,'EVIDENCE_VERIFICATION',null,n.head_sha,
 'input_governance_release_bundle','input-governance-release-bundle',n.subject_sha256);
 exception when others then
 return jsonb_build_object('status','BLOCKED','code','SHADOW_SOURCE_ATTESTATION_INVALID');end;
 return jsonb_build_object('status','PASS','code','SHADOW_BUNDLE_REPLAY_IDENTICAL',
 'receipt_id',r.receipt_id,'receipt_sha256',r.receipt_sha256,
 'source_snapshot_sha256',snapshot,'comparison',e->'comparison',
 'comparison_scope','BUNDLE_DIGEST_ONLY','functional_pipeline_equivalence_proven',false,
 'verification_state',r.verification_state);
exception when others then
 return jsonb_build_object('status','BLOCKED','code','SHADOW_GATE_FAIL_CLOSED');
end $gate$;
revoke all on function programacion.fn_input_governance_shadow_receipt_gate_v1(text,text,text) from public;
grant execute on function programacion.fn_input_governance_shadow_receipt_gate_v1(text,text,text) to service_role;
do $contract$
declare m jsonb;cp text;q text;
 objs jsonb:=jsonb_build_array('private.lf_evidence_ledger_v1','programacion.provenance_receipts','programacion.fn_input_governance_shadow_receipt_gate_v1');
 replay_query text:='select receipt_id,receipt_sha256,receipt_payload,verification_payload from private.lf_evidence_ledger_v1 where receipt_kind=''IG_SHADOW_COMPARISON'' order by created_at desc limit 1';
 negative_query text:='select programacion.fn_input_governance_shadow_receipt_gate_v1(repeat(''f'',64),repeat(''e'',64),repeat(''d'',64)) negative_gate';
begin
 select unit_metadata into strict m from programacion.engineering_plan_units
 where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7' for update;
 foreach cp in array array['REPLAY_REPRODUCIBLE','RECEIPT_MISSING_NEGATIVE'] loop
 q:=case when cp='REPLAY_REPRODUCIBLE' then replay_query else negative_query end;
 m:=jsonb_set(m,array['source_pack_v1','checkpoint_inputs',cp,'inputs','queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,array['source_pack_v1','checkpoint_inputs',cp,'inputs','db_objects'],objs,true);
 m:=jsonb_set(m,array['action_specs_v1',cp,'target','declared_objects'],objs,true);
 m:=jsonb_set(m,array['action_specs_v1',cp,'verification_queries'],jsonb_build_array(q),true);
 m:=jsonb_set(m,array['action_specs_v1',cp,'test_execution_contract','declared_objects'],objs,true);
 m:=jsonb_set(m,array['action_specs_v1',cp,'test_execution_contract','declared_queries'],jsonb_build_array(q),true);
 end loop;
 update programacion.engineering_plan_units set unit_metadata=m
 where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.7';
end $contract$;
do $verify$
declare a jsonb;b jsonb;
begin
 a:=programacion.fn_input_governance_shadow_receipt_gate_v1(
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
 '329416a1e3bf23bc239942135b3e785ad3b6c12ab58bc4606869cb354fabe5f2',
 '89b9fd806f2c776ddd92fb61b6a2f2d9e7af16b69a9620ef730ddacd308e9881');
 if a->>'status'<>'PASS' or a->'functional_pipeline_equivalence_proven'<>'false'::jsonb then
 raise exception 'BLOCK_M97_GATE_POSITIVE:%',a;end if;
 b:=programacion.fn_input_governance_shadow_receipt_gate_v1(repeat('f',64),repeat('e',64),repeat('d',64));
 if b->>'status'<>'BLOCKED' then raise exception 'BLOCK_M97_MISSING_RECEIPT_ACCEPTED';end if;
 b:=programacion.fn_input_governance_shadow_receipt_gate_v1(
 'db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
 '329416a1e3bf23bc239942135b3e785ad3b6c12ab58bc4606869cb354fabe5f2',repeat('f',64));
 if b->>'status'<>'BLOCKED' then raise exception 'BLOCK_M97_WRONG_SNAPSHOT_ACCEPTED';end if;
end $verify$;
commit;
-- INV-5.2–5.4 Git-derived CALLS graph.
-- Source-first evidence:
-- sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_2_5_4/call_graph_evidence_v1.json
-- Pinned main: cbf486c4d60dc3d266a516d5e5fa62ec971dceba
-- Operational inventory write only. NOT a schema migration.
-- Apply only via DIRECT_DB_WRITE / SUPABASE_MCP after merge to main.
-- INV-5.5 Drive citations 10115/10116/10117 are intentionally untouched here.

begin;

do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from (
    values
      (54690::bigint,'repo://.github/workflows/lf-input-governance-recurate.yml'::text),
      (5775::bigint,'edge://lf-profiles-governance-caller-v1'::text),
      (5773::bigint,'edge://input-governance-agent-v1'::text),
      (5744::bigint,'edge://run-creacion-perfil-lf'::text)
  ) expected(object_id,object_ref)
  left join inventory.objects o using(object_id)
  where o.object_id is null or o.object_ref <> expected.object_ref or not o.active;

  if v_bad <> 0 then
    raise exception 'INV_5_2_5_4_OBJECT_PRECONDITION_FAILED count=%',v_bad;
  end if;
end $$;

insert into inventory.dependencies(
  source_object_id,target_object_id,target_ref,relation_type,
  evidence_type,evidence,confidence,source_system,metadata,
  first_seen_at,last_verified_at,active,dependency_key
)
values
(
  54690,5775,null,'CALLS',
  'GITHUB_WORKFLOW_HTTP_CALL',
  'POST /functions/v1/lf-profiles-governance-caller-v1',
  1.0000,'GITHUB_MAIN_STATIC_ANALYSIS',
  jsonb_build_object(
    'unit','INV-5.2',
    'observed_main_sha','cbf486c4d60dc3d266a516d5e5fa62ec971dceba',
    'source_path','.github/workflows/lf-input-governance-recurate.yml',
    'source_blob','eeb5f355aee393c59d543c1de80c455285e2073e',
    'extractor_path','sandbox/lf_contract_gate_test/global_technical_inventory/extract_caller_workflow_calls_v1.py',
    'extractor_blob','9feab5e4f504b134439b9de66718139f51a8b01a',
    'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_2_5_4/call_graph_evidence_v1.json'
  ),
  clock_timestamp(),clock_timestamp(),true,'GITHUB_CALLS|54690|5775'
),
(
  5775,5773,null,'CALLS',
  'GITHUB_TYPESCRIPT_CALL_RUNTIME',
  'callRuntime("input-governance-agent-v1", ...)',
  1.0000,'GITHUB_MAIN_STATIC_ANALYSIS',
  jsonb_build_object(
    'unit','INV-5.4',
    'observed_main_sha','cbf486c4d60dc3d266a516d5e5fa62ec971dceba',
    'source_path','supabase/functions/lf-profiles-governance-caller-v1/index.ts',
    'source_blob','2da23953cb8dc15640a346b18aeed90d10518a83',
    'source_code_object_ref','repo://supabase/functions/lf-profiles-governance-caller-v1/index.ts',
    'extractor_path','sandbox/lf_contract_gate_test/global_technical_inventory/extract_caller_workflow_calls_v1.py',
    'extractor_blob','9feab5e4f504b134439b9de66718139f51a8b01a',
    'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_2_5_4/call_graph_evidence_v1.json'
  ),
  clock_timestamp(),clock_timestamp(),true,'GITHUB_CALLS|5775|5773'
),
(
  5775,5744,null,'CALLS',
  'GITHUB_TYPESCRIPT_CALL_RUNTIME',
  'callRuntime("run-creacion-perfil-lf", ...)',
  1.0000,'GITHUB_MAIN_STATIC_ANALYSIS',
  jsonb_build_object(
    'unit','INV-5.4',
    'observed_main_sha','cbf486c4d60dc3d266a516d5e5fa62ec971dceba',
    'source_path','supabase/functions/lf-profiles-governance-caller-v1/index.ts',
    'source_blob','2da23953cb8dc15640a346b18aeed90d10518a83',
    'source_code_object_ref','repo://supabase/functions/lf-profiles-governance-caller-v1/index.ts',
    'extractor_path','sandbox/lf_contract_gate_test/global_technical_inventory/extract_caller_workflow_calls_v1.py',
    'extractor_blob','9feab5e4f504b134439b9de66718139f51a8b01a',
    'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_2_5_4/call_graph_evidence_v1.json'
  ),
  clock_timestamp(),clock_timestamp(),true,'GITHUB_CALLS|5775|5744'
)
on conflict (dependency_key) do update
set source_object_id=excluded.source_object_id,
    target_object_id=excluded.target_object_id,
    target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,
    evidence_type=excluded.evidence_type,
    evidence=excluded.evidence,
    confidence=excluded.confidence,
    source_system=excluded.source_system,
    metadata=excluded.metadata,
    last_verified_at=excluded.last_verified_at,
    active=true;

update inventory.objects
set metadata =
      coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'callers_in_main_tree','[]'::jsonb,
        'callers_in_main_tree_state','NO_CALLER_IN_MAIN_TREE',
        'callers_in_main_tree_observed_main_sha','cbf486c4d60dc3d266a516d5e5fa62ec971dceba',
        'callers_in_main_tree_extractor','sandbox/lf_contract_gate_test/global_technical_inventory/extract_caller_workflow_calls_v1.py',
        'callers_in_main_tree_evidence','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_2_5_4/call_graph_evidence_v1.json',
        'callers_in_main_tree_dp_issue',1423
      ),
    updated_at=clock_timestamp()
where object_id=54690
  and object_ref='repo://.github/workflows/lf-input-governance-recurate.yml';

do $$
declare
  v_calls integer;
  v_no_caller boolean;
  v_drive_active integer;
begin
  select count(*) into v_calls
  from inventory.dependencies
  where active
    and dependency_key in (
      'GITHUB_CALLS|54690|5775',
      'GITHUB_CALLS|5775|5773',
      'GITHUB_CALLS|5775|5744'
    )
    and relation_type='CALLS'
    and source_system='GITHUB_MAIN_STATIC_ANALYSIS';

  if v_calls <> 3 then
    raise exception 'INV_5_2_5_4_CALLS_READBACK_FAILED expected=3 actual=%',v_calls;
  end if;

  select metadata->'callers_in_main_tree'='[]'::jsonb
     and metadata->>'callers_in_main_tree_state'='NO_CALLER_IN_MAIN_TREE'
     and metadata->>'callers_in_main_tree_dp_issue'='1423'
  into v_no_caller
  from inventory.objects
  where object_id=54690;

  if coalesce(v_no_caller,false) is not true then
    raise exception 'INV_5_3_NO_CALLER_METADATA_READBACK_FAILED';
  end if;

  select count(*) into v_drive_active
  from inventory.dependencies
  where dependency_id in (10115,10116,10117) and active;

  if v_drive_active <> 3 then
    raise exception 'INV_5_5_DRIVE_CITATIONS_CHANGED_EARLY expected=3 actual=%',v_drive_active;
  end if;
end $$;

commit;

select d.dependency_id,so.object_ref source_ref,t.object_ref target_ref,
       d.relation_type,d.evidence_type,d.source_system,d.active,d.dependency_key,d.metadata
from inventory.dependencies d
join inventory.objects so on so.object_id=d.source_object_id
join inventory.objects t on t.object_id=d.target_object_id
where d.dependency_key in (
  'GITHUB_CALLS|54690|5775',
  'GITHUB_CALLS|5775|5773',
  'GITHUB_CALLS|5775|5744'
)
order by d.dependency_key;

select object_ref,
       metadata->'callers_in_main_tree' callers_in_main_tree,
       metadata->>'callers_in_main_tree_state' callers_in_main_tree_state,
       metadata->>'callers_in_main_tree_observed_main_sha' observed_main_sha,
       metadata->>'callers_in_main_tree_dp_issue' dp_issue
from inventory.objects
where object_id=54690;

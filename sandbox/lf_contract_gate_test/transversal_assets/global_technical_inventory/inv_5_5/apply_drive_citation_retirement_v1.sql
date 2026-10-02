-- INV-5.5: retire three historical Drive citations without deleting them.
-- Transaction body only:
--   dry-run: BEGIN; <this file>; ROLLBACK;
--   apply:   BEGIN; <this file>; COMMIT;
-- Source-first evidence:
-- sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_5/drive_citation_retirement_evidence_v1.json
-- Pinned main: 1f883ef738fff85cfeb6ba3e0f580ec0e5f78963
-- Operational inventory write. NOT a schema migration.

do $$
declare
  v_bad integer;
  v_replacements integer;
  v_updated integer;
begin
  select count(*) into v_bad
  from inventory.dependencies d
  where d.dependency_id in (10115,10116,10117)
    and not (
      d.active
      and d.evidence_type='DRIVE_REPO_DEPENDENCY'
      and d.source_system='GOOGLE_DRIVE_REPO_INVENTORY'
      and d.relation_type='CITES'
      and d.dependency_key in ('REPO_DEP|4677','REPO_DEP|4678','REPO_DEP|4679')
    );

  if v_bad <> 0 then
    raise exception 'INV_5_5_DRIVE_PRECONDITION_FAILED count=%',v_bad;
  end if;

  if (
    select count(*)
    from inventory.dependencies
    where dependency_id in (10115,10116,10117)
  ) <> 3 then
    raise exception 'INV_5_5_DRIVE_ROWS_MISSING';
  end if;

  select count(*) into v_replacements
  from inventory.dependencies
  where active
    and (
      (dependency_id=95460
       and dependency_key='GITHUB_CALLS|5775|5773'
       and relation_type='CALLS'
       and evidence_type='GITHUB_TYPESCRIPT_CALL_RUNTIME'
       and source_system='GITHUB_MAIN_STATIC_ANALYSIS')
      or
      (dependency_id=95461
       and dependency_key='GITHUB_CALLS|5775|5744'
       and relation_type='CALLS'
       and evidence_type='GITHUB_TYPESCRIPT_CALL_RUNTIME'
       and source_system='GITHUB_MAIN_STATIC_ANALYSIS')
    );

  if v_replacements <> 2 then
    raise exception 'INV_5_5_REPLACEMENT_CALLS_NOT_READY expected=2 actual=%',v_replacements;
  end if;

  update inventory.dependencies d
  set active=false,
      last_verified_at=clock_timestamp(),
      metadata=jsonb_set(
        coalesce(d.metadata,'{}'::jsonb),
        '{inv_5_5_deactivation}',
        case d.dependency_id
          when 10115 then jsonb_build_object(
            'unit','INV-5.5',
            'reason','REPLACED_BY_GITHUB_CALLS',
            'replacement_dependency_id',95460,
            'replacement_dependency_key','GITHUB_CALLS|5775|5773',
            'observed_main_sha','1f883ef738fff85cfeb6ba3e0f580ec0e5f78963',
            'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_5/drive_citation_retirement_evidence_v1.json',
            'deactivated_at',clock_timestamp()
          )
          when 10116 then jsonb_build_object(
            'unit','INV-5.5',
            'reason','SELF_CITATION_NOT_A_CALL',
            'replacement_dependency_id',null,
            'observed_main_sha','1f883ef738fff85cfeb6ba3e0f580ec0e5f78963',
            'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_5/drive_citation_retirement_evidence_v1.json',
            'deactivated_at',clock_timestamp()
          )
          when 10117 then jsonb_build_object(
            'unit','INV-5.5',
            'reason','REPLACED_BY_GITHUB_CALLS',
            'replacement_dependency_id',95461,
            'replacement_dependency_key','GITHUB_CALLS|5775|5744',
            'observed_main_sha','1f883ef738fff85cfeb6ba3e0f580ec0e5f78963',
            'evidence_path','sandbox/lf_contract_gate_test/transversal_assets/global_technical_inventory/inv_5_5/drive_citation_retirement_evidence_v1.json',
            'deactivated_at',clock_timestamp()
          )
        end,
        true
      )
  where d.dependency_id in (10115,10116,10117);

  get diagnostics v_updated = row_count;
  if v_updated <> 3 then
    raise exception 'INV_5_5_UPDATE_COUNT_FAILED expected=3 actual=%',v_updated;
  end if;

  if (
    select count(*)
    from inventory.dependencies
    where dependency_id in (10115,10116,10117) and active
  ) <> 0 then
    raise exception 'INV_5_5_ACTIVE_DRIVE_ROWS_REMAIN';
  end if;

  if (
    select count(*)
    from inventory.dependencies
    where dependency_id in (10115,10116,10117)
      and metadata ? 'inv_5_5_deactivation'
  ) <> 3 then
    raise exception 'INV_5_5_MARKS_MISSING';
  end if;
end $$;

select dependency_id,active,dependency_key,evidence_type,source_system,
       metadata->'inv_5_5_deactivation' as inv_5_5_deactivation
from inventory.dependencies
where dependency_id in (10115,10116,10117)
order by dependency_id;

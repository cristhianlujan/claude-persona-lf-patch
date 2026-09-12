insert into private.lf_repository_governance_bundle_v4 (
  path,
  expected_sha256,
  expected_git_blob,
  control_kind,
  active,
  approved_commit_sha,
  approved_by_execution_id,
  approved_at,
  revision_id
)
values (
  'scripts/lf_contract_check.py',
  '9b6206208b98172e5f947fc47d1ddeb6a5e69ad68ec8039079fe5a9e03682a7e',
  '24c114142e6a24277e824d196f274c3ed72d72c8',
  'VALIDATOR',
  true,
  'd32e3fd5ecc765b07fd48e4e096f8ffb3705cad4',
  'WORK-PR126-POSTMERGE-GOVERNANCE-PIN-20260810',
  clock_timestamp(),
  13
);

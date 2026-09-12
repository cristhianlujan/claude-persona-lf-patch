create index if not exists idx_agent_tasks_supersedes_task
  on programacion.agent_tasks(supersedes_task_id)
  where supersedes_task_id is not null;

create index if not exists idx_test_contracts_suite_code
  on programacion.test_contracts(suite_code)
  where suite_code is not null;

create index if not exists idx_test_contracts_supersedes_contract
  on programacion.test_contracts(supersedes_contract_id)
  where supersedes_contract_id is not null;

create index if not exists idx_lf_functional_versions_parent_spec
  on public.lf_functional_versions(parent_spec_version_id)
  where parent_spec_version_id is not null;

create index if not exists idx_lf_functional_versions_supersedes
  on public.lf_functional_versions(supersedes_version_id)
  where supersedes_version_id is not null;
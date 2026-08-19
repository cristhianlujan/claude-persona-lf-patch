alter table programacion.input_readiness_runs drop constraint if exists input_readiness_runs_contract_version_check;
alter table programacion.input_readiness_runs add constraint input_readiness_runs_contract_version_check check (contract_version = any (array[1,2,3,4,5]));

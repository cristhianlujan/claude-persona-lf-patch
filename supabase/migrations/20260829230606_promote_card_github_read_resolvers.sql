update public.lf_operation_step_contracts
set resolver_ref='GITHUB_API_LF_READER',
    updated_at=clock_timestamp(),
    updated_by_execution_id='GOV-CARD-DETERMINISTIC-FIRST-20260829'
where operation_code='CREACION_CARD_LF'
  and step_id in ('repo_matrix_read','contract_read','repo_inventory_full');
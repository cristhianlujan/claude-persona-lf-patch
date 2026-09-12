update public.lf_operation_step_contracts
set resolver_ref = case step_id
 when 'creator_asset' then 'public.v_lf_fuente_operativa.ACT-0045'
 when 'destination_validate' then 'public.v_lf_artifact_destination_registry'
 when 'duplicate_check' then 'v_lf_fuente_operativa + lf_activos'
 when 'github_write' then 'GITHUB_API_LF_WRITER'
 when 'github_readback' then 'GITHUB_API_LF_READER'
 else resolver_ref end,
 updated_at = clock_timestamp(),
 updated_by_execution_id = 'GOV-CARD-DETERMINISTIC-FIRST-20260829'
where operation_code='CREACION_CARD_LF'
  and step_id in ('creator_asset','destination_validate','duplicate_check','github_write','github_readback');
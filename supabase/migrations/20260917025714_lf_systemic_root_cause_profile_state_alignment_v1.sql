update public.lf_activos
set estado_original='CANDIDATE_READ_ONLY',
    updated_by_execution_id='EXEC-S30-A2R-PROFILE-SYSTEMIC-ROOT-CAUSE-20260916-001',
    updated_at=now()
where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  and estado_original='CANDIDATO'
  and estado_documental='CANDIDATO'
  and estado_operativo='READ_ONLY'
  and nivel_control='PROFILE_REGISTRY'
  and runtime_estado='NO_HABILITADO'
  and impacto_automatico='BLOQUEADO'
  and archived_at is null;
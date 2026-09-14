-- Final S30 cleanup: remove stale candidate/sandbox source semantics from operational Strategy UPDATE/EXECUTE stacks.
DO $pre$
DECLARE v text;
BEGIN
 SELECT max(version) INTO v FROM supabase_migrations.schema_migrations;
 IF v IS DISTINCT FROM '20260914061116' THEN RAISE EXCEPTION 'S30_CONTRACT_CLEANUP_LEDGER_DRIFT:%',v; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id='EXEC-S30-STRATEGY-UPDATE-CONTRACT-CANONICALIZE-20260914-001' AND operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='IN_PROGRESS') THEN RAISE EXCEPTION 'S30_UPDATE_CONTRACT_CLEANUP_EXECUTION_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001' AND operation_code='EJECUCION_ESTRATEGIA_LF' AND status='IN_PROGRESS') THEN RAISE EXCEPTION 'S30_EXEC_CONTRACT_CLEANUP_EXECUTION_INVALID'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND lifecycle_state_code='OP_OPERATIONAL' AND status='PRODUCCION_CONTROLADA') THEN RAISE EXCEPTION 'S30_UPDATE_NOT_OPERATIONAL_PRE_CLEANUP'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND lifecycle_state_code='OP_OPERATIONAL' AND status='PRODUCCION_CONTROLADA') THEN RAISE EXCEPTION 'S30_EXEC_NOT_OPERATIONAL_PRE_CLEANUP'; END IF;
END $pre$;

-- Strategy UPDATE: canonical v1 contract identity and truthful operational step descriptions.
UPDATE public.lf_operation_contracts
SET contract_code='CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-v1',
    contract_path='supabase://public/lf_operation_contracts/ACTUALIZACION_ESTRATEGIA_LF/v1',
    updated_by_execution_id='EXEC-S30-STRATEGY-UPDATE-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET contract_code='CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-v1',
    notes='Operational governed Strategy update step. Canonical lifecycle PLANNED/ACTIVE is writable; CLOSED/SUPERSEDED fails closed. No automatic lifecycle/runtime/impact promotion.',
    purpose=CASE WHEN step_id='router' THEN 'Resolver ACT-0001 y confirmar ruta activa STRATEGY_UPDATE hacia ACTUALIZACION_ESTRATEGIA_LF.' ELSE purpose END,
    updated_by_execution_id='EXEC-S30-STRATEGY-UPDATE-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF';

UPDATE public.lf_operation_contracts
SET contract_sha=encode(extensions.digest(convert_to(jsonb_build_object(
      'operation_code',operation_code,'contract_code',contract_code,'contract_path',contract_path,
      'required_before_write',required_before_write,'allowed',allowed,'blocked',blocked,'required_after_write',required_after_write
    )::text,'UTF8'),'sha256'),'hex'),
    updated_by_execution_id='EXEC-S30-STRATEGY-UPDATE-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';

-- Strategy EXECUTE: Supabase becomes current operational contract authority; Git remains implementation mirror.
UPDATE public.lf_operation_registry
SET source_model='SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
    source_paths=jsonb_build_array('supabase://public/lf_operation_contracts/EJECUCION_ESTRATEGIA_LF/CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'),
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_contracts
SET contract_path='supabase://public/lf_operation_contracts/EJECUCION_ESTRATEGIA_LF/v1',
    allowed=allowed-'sandbox_runtime_activation',
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_contracts
SET contract_sha=encode(extensions.digest(convert_to(jsonb_build_object(
      'operation_code',operation_code,'contract_code',contract_code,'contract_path',contract_path,
      'required_before_write',required_before_write,'allowed',allowed,'blocked',blocked,'required_after_write',required_after_write
    )::text,'UTF8'),'sha256'),'hex'),
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET purpose=regexp_replace(purpose,'^Source-bound candidate step for controlled single-strategy execution: ','Operational single-strategy execution step: '),
    resolver_ref='EJECUCION_ESTRATEGIA_LF/V1',
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_judges
SET judge_path='supabase://public/lf_operation_judges/EJECUCION_ESTRATEGIA_LF/'||judge_code,
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_judges
SET judge_sha=encode(extensions.digest(convert_to(jsonb_build_object(
      'operation_code',operation_code,'judge_code',judge_code,'judge_path',judge_path,
      'pass_if',pass_if,'fail_if',fail_if,'result_values',result_values
    )::text,'UTF8'),'sha256'),'hex'),
    updated_by_execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF';

UPDATE public.lf_operation_execution
SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,
    manifest=manifest||jsonb_build_object('result','STRATEGY_UPDATE_CONTRACT_V1_CANONICALIZED','contract_code','CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-v1','bootstrap_candidate_semantics_removed',true)
WHERE execution_id='EXEC-S30-STRATEGY-UPDATE-CONTRACT-CANONICALIZE-20260914-001';

UPDATE public.lf_operation_execution
SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,
    manifest=manifest||jsonb_build_object('result','STRATEGY_EXEC_CONTRACT_SOURCE_CANONICALIZED','contract_code','CONTRACT-EJECUCION-ESTRATEGIA-LF-v1','source_authority','SUPABASE','sandbox_candidate_semantics_removed',true,'inflight_start_snapshots_preserved',true)
WHERE execution_id='EXEC-S30-STRATEGY-EXEC-CONTRACT-CANONICALIZE-20260914-001';

DO $post$
DECLARE c int;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_contracts WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND contract_code='CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-v1' AND contract_sha ~ '^[0-9a-f]{64}$') THEN RAISE EXCEPTION 'S30_UPDATE_CONTRACT_V1_POST_FAIL'; END IF;
 SELECT count(*) INTO c FROM public.lf_operation_step_contracts WHERE operation_code='ACTUALIZACION_ESTRATEGIA_LF' AND (contract_code<>'CONTRACT-ACTUALIZACION-ESTRATEGIA-LF-v1' OR notes ~* '(candidate|candidato|no router activation)'); IF c<>0 THEN RAISE EXCEPTION 'S30_UPDATE_STALE_STEP_SEMANTICS:%',c; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1' AND contract_path='supabase://public/lf_operation_contracts/EJECUCION_ESTRATEGIA_LF/v1' AND contract_sha ~ '^[0-9a-f]{64}$' AND NOT (allowed ? 'sandbox_runtime_activation')) THEN RAISE EXCEPTION 'S30_EXEC_CONTRACT_V1_POST_FAIL'; END IF;
 SELECT count(*) INTO c FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND (purpose ~* '(candidate|candidato)' OR resolver_ref ~* '(bootstrap|sandbox)'); IF c<>0 THEN RAISE EXCEPTION 'S30_EXEC_STALE_STEP_SEMANTICS:%',c; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND (source_model ~* '(sandbox|candidate|candidato)' OR source_paths::text ~* '(sandbox|candidate|candidato)')) THEN RAISE EXCEPTION 'S30_EXEC_STALE_SOURCE_AUTHORITY'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_judges WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND (judge_path ~* '(sandbox|candidate|candidato)' OR judge_sha !~ '^[0-9a-f]{64}$')) THEN RAISE EXCEPTION 'S30_EXEC_STALE_JUDGE_AUTHORITY'; END IF;
END $post$;
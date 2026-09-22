-- LF DB owner-first initialization guard v1.
-- Purpose: make ownership and exact source/target binding mandatory before any new ACTUALIZACION_DB_LF write.
-- Source-first migration only. No production activation, no runtime activation, no historical DDL replay.
-- Historical executions created before this cutover remain readable; new executions fail closed without owner_binding.

DO $pre$
DECLARE
  v_execution_id constant text := 'EXEC-DB-OWNER-FIRST-INIT-20260922-001';
  v_exec public.lf_operation_execution%rowtype;
  v_binding jsonb;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id=v_execution_id;

  IF NOT FOUND
     OR v_exec.operation_code <> 'ACTUALIZACION_DB_LF'
     OR v_exec.target_type <> 'MIGRATION'
     OR v_exec.target_code <> 'LF_DB_OWNER_FIRST_INIT_V1'
     OR v_exec.target_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR v_exec.target_path IS DISTINCT FROM 'supabase/migrations/20260922184000_lf_db_owner_first_init_v1.sql'
     OR v_exec.status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_BOOTSTRAP_EXECUTION_BINDING';
  END IF;

  v_binding := v_exec.manifest->'owner_binding';
  IF jsonb_typeof(v_binding) IS DISTINCT FROM 'object'
     OR coalesce(v_binding->>'schema_version','') <> 'LF_DB_OPERATION_OWNER_BINDING_V1'
     OR coalesce(v_binding->>'owner_execution_id','') <> v_execution_id
     OR coalesce(v_binding->>'owner_operation_code','') <> 'ACTUALIZACION_DB_LF'
     OR btrim(coalesce(v_binding->>'owner_ref','')) = ''
     OR coalesce(v_binding->>'target_type','') <> 'MIGRATION'
     OR coalesce(v_binding->>'target_repo','') <> 'cristhianlujan/claude-persona-lf-patch'
     OR coalesce(v_binding->>'target_path','') <> 'supabase/migrations/20260922184000_lf_db_owner_first_init_v1.sql'
     OR btrim(coalesce(v_binding->>'authority_ref','')) = ''
     OR btrim(coalesce(v_binding->>'source_ref','')) = ''
     OR coalesce(v_binding->>'source_revision','') !~ '^[0-9a-f]{40}$'
     OR coalesce(v_binding->>'source_blob_sha','') !~ '^[0-9a-f]{40}$'
     OR coalesce(v_binding->>'handoff_policy','') <> 'NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY'
     OR btrim(coalesce(v_binding->>'bound_at','')) = '' THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_BOOTSTRAP_OWNER_BINDING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_OPERATION_CONTRACT_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_steps
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='init_execution'
      AND active=true
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_INIT_ALREADY_ACTIVE';
  END IF;
END
$pre$;

INSERT INTO public.lf_operation_steps(
  operation_code,step_order,execution_order,step_id,required,evidence_required,
  source_path,source_sha,active,created_by_execution_id,updated_by_execution_id
) VALUES (
  'ACTUALIZACION_DB_LF',5,5,'init_execution',true,
  'owner_binding; exact_target; source_binding_if_migration; explicit_handoff_if_any',
  'public.lf_db_operation_begin_v1',null,true,
  'EXEC-DB-OWNER-FIRST-INIT-20260922-001','EXEC-DB-OWNER-FIRST-INIT-20260922-001'
)
ON CONFLICT (operation_code,step_id) DO UPDATE SET
  step_order=excluded.step_order,
  execution_order=excluded.execution_order,
  required=excluded.required,
  evidence_required=excluded.evidence_required,
  source_path=excluded.source_path,
  active=excluded.active,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=clock_timestamp();

INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,created_by_execution_id,updated_by_execution_id
) VALUES (
  'ACTUALIZACION_DB_LF','init_execution',5,5,'CONTRACT-ACTUALIZACION-DB-LF-v0.1',
  'Crear/reservar la ejecución DB con owner inmutable y target exacto antes de cualquier preflight o write.',
  '["owner_ref","authority_ref","exact_target","source_binding_if_migration","handoff_receipt_if_any"]'::jsonb,
  'public.lf_db_operation_begin_v1',
  '["owner_binding_receipt"]'::jsonb,
  '{"owner_binding_at_init":true,"owner_binding_immutable":true}'::jsonb,
  '{"owner_binding_missing":true}'::jsonb,
  'BLOCK_DB_OWNER_BINDING_AT_INIT',
  'JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1',
  '["owner_binding","owner_binding_receipt","exact_target","source_binding_if_migration"]'::jsonb,
  'preflight','close','ACTIVE_ENFORCEMENT',
  'Owner-first: handoff is a new execution with explicit receipt; owner binding is never inferred after write.',
  'EXEC-DB-OWNER-FIRST-INIT-20260922-001','EXEC-DB-OWNER-FIRST-INIT-20260922-001'
)
ON CONFLICT (operation_code,step_id) DO UPDATE SET
  step_order=excluded.step_order,
  execution_order=excluded.execution_order,
  contract_code=excluded.contract_code,
  purpose=excluded.purpose,
  input_required=excluded.input_required,
  resolver_ref=excluded.resolver_ref,
  output_payload=excluded.output_payload,
  pass_condition=excluded.pass_condition,
  block_condition=excluded.block_condition,
  blocking_code=excluded.blocking_code,
  mini_judge_code=excluded.mini_judge_code,
  required_evidence_keys=excluded.required_evidence_keys,
  next_if_pass=excluded.next_if_pass,
  next_if_blocked=excluded.next_if_blocked,
  status=excluded.status,
  notes=excluded.notes,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=clock_timestamp();

UPDATE public.lf_operation_contracts
SET required_before_write=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          required_before_write || jsonb_build_array(
            'owner_binding_at_init',
            'owner_binding_receipt',
            'source_binding_at_init_if_migration'
          )
        )
      ) q
    ),
    blocked=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          blocked || jsonb_build_array(
            'write_without_owner_binding',
            'owner_inferred_after_write',
            'owner_binding_mutation_in_place',
            'owner_handoff_without_new_execution_receipt',
            'migration_without_exact_source_binding_at_init'
          )
        )
      ) q
    ),
    allowed=allowed || jsonb_build_object(
      'owner_binding_schema','LF_DB_OPERATION_OWNER_BINDING_V1',
      'owner_begin_rpc','public.lf_db_operation_begin_v1',
      'owner_handoff_policy','NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY',
      'owner_binding_immutable',true
    ),
    updated_by_execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_DB_LF'
  AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
  AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_contracts
SET contract_sha=encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'operation_code',operation_code,
            'contract_code',contract_code,
            'contract_path',contract_path,
            'required_before_write',required_before_write,
            'allowed',allowed,
            'blocked',blocked,
            'required_after_write',required_after_write
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ),
    updated_by_execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_DB_LF'
  AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
  AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET input_required=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(input_required || jsonb_build_array('owner_binding','owner_binding_receipt'))
      ) q
    ),
    required_evidence_keys=(
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(required_evidence_keys || jsonb_build_array('owner_binding','owner_binding_receipt'))
      ) q
    ),
    updated_by_execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001',
    updated_at=clock_timestamp()
WHERE operation_code='ACTUALIZACION_DB_LF'
  AND step_id='preflight'
  AND status='ACTIVE_ENFORCEMENT';

CREATE OR REPLACE FUNCTION private.fn_lf_db_owner_binding_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_binding jsonb;
  v_handoff jsonb;
BEGIN
  IF TG_OP='UPDATE'
     AND OLD.operation_code='ACTUALIZACION_DB_LF'
     AND NEW.operation_code IS DISTINCT FROM OLD.operation_code THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BINDING_OPERATION_CODE_IMMUTABLE';
  END IF;

  IF NEW.operation_code <> 'ACTUALIZACION_DB_LF' THEN
    RETURN NEW;
  END IF;

  v_binding := NEW.manifest->'owner_binding';

  IF jsonb_typeof(v_binding) IS DISTINCT FROM 'object'
     OR coalesce(v_binding->>'schema_version','') <> 'LF_DB_OPERATION_OWNER_BINDING_V1'
     OR coalesce(v_binding->>'owner_execution_id','') <> NEW.execution_id
     OR coalesce(v_binding->>'owner_operation_code','') <> 'ACTUALIZACION_DB_LF'
     OR btrim(coalesce(v_binding->>'owner_ref','')) = ''
     OR coalesce(v_binding->>'target_type','') <> NEW.target_type
     OR coalesce(v_binding->>'target_path','') <> coalesce(NEW.target_path,'')
     OR coalesce(v_binding->>'target_repo','') <> coalesce(NEW.target_repo,'')
     OR btrim(coalesce(v_binding->>'authority_ref','')) = ''
     OR coalesce(v_binding->>'handoff_policy','') <> 'NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY'
     OR btrim(coalesce(v_binding->>'bound_at','')) = '' THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BINDING_REQUIRED_AT_INIT';
  END IF;

  IF btrim(coalesce(NEW.target_path,'')) = '' THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BINDING_EXACT_TARGET_PATH_REQUIRED';
  END IF;

  IF NEW.target_type='MIGRATION' THEN
    IF btrim(coalesce(NEW.target_repo,'')) = ''
       OR btrim(coalesce(v_binding->>'source_ref','')) = ''
       OR coalesce(v_binding->>'source_revision','') !~ '^[0-9a-f]{40}$'
       OR coalesce(v_binding->>'source_blob_sha','') !~ '^[0-9a-f]{40}$' THEN
      RAISE EXCEPTION 'LF_DB_OWNER_BINDING_MIGRATION_SOURCE_REQUIRED_AT_INIT';
    END IF;
  END IF;

  IF TG_OP='UPDATE' AND OLD.manifest ? 'owner_binding'
     AND NEW.manifest->'owner_binding' IS DISTINCT FROM OLD.manifest->'owner_binding' THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BINDING_IMMUTABLE_START_NEW_EXECUTION_FOR_HANDOFF';
  END IF;

  IF NEW.manifest ? 'handoff_from_execution_id' THEN
    v_handoff := NEW.manifest->'owner_handoff_receipt';
    IF jsonb_typeof(v_handoff) IS DISTINCT FROM 'object'
       OR coalesce(v_handoff->>'schema_version','') <> 'LF_DB_OWNER_HANDOFF_RECEIPT_V1'
       OR coalesce(v_handoff->>'from_execution_id','') <> coalesce(NEW.manifest->>'handoff_from_execution_id','')
       OR coalesce(v_handoff->>'to_execution_id','') <> NEW.execution_id
       OR btrim(coalesce(v_handoff->>'approved_by_ref','')) = ''
       OR btrim(coalesce(v_handoff->>'evidence_ref','')) = ''
       OR NOT EXISTS (
         SELECT 1
         FROM public.lf_operation_execution prior
         WHERE prior.execution_id=NEW.manifest->>'handoff_from_execution_id'
           AND prior.operation_code='ACTUALIZACION_DB_LF'
       ) THEN
      RAISE EXCEPTION 'LF_DB_OWNER_HANDOFF_RECEIPT_INVALID';
    END IF;
  END IF;

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_lf_db_owner_binding_guard_v1 ON public.lf_operation_execution;
CREATE TRIGGER trg_lf_db_owner_binding_guard_v1
BEFORE INSERT OR UPDATE OF operation_code,target_type,target_code,target_repo,target_path,manifest
ON public.lf_operation_execution
FOR EACH ROW
EXECUTE FUNCTION private.fn_lf_db_owner_binding_guard_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_db_owner_init_step_v1()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_binding jsonb := new.manifest->'owner_binding';
  v_binding_sha text;
  v_receipt jsonb;
BEGIN
  IF new.operation_code <> 'ACTUALIZACION_DB_LF' THEN
    RETURN new;
  END IF;

  v_binding_sha := encode(
    extensions.digest(convert_to(v_binding::text,'UTF8'),'sha256'),
    'hex'
  );
  v_receipt := jsonb_build_object(
    'schema_version','LF_DB_OWNER_BINDING_RECEIPT_V1',
    'execution_id',new.execution_id,
    'operation_code','ACTUALIZACION_DB_LF',
    'owner_binding_sha256',v_binding_sha,
    'owner_binding_at_init',true,
    'owner_binding_immutable',true,
    'handoff_policy','NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY',
    'status','PASS_CLEAN'
  );

  INSERT INTO public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,
    created_by_execution_id,updated_by_execution_id,updated_at
  ) VALUES (
    new.execution_id,5,'init_execution','PASS_CLEAN',
    format('supabase://public/lf_operation_execution/%s#owner_binding',new.execution_id),
    jsonb_build_object(
      'owner_binding',v_binding,
      'owner_binding_receipt',v_receipt,
      'owner_binding_at_init',true,
      'owner_binding_immutable',true,
      'source_binding_required_at_init',new.target_type='MIGRATION',
      'recorded_by_trigger','fn_lf_db_owner_init_step_v1'
    ),
    'Owner and exact target were bound atomically with execution creation.',
    new.execution_id,new.execution_id,clock_timestamp()
  );

  RETURN new;
END
$fn$;

DROP TRIGGER IF EXISTS trg_lf_db_owner_init_step_v1 ON public.lf_operation_execution;
CREATE TRIGGER trg_lf_db_owner_init_step_v1
AFTER INSERT ON public.lf_operation_execution
FOR EACH ROW
EXECUTE FUNCTION private.fn_lf_db_owner_init_step_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_db_owner_init_step_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_execution_id text := CASE WHEN TG_OP='DELETE' THEN old.execution_id ELSE new.execution_id END;
  v_step_id text := CASE WHEN TG_OP='DELETE' THEN old.step_id ELSE new.step_id END;
BEGIN
  IF v_step_id='init_execution'
     AND EXISTS (
       SELECT 1
       FROM public.lf_operation_execution e
       WHERE e.execution_id=v_execution_id
         AND e.operation_code='ACTUALIZACION_DB_LF'
     ) THEN
    RAISE EXCEPTION 'LF_DB_OWNER_INIT_STEP_IMMUTABLE';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN old ELSE new END;
END
$fn$;

DROP TRIGGER IF EXISTS trg_lf_db_owner_init_step_guard_v1 ON public.lf_operation_execution_steps;
CREATE TRIGGER trg_lf_db_owner_init_step_guard_v1
BEFORE UPDATE OR DELETE ON public.lf_operation_execution_steps
FOR EACH ROW
EXECUTE FUNCTION private.fn_lf_db_owner_init_step_guard_v1();

CREATE OR REPLACE FUNCTION public.lf_db_operation_begin_v1(
  p_execution_id text,
  p_target_type text,
  p_target_code text,
  p_target_repo text,
  p_target_path text,
  p_owner_ref text,
  p_authority_ref text,
  p_source_ref text DEFAULT NULL,
  p_source_revision text DEFAULT NULL,
  p_source_blob_sha text DEFAULT NULL,
  p_manifest jsonb DEFAULT '{}'::jsonb,
  p_handoff_from_execution_id text DEFAULT NULL,
  p_handoff_receipt jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_type text := upper(btrim(coalesce(p_target_type,'')));
  v_route jsonb;
  v_binding jsonb;
  v_manifest jsonb;
  v_existing public.lf_operation_execution%rowtype;
  v_binding_sha text;
BEGIN
  IF btrim(coalesce(p_execution_id,''))=''
     OR btrim(coalesce(p_target_code,''))=''
     OR btrim(coalesce(p_target_path,''))=''
     OR btrim(coalesce(p_owner_ref,''))=''
     OR btrim(coalesce(p_authority_ref,''))='' THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_REQUIRED_FIELD_MISSING';
  END IF;

  IF v_type NOT IN ('DB','MIGRATION','FUNCTION','TRIGGER') THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_TARGET_TYPE_INVALID:%',v_type;
  END IF;

  IF jsonb_typeof(coalesce(p_manifest,'{}'::jsonb)) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_MANIFEST_INVALID';
  END IF;

  IF v_type='MIGRATION' THEN
    IF btrim(coalesce(p_target_repo,''))=''
       OR btrim(coalesce(p_source_ref,''))=''
       OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
       OR coalesce(p_source_blob_sha,'') !~ '^[0-9a-f]{40}$' THEN
      RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_MIGRATION_SOURCE_BINDING_REQUIRED';
    END IF;
  END IF;

  v_route := public.lf_router_resolve_v1(
    'Begin owner-bound governed DB mutation',
    p_target_code,
    'UPDATE',
    v_type,
    NULL
  );

  IF coalesce(v_route->>'status','') <> 'READY_TO_EXECUTE'
     OR coalesce(v_route->>'operation_code','') <> 'ACTUALIZACION_DB_LF'
     OR coalesce(v_route->>'action_code','') <> 'UPDATE'
     OR coalesce(v_route->>'asset_type','') <> v_type THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_ROUTER_AUTHORITY_INVALID:%',v_route::text;
  END IF;

  v_binding := jsonb_build_object(
    'schema_version','LF_DB_OPERATION_OWNER_BINDING_V1',
    'owner_execution_id',p_execution_id,
    'owner_operation_code','ACTUALIZACION_DB_LF',
    'owner_ref',btrim(p_owner_ref),
    'authority_ref',btrim(p_authority_ref),
    'target_type',v_type,
    'target_code',p_target_code,
    'target_repo',coalesce(p_target_repo,''),
    'target_path',p_target_path,
    'source_ref',coalesce(p_source_ref,''),
    'source_revision',coalesce(p_source_revision,''),
    'source_blob_sha',coalesce(p_source_blob_sha,''),
    'handoff_policy','NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY',
    'bound_at',clock_timestamp()
  );

  v_manifest := coalesce(p_manifest,'{}'::jsonb) || jsonb_build_object('owner_binding',v_binding);

  IF p_handoff_from_execution_id IS NOT NULL THEN
    IF jsonb_typeof(p_handoff_receipt) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_HANDOFF_RECEIPT_REQUIRED';
    END IF;
    v_manifest := v_manifest || jsonb_build_object(
      'handoff_from_execution_id',p_handoff_from_execution_id,
      'owner_handoff_receipt',p_handoff_receipt
    );
  END IF;

  SELECT * INTO v_existing
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF FOUND THEN
    IF v_existing.operation_code <> 'ACTUALIZACION_DB_LF'
       OR v_existing.target_type <> v_type
       OR v_existing.target_code <> p_target_code
       OR coalesce(v_existing.target_repo,'') <> coalesce(p_target_repo,'')
       OR coalesce(v_existing.target_path,'') <> p_target_path
       OR (v_existing.manifest->'owner_binding' - 'bound_at')
          IS DISTINCT FROM (v_binding - 'bound_at') THEN
      RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_EXECUTION_ID_COLLISION';
    END IF;
    v_binding := v_existing.manifest->'owner_binding';
  ELSE
    INSERT INTO public.lf_operation_execution(
      execution_id,operation_code,target_type,target_code,target_repo,target_path,
      status,manifest,created_by_execution_id,updated_by_execution_id
    ) VALUES (
      p_execution_id,'ACTUALIZACION_DB_LF',v_type,p_target_code,p_target_repo,p_target_path,
      'IN_PROGRESS',v_manifest,p_execution_id,p_execution_id
    );

    SELECT manifest->'owner_binding' INTO v_binding
    FROM public.lf_operation_execution
    WHERE execution_id=p_execution_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution_steps s
    WHERE s.execution_id=p_execution_id
      AND s.step_order=5
      AND s.step_id='init_execution'
      AND s.status='PASS_CLEAN'
      AND s.evidence_payload->'owner_binding' = v_binding
      AND s.evidence_payload->>'recorded_by_trigger'='fn_lf_db_owner_init_step_v1'
  ) THEN
    RAISE EXCEPTION 'LF_DB_OWNER_BEGIN_INIT_STEP_NOT_MATERIALIZED';
  END IF;

  v_binding_sha := encode(
    extensions.digest(convert_to(v_binding::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'schema_version','LF_DB_OWNER_BINDING_RECEIPT_V1',
    'execution_id',p_execution_id,
    'operation_code','ACTUALIZACION_DB_LF',
    'owner_binding_sha256',v_binding_sha,
    'owner_binding_at_init',true,
    'owner_binding_immutable',true,
    'handoff_policy','NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY',
    'status','PASS_CLEAN'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_db_operation_begin_v1(
  text,text,text,text,text,text,text,text,text,text,jsonb,text,jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_db_operation_begin_v1(
  text,text,text,text,text,text,text,text,text,text,jsonb,text,jsonb
) TO service_role;

DO $readback$
DECLARE
  v_contract public.lf_operation_contracts%rowtype;
BEGIN
  IF to_regprocedure('public.lf_db_operation_begin_v1(text,text,text,text,text,text,text,text,text,text,jsonb,text,jsonb)') IS NULL
     OR to_regprocedure('private.fn_lf_db_owner_binding_guard_v1()') IS NULL
     OR to_regprocedure('private.fn_lf_db_owner_init_step_v1()') IS NULL
     OR to_regprocedure('private.fn_lf_db_owner_init_step_guard_v1()') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_FUNCTION_READBACK';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_trigger t
    JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE NOT t.tgisinternal
      AND (
        (n.nspname='public' AND c.relname='lf_operation_execution'
          AND t.tgname IN ('trg_lf_db_owner_binding_guard_v1','trg_lf_db_owner_init_step_v1'))
        OR
        (n.nspname='public' AND c.relname='lf_operation_execution_steps'
          AND t.tgname='trg_lf_db_owner_init_step_guard_v1')
      )
  ) <> 3 THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_TRIGGER_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_steps
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='init_execution'
      AND step_order=5
      AND execution_order=5
      AND required=true
      AND active=true
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='init_execution'
      AND step_order=5
      AND execution_order=5
      AND status='ACTIVE_ENFORCEMENT'
      AND resolver_ref='public.lf_db_operation_begin_v1'
      AND required_evidence_keys ? 'owner_binding'
      AND required_evidence_keys ? 'owner_binding_receipt'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_INIT_STEP_READBACK';
  END IF;

  SELECT * INTO v_contract
  FROM public.lf_operation_contracts
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-DB-LF-v0.1'
    AND status='ACTIVE_ENFORCEMENT';

  IF NOT FOUND
     OR NOT (v_contract.required_before_write ? 'owner_binding_at_init')
     OR NOT (v_contract.required_before_write ? 'owner_binding_receipt')
     OR NOT (v_contract.required_before_write ? 'source_binding_at_init_if_migration')
     OR NOT (v_contract.blocked ? 'write_without_owner_binding')
     OR NOT (v_contract.blocked ? 'owner_inferred_after_write')
     OR NOT (v_contract.blocked ? 'owner_binding_mutation_in_place')
     OR NOT (v_contract.blocked ? 'owner_handoff_without_new_execution_receipt')
     OR v_contract.allowed->>'owner_begin_rpc' <> 'public.lf_db_operation_begin_v1'
     OR v_contract.allowed->>'owner_handoff_policy' <> 'NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY'
     OR coalesce((v_contract.allowed->>'owner_binding_immutable')::boolean,false) IS NOT TRUE
     OR v_contract.contract_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_CONTRACT_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='ACTUALIZACION_DB_LF'
      AND step_id='preflight'
      AND status='ACTIVE_ENFORCEMENT'
      AND input_required ? 'owner_binding'
      AND input_required ? 'owner_binding_receipt'
      AND required_evidence_keys ? 'owner_binding'
      AND required_evidence_keys ? 'owner_binding_receipt'
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_PREFLIGHT_READBACK';
  END IF;
END
$readback$;

UPDATE public.lf_operation_execution
SET manifest=manifest || jsonb_build_object(
      'result','DB_OWNER_FIRST_INIT_V1_APPLIED',
      'owner_first_enforced',true,
      'owner_binding_schema','LF_DB_OPERATION_OWNER_BINDING_V1',
      'owner_begin_rpc','public.lf_db_operation_begin_v1',
      'handoff_policy','NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY',
      'historical_ddl_replayed',false,
      'runtime_activation',false,
      'production_activation',false
    ),
    status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_by_execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001',
    updated_at=clock_timestamp()
WHERE execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001';

DO $final$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='EXEC-DB-OWNER-FIRST-INIT-20260922-001'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND status='COMPLETED'
      AND manifest->>'result'='DB_OWNER_FIRST_INIT_V1_APPLIED'
      AND manifest->'owner_binding'->>'handoff_policy'='NEW_EXECUTION_WITH_EXPLICIT_RECEIPT_ONLY'
      AND coalesce((manifest->>'historical_ddl_replayed')::boolean,true)=false
      AND coalesce((manifest->>'production_activation')::boolean,true)=false
  ) THEN
    RAISE EXCEPTION 'BLOCK_DB_OWNER_FIRST_FINAL_READBACK';
  END IF;
END
$final$;

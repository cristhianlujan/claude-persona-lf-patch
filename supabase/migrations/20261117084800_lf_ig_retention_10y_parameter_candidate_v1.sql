-- LF IG | 2026-11-17 08:17 owner instruction. CANDIDATE DRAFT ONLY.
-- No changes to VIGENTE rules, no credential reads, no promotions, no profile EXECUTE.
-- Not applied. Only the governed migration process may ever apply this source.
-- The two values below are INITIAL PARAMETER DATA; never copy durations into rule text.
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
  IF to_regclass('private.lf_ig_parameters_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'IG_RETENTION_PARAMETER_TABLE_ALREADY_PRESENT';
  END IF;
  IF to_regclass('lf_ops.auditoria_eventos') IS NULL
     OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo='REG_AUD_003' AND estado='VIGENTE')
     OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo='LEGAL-RECLAMOS-04' AND estado='CANDIDATO')
  THEN RAISE EXCEPTION 'IG_RETENTION_SOURCE_PRECONDITIONS_DRIFT'; END IF;
END;
$preflight$;

CREATE TABLE private.lf_ig_parameters_v1 (
  parameter_code text NOT NULL,
  parameter_version integer NOT NULL CHECK(parameter_version>0),
  value_integer integer NOT NULL CHECK(value_integer>0),
  value_unit text NOT NULL CHECK(value_unit IN ('DAYS','MONTHS')),
  lifecycle_status text NOT NULL CHECK(lifecycle_status IN ('CANDIDATO','ACTIVE')),
  effective_from timestamptz,
  source_decision_literal text NOT NULL,
  proposed_by text NOT NULL,
  owner_approval_ref text,
  approved_by_role text,
  approved_at timestamptz,
  authorized_execution_id text,
  change_reason text NOT NULL,
  correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT lf_ig_parameter_version_pkey PRIMARY KEY (parameter_code,parameter_version),
  CONSTRAINT lf_ig_parameter_initial_candidate_check CHECK (
    (lifecycle_status='CANDIDATO' AND effective_from IS NULL
       AND owner_approval_ref IS NULL AND approved_at IS NULL
       AND authorized_execution_id IS NULL AND approved_by_role IS NULL)
    OR
    (lifecycle_status='ACTIVE' AND effective_from IS NOT NULL
       AND nullif(owner_approval_ref,'') IS NOT NULL
       AND approved_at IS NOT NULL AND nullif(authorized_execution_id,'') IS NOT NULL
       AND approved_by_role='OWNER_CHAT_VERIFIED')
  ),
  CONSTRAINT lf_ig_parameter_unit_check CHECK (
    (parameter_code='LF_RECORD_RETENTION_DAYS' AND value_unit='DAYS')
    OR (parameter_code='LF_RETENTION_HOT_MONTHS' AND value_unit='MONTHS')
  )
);

ALTER TABLE private.lf_ig_parameters_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.lf_ig_parameters_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.lf_ig_parameters_v1 FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_lf_ig_parameter_append_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','private','lf_ops'
AS $guard$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'LF_IG_RETENTION_APPEND_ONLY_NO_UPDATE_OR_DELETE';
  END IF;
  -- Owner-approved ACTIVE versions require a separately governed writer;
  -- direct SQL activation is deliberately impossible in this candidate.
  IF NEW.lifecycle_status <> 'CANDIDATO' THEN
    RAISE EXCEPTION 'LF_IG_RETENTION_ACTIVE_WRITER_NOT_AUTHORIZED';
  END IF;
  RETURN NEW;
END;
$guard$;
REVOKE ALL ON FUNCTION private.fn_lf_ig_parameter_append_guard_v1() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_lf_ig_parameter_append_guard_v1
BEFORE INSERT OR UPDATE OR DELETE ON private.lf_ig_parameters_v1
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_ig_parameter_append_guard_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_ig_parameter_audit_candidate_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','private','lf_ops'
AS $audit$
BEGIN
  INSERT INTO lf_ops.auditoria_eventos(
    actor_role,action,policy_snapshot,correlation_id,metadata_redacted
  ) VALUES (
    'GOVERNED_MIGRATION_CANDIDATE',
    'LF_IG_PARAMETER_CANDIDATE_INSERT',
    jsonb_build_object(
      'parameter_code',NEW.parameter_code,
      'parameter_version',NEW.parameter_version,
      'initial_value_integer',NEW.value_integer,
      'value_unit',NEW.value_unit,
      'status',NEW.lifecycle_status,
      'owner_approval_verified',false
    ),
    NEW.correlation_id,
    jsonb_build_object('source_kind','OWNER_CHAT_DECISION_LITERAL_NOT_RECEIPT',
       'source_literal',NEW.source_decision_literal,
       'change_reason',NEW.change_reason,'proposal_only',true)
  );
  RETURN NEW;
END;
$audit$;
REVOKE ALL ON FUNCTION private.fn_lf_ig_parameter_audit_candidate_v1() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_lf_ig_parameter_audit_candidate_v1
AFTER INSERT ON private.lf_ig_parameters_v1
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_ig_parameter_audit_candidate_v1();

-- Single source of truth for REGISTER retention. Hot/cold is a second parameter
-- of the SAME catalog, not a duplicate definition of the ten-year retention.
-- CANDIDATO is inert. No active behavior is authorized by this initial load.
INSERT INTO private.lf_ig_parameters_v1(
  parameter_code,parameter_version,value_integer,value_unit,lifecycle_status,
  source_decision_literal,proposed_by,change_reason
) VALUES
  ('LF_RECORD_RETENTION_DAYS',1,3650,'DAYS','CANDIDATO',
   'OWNER_CHAT_2026-11-17_08:17','IG_PR_DRAFT','Owner requested standardized ten-year record retention'),
  ('LF_RETENTION_HOT_MONTHS',1,12,'MONTHS','CANDIDATO',
   'OWNER_CHAT_2026-11-17_08:17','IG_PR_DRAFT','Owner requested editable 12-month hot tier');

-- Read contract for the two legacy rules. Neither rule row nor text is modified.
-- No grant to new roles. Consumers are NOT bound by this candidate.
CREATE OR REPLACE FUNCTION private.fn_lf_ig_record_retention_for_rule_v1(
  p_rule_code text, p_as_of timestamptz DEFAULT clock_timestamp()
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','private'
AS $reader$
DECLARE
  v private.lf_ig_parameters_v1%rowtype;
BEGIN
  IF p_rule_code NOT IN ('REG_AUD_003','LEGAL-RECLAMOS-04') THEN
    RAISE EXCEPTION 'LF_IG_RETENTION_RULE_OUT_OF_SCOPE';
  END IF;
  SELECT * INTO v FROM private.lf_ig_parameters_v1
  WHERE parameter_code='LF_RECORD_RETENTION_DAYS'
    AND lifecycle_status='ACTIVE'
    AND owner_approval_ref IS NOT NULL
    AND authorized_execution_id IS NOT NULL
    AND effective_from<=p_as_of
  ORDER BY effective_from DESC,parameter_version DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_IG_RETENTION_NO_OWNER_APPROVED_ACTIVE_PARAMETER';
  END IF;
  RETURN jsonb_build_object(
    'rule_code',p_rule_code,'parameter_code',v.parameter_code,
    'retention_days',v.value_integer,'parameter_version',v.parameter_version,
    'owner_approval_ref',v.owner_approval_ref,
    'authorized_execution_id',v.authorized_execution_id
  );
END;
$reader$;
REVOKE ALL ON FUNCTION private.fn_lf_ig_record_retention_for_rule_v1(text,timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;

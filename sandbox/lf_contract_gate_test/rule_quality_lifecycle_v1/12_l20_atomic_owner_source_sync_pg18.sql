-- LOTE 20 PG18 SANDBOX ONLY. NOT A SUPABASE MIGRATION. NO GATE MODIFICATION.
-- Source/registry transition = one function invocation = one SQL statement transaction.
SET search_path=rule_quality_l13,public;

CREATE TABLE l20_sync_receipts (
 project_code text NOT NULL, rule_code text NOT NULL,
 decision_id bigint NOT NULL UNIQUE REFERENCES review_decisions(decision_id),
 owner_actor text NOT NULL, owner_sub text NOT NULL,
 decision_code text NOT NULL CHECK(decision_code IN ('EXPIRE','SUPERSEDE')),
 target_state text NOT NULL CHECK(target_state IN ('CADUCADA','SUCEDIDA')),
 successor_rule_code text,
 effective_to timestamptz,
 sync_readback jsonb NOT NULL CHECK(jsonb_typeof(sync_readback)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(project_code,rule_code),
 FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code),
 FOREIGN KEY(project_code,owner_actor) REFERENCES actors(project_code,actor_code)
);

-- INTERNAL ONLY. Query dynamic source exclusively through the project adapter,
-- never through caller-controlled SQL/schema/table/column names.
CREATE FUNCTION l20_source_snapshot_internal(p_project text,p_rule text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE a project_source_adapters%ROWTYPE; v jsonb;
BEGIN
 SELECT * INTO a FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNKNOWN_ADAPTER';
 END IF;
 IF (p_project='lf' AND a.engine<>'LF_FROZEN_APPLY')
    OR (p_project='saly' AND a.engine<>'SALY_SYNTHETIC_APPLY')
    OR p_project NOT IN ('lf','saly') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNAUTHORIZED_SOURCE_ENGINE';
 END IF;
 EXECUTE format('SELECT to_jsonb(s) FROM %s s WHERE %I=$1',a.source_table,a.code_col)
 INTO v USING p_rule;
 RETURN v;
END $fn$;

-- Lists all detected mismatches, not just those L20 itself will repair.
-- Calling it is read-only: no UPDATE, no scheduled expiry, no ticket issuance.
CREATE FUNCTION l20_list_divergences_v1(p_project text)
RETURNS TABLE(project_code text, rule_code text, registry_state text,
              source_state text, classification text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_actor text; r rules%ROWTYPE; a project_source_adapters%ROWTYPE;
        s jsonb; active text; mark text; disagree boolean;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 SELECT * INTO a FROM project_source_adapters pad WHERE pad.project_code=p_project;
 IF NOT FOUND THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNKNOWN_ADAPTER';
 END IF;
 FOR r IN SELECT * FROM rules rr WHERE rr.project_code=p_project ORDER BY rr.rule_code
 LOOP
  s:=l20_source_snapshot_internal(p_project,r.rule_code);
  project_code:=p_project; rule_code:=r.rule_code; registry_state:=r.state;
  source_state:=NULL; classification:=NULL; disagree:=false;
  IF s IS NULL THEN
    source_state:='SOURCE_MISSING';classification:='SOURCE_ROW_MISSING';disagree:=true;
  ELSIF a.engine='LF_FROZEN_APPLY' THEN
    source_state:=s->>a.state_col;
    disagree:=source_state IS DISTINCT FROM r.state;
    IF disagree THEN classification:='LIFECYCLE_STATE_MISMATCH';END IF;
  ELSIF a.engine='SALY_SYNTHETIC_APPLY' THEN
    active:=s->>a.state_col;
    mark:=s->'metadata'->>'l20_lifecycle_state';
    source_state:=CASE WHEN active='true' THEN 'VIGENTE'
      WHEN mark IN ('CADUCADA','SUCEDIDA') THEN mark
      WHEN active='false' THEN 'INACTIVE_WITHOUT_TERMINAL_REASON'
      ELSE 'INVALID_SOURCE_FLAG' END;
    IF r.state='VIGENTE' THEN
      disagree:=active IS DISTINCT FROM 'true' OR mark IN ('CADUCADA','SUCEDIDA');
    ELSIF r.state IN ('CADUCADA','SUCEDIDA') THEN
      disagree:=active IS DISTINCT FROM 'false' OR mark IS DISTINCT FROM r.state;
    ELSE
      disagree:=active IS DISTINCT FROM 'false';
    END IF;
    IF disagree THEN classification:='SALY_ACTIVE_OR_TERMINAL_MARKER_MISMATCH';END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNKNOWN_ENGINE';
  END IF;
  IF disagree THEN RETURN NEXT;END IF;
 END LOOP;
END $fn$;

-- One governed SQL command. Signed PostgREST session/role/JWT is verified by L17.
-- L18 owner review (L13 decision + readback) and source UPDATE happen in the SAME
-- PostgreSQL function statement. Any exception, including after source UPDATE,
-- rolls back L13 decision AND source UPDATE, not merely the source UPDATE.
CREATE FUNCTION l20_owner_decide_and_sync_v1(
 p_project text,p_rule text,p_decision text,p_evidence jsonb,
 p_as_of timestamptz,p_successor text DEFAULT NULL,
 p_inject_failure_after_source boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE actor text; identity jsonb; a project_source_adapters%ROWTYPE;
        r rules%ROWTYPE; succ rules%ROWTYPE; src jsonb; src_after jsonb;
        desired text; v_decision jsonb; v_id bigint; v_link text; v_changes integer;
        v_before integer;v_after integer; receipt l20_sync_receipts%ROWTYPE;
        v_ledger review_decisions%ROWTYPE; v_result jsonb;
BEGIN
 identity:=l17_verify_signed_claim_v2(p_project); -- HMAC fixture only
 actor:=trusted_actor_role_v2(p_project);
 IF actor IS DISTINCT FROM identity->>'actor_code' THEN
   RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='BLOCK_L20_ACTOR_BINDING_CHANGED';
 END IF;
 IF p_decision NOT IN ('EXPIRE','SUPERSEDE') OR p_decision IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_OWNER_DECISION_REQUIRED';
 END IF;
 desired:=CASE p_decision WHEN 'EXPIRE' THEN 'CADUCADA' ELSE 'SUCEDIDA' END;
 SELECT * INTO a FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND OR (p_project='lf' AND a.engine<>'LF_FROZEN_APPLY')
    OR (p_project='saly' AND a.engine<>'SALY_SYNTHETIC_APPLY')
    OR p_project NOT IN ('lf','saly') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNKNOWN_ADAPTER';
 END IF;
 SELECT * INTO r FROM rules WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L20_REGISTRY_RULE_NOT_FOUND';
 END IF;
 src:=l20_source_snapshot_internal(p_project,p_rule);
 IF src IS NULL THEN
   RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L20_SOURCE_RULE_NOT_FOUND';
 END IF;

 SELECT * INTO receipt FROM l20_sync_receipts
 WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF FOUND THEN
   -- Idempotent only when same authenticated owner, same decision AND both
   -- sources still match the originally witnessed terminal lifecycle.
   IF receipt.owner_actor IS DISTINCT FROM actor
      OR receipt.owner_sub IS DISTINCT FROM identity->>'sub'
      OR receipt.decision_code IS DISTINCT FROM p_decision
      OR receipt.successor_rule_code IS DISTINCT FROM p_successor
      OR receipt.target_state IS DISTINCT FROM desired
      OR r.state IS DISTINCT FROM desired
      OR r.successor_rule_code IS DISTINCT FROM receipt.successor_rule_code
      OR (a.engine='LF_FROZEN_APPLY' AND src->>a.state_col IS DISTINCT FROM desired)
      OR (a.engine='SALY_SYNTHETIC_APPLY' AND (
         src->>a.state_col IS DISTINCT FROM 'false'
         OR src->'metadata'->>'l20_lifecycle_state' IS DISTINCT FROM desired)) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_IDEMPOTENT_READBACK_DRIFT';
   END IF;
   RETURN jsonb_build_object('status','ALREADY_SYNCED_NOOP','project',p_project,
     'rule_code',p_rule,'decision_id',receipt.decision_id,
     'owner_actor',actor,'registry_state',r.state,
     'source_state',CASE WHEN a.engine='LF_FROZEN_APPLY' THEN src->>a.state_col
                   ELSE src->'metadata'->>'l20_lifecycle_state' END,
     'rows_updated',0,'decisions_added',0,'receipts_added',0);
 END IF;

 IF r.state<>'VIGENTE' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_RULE_NOT_VIGENTE';
 END IF;
 IF a.engine='LF_FROZEN_APPLY' AND src->>a.state_col IS DISTINCT FROM a.active_value
    OR a.engine='SALY_SYNTHETIC_APPLY' AND src->>a.state_col IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_SOURCE_NOT_VIGENTE';
 END IF;
 IF p_decision='SUPERSEDE' THEN
   IF p_successor IS NULL OR p_successor=p_rule
      OR NOT EXISTS (SELECT 1 FROM correction_requests c
       WHERE c.project_code=p_project AND c.original_rule_code=p_rule
        AND c.successor_rule_code=p_successor AND c.owner_role=actor) THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_EXPLICIT_SUCCESSOR_REQUIRED';
   END IF;
   SELECT * INTO succ FROM rules WHERE project_code=p_project
      AND rule_code=p_successor FOR SHARE;
   IF NOT FOUND OR succ.state<>'VIGENTE' THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_SUCCESSOR_NOT_VIGENTE';
   END IF;
   src_after:=l20_source_snapshot_internal(p_project,p_successor);
   IF src_after IS NULL OR (a.engine='LF_FROZEN_APPLY'
      AND src_after->>a.state_col IS DISTINCT FROM a.active_value)
      OR (a.engine='SALY_SYNTHETIC_APPLY'
      AND src_after->>a.state_col IS DISTINCT FROM 'true') THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_SOURCE_SUCCESSOR_NOT_VIGENTE';
   END IF;
 ELSE
   IF p_successor IS NOT NULL THEN
     RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_EXPIRE_WITH_SUCCESSOR';
   END IF;
 END IF;

 -- Owner (signed) decision plus L13 readback. No separate committed transaction.
 v_decision:=l18_owner_review_decide_v1(p_project,p_rule,p_decision,
                                         p_as_of,p_evidence,p_successor);
 v_id:=(v_decision->>'decision_id')::bigint;
 SELECT * INTO v_ledger FROM review_decisions WHERE decision_id=v_id;
 SELECT * INTO r FROM rules WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF v_decision->>'actor' IS DISTINCT FROM actor OR v_decision->>'state' IS DISTINCT FROM desired
    OR r.state IS DISTINCT FROM desired OR r.successor_rule_code IS DISTINCT FROM p_successor
    OR r.effective_to IS NULL OR r.next_review_at IS NOT NULL
    OR v_ledger.actor_code IS DISTINCT FROM actor
    OR v_ledger.project_code IS DISTINCT FROM p_project
    OR v_ledger.rule_code IS DISTINCT FROM p_rule
    OR v_ledger.decision_code IS DISTINCT FROM p_decision THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_DECISION_READBACK_FAILED';
 END IF;
 SELECT count(*) INTO v_before FROM l20_list_divergences_v1(p_project) d
 WHERE d.rule_code=p_rule;
 IF v_before<>1 THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_EXPECTED_PRE_SYNC_DIVERGENCE_MISSING';
 END IF;

 IF a.engine='LF_FROZEN_APPLY' THEN
   EXECUTE format('UPDATE %s SET %I=$2 WHERE %I=$1 AND %I=$3',
      a.source_table,a.state_col,a.code_col,a.state_col)
   USING p_rule,desired,a.active_value;
 ELSE
   -- SALY's existing "estado" is a VALIDADO validation state, not a lifecycle enum.
   -- Keep its semantics; vigente=false and metadata marker carry the terminal type
   -- in SANDBOX only. Production proposal adds lifecycle_state as a real column.
   EXECUTE format('UPDATE %s SET %I=false, metadata=coalesce(metadata,''{}''::jsonb)'
    || ' || jsonb_build_object(''l20_lifecycle_state'',$2,''l20_decision_id'',$3) '
    || 'WHERE %I=$1 AND %I=true',
     a.source_table,a.state_col,a.code_col,a.state_col)
   USING p_rule,desired,v_id;
 END IF;
 GET DIAGNOSTICS v_changes=ROW_COUNT;
 IF v_changes<>1 THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_SOURCE_UPDATE_ROWCOUNT';
 END IF;

 -- Deliberate fault injection for proof of all-or-nothing behavior in PG18 only.
 IF p_inject_failure_after_source THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='L20_INJECTED_MIDWAY_FAIL_ROLLBACK_ALL';
 END IF;
 src_after:=l20_source_snapshot_internal(p_project,p_rule);
 IF src_after IS NULL
  OR (a.engine='LF_FROZEN_APPLY' AND src_after->>a.state_col IS DISTINCT FROM desired)
  OR (a.engine='SALY_SYNTHETIC_APPLY' AND
   (src_after->>a.state_col IS DISTINCT FROM 'false'
   OR src_after->'metadata'->>'l20_lifecycle_state' IS DISTINCT FROM desired)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_SOURCE_READBACK_FAILED';
 END IF;
 SELECT count(*) INTO v_after FROM l20_list_divergences_v1(p_project) d
 WHERE d.rule_code=p_rule;
 IF v_after<>0 THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_DIVERGENCE_REMAINS';
 END IF;
 v_result:=jsonb_build_object(
   'status','SYNCED_ATOMIC_PG18','project',p_project,'rule_code',p_rule,
   'owner_actor',actor,'owner_sub',identity->>'sub','decision_id',v_id,
   'decision',p_decision,'registry_state',r.state,'source_state',desired,
   'successor_rule_code',r.successor_rule_code,'effective_to',r.effective_to,
   'next_review_at',r.next_review_at,'source_rows_updated',v_changes,
   'target_divergences_before_sync',v_before,'target_divergences_after_sync',v_after,
   'verified_owner_jwt','HMAC_SANDBOX_ONLY','production_attested',false);

 INSERT INTO l20_sync_receipts(project_code,rule_code,decision_id,owner_actor,
    owner_sub,decision_code,target_state,successor_rule_code,effective_to,sync_readback)
 VALUES(p_project,p_rule,v_id,actor,identity->>'sub',p_decision,desired,
    p_successor,r.effective_to,v_result);
 RETURN v_result;
END $fn$;

-- Direct table DML stays unavailable to requester roles. Defender role is the
-- PG18 superuser fixture, NEVER a proposed product runtime privilege design.
REVOKE ALL ON l20_sync_receipts FROM PUBLIC;
REVOKE ALL ON FUNCTION l20_source_snapshot_internal(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION l20_list_divergences_v1(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION l20_owner_decide_and_sync_v1(
 text,text,text,jsonb,timestamptz,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l20_list_divergences_v1(text),
  l20_owner_decide_and_sync_v1(text,text,text,jsonb,timestamptz,text,boolean)
 TO lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;
REVOKE INSERT,UPDATE,DELETE ON lf_ops.reglas FROM PUBLIC,lf_owner_role,lf_super_role,lf_reader_role;
REVOKE INSERT,UPDATE,DELETE ON saly_source_synthetic FROM PUBLIC,
 saly_owner_role,saly_super_role;


-- The caller sees a limited, read-only decision/source snapshot after signed
-- owner JWT verification. No direct SELECT grants on either table are required.
CREATE FUNCTION l20_target_readback_v1(
 p_project text,p_rule text,p_successor text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=rule_quality_l13,pg_temp AS $fn$
DECLARE v_actor text;a project_source_adapters%ROWTYPE;
        r rules%ROWTYPE; succ rules%ROWTYPE; src jsonb; src_succ jsonb;
        v_status text;v_source text;v_marker text;v_succ_state text;v_succ_source text;
        v_count int;v_receipts int;v_div int;
BEGIN
 v_actor:=trusted_actor_role_v2(p_project);
 SELECT * INTO a FROM project_source_adapters WHERE project_code=p_project;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLOCK_L20_UNKNOWN_ADAPTER';
 END IF;
 SELECT * INTO r FROM rules WHERE project_code=p_project AND rule_code=p_rule;
 IF NOT FOUND THEN
   RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='BLOCK_L20_REGISTRY_RULE_NOT_FOUND';
 END IF;
 src:=l20_source_snapshot_internal(p_project,p_rule);
 v_marker:=src->'metadata'->>'l20_lifecycle_state';
 v_status:=src->>a.state_col;
 v_source:=CASE WHEN a.engine='LF_FROZEN_APPLY' THEN v_status
   WHEN v_status='true' THEN 'VIGENTE'
   ELSE coalesce(v_marker,'INACTIVE_UNSPECIFIED') END;
 IF p_successor IS NOT NULL THEN
   SELECT * INTO succ FROM rules
    WHERE project_code=p_project AND rule_code=p_successor;
   src_succ:=l20_source_snapshot_internal(p_project,p_successor);
   v_succ_state:=succ.state;
   v_succ_source:=CASE WHEN a.engine='LF_FROZEN_APPLY' THEN src_succ->>a.state_col
    WHEN src_succ->>a.state_col='true' THEN 'VIGENTE'
    ELSE coalesce(src_succ->'metadata'->>'l20_lifecycle_state','INACTIVE_UNSPECIFIED') END;
 END IF;
 SELECT count(*) INTO v_count FROM review_decisions
 WHERE project_code=p_project AND rule_code=p_rule;
 SELECT count(*) INTO v_receipts FROM l20_sync_receipts
 WHERE project_code=p_project AND rule_code=p_rule;
 SELECT count(*) INTO v_div FROM l20_list_divergences_v1(p_project) d
 WHERE d.rule_code=p_rule;
 RETURN jsonb_build_object('project',p_project,'rule_code',p_rule,
   'registry',r.state,'source',v_source,
   'source_vigente',CASE WHEN a.engine='SALY_SYNTHETIC_APPLY'
                         THEN v_status='true' ELSE NULL END,
   'source_terminal',v_marker,'registry_successor',r.successor_rule_code,
   'successor_registry',v_succ_state,'successor_source',v_succ_source,
   'target_divergence',v_div,'decision_count',v_count,
   'receipt_count',v_receipts,
   'next_review_at',r.next_review_at,'effective_to',r.effective_to,
   'owner_actor',v_actor);
END $fn$;

REVOKE ALL ON FUNCTION l20_target_readback_v1(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION l20_target_readback_v1(text,text,text) TO
 lf_owner_role,lf_super_role,lf_reader_role,saly_owner_role,saly_super_role;

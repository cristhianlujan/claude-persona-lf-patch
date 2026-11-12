-- LOTE 13: POSTGRES SANDBOX ONLY. NEVER APPLY TO SUPABASE/LIVE.
-- Generic rule-family and lifecycle model; no real LF/SALY tables referenced.
CREATE SCHEMA rule_quality_l13;
SET search_path = rule_quality_l13, public;

CREATE TABLE projects (
  project_code text PRIMARY KEY CHECK (project_code ~ '^[a-z][a-z0-9_]*$'),
  owner_name text NOT NULL CHECK (btrim(owner_name) <> ''),
  owner_profile_code text NOT NULL CHECK (
    btrim(owner_profile_code) <> '' AND upper(btrim(owner_profile_code)) <> 'SUPER_ADMIN'
  ),
  created_by text NOT NULL CHECK (btrim(created_by) <> ''),
  review_interval_days integer NOT NULL DEFAULT 90 CHECK (review_interval_days BETWEEN 1 AND 730),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE actors (
  project_code text NOT NULL REFERENCES projects(project_code),
  actor_code text NOT NULL,
  profile_code text NOT NULL,
  can_approve boolean NOT NULL DEFAULT false,
  PRIMARY KEY (project_code, actor_code),
  CHECK (btrim(profile_code) <> '')
);

CREATE TABLE families (
  project_code text NOT NULL REFERENCES projects(project_code),
  family_code text NOT NULL CHECK (family_code ~ '^[A-Z][A-Z0-9_]*$'),
  scope text NOT NULL CHECK (btrim(scope) <> ''),
  owner_profile_code text NOT NULL CHECK (
    btrim(owner_profile_code) <> '' AND upper(btrim(owner_profile_code)) <> 'SUPER_ADMIN'
  ),
  new_family_criterion text NOT NULL CHECK (length(btrim(new_family_criterion)) >= 12),
  merge_criterion text NOT NULL CHECK (length(btrim(merge_criterion)) >= 12),
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (project_code, family_code)
);

CREATE TABLE category_family_map (
  project_code text NOT NULL,
  category_raw text NOT NULL,
  family_code text NOT NULL,
  mapping_status text NOT NULL DEFAULT 'PROPOSED' CHECK (mapping_status IN ('PROPOSED','APPROVED')),
  PRIMARY KEY (project_code, category_raw),
  UNIQUE (project_code, category_raw, family_code),
  FOREIGN KEY (project_code, family_code) REFERENCES families(project_code, family_code)
);

CREATE TABLE rules (
  project_code text NOT NULL,
  rule_code text NOT NULL,
  family_code text NOT NULL,
  category_raw text NOT NULL,
  entity_code text NOT NULL CHECK (btrim(entity_code) <> ''),
  definition_text text NOT NULL CHECK (btrim(definition_text) <> ''),
  config jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(config)='object'),
  state text NOT NULL DEFAULT 'CANDIDATO'
    CHECK (state IN ('CANDIDATO','EN_REVISION','VIGENTE','CADUCADA','SUCEDIDA')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  reviewed_at timestamptz,
  next_review_at timestamptz,
  effective_from timestamptz,
  effective_to timestamptz,
  successor_rule_code text,
  PRIMARY KEY (project_code,rule_code),
  FOREIGN KEY(project_code, family_code) REFERENCES families(project_code,family_code),
  FOREIGN KEY(project_code,category_raw,family_code)
    REFERENCES category_family_map(project_code,category_raw,family_code),
  FOREIGN KEY(project_code,successor_rule_code)
    REFERENCES rules(project_code,rule_code) DEFERRABLE INITIALLY DEFERRED,
  CHECK (successor_rule_code IS NULL OR successor_rule_code <> rule_code),
  CHECK (state <> 'SUCEDIDA' OR successor_rule_code IS NOT NULL),
  CHECK (effective_to IS NULL OR (effective_from IS NOT NULL AND effective_to >= effective_from)),
  CHECK (next_review_at IS NULL OR reviewed_at IS NOT NULL)
);

-- Deliberately no target FK: a missing destination must be observable by a read-only detector.
CREATE TABLE rule_references (
  project_code text NOT NULL,
  source_rule_code text NOT NULL,
  target_rule_code text NOT NULL,
  reference_kind text NOT NULL CHECK (btrim(reference_kind) <> ''),
  PRIMARY KEY(project_code,source_rule_code,target_rule_code,reference_kind),
  FOREIGN KEY(project_code,source_rule_code) REFERENCES rules(project_code,rule_code)
);

CREATE TABLE family_change_requests (
  request_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_code text NOT NULL,
  source_family_code text NOT NULL,
  target_family_code text NOT NULL,
  requested_by text NOT NULL,
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  status text NOT NULL DEFAULT 'PROPOSED' CHECK (status='PROPOSED'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(project_code,source_family_code) REFERENCES families(project_code,family_code),
  FOREIGN KEY(project_code,target_family_code) REFERENCES families(project_code,family_code),
  CHECK (source_family_code <> target_family_code)
);

CREATE TABLE review_decisions (
  decision_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_code text NOT NULL,
  rule_code text NOT NULL,
  actor_code text NOT NULL,
  decision_code text NOT NULL CHECK (decision_code IN ('KEEP_VIGENTE','EXPIRE','SUPERSEDE')),
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
  decision_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(project_code,rule_code) REFERENCES rules(project_code,rule_code),
  FOREIGN KEY(project_code,actor_code) REFERENCES actors(project_code,actor_code)
);

-- No DML, VOLATILITY STABLE: "overdue" is a proposal, NEVER an automatic transition.
CREATE FUNCTION list_review_due(p_project text, p_as_of timestamptz)
RETURNS TABLE(project_code text,rule_code text,family_code text,state text,
              next_review_at timestamptz,proposal text,classification text)
LANGUAGE sql STABLE AS $$
 SELECT r.project_code,r.rule_code,r.family_code,r.state,r.next_review_at,
        'PROPONER_REVISION'::text,'OBJETIVO_FECHA'::text
   FROM rules r
  WHERE r.project_code=p_project AND r.state='VIGENTE'
    AND r.next_review_at IS NOT NULL AND r.next_review_at <= p_as_of
  ORDER BY r.next_review_at,r.rule_code
$$;

-- Both detectors are read-only and never label a semantic contradiction as proved.
CREATE FUNCTION find_noncurrent_references(p_project text)
RETURNS TABLE(source_rule_code text,target_rule_code text,reference_kind text,
              source_state text,target_state text,classification text)
LANGUAGE sql STABLE AS $$
 SELECT r.source_rule_code,r.target_rule_code,r.reference_kind,s.state,t.state,
        'REQUIERE_REVISION_SEMANTICA'::text
   FROM rule_references r
   JOIN rules s ON s.project_code=r.project_code AND s.rule_code=r.source_rule_code
   LEFT JOIN rules t ON t.project_code=r.project_code AND t.rule_code=r.target_rule_code
  WHERE r.project_code=p_project AND s.state='VIGENTE'
    AND (t.rule_code IS NULL OR t.state<>'VIGENTE')
  ORDER BY r.source_rule_code,r.target_rule_code,r.reference_kind
$$;

CREATE FUNCTION find_parameter_differences(p_project text)
RETURNS TABLE(rule_a text,rule_b text,entity_code text,
              parameter_key text,value_a jsonb,value_b jsonb,classification text)
LANGUAGE sql STABLE AS $$
 SELECT a.rule_code,b.rule_code,a.entity_code,ka.key,ka.value,kb.value,
        'REQUIERE_REVISION_SEMANTICA'::text
   FROM rules a
   JOIN rules b ON b.project_code=a.project_code AND a.rule_code<b.rule_code
               AND b.entity_code=a.entity_code AND b.state='VIGENTE'
   CROSS JOIN LATERAL jsonb_each(a.config) ka
   JOIN LATERAL jsonb_each(b.config) kb ON kb.key=ka.key
  WHERE a.project_code=p_project AND a.state='VIGENTE'
    AND ka.value<>kb.value
    AND jsonb_typeof(ka.value) IN ('number','boolean','string')
    AND jsonb_typeof(kb.value) IN ('number','boolean','string')
  ORDER BY a.rule_code,b.rule_code,ka.key
$$;

-- The caller-provided actor ID is ONLY a sandbox fixture.
-- Production MUST bind actor identity to authenticated server context (never request JSON).
CREATE FUNCTION require_owner(p_project text,p_actor text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_actor actors%ROWTYPE; v_owner text;
BEGIN
 SELECT * INTO v_actor FROM actors
  WHERE project_code=p_project AND actor_code=p_actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_ACTOR_UNRESOLVED'
   USING ERRCODE='42501'; END IF;
 IF upper(btrim(v_actor.profile_code))='SUPER_ADMIN' THEN
   RAISE EXCEPTION 'BLOCK_SUPER_ADMIN_APPROVAL'
   USING ERRCODE='42501';
 END IF;
 SELECT owner_profile_code INTO v_owner FROM projects WHERE project_code=p_project;
 IF v_owner IS NULL OR v_actor.profile_code<>v_owner OR NOT v_actor.can_approve THEN
   RAISE EXCEPTION 'BLOCK_NOT_OWNER_PROFILE' USING ERRCODE='42501';
 END IF;
 RETURN v_actor.profile_code;
END $$;

-- Proposes a merge. Does not merge categories or families.
CREATE FUNCTION propose_family_merge(p_project text,p_source text,p_target text,
                                     p_actor text,p_evidence jsonb)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
 PERFORM require_owner(p_project,p_actor);
 IF p_source=p_target THEN RAISE EXCEPTION 'BLOCK_SAME_FAMILY'
    USING ERRCODE='23514'; END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
    OR coalesce(btrim(p_evidence->>'semantic_equivalence'),'')=''
    OR coalesce(btrim(p_evidence->>'impact_review'),'')=''
    OR coalesce(btrim(p_evidence->>'decision_ref'),'')=''
    OR coalesce(btrim(p_evidence->>'source_ref'),'')='' THEN
   RAISE EXCEPTION 'BLOCK_MERGE_EVIDENCE_MISSING' USING ERRCODE='23514';
 END IF;
 INSERT INTO family_change_requests
   (project_code,source_family_code,target_family_code,requested_by,evidence)
 VALUES(p_project,p_source,p_target,p_actor,p_evidence) RETURNING request_id INTO v_id;
 RETURN v_id;
END $$;

-- Owner decision only. Never called automatically by list_review_due.
CREATE FUNCTION decide_rule_review(p_project text,p_rule text,p_actor text,
  p_decision text,p_evidence jsonb,p_as_of timestamptz,
  p_successor text DEFAULT NULL) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_days int;v_id bigint;v_current text;v_successor text;
BEGIN
 PERFORM require_owner(p_project,p_actor);
 IF p_decision NOT IN ('KEEP_VIGENTE','EXPIRE','SUPERSEDE') THEN
   RAISE EXCEPTION 'BLOCK_INVALID_DECISION' USING ERRCODE='23514'; END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
   OR coalesce(btrim(p_evidence->>'source_ref'),'')=''
   OR coalesce(btrim(p_evidence->>'rationale'),'')='' THEN
   RAISE EXCEPTION 'BLOCK_DECISION_EVIDENCE_MISSING' USING ERRCODE='23514'; END IF;
 SELECT state INTO v_current FROM rules WHERE project_code=p_project AND rule_code=p_rule FOR UPDATE;
 IF v_current IS NULL THEN RAISE EXCEPTION 'BLOCK_RULE_NOT_FOUND'
    USING ERRCODE='23503'; END IF;
 IF v_current NOT IN ('VIGENTE','EN_REVISION') THEN
   RAISE EXCEPTION 'BLOCK_RULE_NOT_REVIEWABLE' USING ERRCODE='23514'; END IF;
 SELECT review_interval_days INTO v_days FROM projects WHERE project_code=p_project;
 IF p_decision='SUPERSEDE' THEN
   IF p_successor IS NULL OR p_successor=p_rule THEN
      RAISE EXCEPTION 'BLOCK_SUCCESSOR_REQUIRED' USING ERRCODE='23514'; END IF;
   SELECT state INTO v_successor FROM rules WHERE project_code=p_project AND rule_code=p_successor;
   IF v_successor IS DISTINCT FROM 'VIGENTE' THEN
      RAISE EXCEPTION 'BLOCK_SUCCESSOR_NOT_VIGENTE' USING ERRCODE='23514'; END IF;
 END IF;
 UPDATE rules SET
   state=CASE p_decision WHEN 'KEEP_VIGENTE' THEN 'VIGENTE'
                WHEN 'EXPIRE' THEN 'CADUCADA' ELSE 'SUCEDIDA' END,
   reviewed_at=p_as_of,
   next_review_at=CASE WHEN p_decision='KEEP_VIGENTE'
                       THEN p_as_of + make_interval(days => v_days) ELSE NULL END,
   effective_to=CASE WHEN p_decision='KEEP_VIGENTE' THEN effective_to ELSE p_as_of END,
   successor_rule_code=CASE WHEN p_decision='SUPERSEDE' THEN p_successor ELSE NULL END
 WHERE project_code=p_project AND rule_code=p_rule;
 INSERT INTO review_decisions(project_code,rule_code,actor_code,decision_code,evidence,decision_at)
 VALUES(p_project,p_rule,p_actor,p_decision,p_evidence,p_as_of)
 RETURNING decision_id INTO v_id;
 RETURN v_id;
END $$;

CREATE TABLE family_birth_requests (
 request_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 project_code text NOT NULL REFERENCES projects(project_code),
 proposed_family_code text NOT NULL CHECK (proposed_family_code ~ '^[A-Z][A-Z0-9_]*$'),
 scope text NOT NULL CHECK (length(btrim(scope))>=12),
 requested_by text NOT NULL,
 evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object'),
 status text NOT NULL DEFAULT 'PROPOSED' CHECK (status='PROPOSED'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(project_code,requested_by) REFERENCES actors(project_code,actor_code),
 UNIQUE(project_code,proposed_family_code)
);
CREATE FUNCTION propose_family_birth(p_project text,p_family text,p_scope text,
                                     p_actor text,p_evidence jsonb)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
 PERFORM require_owner(p_project,p_actor);
 IF EXISTS(SELECT 1 FROM families WHERE project_code=p_project AND family_code=p_family) THEN
   RAISE EXCEPTION 'BLOCK_FAMILY_ALREADY_EXISTS' USING ERRCODE='23505';
 END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
   OR coalesce(btrim(p_evidence->>'scope_difference'),'')=''
   OR coalesce(btrim(p_evidence->>'owner_impact'),'')=''
   OR coalesce(btrim(p_evidence->>'decision_ref'),'')=''
   OR coalesce(btrim(p_evidence->>'source_ref'),'')='' THEN
   RAISE EXCEPTION 'BLOCK_BIRTH_EVIDENCE_MISSING' USING ERRCODE='23514';
 END IF;
 INSERT INTO family_birth_requests(project_code,proposed_family_code,scope,requested_by,evidence)
 VALUES(p_project,p_family,p_scope,p_actor,p_evidence) RETURNING request_id INTO v_id;
 RETURN v_id;
END $$;


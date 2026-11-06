-- IG-EVO: governed reference inventory for ONE rule and its reachable sources.
-- NO semantic PASS, NO new Router, judge, table, workflow or canonical mutation.
-- Policy family/table resolved from pg_catalog PK metadata and existing
-- lf_ops.pantallas_politicas; no hardcoded two-reference match.
-- Narrative source is preserved intact and explicitly NOT semantically certified.
BEGIN;
CREATE OR REPLACE FUNCTION programacion.fn_ig_evo_rule_graph_inventory_v1(
  p_pantalla_id integer, p_regla_id integer, p_max_hops integer DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion','lf_ops'
AS $graph$
DECLARE
  v_root lf_ops.reglas%ROWTYPE;
  v_screen lf_ops.pantallas%ROWTYPE;
  v_module lf_ops.modulos%ROWTYPE;
  v_binding_source text;
  v_queue jsonb := '[]'::jsonb;
  v_nodes jsonb := '[]'::jsonb;
  v_edges jsonb := '[]'::jsonb;
  v_visited jsonb := '[]'::jsonb;
  v_q_idx integer := 0;
  v_hops integer;
  v_node jsonb;
  v_node_key text;
  v_node_cfg jsonb;
  v_ref record;
  v_ref_key text;
  v_ref_id text;
  v_kind text;
  v_tbl text;
  v_pk text;
  v_bind_kind text;
  v_bind_id bigint;
  v_bind_state text;
  v_target jsonb;
  v_target_id text;
  v_target_key text;
  v_target_code text;
  v_target_state text;
  v_resolution text;
  v_row_hash text;
  v_ref_total integer := 0;
  v_root_refs integer := 0;
  v_root_resolved integer := 0;
  v_not_resolved integer := 0;
  v_limit_hit boolean := false;
BEGIN
  IF p_pantalla_id IS NULL OR p_regla_id IS NULL
      OR p_max_hops IS NULL OR p_max_hops NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_BAD_INPUT';
  END IF;
  SELECT r,e.binding_source INTO v_root,v_binding_source
  FROM lf_ops.reglas r
  JOIN programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') e
     ON e.regla_id=r.id AND e.pantalla_id=p_pantalla_id
  WHERE r.id=p_regla_id AND e.binding_source<>'DERIVED_GLOBAL'
    AND r.estado IN('VIGENTE','CANDIDATO')
  LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_RULE_SCOPE_NOT_ATTESTED:%:%',p_pantalla_id,p_regla_id;
  END IF;
  SELECT p.* INTO v_screen FROM lf_ops.pantallas p WHERE p.id=p_pantalla_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'IG_EVO_INTENT_SCREEN_CONTEXT_MISSING:%',p_pantalla_id; END IF;
  SELECT m.* INTO v_module FROM lf_ops.modulos m WHERE m.module_code=v_screen.module_code LIMIT 1;
  v_queue:=jsonb_build_array(jsonb_build_object(
    'entity_key','RULE:'||p_regla_id::text,'entity_kind','RULE',
    'entity_id',p_regla_id,'depth',0,
    'config',coalesce(v_root.valor_config,'{}'::jsonb),
    'full_source_text',jsonb_build_object('titulo',v_root.titulo,
       'descripcion',v_root.descripcion,'razon',v_root.razon,
       'pendiente_detalle',v_root.pendiente_detalle),
    'source_status',v_root.estado,'binding_source',v_binding_source,
    'source_row_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(v_root))
  ));
  WHILE v_q_idx<jsonb_array_length(v_queue) LOOP
    IF v_q_idx>=128 THEN
      v_limit_hit:=true;
      EXIT;
    END IF;
    v_node:=v_queue->v_q_idx;
    v_q_idx:=v_q_idx+1;
    v_node_key:=v_node->>'entity_key';
    v_hops:=(v_node->>'depth')::integer;
    IF v_visited ? v_node_key THEN CONTINUE; END IF;
    v_visited:=v_visited||jsonb_build_array(v_node_key);
    v_nodes:=v_nodes||jsonb_build_array(v_node-'config');
    v_node_cfg:=coalesce(v_node->'config','{}'::jsonb);
    -- Collect all nested scalar reference leaves, including array elements.
    FOR v_ref IN
      WITH RECURSIVE walk(path, j, ref_key, d) AS (
        SELECT '$'::text,v_node_cfg,null::text,0
        UNION ALL
        SELECT w.path||CASE WHEN c.k IS NULL THEN '['||(c.i-1)::text||']'
                    ELSE '.'||c.k END,
          c.val,coalesce(c.k,w.ref_key),w.d+1
        FROM walk w
        CROSS JOIN LATERAL (
          SELECT kv.key k,kv.value val,null::bigint i
          FROM jsonb_each(CASE WHEN jsonb_typeof(w.j)='object'
                           THEN w.j ELSE '{}'::jsonb END) kv
          UNION ALL
          SELECT null::text,ar.value,ar.ordinality
          FROM jsonb_array_elements(CASE WHEN jsonb_typeof(w.j)='array'
                                       THEN w.j ELSE '[]'::jsonb END)
                 WITH ORDINALITY ar(value,ordinality)
        ) c
        WHERE w.d<24
      )
      SELECT path,ref_key,trim(both '"' from j::text) ref_val
      FROM walk
      WHERE jsonb_typeof(j) IN('number','string')
        AND ref_key ~ '(^|_)(policy_id|policy_ids|policy_code|rule_id|rule_ids|rule_code|rule_codes)$'
      ORDER BY path
    LOOP
      v_ref_total:=v_ref_total+1;
      IF v_hops=0 THEN v_root_refs:=v_root_refs+1; END IF;
      IF v_ref_total>512 THEN v_limit_hit:=true; EXIT; END IF;
      v_ref_key:=v_ref.ref_key;
      v_ref_id:=v_ref.ref_val;
      v_target:=NULL;
      v_tbl:=NULL;
      v_pk:=NULL;
      v_bind_id:=NULL;
      v_bind_state:=NULL;
      v_bind_kind:=NULL;
      v_resolution:='UNRESOLVED_REFERENCE_KIND';
      v_kind:=CASE
        WHEN v_ref_key ~ '(^|_)rule_(id|ids|code|codes)$' THEN 'RULE'
        WHEN v_ref_key ~ '(^|_)policy_(id|ids|code)$' THEN 'POLICY'
        ELSE 'UNKNOWN' END;
      IF v_kind='RULE' THEN
        IF v_ref_key ~ '(rule_id|rule_ids)$' AND v_ref_id ~ '^[0-9]{1,18}$' THEN
          SELECT to_jsonb(r) INTO v_target FROM lf_ops.reglas r
          WHERE r.id::text=v_ref_id LIMIT 1;
        ELSIF v_ref_key ~ '(rule_code|rule_codes)$' THEN
          SELECT to_jsonb(r) INTO v_target FROM lf_ops.reglas r
          WHERE r.codigo=v_ref_id LIMIT 1;
        ELSE v_resolution:='MALFORMED_RULE_REFERENCE'; END IF;
        v_tbl:='reglas';v_pk:='id';
      ELSIF v_kind='POLICY' THEN
        -- Resolve target column/table from the OWNED primary-key catalog;
        -- ambiguous bare policy_id/code is not guessed.
        IF v_ref_id ~ '^[0-9]{1,18}$' AND v_ref_key ~ '(policy_id|policy_ids)$' THEN
          SELECT c.relname,a.attname INTO v_tbl,v_pk
          FROM pg_constraint pc
          JOIN pg_class c ON c.oid=pc.conrelid
          JOIN pg_namespace ns ON ns.oid=c.relnamespace
          JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=ANY(pc.conkey)
          WHERE pc.contype='p' AND ns.nspname='lf_ops'
            AND c.relname LIKE 'politicas_%'
            AND a.attname<>'policy_id'
            AND (v_ref_key=a.attname OR right(v_ref_key,length(a.attname)+1)='_'||a.attname
                 OR (v_ref_key ~ '_policy_ids$' AND
                     right(v_ref_key,length(a.attname)+2)='_'||replace(a.attname,'_id','_ids')))
          ORDER BY length(a.attname) DESC LIMIT 1;
          -- Prefer an existing governed binding. The registry carries
          -- reference_role and policy_kind, not inferred global authority.
          IF v_pk IS NOT NULL THEN
            SELECT b.pantalla_politica_id,b.status,b.policy_kind
              INTO v_bind_id,v_bind_state,v_bind_kind
            FROM lf_ops.pantallas_politicas b
            WHERE b.pantalla_id=p_pantalla_id
              AND b.reference_role=v_ref_key
              AND to_jsonb(b)->>v_pk=v_ref_id
            LIMIT 1;
          END IF;
          IF v_tbl IS NOT NULL AND v_pk IS NOT NULL THEN
            EXECUTE format('SELECT to_jsonb(t) FROM %I.%I t WHERE t.%I::text=$1 LIMIT 1',
                     'lf_ops',v_tbl,v_pk)
            INTO v_target USING v_ref_id;
          ELSE
            v_resolution:='POLICY_TARGET_TYPE_UNRESOLVED';
          END IF;
        ELSE
          v_resolution:='POLICY_REFERENCE_REQUIRES_AUTHORITY';
        END IF;
      END IF;
      IF v_target IS NULL THEN
        IF v_resolution='UNRESOLVED_REFERENCE_KIND' THEN
          v_resolution:='REFERENCE_TARGET_NOT_FOUND';
        END IF;
        v_not_resolved:=v_not_resolved+1;
        v_target_id:=v_ref_id;
        v_target_code:=NULL;
        v_target_state:=NULL;
        v_row_hash:=NULL;
      ELSE
        v_target_id:=coalesce(v_target->>coalesce(v_pk,'id'),v_ref_id);
        v_target_code:=coalesce(v_target->>'policy_code',v_target->>'codigo');
        v_target_state:=coalesce(v_target->>'status',v_target->>'estado');
        v_row_hash:=programacion.fn_v09_sha256_jsonb(v_target);
        v_target_key:=v_kind||':'||coalesce(v_tbl,'reglas')||':'||v_target_id;
        v_resolution:=CASE WHEN v_kind='POLICY' AND v_bind_id IS NULL
          THEN 'SOURCE_FOUND_BINDING_NOT_ATTESTED'
          WHEN v_kind='RULE' THEN 'RULE_SOURCE_FOUND_SCOPE_NOT_ATTESTED'
          ELSE 'EXPLICIT_SOURCE_AND_BINDING_FOUND' END;
        IF v_resolution<>'EXPLICIT_SOURCE_AND_BINDING_FOUND' THEN
          v_not_resolved:=v_not_resolved+1;
        END IF;
        IF v_hops=0 AND v_resolution='EXPLICIT_SOURCE_AND_BINDING_FOUND' THEN
          v_root_resolved:=v_root_resolved+1;
        END IF;
        IF v_hops<p_max_hops AND jsonb_array_length(v_queue)<128
          AND NOT v_visited ? v_target_key THEN
          v_queue:=v_queue||jsonb_build_array(jsonb_build_object(
            'entity_key',v_target_key,'entity_kind',v_kind,
            'entity_id',v_target_id,'depth',v_hops+1,
            'config',coalesce(CASE WHEN v_kind='RULE'
                  THEN v_target->'valor_config'
                  ELSE v_target->'policy_config' END,'{}'::jsonb),
            'source_status',v_target_state,'source_row_sha256',v_row_hash,
            'full_source_text',CASE WHEN v_kind='RULE' THEN
               jsonb_build_object('titulo',v_target->>'titulo',
                  'descripcion',v_target->>'descripcion',
                  'razon',v_target->>'razon')
               ELSE jsonb_build_object('policy_code',v_target_code,
                  'policy_config',v_target->'policy_config') END));
        ELSIF v_hops<p_max_hops AND jsonb_array_length(v_queue)>=128 THEN
          v_limit_hit:=true;
        END IF;
      END IF;
      v_edges:=v_edges||jsonb_build_array(jsonb_build_object(
        'source_entity',v_node_key,'reference_path',v_ref.path,
        'reference_key',v_ref_key,'reference_value',v_ref_id,
        'target_kind',v_kind,'target_table',v_tbl,'target_pk',v_pk,
        'target_id',v_target_id,'target_code',v_target_code,
        'target_status',v_target_state,'target_row_sha256',v_row_hash,
        'binding_id',v_bind_id,'binding_status',v_bind_state,
        'binding_kind',v_bind_kind,'resolution',v_resolution,
        'semantic_verdict','NOT_TESTED'));
    END LOOP;
    IF v_limit_hit THEN EXIT; END IF;
  END LOOP;
  RETURN jsonb_build_object(
    'schema_version','IG_EVO_REFERENCE_GRAPH_V1_CANDIDATE',
    'pantalla_id',p_pantalla_id,'root_rule_id',p_regla_id,
    'root_rule_code',v_root.codigo,'root_rule_status',v_root.estado,
    'root_binding_source',v_binding_source,
    'graph_scope','GOVERNED_EXPLICIT_RULE_WITH_TRANSITIVE_POLICY_REFERENCES',
    -- Source context is supplied BEFORE any interpretation. This is not
    -- a decision, it is the evidence envelope for the native semantic stage.
    'intent_context',jsonb_build_object(
      'scope_source','lf_ops.pantallas+lf_ops.modulos+lf_ops.reglas',
      'business_identification','REQUIRES_SEMANTIC_OR_GOVERNED_BUSINESS_AUTHORITY',
      'screen',jsonb_build_object(
        'id',v_screen.id,'code',v_screen.codigo,'name',v_screen.nombre,
        'description',v_screen.descripcion,'objective',v_screen.objective,
        'flow',v_screen.flujo,'step',v_screen.paso,
        'module_code',v_screen.module_code,'screen_status',v_screen.estado,
        'source_decision_id',v_screen.source_decision_id,
        'allowed_profiles',v_screen.allowed_profiles,
        'dependencies',v_screen.dependencies,
        'source_row_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(v_screen))),
      'module',CASE WHEN v_module.module_code IS NULL
          THEN jsonb_build_object('state','NOT_FOUND')
          ELSE jsonb_build_object(
            'code',v_module.module_code,'name',v_module.name,
            'description',v_module.description,
            'app_shell_code',v_module.app_shell_code,
            'status',v_module.status,
            'source_decision_id',v_module.source_decision_id,
            'source_row_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(v_module))) END,
      'rule',jsonb_build_object(
        'id',v_root.id,'code',v_root.codigo,'title',v_root.titulo,
        'description',v_root.descripcion,'reason',v_root.razon,
        'pending_detail',v_root.pendiente_detalle,
        'status',v_root.estado,'binding_source',v_binding_source,
        'source_row_sha256',programacion.fn_v09_sha256_jsonb(to_jsonb(v_root))),
      'context_completeness',CASE
        WHEN v_module.module_code IS NULL
          OR nullif(btrim(coalesce(v_screen.objective,'')),'') IS NULL
          OR nullif(btrim(coalesce(v_screen.descripcion,'')),'') IS NULL
          THEN 'PARTIAL_RESEARCH_REQUIRED'
        ELSE 'CONTEXT_SOURCES_AVAILABLE' END),
    'intent_interpretation_request',jsonb_build_object(
      'schema_version','IG_EVO_INTENT_INTERPRETATION_REQUEST_V1_CANDIDATE',
      'decision_stage','NATIVE_CURATOR_SEMANTIC_BEFORE_FAMILY_EVALUATION',
      'semantic_interpretation_performed',false,
      'task_objectives',jsonb_build_array(
        'INFER_BUSINESS_PURPOSE_FROM_SCREEN_MODULE_FLOW_AND_RULE',
        'DISTINGUISH_EXPLICIT_REQUIREMENTS_FROM_CONTEXTUAL_EXPECTATIONS',
        'DISCOVER_UNWRITTEN_DOMAIN_RISK_HYPOTHESES',
        'ASSESS_USER_AND_BUSINESS_HARM_IF_RULE_IS_INCOMPLETE',
        'IDENTIFY_MULTIPLE_SIGNALS_PER_TEXT_CLAUSE',
        'RECONCILE_SIGNALS_WITH_GRAPH_EDGES_WITHOUT_FORCED_MATCH',
        'IDENTIFY_MISSING_POLICY_METADATA_AND_AUTHORITY',
        'CHOOSE_APPLICABLE_FAMILIES_FROM_CURRENT_GOVERNED_REGISTRY',
        'DERIVE_POSITIVE_NEGATIVE_AND_ADVERSARIAL_SCENARIOS'),
      'required_signal_fields',jsonb_build_array(
        'signal_id','intent_role','expected_behavior','source_locations',
        'reasoning','evidence_type','confidence','authority_status',
        'candidate_family_codes','graph_edge_refs','unresolved_reason'),
      'evidence_types',jsonb_build_array(
        'EXPLICIT_RULE_STATEMENT','SCREEN_CONTEXT_DERIVATION',
        'GOVERNED_POLICY_REFERENCE','DOMAIN_RISK_HYPOTHESIS',
        'EXTERNAL_GUIDANCE_CONDITIONAL'),
      'family_registry_binding','INPUT_FAMILY_POLICY_REGISTRY:RESOLVE_FROM_RUN_VERSION',
      'external_guarantee','NONE_UNTIL_NATIVE_VALIDATOR',
      'allow_unmatched_signals',true,'allow_multiple_signals_per_clause',true,
      'may_infer_but_must_not_invent_authority',true,
      'semantic_judge_to_reuse','NATIVE_VALIDATOR_AND_ASSURANCE_EVALUATOR',
      'no_new_execution_route',true,'no_automatic_writes',true),

    'explicit_reference_count',v_ref_total,
    'root_explicit_reference_count',v_root_refs,
    'root_bound_policy_reference_count',v_root_resolved,
    'unresolved_or_unattested_count',v_not_resolved,
    'graph_limit_hit',v_limit_hit,
    'graph_reference_status',CASE WHEN v_limit_hit THEN 'TRUNCATED'
      WHEN v_ref_total=0 THEN 'NO_EXPLICIT_REFS_SEMANTIC_REVIEW_REQUIRED'
      WHEN v_not_resolved>0 THEN 'INCOMPLETE_UNRESOLVED_REFERENCES'
      ELSE 'EXPLICIT_REFERENCES_ACCOUNTED_FOR' END,
    'narrative_clause_inventory',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
         'source_field',src.k,'clause_index',seg.ord,
         'verbatim_clause',btrim(seg.val),
         'signal_count','UNKNOWN','semantic_resolution','PENDING_CLASSIFICATION'
       ) ORDER BY src.k,seg.ord),'[]'::jsonb)
      FROM jsonb_each_text(jsonb_build_object(
          'titulo',v_root.titulo,'descripcion',v_root.descripcion,
          'razon',v_root.razon,'pendiente_detalle',v_root.pendiente_detalle)) src(k,val)
      CROSS JOIN LATERAL regexp_split_to_table(coalesce(src.val,''),
           '[,;.]'::text) WITH ORDINALITY seg(val,ord)
      WHERE length(btrim(seg.val))>0),
    'clause_inventory_is_not_semantic_obligation_count',true,
    'semantic_text_signals_status','NOT_TESTED',
    'contextual_intent_status','NOT_TESTED',
    'semantic_match_status','NOT_TESTED',
    'semantic_source_manifest',jsonb_build_object(
       'root_text_fields',jsonb_build_array('titulo','descripcion','razon','pendiente_detalle'),
       'policy_text_fields',jsonb_build_array('policy_code','policy_config'),
       'signal_decomposition','REQUIRES_SEMANTIC_EVALUATION',
       'edge_to_text_reconciliation','REQUIRES_SEMANTIC_EVALUATION',
       'not_found_is_not_not_applicable',true,
       'family_selection','RESOLVE_FROM_INPUT_FAMILY_POLICY_REGISTRY_NOT_FROM_FIXED_DETECTOR_NAMES'),
    'screen_policy_candidates',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'pantalla_politica_id',b.pantalla_politica_id,
        'policy_kind',b.policy_kind,'reference_role',b.reference_role,
        'binding_status',b.status,
        'policy_target_identifiers',jsonb_strip_nulls(jsonb_build_object(
          'rate_limit_policy_id',b.rate_limit_policy_id,
          'security_policy_id',b.security_policy_id,
          'timeout_policy_id',b.timeout_policy_id,
          'session_policy_id',b.session_policy_id))
      ) ORDER BY b.pantalla_politica_id),'[]'::jsonb)
      FROM lf_ops.pantallas_politicas b
      WHERE b.pantalla_id=p_pantalla_id),
    'semantic_completeness_authorized',false,
    'required_next_step','EXTRACT_OBLIGATIONS_FROM_SOURCE_TEXT_AND_COMPARE_WITH_ALL_GRAPH_EDGES_IN_NATIVE_SEMANTIC_EVALUATION',
    'canonical_write_authorized',false,
    'nodes',v_nodes,'edges',v_edges);
END;
$graph$;
REVOKE ALL ON FUNCTION programacion.fn_ig_evo_rule_graph_inventory_v1(integer,integer,integer) FROM PUBLIC;

-- This is NOT a semantic judge. It proves inventory accounting only,
-- before an existing governed semantic evaluator may inspect content.
CREATE OR REPLACE FUNCTION programacion.fn_ig_evo_graph_evidence_coverage_gate_v1(
  p_graph jsonb,p_manifest jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion'
AS $coverage$
DECLARE
  v_expected_sha text;
  v_clause_gaps jsonb;
  v_edge_gaps jsonb;
  v_pending_clauses integer;
  v_pending_edges integer;
  v_clause_total integer;
  v_edge_total integer;
BEGIN
  IF p_graph IS NULL OR p_graph->>'schema_version'<>'IG_EVO_REFERENCE_GRAPH_V1_CANDIDATE' THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_EVIDENCE_UNKNOWN_GRAPH_CONTRACT';
  END IF;
  v_expected_sha:=programacion.fn_v09_sha256_jsonb(p_graph);
  IF p_manifest IS NULL OR jsonb_typeof(p_manifest)<>'object'
     OR p_manifest->>'graph_sha256' IS DISTINCT FROM v_expected_sha THEN
    RETURN jsonb_build_object(
      'status','GRAPH_HASH_MISMATCH_OR_MANIFEST_ABSENT',
      'semantic_verdict','NOT_TESTED',
      'semantic_pass_authorized',false,
      'source_graph_sha256',v_expected_sha,
      'missing_evidence','MANIFEST_GRAPH_BINDING');
  END IF;
  IF jsonb_typeof(p_manifest->'clause_assessments') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_manifest->'edge_assessments') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_EVIDENCE_MISSING_ACCOUNTING_ARRAYS';
  END IF;
  SELECT coalesce(jsonb_agg(c),'[]'::jsonb) INTO v_clause_gaps
  FROM jsonb_array_elements(coalesce(p_graph->'narrative_clause_inventory','[]'::jsonb)) c
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_manifest->'clause_assessments') a
    WHERE a->>'source_field'=c->>'source_field'
       AND a->>'clause_index'=c->>'clause_index'
       AND a->>'status' IN(
         'PENDING_SEMANTIC_CLASSIFICATION','EXTRACTED',
         'NOT_APPLICABLE_WITH_AUTHORITY')
       AND (
         a->>'status'='PENDING_SEMANTIC_CLASSIFICATION'
         OR (
           a->>'status'='EXTRACTED' AND jsonb_typeof(a->'signal_ids')='array'
           AND jsonb_array_length(a->'signal_ids')>0
         )
         OR (
           a->>'status'='NOT_APPLICABLE_WITH_AUTHORITY'
           AND nullif(a->>'authority_ref','') IS NOT NULL
         )
       )
  );
  SELECT coalesce(jsonb_agg(e),'[]'::jsonb) INTO v_edge_gaps
  FROM jsonb_array_elements(coalesce(p_graph->'edges','[]'::jsonb)) e
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_manifest->'edge_assessments') a
    WHERE a->>'source_entity'=e->>'source_entity'
      AND a->>'reference_path'=e->>'reference_path'
      AND a->>'reference_key'=e->>'reference_key'
      AND a->>'status' IN(
        'PENDING_SEMANTIC_CLASSIFICATION','RESOLVED_EXPLICIT',
        'RESOLVED_SEMANTIC_WITH_EVIDENCE','UNRESOLVED',
        'NOT_APPLICABLE_WITH_AUTHORITY')
  );
  SELECT count(*) INTO v_pending_clauses
  FROM jsonb_array_elements(p_manifest->'clause_assessments') a
  WHERE a->>'status'='PENDING_SEMANTIC_CLASSIFICATION';
  SELECT count(*) INTO v_pending_edges
  FROM jsonb_array_elements(p_manifest->'edge_assessments') a
  WHERE a->>'status' IN('PENDING_SEMANTIC_CLASSIFICATION','UNRESOLVED');
  v_clause_total:=jsonb_array_length(coalesce(p_graph->'narrative_clause_inventory','[]'::jsonb));
  v_edge_total:=jsonb_array_length(coalesce(p_graph->'edges','[]'::jsonb));
  RETURN jsonb_build_object(
    'schema_version','IG_EVO_GRAPH_EVIDENCE_COVERAGE_V1_CANDIDATE',
    'source_graph_sha256',v_expected_sha,
    'clause_count',v_clause_total,'edge_count',v_edge_total,
    'missing_clause_count',jsonb_array_length(v_clause_gaps),
    'missing_edge_count',jsonb_array_length(v_edge_gaps),
    'pending_clause_count',v_pending_clauses,'pending_edge_count',v_pending_edges,
    'missing_clauses',v_clause_gaps,'missing_edges',v_edge_gaps,
    'status',CASE WHEN jsonb_array_length(v_clause_gaps)>0
                        OR jsonb_array_length(v_edge_gaps)>0
                    THEN 'INCOMPLETE_SOURCE_ACCOUNTING'
                  ELSE 'SOURCE_ACCOUNTED_SEMANTIC_JUDGE_REQUIRED' END,
    'graph_references_status',p_graph->>'graph_reference_status',
    'semantic_verdict','NOT_TESTED',
    'semantic_pass_authorized',false,
    'repair_ready',false,
    'required_next_step','NATIVE_VALIDATOR_SEMANTIC_OBLIGATIONS_AND_DEFEATERS');
END;
$coverage$;
REVOKE ALL ON FUNCTION programacion.fn_ig_evo_graph_evidence_coverage_gate_v1(jsonb,jsonb) FROM PUBLIC;

-- Fail-closed checks run only by the governed migration executor.
DO $verify$
DECLARE v jsonb;v_neg jsonb;
BEGIN
  v:=programacion.fn_ig_evo_rule_graph_inventory_v1(51,440,3);
  v_neg:=programacion.fn_ig_evo_graph_evidence_coverage_gate_v1(v,'{}'::jsonb);
  IF v_neg->>'status'<>'GRAPH_HASH_MISMATCH_OR_MANIFEST_ABSENT'
    OR v_neg->>'semantic_pass_authorized'<>'false' THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_SEMANTIC_GATE_ACCEPTED_UNBOUND_MANIFEST';
  END IF;
  v_neg:=programacion.fn_ig_evo_graph_evidence_coverage_gate_v1(
     v,jsonb_build_object(
       'graph_sha256',programacion.fn_v09_sha256_jsonb(v),
       'clause_assessments','[]'::jsonb,'edge_assessments','[]'::jsonb));
  IF (v_neg->>'missing_clause_count')::integer<8
    OR (v_neg->>'missing_edge_count')::integer<3
    OR v_neg->>'status'<>'INCOMPLETE_SOURCE_ACCOUNTING'
    OR v_neg->>'semantic_pass_authorized'<>'false' THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_INCOMPLETE_COVERAGE_WAS_ACCEPTED:%',v_neg;
  END IF;
  IF v->>'root_rule_code'<>'B2B-RULE-AUTH-021'
   OR (v->>'root_explicit_reference_count')::integer<>3
   OR (v->>'root_bound_policy_reference_count')::integer<>3
   OR v#>>'{intent_context,screen,objective}'<>'Autenticar a un usuario B2B y habilitar el acceso según su perfil, empresa y políticas de seguridad.'
   OR v#>>'{intent_context,screen,flow}'<>'BACKOFFICE_B2B'
   OR v#>>'{intent_context,module,app_shell_code}'<>'B2B_APP_SHELL'
   OR v#>>'{intent_interpretation_request,semantic_interpretation_performed}'<>'false'
   OR v#>>'{intent_interpretation_request,allow_unmatched_signals}'<>'true'
   OR v->>'contextual_intent_status'<>'NOT_TESTED'
   OR jsonb_array_length(v->'narrative_clause_inventory')<8
   OR NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v->'edges') e
      WHERE e->>'reference_key'='anti_bot_security_policy_id'
        AND e->>'target_code'='SEC-B2B-LOGIN-ANTIBOT'
        AND e->>'target_status'='VIGENTE'
        AND e->>'binding_status'='CANDIDATO')
   OR NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v->'edges') e
      WHERE e->>'reference_key'='abuse_security_policy_id'
        AND e->>'target_code'='SEC-B2B-AUTH-ABUSE-PROTECTION')
   OR v->>'semantic_completeness_authorized'<>'false' THEN
    RAISE EXCEPTION 'IG_EVO_GRAPH_ROOT_3_OF_3_NOT_PROVEN:%',v;
  END IF;
  BEGIN
    v_neg:=programacion.fn_ig_evo_rule_graph_inventory_v1(1,440,3);
    RAISE EXCEPTION 'IG_EVO_GRAPH_OUT_OF_SCOPE_WAS_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'IG_EVO_GRAPH_RULE_SCOPE_NOT_ATTESTED:%' THEN
      RAISE EXCEPTION 'IG_EVO_GRAPH_WRONG_NEGATIVE_ERROR:%',SQLERRM;
    END IF;
  END;
  IF has_function_privilege('public',
    'programacion.fn_ig_evo_rule_graph_inventory_v1(integer,integer,integer)'::regprocedure,'EXECUTE')
    THEN RAISE EXCEPTION 'IG_EVO_GRAPH_PUBLIC_EXECUTE'; END IF;
END $verify$;
COMMIT;

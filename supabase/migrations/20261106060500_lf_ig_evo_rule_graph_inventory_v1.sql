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
    'explicit_reference_count',v_ref_total,
    'root_explicit_reference_count',v_root_refs,
    'root_bound_policy_reference_count',v_root_resolved,
    'unresolved_or_unattested_count',v_not_resolved,
    'graph_limit_hit',v_limit_hit,
    'graph_reference_status',CASE WHEN v_limit_hit THEN 'TRUNCATED'
      WHEN v_not_resolved>0 THEN 'INCOMPLETE_UNRESOLVED_REFERENCES'
      ELSE 'EXPLICIT_REFERENCES_ACCOUNTED_FOR' END,
    'semantic_text_signals_status','NOT_TESTED',
    'semantic_match_status','NOT_TESTED',
    'semantic_completeness_authorized',false,
    'required_next_step','EXTRACT_OBLIGATIONS_FROM_SOURCE_TEXT_AND_COMPARE_WITH_ALL_GRAPH_EDGES_IN_NATIVE_SEMANTIC_EVALUATION',
    'canonical_write_authorized',false,
    'nodes',v_nodes,'edges',v_edges);
END;
$graph$;
REVOKE ALL ON FUNCTION programacion.fn_ig_evo_rule_graph_inventory_v1(integer,integer,integer) FROM PUBLIC;

-- Fail-closed checks run only by the governed migration executor.
DO $verify$
DECLARE v jsonb;v_neg jsonb;
BEGIN
  v:=programacion.fn_ig_evo_rule_graph_inventory_v1(51,440,3);
  IF v->>'root_rule_code'<>'B2B-RULE-AUTH-021'
   OR (v->>'root_explicit_reference_count')::integer<>3
   OR (v->>'root_bound_policy_reference_count')::integer<>3
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

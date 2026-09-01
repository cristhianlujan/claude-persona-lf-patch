-- INPUT_GOVERNANCE_AGENT 5.12
-- Keep cached classifier semantically equivalent to the live classifier.
-- Adds the existing semantic stage_statuses/stage_blockers overlay only.
-- No product data, readiness outcome, timeout, or authorization policy is relaxed.

do $migration$
declare
  v_def text;
  v_sha text;
  v_anchor text := E'        )),true);\n      end if;\n    end if;\n  end if;\n\n  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);';
  v_replacement text := E'        )),true);\n      end if;\n      if jsonb_typeof(v_sem->''stage_statuses'')=''object'' then\n        v:=jsonb_set(v,''{severity}'',to_jsonb(coalesce(v_sem->>''severity'',v->>''severity'')),true);\n        v:=jsonb_set(v,''{story_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''story'',v->>''story_ready_status'')),true);\n        v:=jsonb_set(v,''{implementation_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''implementation'',v->>''implementation_ready_status'')),true);\n        v:=jsonb_set(v,''{qa_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''qa'',v->>''qa_ready_status'')),true);\n        v:=jsonb_set(v,''{production_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''production'',v->>''production_ready_status'')),true);\n        v:=jsonb_set(v,''{blockers}'',coalesce(v_sem->''stage_blockers'',''[]''::jsonb),true);\n      end if;\n    end if;\n  end if;\n\n  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);';
  v_new text;
  v_occurrences integer;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    into v_def,v_sha;

  if v_sha <> 'b15f441adeffcd35db74c00fc817fa01816745b82c9788e70bdb7833c397d718' then
    raise exception 'INPUT_GOV_CACHED_CLASSIFIER_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;

  v_occurrences := (length(v_def)-length(replace(v_def,v_anchor,''))) / nullif(length(v_anchor),0);
  if v_occurrences <> 1 then
    raise exception 'INPUT_GOV_CACHED_CLASSIFIER_STAGE_ANCHOR_COUNT:%',v_occurrences;
  end if;

  v_new := replace(v_def,v_anchor,v_replacement);
  execute v_new;

  if position('stage_statuses' in pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure)) = 0 then
    raise exception 'INPUT_GOV_CACHED_CLASSIFIER_STAGE_OVERLAY_NOT_INSTALLED';
  end if;
end;
$migration$;

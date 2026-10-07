-- Durable transport error handling for ACTUALIZACION_PERFIL_LF.semantic_judge.
-- Applied first in Supabase migration 20261007151652; this file restores Git/source parity.

create or replace function public.lf_parse_semantic_judge_output_v1(p_raw text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_trim text;
  v_body text;
  v_obj jsonb;
  v_fence text := repeat(chr(96), 3);
  v_prefix text;
  v_suffix text := chr(10) || repeat(chr(96), 3);
begin
  if p_raw is null or btrim(p_raw) = '' then
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_EMPTY','normalization','NONE');
  end if;

  v_trim := replace(btrim(p_raw), chr(13) || chr(10), chr(10));

  begin
    v_obj := v_trim::jsonb;
    if jsonb_typeof(v_obj) <> 'object' then
      return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_ROOT_NOT_OBJECT','normalization','NONE');
    end if;
    return jsonb_build_object('status','PASS','code',null,'normalization','NONE','payload',v_obj);
  exception when others then
    v_obj := null;
  end;

  if left(lower(v_trim), length(v_fence || 'json' || chr(10))) = v_fence || 'json' || chr(10) then
    v_prefix := v_fence || 'json' || chr(10);
  elsif left(v_trim, length(v_fence || chr(10))) = v_fence || chr(10) then
    v_prefix := v_fence || chr(10);
  else
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_NOT_EXACT_JSON','normalization','NONE');
  end if;

  if right(v_trim, length(v_suffix)) <> v_suffix then
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_NOT_EXACT_JSON','normalization','NONE');
  end if;

  v_body := substring(v_trim from length(v_prefix) + 1 for length(v_trim) - length(v_prefix) - length(v_suffix));
  if strpos(v_body, v_fence) > 0 then
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_NOT_EXACT_JSON','normalization','NONE');
  end if;

  begin
    v_obj := btrim(v_body)::jsonb;
  exception when others then
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_JSON_INVALID','normalization','EXACT_SINGLE_MARKDOWN_JSON_FENCE');
  end;

  if jsonb_typeof(v_obj) <> 'object' then
    return jsonb_build_object('status','FAIL','code','MODEL_OUTPUT_ROOT_NOT_OBJECT','normalization','EXACT_SINGLE_MARKDOWN_JSON_FENCE');
  end if;

  return jsonb_build_object('status','PASS','code',null,'normalization','EXACT_SINGLE_MARKDOWN_JSON_FENCE','payload',v_obj);
end;
$$;

comment on function public.lf_parse_semantic_judge_output_v1(text) is
'Transport-only semantic judge output parser. Accepts a JSON object directly or exactly one outer Markdown JSON fence; malformed/prose/nested-fence outputs return structured FAIL and never require a judge rerun.';

do $$
declare
  v jsonb;
  f text := repeat(chr(96),3);
begin
  v := public.lf_parse_semantic_judge_output_v1(f || 'json' || chr(10) || '{"verdict":"PASS_INDEPENDENT_SEMANTIC"}' || chr(10) || f);
  if v->>'status' <> 'PASS' or v->>'normalization' <> 'EXACT_SINGLE_MARKDOWN_JSON_FENCE' or v#>>'{payload,verdict}' <> 'PASS_INDEPENDENT_SEMANTIC' then
    raise exception 'SEMANTIC_JSON_FENCE_POSITIVE_CASE_FAILED: %', v;
  end if;

  v := public.lf_parse_semantic_judge_output_v1('resultado:' || chr(10) || f || 'json' || chr(10) || '{"verdict":"PASS_INDEPENDENT_SEMANTIC"}' || chr(10) || f);
  if v->>'status' <> 'FAIL' or v->>'code' <> 'MODEL_OUTPUT_NOT_EXACT_JSON' then
    raise exception 'SEMANTIC_JSON_FENCE_PROSE_CASE_FAILED: %', v;
  end if;

  v := public.lf_parse_semantic_judge_output_v1(f || 'json' || chr(10) || '{"verdict":' || chr(10) || f);
  if v->>'status' <> 'FAIL' or v->>'code' <> 'MODEL_OUTPUT_JSON_INVALID' then
    raise exception 'SEMANTIC_JSON_FENCE_MALFORMED_CASE_FAILED: %', v;
  end if;

  v := public.lf_parse_semantic_judge_output_v1(f || 'json' || chr(10) || f || 'json' || chr(10) || '{"verdict":"PASS"}' || chr(10) || f || chr(10) || f);
  if v->>'status' <> 'FAIL' or v->>'code' <> 'MODEL_OUTPUT_NOT_EXACT_JSON' then
    raise exception 'SEMANTIC_JSON_FENCE_NESTED_CASE_FAILED: %', v;
  end if;
end;
$$;

update public.lf_operation_step_contracts
set pass_condition = pass_condition || jsonb_build_object(
      'transport_error_handler', jsonb_build_object(
        'parser_ref','public.lf_parse_semantic_judge_output_v1',
        'accept_plain_json_object',true,
        'accept_exact_single_markdown_json_fence',true,
        'preserve_raw_output',true,
        'rerun_judge_on_parser_failure',false,
        'parser_failure_disposition','STRUCTURED_FAIL_NOT_EXCEPTION'
      )
    ),
    fail_condition = coalesce(fail_condition, '{}'::jsonb) || jsonb_build_object(
      'transport_parser_fail_codes', jsonb_build_array(
        'MODEL_OUTPUT_EMPTY','MODEL_OUTPUT_NOT_EXACT_JSON','MODEL_OUTPUT_JSON_INVALID','MODEL_OUTPUT_ROOT_NOT_OBJECT'
      )
    ),
    notes = concat_ws(' ', nullif(notes,''),
      'Transport parser: public.lf_parse_semantic_judge_output_v1. Exact single Markdown JSON fences are normalized without rerunning the judge; raw output remains evidence. Malformed, prose-wrapped, nested-fence, empty or non-object output returns a structured failure instead of an uncaught parser exception.'
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-d3056fd3-b721-4e92-ad4a-ee150fe5e8d3'
where operation_code = 'ACTUALIZACION_PERFIL_LF' and step_id = 'semantic_judge';

do $$
begin
  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='ACTUALIZACION_PERFIL_LF' and step_id='semantic_judge'
      and pass_condition#>>'{transport_error_handler,parser_ref}' = 'public.lf_parse_semantic_judge_output_v1'
      and pass_condition#>>'{transport_error_handler,parser_failure_disposition}' = 'STRUCTURED_FAIL_NOT_EXCEPTION'
  ) then
    raise exception 'SEMANTIC_JUDGE_ERROR_HANDLER_BINDING_FAILED';
  end if;
end;
$$;

-- Q12 pre-merge correction: the shared UPDATE judge is structural-only and
-- must not claim the semantic source/digest owned by the dedicated step-60 judge.

update public.lf_operation_judges
set judge_path = 'update_judge_structural_source_v1.json',
    judge_sha = '8e45c898d8e1a20ce4f93b13bb22bb25c8b7ec7f28a8a1e96ad92f7c2d7c9902',
    updated_at = now()
where operation_code = 'ACTUALIZACION_PERFIL_LF'
  and judge_code = 'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1'
  and jsonb_array_length(coalesce(pass_if, '[]'::jsonb)) = 0
  and jsonb_array_length(coalesce(fail_if, '[]'::jsonb)) = 0;

-- Fail closed if the row is missing or is no longer structural-only.
do $$
begin
  if not exists (
    select 1
    from public.lf_operation_judges
    where operation_code = 'ACTUALIZACION_PERFIL_LF'
      and judge_code = 'JUDGE-ACTUALIZACION-PERFIL-LF-v0.1'
      and judge_path = 'update_judge_structural_source_v1.json'
      and judge_sha = '8e45c898d8e1a20ce4f93b13bb22bb25c8b7ec7f28a8a1e96ad92f7c2d7c9902'
      and jsonb_array_length(coalesce(pass_if, '[]'::jsonb)) = 0
      and jsonb_array_length(coalesce(fail_if, '[]'::jsonb)) = 0
  ) then
    raise exception 'Q12_SHARED_JUDGE_STRUCTURAL_SOURCE_NOT_MATERIALIZED';
  end if;
end
$$;

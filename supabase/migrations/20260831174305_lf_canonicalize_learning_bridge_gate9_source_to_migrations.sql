update public.lf_router_action_registry
set notes='Canonical Gate9 source: supabase/migrations/20260831171812_lf_materialize_learning_bridge_minimum_lifecycle.sql; relocation history: 20260831174116_lf_relocate_learning_bridge_router_source.sql. Read-only Router entry for eligible canonical LF knowledge.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where asset_type='KNOWLEDGE'
  and action_code='KNOWLEDGE_LEARNING_BRIDGE'
  and operation_code='LEARNING_BRIDGE_KB_CARD_LF';

update public.lf_operation_step_contracts
set notes='Canonical Gate9 source: supabase/migrations/20260831171812_lf_materialize_learning_bridge_minimum_lifecycle.sql; exact step contract materialization, no policy/judge binding activation.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where operation_code='LEARNING_BRIDGE_KB_CARD_LF'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_registry
set source_paths = (
      select jsonb_agg(to_jsonb(path) order by ord)
      from (
        select distinct on (path) path, min(ord) over(partition by path) ord
        from (
          select value as path, ord::bigint
          from jsonb_array_elements_text(source_paths) with ordinality a(value,ord)
          where value not in (
            'gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml',
            'gobernanza/procedimientos/learning_bridge_kb_card_lf_router_action.yaml',
            'gobernanza/procedimientos/learning_bridge_kb_card_lf_step_contracts.yaml'
          )
          union all select 'supabase/migrations/20260831171812_lf_materialize_learning_bridge_minimum_lifecycle.sql',1000
          union all select 'supabase/migrations/20260831174116_lf_relocate_learning_bridge_router_source.sql',1001
        ) q
      ) d
    ),
    notes=coalesce(notes,'') || ' | Gate9 supplemental source canonicalized to migration files after CI-010; no validator allowlist expansion.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where operation_code='LEARNING_BRIDGE_KB_CARD_LF';

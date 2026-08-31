update public.lf_router_action_registry
set notes = replace(coalesce(notes,''),
    'gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml',
    'gobernanza/procedimientos/learning_bridge_kb_card_lf_router_action.yaml'),
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where asset_type='KNOWLEDGE'
  and action_code='KNOWLEDGE_LEARNING_BRIDGE'
  and operation_code='LEARNING_BRIDGE_KB_CARD_LF';

update public.lf_operation_registry
set source_paths = (
      select coalesce(jsonb_agg(to_jsonb(p) order by ord),'[]'::jsonb)
      from (
        select case
          when value='gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml'
            then 'gobernanza/procedimientos/learning_bridge_kb_card_lf_router_action.yaml'
          else value end as p,
          ord
        from jsonb_array_elements_text(source_paths) with ordinality a(value,ord)
      ) s
    ),
    notes = coalesce(notes,'') || ' | Gate9 source path relocated into governed procedimientos tree after CI-010 scope validation.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where operation_code='LEARNING_BRIDGE_KB_CARD_LF'
  and source_paths @> '["gobernanza/router/learning_bridge_kb_card_lf_router_action.yaml"]'::jsonb;

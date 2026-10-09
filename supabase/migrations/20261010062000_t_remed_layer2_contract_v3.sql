-- T-REMED layer 2 (complete) contract. Depends on layer 1 only through the documented proposals fields.
-- input : p_pantalla_id integer, p_consumer text (required)
-- output: jsonb {layer='COMPLETE', applied_count, already_linked_count, skipped_count, actions[]}
-- writes: programacion.t_remed_links, t_remed_link_sources, t_remed_change_log (kind LINK_INSERT), t_remed_receipts
comment on function programacion.fn_t_remed_complete_v3(integer,text) is
  'T-REMED L2 contract v3. in: pantalla_id, consumer. out: {applied_count,already_linked_count,skipped_count,actions}. Writes links as CANDIDATO (weakest-state inheritance), logs each insert in t_remed_change_log. Uses layer 1 proposals fields only.';

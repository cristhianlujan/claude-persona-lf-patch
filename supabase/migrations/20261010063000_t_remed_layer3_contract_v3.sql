-- T-REMED layer 3 (judge + promote + undo) contract. Depends on layer 2 only through programacion.t_remed_links.
-- judge  : in pantalla_id; out {items[{link_id,verdict PASS|FAIL,failed[]}],checked_count,failed_count}; recomputes from raw tables, never calls layers 1-2.
-- promote: in pantalla_id, consumer; acts only on judge PASS; every status change is logged in t_remed_change_log.
-- undo   : in change_id; restores the logged before value; refuses on state drift.
comment on function public.lf_t_remed_judge_v3(integer) is
  'T-REMED L3 judge contract v3. in: pantalla_id. out: {items[{link_id,verdict,failed[]}],checked_count,failed_count}. Independent: reads raw tables and t_remed_links only.';
comment on function programacion.fn_t_remed_promote_v3(integer,text) is
  'T-REMED L3 promote contract v3. in: pantalla_id, consumer. Promotes only judge PASS links (target policy, then rules whose references are all VIGENTE). Logs every change; undoable.';
comment on function programacion.fn_t_remed_undo_v3(bigint,text) is
  'T-REMED L3 undo contract v3. in: change_id, actor. Restores before_value from t_remed_change_log; raises T_REMED_UNDO_STATE_DRIFT if the value changed since.';
comment on function programacion.fn_t_remed_run_v3(integer,text) is
  'T-REMED entry point v3: thin caller, no logic of its own. complete (L2) then promote (L3). Consumers may call any layer directly.';

-- T-REMED layer 1 (reconcile) contract. Owner of this layer: changes here ship in their own migration/PR.
-- input : p_pantalla_id integer
-- output: jsonb {capability, layer='RECONCILE', version, subject{kind,id}, proposals[{reference_role,target_id,target_table,pk_col,rule_codes[],rule_ids[],rule_states[],target_status,verdict}], summary{verdict:count}}
-- verdict values: LINK_CANDIDATE | ABSTAIN:* | ESCALATE:* | DENY:*  (layer 2 consumes only these fields)
comment on function programacion.fn_t_remed_reconcile_v3(integer) is
  'T-REMED L1 contract v3. in: pantalla_id. out: {proposals[{reference_role,target_id,target_table,pk_col,rule_codes,rule_ids,rule_states,target_status,verdict}],summary}. Read-only. Layer 2 depends only on these fields.';
comment on function programacion.fn_t_remed_target_of_key_v3(text) is
  'T-REMED L1 helper v3. in: reference key. out: (target_table, pk_col) discovered from the lf_ops catalog (single-column PK ending _policy_id with a status column), or no row.';

# SALY — TRACE LITERAL rollback 55 tokens (NO APPLY)

**Fuente base:** Supabase rol `supabase_read_only_user`. **Ejecución de escrituras:** PostgreSQL 17 desechable, NO SALY real.
**Evidencia corrida:** https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45290374436
**Transacción:** `BEGIN` + pasos 1–7 + `ROLLBACK` + readback post-rollback.

| Paso | INPUT literal ejecutado | OUTPUT literal obtenido |
|---|---|---|
| PRETEST | 55 real token versions; contexts 3/4; orders 7/8/9; items 10/11/13 | `{"ctx3": 7, "ctx4": 5, "order9_ctx": 3, "total_tokens": 55, "item10_status": "TERMINADO", "item11_status": "PENDIENTE", "item13_status": "PENDIENTE"}` |
| 01 Alias | UPDATE identity_versions.metadata for alias ids 21..33 only; 58..61 unchanged | `{"unresolved_targets": 0, "aliases_21_33_fixed": 13, "aliases_58_61_existing": 4}` |
| 02 Contexto 55 | INSERT new context DRAFT + all 55 tokens; SEAL context; retain approval statuses | `{"official": 2, "candidate": 53, "context_id": 5, "token_count": 55, "context_state": "SEALED", "sha_mismatches": 0}` |
| 03 Snapshot 9 | UPDATE order 9 context_set_id + identity_snapshot from selected 55 token versions | `{"order9_ctx": 5, "matches_context": true, "snapshot_versions": 55}` |
| 04 Token codes 10/11/13 | Set candidate token_codes for items 10,11,13; preserve terminal guard | `{"item11_ctx": 4, "item10_token_codes": null, "item11_token_count": 53, "item13_token_count": 53}` |
| 05 Visual rules | Add visual_rules to items 10,11,13; no new blocking rules | `{"item11_visual_rules": {"radii": "OBSERVE", "scope": "SALY_ADELANTO_V015_SINGLE_20261123", "spacing": "OBSERVE", "elevation": "OBSERVE", "typography": "OBSERVE", "no_decorative_rays": true}, "item13_visual_rules": {"radii": "OBSERVE", "scope": "SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123", "spacing": "OBSERVE", "elevation": "OBSERVE", "typography": "OBSERVE", "no_decorative_rays": true}, "item10_has_visual_rules": false}` |
| 06 Compilador L3B | Compile modified L3B with 23 nonblocking checks (SQL source: proposed_l3b_observe_only.sql) | `{"families": {"RULE": 3, "COLOR": 32, "LAYOUT": 5, "SPACING": 7, "TYPOGRAPHY": 8}, "existing_checks": 5, "added_observation_checks": 23, "l3b_proposed_function_compiled": true}` |
| 06B Contexto L2A | Try real L2A context binding for 11 and 13 without granting runtime authority | `NO CAPTURADO` |
| 07 Handoff literal | Build exact prompt with original value_json and alias resolutions; attach official logo ref+sha; store BEFORE dispatch | `{"item_id": 13, "order_id": 9, "token_count": 55, "transmitted": false, "prompt_bytes": 4502, "prompt_sha256": "6edb2cc3aee48ec734d826fa16d35600c9403a539ece652fc42a489a49eb57fc", "attachment_count": 1, "unresolved_alias_values": 0, "handoff_saved_before_send": true}` |
| 08 Rollback | ROLLBACK entire simulation; no database modifications persist | `{"item11_token_codes": null, "item13_token_codes": null, "item13_visual_rules": null, "version21_alias_kind": null, "order9_context_set_id": 3, "simulated_context_rows": 0, "handoff_temp_table_exists": false, "proposed_l3b_function_exists": false}` |

### Entradas y salidas íntegras (sin reconstrucción)
- **INPUT SQL exacto:** [test_transaction_rollback_pg17.sql](./test_transaction_rollback_pg17.sql)
- **OUTPUT completo:** [github_actions_exact_stdout_20261123.txt](./github_actions_exact_stdout_20261123.txt)
- **Fuente real 55 tokens/funciones:** [supabase_readback_exact_20261123.json](./supabase_readback_exact_20261123.json)
- **L3B propuesta no bloqueante:** [proposed_l3b_observe_only.sql](./proposed_l3b_observe_only.sql)

### Resultado de la prueba (no es aprobación)
- `STEP04_ITEM10_OUTPUT=SALY_CHAT_TERMINAL_ITEM_IMMUTABLE`: no se aplicaron token_codes a ítem 10.
- `STEP05_ITEM10_OUTPUT=SALY_CHAT_TERMINAL_ITEM_IMMUTABLE`: no se aplicaron visual_rules a ítem 10.
- `STEP06B_ITEM11_OUTPUT=CREATIVE_ITEM_TOKEN_NOT_IN_LOCKED_CONTEXT`: ítem 11 apunta a contexto 4 con 5 tokens.
- `STEP06B_ITEM13_OUTPUT=CREATIVE_ITEM_CONTEXT_NOT_ADMITTED`: pedido 9 sigue BORRADOR.
- `STEP07_OUTPUT transmitted=false`: el prompt se serializó en tabla temporal dentro de la transacción y NO fue enviado a image_gen.
- `STEP07_EXACT_INPUT_PAYLOAD`: contiene `prompt_utf8` completo, 55 tokens con valores resueltos y referencia+hash del logo.
- `STEP08_OUTPUT_AFTER_ROLLBACK`: 0 contextos nuevos y sin cambios.

### Readback de SALY real (solo lectura)
INPUT:
```sql
SELECT (SELECT count(*) FROM saly.identity_versions) total_versions,
 (SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=3) ctx3_versions,
 (SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=4) ctx4_versions,
 (SELECT count(*) FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123') simulated_ctx_exists,
 (SELECT context_set_id FROM saly.creative_orders WHERE id=9) order9_context,
 (SELECT status FROM saly.creative_order_items WHERE id=10) item10_status,
 (SELECT context_json ? 'token_codes' FROM saly.creative_order_items WHERE id=11) item11_has_codes,
 (SELECT context_json ? 'token_codes' FROM saly.creative_order_items WHERE id=13) item13_has_codes,
 (SELECT acceptance_json ? 'visual_rules' FROM saly.creative_order_items WHERE id=13) item13_has_rules,
 (SELECT metadata->>'kind' FROM saly.identity_versions WHERE id=21) alias21_kind;
```
OUTPUT:
```json
[{"total_versions":55,"ctx3_versions":7,"ctx4_versions":5,"simulated_ctx_exists":0,"order9_context":3,"item10_status":"TERMINADO","item11_has_codes":false,"item13_has_codes":false,"item13_has_rules":false,"alias21_kind":null}]
```

**Estado:** SOLO PRUEBA. PR #4688 DRAFT. Ninguna migración aplicada; sin cambios en producción.

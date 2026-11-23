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

## Anexo A — INPUT SQL completo ejecutado y OUTPUT literal por etapa

Los siguientes bloques proceden del SQL ejecutado y del log GitHub Actions, sin recrear instrucciones.

### PRETEST
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'PRETEST_INPUT|55 real token versions; contexts 3/4; orders 7/8/9; items 10/11/13';
SELECT 'PRETEST_OUTPUT|' || jsonb_build_object(
  'total_tokens',(SELECT count(*) FROM saly.identity_versions),
  'ctx3',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=3),
  'ctx4',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=4),
  'order9_ctx',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
  'item10_status',(SELECT status FROM saly.creative_order_items WHERE id=10),
  'item11_status',(SELECT status FROM saly.creative_order_items WHERE id=11),
  'item13_status',(SELECT status FROM saly.creative_order_items WHERE id=13)
)::text;
BEGIN;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5155173Z PRETEST_OUTPUT|{"ctx3": 7, "ctx4": 5, "order9_ctx": 3, "total_tokens": 55, "item10_status": "TERMINADO", "item11_status": "PENDIENTE", "item13_status": "PENDIENTE"}
```

### STEP01
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP01_INPUT|UPDATE identity_versions.metadata for alias ids 21..33 only; 58..61 unchanged';
UPDATE saly.identity_versions v
SET metadata=v.metadata||jsonb_build_object(
 'kind','ALIAS',
 'alias_target_code','candidate.saly_ds_v1.' ||
     trim(both '{}' from v.value_json->>'value'))
WHERE v.id BETWEEN 21 AND 33 AND v.metadata->>'kind' IS DISTINCT FROM 'ALIAS';
SELECT 'STEP01_OUTPUT|' || jsonb_build_object(
 'aliases_21_33_fixed',(SELECT count(*) FROM saly.identity_versions v WHERE v.id BETWEEN 21 AND 33 AND v.metadata->>'kind'='ALIAS'),
 'aliases_58_61_existing',(SELECT count(*) FROM saly.identity_versions v WHERE v.id BETWEEN 58 AND 61 AND v.metadata->>'kind'='ALIAS'),
 'unresolved_targets',(SELECT count(*) FROM saly.identity_versions v WHERE v.metadata->>'kind'='ALIAS' AND NOT EXISTS(
  SELECT 1 FROM saly.identity_elements e WHERE e.code=v.metadata->>'alias_target_code'))
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5167735Z STEP01_OUTPUT|{"unresolved_targets": 0, "aliases_21_33_fixed": 13, "aliases_58_61_existing": 4}
```

### STEP02
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP02_INPUT|INSERT new context DRAFT + all 55 tokens; SEAL context; retain approval statuses';
INSERT INTO saly.creative_context_sets(
 id,project_id,code,version_label,mode,state,provenance)
SELECT max(id)+1,2,'SALY_HOME_55TOKENS_ROLLBACK_20261123','simulation','EXPLORE',
 'DRAFT','OWNER_SIMULATION_ONLY_ROLLBACK'
FROM saly.creative_context_sets;
INSERT INTO saly.creative_context_tokens(context_set_id,identity_version_id,role,value_sha256)
SELECT (SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
  v.id,
  CASE WHEN e.code IN('color.action.primary.bg','color.brand.primary')
          AND v.approval_status='APPROVED' THEN 'OFFICIAL'
       WHEN e.code LIKE 'candidate.saly_home_v3.%' THEN 'HOME'
       ELSE 'EXISTING' END,
  repeat('0',64)
FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
WHERE e.project_id=2 ORDER BY v.id;
UPDATE saly.creative_context_sets
SET state='SEALED'
WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123';
SELECT 'STEP02_OUTPUT|' || jsonb_build_object(
 'context_id',(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'context_state',(SELECT state FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'token_count',(SELECT count(*) FROM saly.creative_context_tokens WHERE context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'official',(SELECT count(*) FROM saly.creative_context_tokens WHERE role='OFFICIAL' AND context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'candidate',(SELECT count(*) FROM saly.creative_context_tokens WHERE role<>'OFFICIAL' AND context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')),
 'sha_mismatches',(SELECT count(*) FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
   WHERE t.context_set_id=(SELECT id FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123')
     AND t.value_sha256<>encode(extensions.digest(v.value_json::text,'sha256'),'hex'))
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5226553Z STEP02_OUTPUT|{"official": 2, "candidate": 53, "context_id": 5, "token_count": 55, "context_state": "SEALED", "sha_mismatches": 0}
```

### STEP03
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP03_INPUT|UPDATE order 9 context_set_id + identity_snapshot from selected 55 token versions';
UPDATE saly.creative_orders o
SET context_set_id=c.id,
identity_snapshot=jsonb_build_object('context_set_id',c.id,'selected_versions',
 (SELECT jsonb_agg(jsonb_build_object('version_id',t.identity_version_id,
  'sha256',t.value_sha256,'role',t.role) ORDER BY t.identity_version_id)
 FROM saly.creative_context_tokens t WHERE t.context_set_id=c.id))
FROM saly.creative_context_sets c
WHERE o.id=9 AND o.status='BORRADOR'
AND c.code='SALY_HOME_55TOKENS_ROLLBACK_20261123';
SELECT 'STEP03_OUTPUT|' || jsonb_build_object(
 'order9_ctx',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
 'snapshot_versions',(SELECT jsonb_array_length(identity_snapshot->'selected_versions') FROM saly.creative_orders WHERE id=9),
 'matches_context',(SELECT
 o.identity_snapshot IS NOT DISTINCT FROM jsonb_build_object(
 'context_set_id',o.context_set_id,'selected_versions',
 (SELECT jsonb_agg(jsonb_build_object('version_id',t.identity_version_id,'sha256',t.value_sha256,'role',t.role)
 ORDER BY t.identity_version_id) FROM saly.creative_context_tokens t WHERE t.context_set_id=o.context_set_id))
 FROM saly.creative_orders o WHERE o.id=9)
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5241087Z STEP03_OUTPUT|{"order9_ctx": 5, "matches_context": true, "snapshot_versions": 55}
```

### STEP04
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP04_INPUT|Set candidate token_codes for items 10,11,13; preserve terminal guard';
DO $attempt$
DECLARE err text;
BEGIN
 BEGIN
  UPDATE saly.creative_order_items
  SET context_json=jsonb_set(context_json,'{token_codes}',
      (SELECT jsonb_agg(e.code ORDER BY e.code) FROM saly.identity_versions v
       JOIN saly.identity_elements e ON e.id=v.element_id
       WHERE e.code LIKE 'candidate.%'),true)
  WHERE id=10 AND order_id=7;
  RAISE NOTICE 'STEP04_ITEM10_OUTPUT: UPDATED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP04_ITEM10_OUTPUT: %',err;
 END;
END $attempt$;
UPDATE saly.creative_order_items i
SET context_json=jsonb_set(i.context_json,'{token_codes}',
 (SELECT jsonb_agg(e.code ORDER BY e.code)
 FROM saly.identity_versions v JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE e.code LIKE 'candidate.%'),true)
WHERE i.id IN (11,13);
SELECT 'STEP04_OUTPUT|' || jsonb_build_object(
 'item10_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=10),
 'item11_token_count',(SELECT jsonb_array_length(context_json->'token_codes') FROM saly.creative_order_items WHERE id=11),
 'item13_token_count',(SELECT jsonb_array_length(context_json->'token_codes') FROM saly.creative_order_items WHERE id=13),
 'item11_ctx',(SELECT o.context_set_id FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id WHERE i.id=11)
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5250989Z psql:sandbox/creative_factory/rollback55_v1/test_transaction_rollback_pg17.sql:97: NOTICE:  STEP04_ITEM10_OUTPUT: SALY_CHAT_TERMINAL_ITEM_IMMUTABLE
2026-11-23T23:37:58.5260379Z STEP04_OUTPUT|{"item11_ctx": 4, "item10_token_codes": null, "item11_token_count": 53, "item13_token_count": 53}
```

### STEP05
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP05_INPUT|Add visual_rules to items 10,11,13; no new blocking rules';
DO $attempt$
DECLARE err text;
BEGIN
 BEGIN
  UPDATE saly.creative_order_items i
  SET acceptance_json=jsonb_set(acceptance_json,'{visual_rules}',
      jsonb_build_object('scope',o.code,'no_decorative_rays',true,
      'spacing','OBSERVE','typography','OBSERVE','radii','OBSERVE','elevation','OBSERVE'),true)
  FROM saly.creative_orders o WHERE i.order_id=o.id AND i.id=10;
  RAISE NOTICE 'STEP05_ITEM10_OUTPUT: UPDATED';
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP05_ITEM10_OUTPUT: %',err;
 END;
END $attempt$;
UPDATE saly.creative_order_items i
SET acceptance_json=jsonb_set(acceptance_json,'{visual_rules}',
  jsonb_build_object('scope',o.code,'no_decorative_rays',true,
    'spacing','OBSERVE','typography','OBSERVE','radii','OBSERVE','elevation','OBSERVE'),true)
FROM saly.creative_orders o
WHERE i.order_id=o.id AND i.id IN(11,13);
SELECT 'STEP05_OUTPUT|' || jsonb_build_object(
 'item10_has_visual_rules',(SELECT acceptance_json?'visual_rules' FROM saly.creative_order_items WHERE id=10),
 'item11_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=11),
 'item13_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=13)
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5266603Z psql:sandbox/creative_factory/rollback55_v1/test_transaction_rollback_pg17.sql:126: NOTICE:  STEP05_ITEM10_OUTPUT: SALY_CHAT_TERMINAL_ITEM_IMMUTABLE
2026-11-23T23:37:58.5274826Z STEP05_OUTPUT|{"item11_visual_rules": {"radii": "OBSERVE", "scope": "SALY_ADELANTO_V015_SINGLE_20261123", "spacing": "OBSERVE", "elevation": "OBSERVE", "typography": "OBSERVE", "no_decorative_rays": true}, "item13_visual_rules": {"radii": "OBSERVE", "scope": "SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123", "spacing": "OBSERVE", "elevation": "OBSERVE", "typography": "OBSERVE", "no_decorative_rays": true}, "item10_has_visual_rules": false}
```

### STEP06
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP06_INPUT|Compile modified L3B with 23 nonblocking checks (SQL source: proposed_l3b_observe_only.sql)';
\i sandbox/creative_factory/rollback55_v1/proposed_l3b_observe_only.sql
SELECT 'STEP06_OUTPUT|' || jsonb_build_object(
 'l3b_proposed_function_compiled',to_regprocedure('saly.creative_item_visual_contract_l3b(bigint)') IS NOT NULL,
 'existing_checks',5,
 'added_observation_checks',(SELECT count(*) FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
    JOIN saly.identity_elements e ON e.id=v.element_id
    WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
     AND e.family IN('SPACING','TYPOGRAPHY','LAYOUT','RULE')),
 'families',(SELECT jsonb_object_agg(family,qty) FROM
    (SELECT e.family,count(*) qty FROM saly.creative_context_tokens t JOIN saly.identity_versions v ON v.id=t.identity_version_id
     JOIN saly.identity_elements e ON e.id=v.element_id WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
     GROUP BY e.family) grouped)
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5294441Z STEP06_OUTPUT|{"families": {"RULE": 3, "COLOR": 32, "LAYOUT": 5, "SPACING": 7, "TYPOGRAPHY": 8}, "existing_checks": 5, "added_observation_checks": 23, "l3b_proposed_function_compiled": true}
```

### STEP06B
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP06B_INPUT|Try real L2A context binding for 11 and 13 without granting runtime authority';
DO $attempt$
DECLARE err text; obj jsonb;
BEGIN
 BEGIN
  obj:=saly.creative_item_context_l2a(11);
  RAISE NOTICE 'STEP06B_ITEM11_OUTPUT: CONTEXT_OK, token_count=%',jsonb_array_length(obj->'tokens');
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP06B_ITEM11_OUTPUT: %',err;
 END;
 BEGIN
  obj:=saly.creative_item_context_l2a(13);
  RAISE NOTICE 'STEP06B_ITEM13_OUTPUT: CONTEXT_OK, token_count=%',jsonb_array_length(obj->'tokens');
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS err=MESSAGE_TEXT;
  RAISE NOTICE 'STEP06B_ITEM13_OUTPUT: %',err;
 END;
END $attempt$;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5307080Z psql:sandbox/creative_factory/rollback55_v1/test_transaction_rollback_pg17.sql:172: NOTICE:  STEP06B_ITEM11_OUTPUT: CREATIVE_ITEM_TOKEN_NOT_IN_LOCKED_CONTEXT
2026-11-23T23:37:58.5309432Z psql:sandbox/creative_factory/rollback55_v1/test_transaction_rollback_pg17.sql:172: NOTICE:  STEP06B_ITEM13_OUTPUT: CREATIVE_ITEM_CONTEXT_NOT_ADMITTED
```

### STEP07
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP07_INPUT|Build exact prompt with original value_json and alias resolutions; attach official logo ref+sha; store BEFORE dispatch';
CREATE TEMP TABLE saly_handoff_simulation AS
WITH resolved AS (
 SELECT e.code,e.family,v.approval_status,v.id,
   CASE WHEN v.metadata->>'kind'='ALIAS'
      THEN (SELECT v2.value_json->'value'
            FROM saly.identity_versions v2 JOIN saly.identity_elements e2 ON e2.id=v2.element_id
            WHERE e2.code=v.metadata->>'alias_target_code')
      ELSE v.value_json->'value' END AS real_value
 FROM saly.creative_context_tokens t
 JOIN saly.identity_versions v ON v.id=t.identity_version_id
 JOIN saly.identity_elements e ON e.id=v.element_id
 WHERE t.context_set_id=(SELECT context_set_id FROM saly.creative_orders WHERE id=9)
),
msg AS (
 SELECT jsonb_agg(jsonb_build_object('token_code',code,'family',family,'status',approval_status,
         'version_id',id,'real_value',real_value) ORDER BY code) AS tokens,
    string_agg(format('%s = %s [%s]',code,real_value::text,approval_status),E'\n' ORDER BY code) AS token_lines,
    count(*) AS token_count, count(*) FILTER(WHERE real_value IS NULL) AS unresolved
 FROM resolved
)
SELECT 9::bigint AS order_id,13::bigint AS item_id,
 'HOME SALY, iPhone 16 Pro. Cambio solicitado: Mi disponible -> Cómo se calcula; sin monto. '||
 'Conservar las demás regiones y copys. TOKEN_VALUES:'||E'\n'||token_lines||E'\n'||
 'LOGO_FILE: 01_SALY_PRINCIPAL_TRANSPARENTE.png'||E'\n'||
 'LOGO_SOURCE: https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view'
 AS prompt_utf8,
 tokens AS token_payload,
 jsonb_build_array(jsonb_build_object('name','01_SALY_PRINCIPAL_TRANSPARENTE.png',
   'url','https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view',
   'sha256','5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995',
   'file_attached_to_renderer',false)) AS attachments,
 token_count,unresolved,false::boolean AS transmitted
FROM msg;
SELECT 'STEP07_OUTPUT|' || jsonb_build_object(
 'order_id',order_id,'item_id',item_id,'token_count',token_count,
 'unresolved_alias_values',unresolved,
 'attachment_count',jsonb_array_length(attachments),
 'prompt_sha256',encode(extensions.digest(convert_to(prompt_utf8,'UTF8'),'sha256'),'hex'),
 'prompt_bytes',octet_length(prompt_utf8),
 'transmitted',transmitted,'handoff_saved_before_send',true
)::text FROM saly_handoff_simulation;
SELECT 'STEP07_EXACT_INPUT_PAYLOAD|' || jsonb_build_object(
 'order_id',order_id,'item_id',item_id,'prompt_utf8',prompt_utf8,
 'attachments',attachments,'token_values',token_payload,
 'prompt_sha256',encode(extensions.digest(convert_to(prompt_utf8,'UTF8'),'sha256'),'hex'),
 'transmitted',transmitted)::text FROM saly_handoff_simulation;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5339305Z STEP07_OUTPUT|{"item_id": 13, "order_id": 9, "token_count": 55, "transmitted": false, "prompt_bytes": 4502, "prompt_sha256": "6edb2cc3aee48ec734d826fa16d35600c9403a539ece652fc42a489a49eb57fc", "attachment_count": 1, "unresolved_alias_values": 0, "handoff_saved_before_send": true}
2026-11-23T23:37:58.5378574Z STEP07_EXACT_INPUT_PAYLOAD|{"item_id": 13, "order_id": 9, "attachments": [{"url": "https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view", "name": "01_SALY_PRINCIPAL_TRANSPARENTE.png", "sha256": "5573f0503ddb3dd1029221a9ee336d0e28155c392598286628dbf294da146995", "file_attached_to_renderer": false}], "prompt_utf8": "HOME SALY, iPhone 16 Pro. Cambio solicitado: Mi disponible -> Cómo se calcula; sin monto. Conservar las demás regiones y copys. TOKEN_VALUES:\ncandidate.saly_ds_v1.accessibility.supports_font_scaling = true [CANDIDATE]\ncandidate.saly_ds_v1.accessibility.touch_target_min_px = 44 [CANDIDATE]\ncandidate.saly_ds_v1.accessibility.use_color_as_sole_signal = false [CANDIDATE]\ncandidate.saly_ds_v1.color.accent.benefits.purple = \"#923CF3\" [CANDIDATE]\ncandidate.saly_ds_v1.color.accent.reward.gold.700 = \"#9D6800\" [CANDIDATE]\ncandidate.saly_ds_v1.color.accent.reward.yellow = \"#F6B400\" [CANDIDATE]\ncandidate.saly_ds_v1.color.brand.green.600 = \"#008200\" [CANDIDATE]\ncandidate.saly_ds_v1.color.ink.gray.600 = \"#5C6577\" [CANDIDATE]\ncandidate.saly_ds_v1.color.ink.navy.900 = \"#081631\" [CANDIDATE]\ncandidate.saly_ds_v1.color.stroke.gray.200 = \"#E4E8E8\" [CANDIDATE]\ncandidate.saly_ds_v1.color.surface.canvas = \"#F5F7F7\" [CANDIDATE]\ncandidate.saly_ds_v1.color.surface.mint = \"#EAF9EE\" [CANDIDATE]\ncandidate.saly_ds_v1.color.surface.reward = \"#FFF9E9\" [CANDIDATE]\ncandidate.saly_ds_v1.color.surface.white = \"#FFFFFF\" [CANDIDATE]\ncandidate.saly_ds_v1.radius.radius.button.primary = 14 [CANDIDATE]\ncandidate.saly_ds_v1.radius.radius.card.hero = 24 [CANDIDATE]\ncandidate.saly_ds_v1.radius.radius.card.secondary = 16 [CANDIDATE]\ncandidate.saly_ds_v1.radius.radius.pill = 999 [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.action.primary.bg = \"#008200\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.action.primary.text = \"#FFFFFF\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.border.subtle = \"#E4E8E8\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.module.benefits.icon = \"#923CF3\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.module.plus.bg = \"#EAF9EE\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.module.plus.icon = \"#008200\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.module.rewards.bg = \"#FFF9E9\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.module.rewards.icon = \"#9D6800\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.surface.card = \"#FFFFFF\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.surface.page = \"#FFFFFF\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.surface.subtle = \"#F5F7F7\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.text.primary = \"#081631\" [CANDIDATE]\ncandidate.saly_ds_v1.semantic.color.text.secondary = \"#5C6577\" [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.12 = 12 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.16 = 16 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.24 = 24 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.32 = 32 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.4 = 4 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.48 = 48 [CANDIDATE]\ncandidate.saly_ds_v1.spacing.space.8 = 8 [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.amount.hero = {\"weight\": 700, \"size_px\": 48, \"line_height_px\": 56} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.body.default = {\"weight\": 400, \"size_px\": 16, \"line_height_px\": 24} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.body.secondary = {\"weight\": 400, \"size_px\": 14, \"line_height_px\": 20} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.button.primary = {\"weight\": 600, \"size_px\": 16, \"line_height_px\": 24} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.caption = {\"weight\": 400, \"size_px\": 12, \"line_height_px\": 16} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.family.base = \"Inter, system-ui, sans-serif\" [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.heading.card = {\"weight\": 600, \"size_px\": 20, \"line_height_px\": 28} [CANDIDATE]\ncandidate.saly_ds_v1.typography.font.heading.section = {\"weight\": 700, \"size_px\": 22, \"line_height_px\": 30} [CANDIDATE]\ncandidate.saly_home_v3.color.surface.benefits = \"#F4E7FD\" [CANDIDATE]\ncandidate.saly_home_v3.elevation.card.hero = {\"blur\": 16, \"color\": \"#081631\", \"spread\": 0, \"opacity\": 0.1, \"offset_x\": 0, \"offset_y\": 4} [CANDIDATE]\ncandidate.saly_home_v3.semantic.color.module.benefits.bg = \"#F4E7FD\" [CANDIDATE]\ncandidate.saly_home_v3.semantic.color.navigation.active = \"#008200\" [CANDIDATE]\ncandidate.saly_home_v3.semantic.color.navigation.background = \"#FFFFFF\" [CANDIDATE]\ncandidate.saly_home_v3.semantic.color.navigation.inactive = \"#5C6577\" [CANDIDATE]\ncandidate.saly_home_v3.semantic.color.notification.badge = \"#E62F40\" [CANDIDATE]\ncolor.action.primary.bg = \"#008200\" [APPROVED]\ncolor.brand.primary = \"#00C853\" [APPROVED]\nLOGO_FILE: 01_SALY_PRINCIPAL_TRANSPARENTE.png\nLOGO_SOURCE: https://drive.google.com/file/d/1xQyhrhrqgjHvkPVSg1vYCgDjlFV7ox78/view", "transmitted": false, "token_values": [{"family": "RULE", "status": "CANDIDATE", "real_value": true, "token_code": "candidate.saly_ds_v1.accessibility.supports_font_scaling", "version_id": 54}, {"family": "RULE", "status": "CANDIDATE", "real_value": 44, "token_code": "candidate.saly_ds_v1.accessibility.touch_target_min_px", "version_id": 53}, {"family": "RULE", "status": "CANDIDATE", "real_value": false, "token_code": "candidate.saly_ds_v1.accessibility.use_color_as_sole_signal", "version_id": 55}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#923CF3", "token_code": "candidate.saly_ds_v1.color.accent.benefits.purple", "version_id": 19}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#9D6800", "token_code": "candidate.saly_ds_v1.color.accent.reward.gold.700", "version_id": 17}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#F6B400", "token_code": "candidate.saly_ds_v1.color.accent.reward.yellow", "version_id": 16}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#008200", "token_code": "candidate.saly_ds_v1.color.brand.green.600", "version_id": 10}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#5C6577", "token_code": "candidate.saly_ds_v1.color.ink.gray.600", "version_id": 15}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#081631", "token_code": "candidate.saly_ds_v1.color.ink.navy.900", "version_id": 11}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#E4E8E8", "token_code": "candidate.saly_ds_v1.color.stroke.gray.200", "version_id": 20}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#F5F7F7", "token_code": "candidate.saly_ds_v1.color.surface.canvas", "version_id": 13}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#EAF9EE", "token_code": "candidate.saly_ds_v1.color.surface.mint", "version_id": 14}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFF9E9", "token_code": "candidate.saly_ds_v1.color.surface.reward", "version_id": 18}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFFFFF", "token_code": "candidate.saly_ds_v1.color.surface.white", "version_id": 12}, {"family": "LAYOUT", "status": "CANDIDATE", "real_value": 14, "token_code": "candidate.saly_ds_v1.radius.radius.button.primary", "version_id": 51}, {"family": "LAYOUT", "status": "CANDIDATE", "real_value": 24, "token_code": "candidate.saly_ds_v1.radius.radius.card.hero", "version_id": 49}, {"family": "LAYOUT", "status": "CANDIDATE", "real_value": 16, "token_code": "candidate.saly_ds_v1.radius.radius.card.secondary", "version_id": 50}, {"family": "LAYOUT", "status": "CANDIDATE", "real_value": 999, "token_code": "candidate.saly_ds_v1.radius.radius.pill", "version_id": 52}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#008200", "token_code": "candidate.saly_ds_v1.semantic.color.action.primary.bg", "version_id": 21}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFFFFF", "token_code": "candidate.saly_ds_v1.semantic.color.action.primary.text", "version_id": 22}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#E4E8E8", "token_code": "candidate.saly_ds_v1.semantic.color.border.subtle", "version_id": 28}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#923CF3", "token_code": "candidate.saly_ds_v1.semantic.color.module.benefits.icon", "version_id": 33}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#EAF9EE", "token_code": "candidate.saly_ds_v1.semantic.color.module.plus.bg", "version_id": 30}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#008200", "token_code": "candidate.saly_ds_v1.semantic.color.module.plus.icon", "version_id": 29}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFF9E9", "token_code": "candidate.saly_ds_v1.semantic.color.module.rewards.bg", "version_id": 32}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#9D6800", "token_code": "candidate.saly_ds_v1.semantic.color.module.rewards.icon", "version_id": 31}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFFFFF", "token_code": "candidate.saly_ds_v1.semantic.color.surface.card", "version_id": 26}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFFFFF", "token_code": "candidate.saly_ds_v1.semantic.color.surface.page", "version_id": 25}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#F5F7F7", "token_code": "candidate.saly_ds_v1.semantic.color.surface.subtle", "version_id": 27}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#081631", "token_code": "candidate.saly_ds_v1.semantic.color.text.primary", "version_id": 23}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#5C6577", "token_code": "candidate.saly_ds_v1.semantic.color.text.secondary", "version_id": 24}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 12, "token_code": "candidate.saly_ds_v1.spacing.space.12", "version_id": 44}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 16, "token_code": "candidate.saly_ds_v1.spacing.space.16", "version_id": 45}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 24, "token_code": "candidate.saly_ds_v1.spacing.space.24", "version_id": 46}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 32, "token_code": "candidate.saly_ds_v1.spacing.space.32", "version_id": 47}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 4, "token_code": "candidate.saly_ds_v1.spacing.space.4", "version_id": 42}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 48, "token_code": "candidate.saly_ds_v1.spacing.space.48", "version_id": 48}, {"family": "SPACING", "status": "CANDIDATE", "real_value": 8, "token_code": "candidate.saly_ds_v1.spacing.space.8", "version_id": 43}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 700, "size_px": 48, "line_height_px": 56}, "token_code": "candidate.saly_ds_v1.typography.font.amount.hero", "version_id": 35}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 400, "size_px": 16, "line_height_px": 24}, "token_code": "candidate.saly_ds_v1.typography.font.body.default", "version_id": 38}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 400, "size_px": 14, "line_height_px": 20}, "token_code": "candidate.saly_ds_v1.typography.font.body.secondary", "version_id": 39}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 600, "size_px": 16, "line_height_px": 24}, "token_code": "candidate.saly_ds_v1.typography.font.button.primary", "version_id": 41}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 400, "size_px": 12, "line_height_px": 16}, "token_code": "candidate.saly_ds_v1.typography.font.caption", "version_id": 40}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": "Inter, system-ui, sans-serif", "token_code": "candidate.saly_ds_v1.typography.font.family.base", "version_id": 34}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 600, "size_px": 20, "line_height_px": 28}, "token_code": "candidate.saly_ds_v1.typography.font.heading.card", "version_id": 36}, {"family": "TYPOGRAPHY", "status": "CANDIDATE", "real_value": {"weight": 700, "size_px": 22, "line_height_px": 30}, "token_code": "candidate.saly_ds_v1.typography.font.heading.section", "version_id": 37}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#F4E7FD", "token_code": "candidate.saly_home_v3.color.surface.benefits", "version_id": 57}, {"family": "LAYOUT", "status": "CANDIDATE", "real_value": {"blur": 16, "color": "#081631", "spread": 0, "opacity": 0.1, "offset_x": 0, "offset_y": 4}, "token_code": "candidate.saly_home_v3.elevation.card.hero", "version_id": 63}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#F4E7FD", "token_code": "candidate.saly_home_v3.semantic.color.module.benefits.bg", "version_id": 61}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#008200", "token_code": "candidate.saly_home_v3.semantic.color.navigation.active", "version_id": 58}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#FFFFFF", "token_code": "candidate.saly_home_v3.semantic.color.navigation.background", "version_id": 60}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#5C6577", "token_code": "candidate.saly_home_v3.semantic.color.navigation.inactive", "version_id": 59}, {"family": "COLOR", "status": "CANDIDATE", "real_value": "#E62F40", "token_code": "candidate.saly_home_v3.semantic.color.notification.badge", "version_id": 62}, {"family": "COLOR", "status": "APPROVED", "real_value": "#008200", "token_code": "color.action.primary.bg", "version_id": 7}, {"family": "COLOR", "status": "APPROVED", "real_value": "#00C853", "token_code": "color.brand.primary", "version_id": 8}], "prompt_sha256": "6edb2cc3aee48ec734d826fa16d35600c9403a539ece652fc42a489a49eb57fc"}
```

### STEP08
INPUT (SQL literalmente ejecutado):
```sql
SELECT 'STEP08_INPUT|ROLLBACK entire simulation; no database modifications persist';
ROLLBACK;
SELECT 'STEP08_OUTPUT_AFTER_ROLLBACK|' || jsonb_build_object(
 'version21_alias_kind',(SELECT metadata->>'kind' FROM saly.identity_versions WHERE id=21),
 'simulated_context_rows',(SELECT count(*) FROM saly.creative_context_sets WHERE code='SALY_HOME_55TOKENS_ROLLBACK_20261123'),
 'order9_context_set_id',(SELECT context_set_id FROM saly.creative_orders WHERE id=9),
 'item11_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=11),
 'item13_token_codes',(SELECT context_json->'token_codes' FROM saly.creative_order_items WHERE id=13),
 'item13_visual_rules',(SELECT acceptance_json->'visual_rules' FROM saly.creative_order_items WHERE id=13),
 'proposed_l3b_function_exists',to_regprocedure('saly.creative_item_visual_contract_l3b(bigint)') IS NOT NULL,
 'handoff_temp_table_exists',to_regclass('saly_handoff_simulation') IS NOT NULL
)::text;
```
OUTPUT (log original con timestamp):
```text
2026-11-23T23:37:58.5407984Z ROLLBACK
2026-11-23T23:37:58.5408714Z STEP08_OUTPUT_AFTER_ROLLBACK|{"item11_token_codes": null, "item13_token_codes": null, "item13_visual_rules": null, "version21_alias_kind": null, "order9_context_set_id": 3, "simulated_context_rows": 0, "handoff_temp_table_exists": false, "proposed_l3b_function_exists": false}
2026-11-23T23:37:58.5409577Z PASS_SALY_55_TOKEN_SINGLE_TRANSACTION_ROLLBACK_NO_PERSISTENCE
```

# IG M10.13 — CP3 / Lote 2: Curator semántica y referencias

**Objeto:** Desconectar los 2 restantes alcanzables desde Curator dentro de M10.4, sin alterar fuentes congeladas.

**Call site:** `programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)` (nonfrozen). Cambiar exactamente:
- `fn_input_governance_semantic_probe_v2_cached_v1(...p_graph)` → sobrecarga de la función CURRENT `fn_input_governance_semantic_probe_v2(...p_graph)`.
- `fn_input_governance_field_reference_probe_v1_cached_v1(...p_graph)` → sobrecarga CURRENT `fn_input_governance_field_reference_probe_v1(...p_graph)`.

**Dependencia interna:** sobrecarga `fn_input_governance_semantic_probe_v1(...p_graph)`, para que v2 use versión CURRENT en vez de `semantic_probe_v1_cached_v1`. Código derivado de las fuentes vivas, sin cambios de semántica ni reconstrucción del grafo.

**Guardias:** exact `pg_proc` hashes, 47 familias RUN 951, 94 comparaciones JSON exactas (47 v2 + 47 field), presupuesto 3x+150ms por familia agregada, no cambios M10.4, ACL público denegado, recibo `operational-event/v2` con `checkpoint_pass=false`. Fallar íntegramente ante drift/resultado desigual. Aplicar solo mediante `ACTUALIZACION_DB_LF` / `DB_WRITE_TRANSPORT` / LF Migration Merge Train.

**No incluido:** sustitución del anchor compartido `public.fn_lf_evidence_ledger_anchor_v1`, eliminación/REVOKE de legacy congelado, AUD045, cambio de Router, cierre de CP3.

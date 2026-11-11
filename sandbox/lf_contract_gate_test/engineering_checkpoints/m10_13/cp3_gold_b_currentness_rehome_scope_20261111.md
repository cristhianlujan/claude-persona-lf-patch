# LF M10.13 / CP3 — Lote 3

**Objetivo:** reemplazar una llamada SQL legacy de Gold B por función canónica vigente, sin crear ningún nuevo mecanismo ni tocar M10.4.

**Fuente no congelada:** `programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)`, fuente original MD5 `212ebc254d8a1f3a0bffb7724f246f08`.

**Remover llamada:** `programacion.fn_input_readiness_run_is_current_cached_v2(p_run_id)` MD5 congelado `99d54f5dcc27617831b0eb6098000777`.

**Usar:** `programacion.fn_input_run_is_source_current(p_run_id)`, MD5 `2da27107c85d593ca54068658c3cc7d4`. La función congelada ejecuta directamente esta función, sin transformación.

**Pruebas de admisión:** 4 pares RUN 951, 944, 949 y run inexistente, fuente pin y cardinalidad de reemplazo exactamente 1; hash y ACL M10.4 intactos; recibo `ARTIFACT_RECONCILED` no terminal y readback tras Merge Train.

**No tocar:** `public.fn_lf_evidence_ledger_anchor_v1`, EVIDENCE_LEDGER, Router, Edge, políticas, work items ni checkpoints.

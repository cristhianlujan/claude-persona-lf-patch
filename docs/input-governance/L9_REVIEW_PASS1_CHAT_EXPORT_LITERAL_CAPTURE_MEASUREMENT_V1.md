# LF — Lote 9 · medición de captura literal desde exportación de chat

**Estado:** DRAFT / NO-GO · sandbox PostgreSQL 18 con ROLLBACK · NO oficial, NO producción, NO merge, NO apply live, NO Router, NO RUN históricos.

## Fuente y verificación
- Fuente aportada por el auditor: chat `c/6af4e9a2-f0f4-83ea-84af-c5a66452cba1`, 154 líneas originales `id|ALLOW/BLOCK|cita`, orden exacto y salto LF final. Etiqueta **`REAL_REVIEW_PASS1_CHAT_EXPORT_NOT_NATIVE_IG_RECEIPT`**.
- SHA256 esperado de bytes UTF-8 exactos: `d319670079ece0e0285e37a3194a1e1c9e784e9b7b6f5e7d35ed4882200bf4bc`; un hash no coincidente debe producir fallo de CI. Modelo revisor **`REVIEWER_CHAT_EXPORT_MODEL_UNATTESTED`**. No atribuir a Claude ni ChatGPT. Los cinco pases del mismo modelo no acreditan independencia.
- Almacén: `sandbox/lf_contract_gate_test/rule_promotion_v1/lote9_real_review_pass1_chat_export_model_unattested.txt` y metadatos `.json`. **No es recibo nativo #3682** y no se puede presentar como evidencia auténtica de Step70.
- El fixture L6 recibió SOLO corrección de etiqueta a `REVIEW_5PASS_VERDICTS_NOT_NATIVE_IG_RECEIPT_MODEL_UNATTESTED`; conservar IDs, veredictos y 5 pasadas reportadas. Nombre histórico de archivo L6 no acredita identidad del modelo.

## Dos mediciones distintas y sin alterar el gate
1. **Diagnóstico sobre los campos de fuente congelada**: 154/154 citas aparecen en JSON completo (regla base o propuesta, incluida metadata de operación/config). Solo se consideran elegibles si son subsecuencia exacta de `base_rule.description` o `proposal.description`, mínimo 40 caracteres y 6 palabras. **106 elegibles**, **22 fuera de description** y **26 cortas dentro de description**. Son categorizaciones analíticas, NO dictámenes de un juez.
2. **Respuesta REAL del gate L7 sin modificar**: en `lf_rule_promotion_citation_line_check_v1` se valida **longitud antes que literalidad**. Las 22 citas de metadatos son también cortas; por tanto el código real para **las 48** es `L7_QUOTE_EMPTY_OR_TRIVIAL`, no `L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT`. La distinción 22+26 existe en el diagnóstico de fuente, no en el código de bloqueo actual. No cambiar el orden ni los MD5 del gate por una expectativa no demostrada.
3. Las diez propuestas `CREATE` emplean un `rule_code` nuevo distinto de la regla base: la ruta existente de `source_publish_v1` también rechaza su congelación con `L7_SOURCE_OR_RULE_MISMATCH`. El gate permanece **fail-closed**; para citas fuera de descripción no debe fingirse congelación exitosa.
4. **De los 24 ALLOW, 22 son elegibles**. Los dos no elegibles por el umbral concreto son **`K00C8E827`** (39 caracteres) y **`K00CF241C`** (5 palabras); no `K0113B7A3`, cuya cita tiene 40 caracteres y 6 palabras. Ambas diferencias se conservarán en los registros RAW.
5. Las **106 citas elegibles** pasan la estructura de captura L7/L8 en PG18 con recibo/Step70 **simulados** del sandbox; los 22 ALLOW elegibles quedan en `PROFILE_OWNER_REVIEW_ONLY` **sin aprobación acreditada**; los BLOCK pasan a humano. Las 48 restantes se bloquean y no promocionan. Todos los intentos de `apply` quedan bloqueados; cada transacción debe devolver readback de ROLLBACK con 0 fuentes y 0 capturas.
6. **La literalidad no demuestra pertinencia semántica**. El perfil propietario debe revisar la relevancia de cita para veredicto, con autoridad separada de la propuesta de IG. Al compartir modelo con IG, sería una prueba de **consistencia**, no independencia. Ni estas citas ni un gate estructural pueden autorizar por sí mismos `VIGENTE`.

## Autoridad, límites y cierre
No se instala ninguna función ni trigger nuevo en L9. Se reutiliza exactamente el L7/L8 anterior en PG18; MD5 de `line_check`, `capture_record`, `citation_verify`, `blind_verdict_verify`, `apply`, `existing_ig_citation_verify`, `L8 reuse guard` deben conservar sus valores anteriores. Tests L6 cambian etiqueta y fuente de metadatos; valores de las 154 decisiones NO cambian.

**UNVERIFIED:** identidad del modelo o firma criptográfica del chat exportado, autoría de la evidencia nativa #3682/Step70, enlace OIDC/roles del bridge, perfil propietario real, relevancia semántica, independencia, reproducción L9 en banco del auditor, PASE y autorización de producción. **NO-GO** hasta pruebas y readback gobernado real.

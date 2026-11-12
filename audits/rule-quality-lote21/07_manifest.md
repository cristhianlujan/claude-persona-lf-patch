# L27 — Prefacio de actualización documental del manifiesto L21

**ESTADO ACTUAL DEL REGISTRO:** 32 decisiones; **3 DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA** (L16-Q03/Q04/Q05), **1 RECOMENDADA_SIN_CONFIRMAR** (L16-Q01), **28 PENDIENTE**. **0/32 FIRMADAS**. Q04 retiene cuatro temas abiertos: reintentos automáticos, recordatorios, mora y destino contable de INCOBRABLE. Q02 ledger PENDIENTE, construcción asignada a Producto/QA fuera de IG.

**AVISO DE PROVENANCE:** el texto del manifiesto L21 reproducido debajo describe exclusivamente el corte histórico L21. Sus referencias a "firma 0/32" siguen correctas; las 32 "PENDIENTE" son estado histórico, **no el estado actual L27**. Su afirmación sobre recomendación MFA "C=dejar" NO significa confirmación del dueño; en L27 es **RECOMENDADA_SIN_CONFIRMAR**.

**SIN SUPABASE NI PG18 EN L27:** todas las consultas S21_01..S21_06 del SQL reproducido son evidencia histórica, no ejecutadas en este lote. L19/L21 acreditan 45 permisos y cero asignaciones en cuatro tablas; "16 resource_type y sin permiso pricing" es dato comunicado por el dueño, pendiente de readback SQL independiente, no un SELECT nuevo. Ver `audits/rule-quality-lote27/`.

**Tablero y criterio GO/NO-GO L21 permanecen byte por byte:** 15/36 REAL_EN_SANDBOX, 0/36 E2E productivo en el marco L21, 15 gates sin verificar, NO-GO. Este lote sólo registra decisiones, no adopta L25 ni elige responsable de deuda contable.

**JUEZ:** GPT-6, mismo modelo, sin independencia; **FIRMA**: ninguna acreditada. **PRODUCCIÓN NO-GO / UNVERIFIED**.

---

# Lote 21 — Manifiesto de evidencia, alcance y NO-GO

## Identidad de la ejecución
- **Auditor/juez:** GPT-6, **mismo modelo GPT**, no independiente. Usuario solicita «Claude»: **no hay identidad Claude acreditada**. No hubo segundo juez ni recibo de independencia.
- **Autoridad EKB:** INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4, `CANDIDATO VERIFICADO PARCIALMENTE`, lectura de copia proporcionada; SHA-256 exacto del archivo DOCX `234fafb2b06b91e96a979feac138069ec75863aae1bd75aea93c72740c075f79`. Los contratos runtime vivos mantienen prioridad.
- **Supabase:** `mhwmirqcgxxukpctffuv`, consultas exclusivamente **SELECT** como fuente. PostgreSQL 17.6 según L19/L20; no afirmar que el PG18 del dueño es esta instancia. Cero DML/DDL, cero producción, cero escrituras en fuente o RUN.
- **Rama:** `lf/issue-3779-lote21-owner-signoff-dossier-v1` creada desde SHA exacto `5ee4c92632d41c31fdec6807dee99a2207104d4a`. Único espacio de escritura: documentos/CSV/SQL de `audits/rule-quality-lote21/`.
- **Objetivo:** paquete documental de decisiones. **NO-GO / UNVERIFIED** hasta firma legítima y verificación posterior por actor competente. No se pidió ni ejecutó un cambio en RUN o activos.

## Evidencia directa de Supabase: SELECT + SHA-256 de resultado

SHA-256 calculado en el servidor a partir del arreglo JSONB de **todas las filas**, ordenadas por serialización textual JSONB, UTF-8. El resultado cambia si datos o reloj afectan la consulta; conserva la foto lógica de la lectura. SQL literal: `06_select_evidencia_live.sql`.

| SELECT | Filas | SHA-256 |
|---|---:|---|
| S21_01 — conteos LF/SALY, perfiles, RUN, leases | 1 | `4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933` |
| S21_02 — presencia de 4+5 campos lifecycle | 9 | `0a8624c58887c553249137fe556594d311ced96ced7ed4cf12d7af0fa34c7090` |
| S21_03 — MFA factor/rule status | 12 | `3cff7e13769ed846a69c274f88e4f89cabea989a13c2c6488a6e7acc0ca371ee` |
| S21_04 — cuatro funciones legacy | 4 | `344c5611f98c1933f8e6337e53e24b74e3cdda4af7e045ba96335878e7e97016` |
| S21_05 — presencia/ausencia owners L13 vs tablas LF/SALY | 7 | `44e9708a9659dcec3d11e9dcc4ff304a025c23606cce150852058b7a08512f83` |
| S21_06 — AUTH-018, AUTH-022 y SALY rules | 16 | `30967bfb310f175f85bbd171c91a350a6b5c8712b81df662919e607e331f0313` |

**OBJETIVO:** LF 578=412 VIGENTE +166 CANDIDATO; SALY 14 con `vigente=true`; 232 RUN `IN_PROGRESS`, 184 `started_at` mayores a 30 días al momento del SELECT; 8 lease expirados; 8 perfiles LF app, 45 permisos, 129 vínculos perfil-permiso, 0 asignaciones usuario-perfil inspeccionadas; 1 proyecto SALY. Conservar exactitud del campo `started_at` para la antigüedad de 184, que no es `updated_at`.

**OBJETIVO MFA:** política general SEC-B2B-MFA ID 3 **VIGENTE**, política de factor SEC-B2B-MFA-FACTOR-ELIGIBILITY ID 19 **CANDIDATO**, recuperación ID 20 **CANDIDATO**; regla AUTH-018 CANDIDATO y AUTH-022 VIGENTE. El número «11 reglas MFA CANDIDATO» fue informado como reproducido por el dueño, **no contado de nuevo de manera independiente**; evitar presentarlo como resultado de S21_03.

**OBJETIVO lifecycle:** cuatro columnas faltan en LF y cinco en SALY (incluyendo `lifecycle_state`). La cantidad 426 reglas activas es población potencial a reconciliar, **NO** divergencias reales detectadas. No hay registro productivo L13 para comparación.

**OBJETIVO funciones:** `public.lf_rule_promotion_apply_batch_v1`, `public.lf_rule_promotion_decide_batch_v1`, `public.lf_rule_promotion_report_v1`, `public.lf_rule_promotion_guard_v1` aparecen en catálogo con firmas. **NO PROBADO** que sean compatibles con un futuro esquema tras migración.

## Fuentes de otros lotes — GitHub (NO extrapolar alcance)
- L16: HEAD documental `63c96935dd594f13cec4e3291c2a58931094cb7a`, decisiones 12 en `audits/rule-quality-lote16/05_decisiones_dueno.md`, blob `57743fc2c89c2b66df128d3759af52e1e428d0be`. 15 familias; 23 pertenencias dudosas; 57 pendientes; 3 referencias; 20 pares. Los SHA SQL anteriores están en el mismo paquete L16.
- L19: HEAD documental `5ee4c92632d41c31fdec6807dee99a2207104d4a`, decisiones 8 en `audits/rule-quality-lote19/07_preguntas_dueno.csv` blob `0f1d73e2969145f1ca47c056aa6b53f9cab5dc26`. R01 SHA256 `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0`; 232 RUN, clasificación 6/56/4/166 propuesta, 8 leases vencidos.
- L13: `docs/rule-quality-lote13/03_design_generic.md` blob `26a06c7c64ab40368f4da22d478298676bdcbfcd`; modelo `projects,actors,families,category_family_map` probado **en sandbox**; intervalos LF 90d/SALY 60d **SINTÉTICOS**.
- L17: `docs/rule-quality-lote17/03_design_results_limits.md` blob `6c873b32f9bd7004b82f80c64e40c297cdb1a3af`; JWT/HMAC fixture, no Supabase Auth real.
- L18: CI probado commit `abeea154a559759dcf2f56f42c8fd106ca768b64`, Actions #43299324221; `docs/rule-quality-lote18/03_integrated_cycle_audit.md` blob `64f763defa2e929e87539a5507126860ffd61577`. 3 escenarios y 12 etapas; Router, perfil, RUN, IG, Curator y cierre **no ejecutados como servicios nativos**.
- L20: CI probado commit `b7e362b36e82b4075bc9effc363ec777c6756d87`, Actions #43305361826; `docs/rule-quality-lote20/03_resultado_y_limites.md` blob `4b28a22978061bb049c541a0713636597e830d3b`, 17/17 pruebas nuevas y 18/18 scripts PG18; **L20 solo se aplicó a PG18 sandbox**, sin SQL LIVE. UP draft SHA256 `ef65c2f5d8c64547d017d410e14093403890de281d83aaf924437b7d6db29819`; DOWN draft SHA256 `c2bd75ea6e2858cc4e4c692b6a5c253637fd16fb3f7a6638135cbd8a1ca84b30`.
- Gates congelados, MD5 en PG18 L20: apply `86b0494984edf95cf0f9c0a0df67000b`; capture_record `89cbfac4162dbc9f8ecca59f2c3ab4c3`; citation_verify `773a62783baa5edbe967200cac66b8c3`; l8_guard `522d12f0843be1da3c785cef3c0bf3fc`. Son hash de PG18, NO verificación reciente en producción.

## Métrica honesta y derivación
- Tabla de 12 etapas para 3 escenarios: A_NEW=5 REAL_EN_SANDBOX, 6 SINTETICO,1 NO_PROBADO; B_CORRECTED=5/6/1; C_SALY_NEW=5/2/5.
- Total: **15 REAL_EN_SANDBOX / 36 celdas = 41,7%** de la matriz bajo esta definición, no disponibilidad de producto.
- 18/18 scripts PG18 PASS = **100% ejecución del inventario de scripts**, no 100% etapas reales ni E2E.
- Evidencia nativa productiva acreditada en **estos lotes**: 0/36 = 0%; no inferir ausencia de componentes del producto fuera del alcance.
- Firma del dueño: **0/32 decisiones = 0% verificadas**, al no existir recibo de firma emitido.

## Limitaciones y prohibiciones
- Ninguna cifra de divergencias LF↔L13/SALY probada; **no confundir 426 activas con 426 divergencias**.
- Las seis categorías A/B/C/D de L19 y su reclasificación son preliminares; ninguna autoriza cerrar o reintentar RUN.
- L16-Q01 letras originales A/promover, B/mantener, C/quitar. L21 **transparente cambia** B/quitar y C/dejar por instrucción explícita del dueño; no atribuir esa convención al texto L16 original.
- **Backup físico/PITR/restore:** NO_VERIFICADO. Su existencia, ventanas, operadores, checksum y tiempos NO se pueden derivar con este SELECT.
- **Supabase Auth real, Step70/OIDC, Curator, 11 pasos nativos, owner firmado, juez independiente:** NO_PROBADO por estos lotes.
- **No ejecutar:** ninguna propuesta de borrador UP/DOWN, DML/DDL, RUN cerrar/reintentar, activación de regla o política, operación de producción, merge, alteración de cuatro funciones legacy o lectura de secretos.
- El readback final GitHub y SHA del último commit debe verificarse después de publicar este manifiesto. Un READBACK_PASS documental **no es PASS funcional**.

## Índice
`00_portada_dossier.md`, `01_registro_unico_decisiones.md`, `02_matriz_bloqueos_produccion.md`, `03_tablero_12_etapas.md`, `04_go_no_go_firmable.md`, `05_respuestas_dueno.csv`, `06_select_evidencia_live.sql`, `07_manifest.md`.

**Dictamen:** NO-GO / UNVERIFIED. **Solicitud posterior solo cuando el dueño firme con identidad, alcance y recibos; no por esta entrega.**

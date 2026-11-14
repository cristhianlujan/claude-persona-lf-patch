# LF / Input Governance — 17 familias PARTIAL, pantalla 44, run 956

**Estado:** evaluación por SELECT + migración gobernada de mapeo. **NO** cambia cobertura del run 956, reglas, políticas operativas, enlaces existentes ni promociones. **Criterio:** 1 heredar transversal VIGENTE, 2 atar política existente, 3 regla candidata con casos, 4 decisión cerrada del owner. La clasificación identifica la **primera vía de reutilización**, no declara que el blocker del Curator haya desaparecido.

## Alcance y fuentes

- `programacion.input_readiness_runs.id=956`: `pantalla_id=44`, `version_id=19`, `B2B-CARGA-002`. `programacion.input_family_assessments`: 47 familias, 30 COMPLETE y **17 PARTIAL**. Las 17 conservan blockers.
- `lf_ops.reglas`: **127 VIGENTE transversales**, comparadas por id, código, categoría, título y descripción; 43 reglas directamente vinculadas a pantalla 44 (incluyendo candidatas, que **no** se heredan como vigentes).
- Catálogo SELECT de seis tablas: **49** políticas (OTP, aprobación, rate limit, seguridad, sesión, timeout). `lf_ops.pantallas_politicas`: **13 filas, todas pantalla 51**; 0 para pantalla 44. `pantallas_politicas_reglas` tiene **21 enlaces**, ninguno para pantalla 44.
- Evidencia completa por ID, blocker, `curator_sha256`, regla y política: [snapshot SELECT](lf_ig_956_reuse_source_select_snapshot_20261114.json). Las decisiones siguientes son **propuestas**, no recibos de implementación ni aprobación del owner.

## Clasificación priorizada, una por familia

| Familia PARTIAL | Bloqueo exacto de run 956 | Camino propuesto | Evidencia de fuente | Pendiente real, **no** rule blocker del run |
|---|---|---|---|---|
| API_DATA_CONTRACT | API_OPERATION_SCHEMA_SOURCE_INCOMPLETE | **1 HEREDAR base** | VIGENTE transversal **179** REG_TEC_003; también 213/217/218, sin contrato específico | 0 esquemas API ejecutables/materializados de carga; definir/probar request/response |
| ASSETS_ICONS | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **1 HEREDAR base** | VIGENTE transversal **362** NEG-GOBERNANZA-PROVENANCE-01; 420 es logo de Login, no regla general de íconos | 26/27 elementos semánticos, **1 componente faltante**; UI/curación de asset |
| AUDIT | AUDIT_CANONICAL_SOURCE_INCOMPLETE | **1 HEREDAR base** | VIGENTE transversal **416** B2B-RULE-AUDIT-001; 409/412 correlación | `required_action_contract_count=0`; falta catálogo de acciones auditables |
| BROWSER_PLATFORM | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **3 REGLA CANDIDATA (casos)** | 218 CORS, 465/466 accesibilidad; **no prueban cobertura del selector/upload en todos los browsers** | Matriz Chrome/Edge/Safari móvil, fallback de file input y una candidata sin resolver del run |
| DESIGN_SYSTEM | DESIGN_BINDING_INCOMPLETE | **1 HEREDAR base** | VIGENTE transversal **387** B2B-RULE-DESIGN-001; 388 sin hardcodes | 65/73 campos sin vínculo a componente; 1/27 elemento faltante; DS v1.3 CANDIDATO_OPERATIVO |
| IDEMPOTENCY_CONCURRENCY | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **2 ATAR POLÍTICA (propuesta)** | **SEC-B2B-IDEMPOTENCY**, SECURITY ID **9**, CANDIDATO; regla **403** CANDIDATO (no heredar) | Vincular/QA clave única para upload/process/reprocess; reintento sin efecto duplicado |
| LOADING_EMPTY_ERROR_STATES | LOADING_EMPTY_ERROR_STATES_SOURCE_INCOMPLETE | **1 HEREDAR base** | VIGENTE transversal **199** REG_UI_001; 200/201 estados; 408/410 errores | 2 reglas candidatas y 1 marcador pendiente, estados y recuperación por paso |
| OBSERVABILITY | OBSERVABILITY_RUNTIME_PROVIDER_NOT_READY | **1 HEREDAR base** | VIGENTE transversal **412** B2B-RULE-OBS-001; 413 proveedor honesto | **Dependencia técnica externa, NO regla**: 8 proveedores catalogados, **0 runtime-ready**; instrumentación/QA |
| PRIVACY_PII | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **1 HEREDAR base** | VIGENTE transversal **411** B2B-RULE-PRIVACY-001; 21/37/87/95 | Cobertura de casos faltantes: 5 CANDIDATO, 3 marcadores y 1 decisión pendiente en evaluación |
| RATE_LIMIT | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **2 ATAR POLÍTICA (propuesta)** | **RATE-B2B-UPLOAD**, RATE_LIMIT ID **2**, CANDIDATO; VIGENTE transversal **418** | FILE_UPLOAD 20 por 3600 s, TENANT_USER; probar contador y aplicabilidad antes de activar |
| SECURITY | SECURITY_SEMANTIC_DEPTH_REVIEW_REQUIRED | **1 HEREDAR base** | VIGENTE transversal **396** B2B-RULE-AUTH-001; 397 aislamiento tenant | 27/30 amenazas y 50/73 sujetos incompletos; capacidad de perfil unresolved; modelado y QA RLS |
| SESSION | SESSION_CANONICAL_SOURCE_INCOMPLETE | **2 ATAR POLÍTICA (propuesta)** | **SESSION-B2B-DEFAULT**, SESSION ID **1**, VIGENTE; transversales **399/400** | Run956 referencia **SESSION-CLIENT-DEFAULT**; reconciliar al frente B2B y `session_context_contract` |
| TESTING_OBLIGATIONS | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **1 HEREDAR base** | VIGENTE transversal **424** B2B-RULE-PROD-001 (QA/seguridad para producción) | No confundir gate con pruebas realizadas: 5 marcadores, 1 decisión existente pendiente y matriz test |
| TIMEOUT_RETRY | TIMING_RECONCILIATION_REQUIRED | **2 ATAR POLÍTICA (propuesta)** | **TIMEOUT-B2B-UPLOAD**, TIMEOUT ID **2**, CANDIDATO; transversal **417** | 300 s y 2 reintentos; contrastar VALIDATION ID4 y PROCESSING ID5, sin heredar tiempos de Login |
| TRANSITIONS | CANONICAL_TRANSITIONS_INSUFFICIENT | **3 REGLA CANDIDATA existente (casos)** | Regla **581** CANDIDATO del wizard; regla **404** VIGENTE pero **no transversal**, por eso no cuenta como vía 1 | 12 estados del catálogo; verificar transiciones físicas y permisos para 3 pasos, sin cuarto paso UI |
| VALIDATIONS | BOOTSTRAP_CANONICAL_EVIDENCE_PARTIAL | **1 HEREDAR base** | VIGENTE transversal **25** REG_SEG_007 | 7/73 campos obligatorios sin validación catalogada; curador de campos y QA |
| VISUAL_EVIDENCE | CURRENT_VISUAL_EVIDENCE_PARTIAL | **1 HEREDAR base** | VIGENTE transversal **370** NEG-GOBERNANZA-VISUAL-CONFIRM-01 | 8 evidencias actuales / 9 artefactos; reconciliar 1 versión/captura con perfil UI, no crear regla |

### Conteo sin doble contabilización

| Camino prioritario | Familias | ¿Crea nueva regla? | ¿Cierra COMPLETE ahora? |
|---|---:|---|---|
| 1 HEREDAR transversal VIGENTE | **11** | No | No: todas mantienen residual |
| 2 ATAR política existente | **4** | No; **sí requeriría filas de vínculo** en lote posterior | No: vínculo y QA pendientes |
| 3 REGLA CANDIDATA con casos | **2** | Solo propuesta/revisión; **0 INSERT** | No |
| 4 DECISIÓN OWNER | **0** nuevas | No | No |
| **Total** | **17** | **0 nuevas reglas** | **0/17 COMPLETE confirmado** |

**Así, 11 familias pueden reutilizar una regla transversal sin crear una regla nueva, y otras 4 una política ya existente si después se aprueban/escriben sus enlaces.** No son 15 cierres de readiness. No se obtuvo evidencia que permita cerrar PARTIAL en el run original. Un faltante de contenido es un hallazgo que acompaña el proceso, no un error del flujo.

## Cuatro vínculos propuestos — ninguna fila aplicada

Cada par de filas se ejecutaría más adelante por **ruta gobernada de vinculación**, con `pantalla_politica_id` retornado por inserción. Nunca copiar `pantalla_politica_id` de pantalla 51. **No ejecutar en esta tarea**.

| Familia | Fila nueva propuesta en `lf_ops.pantallas_politicas` | Fila(s) propuesta(s) en `lf_ops.pantallas_politicas_reglas` | Precaución |
|---|---|---|---|
| IDEMPOTENCY_CONCURRENCY | `(pantalla_id=44, policy_kind=SECURITY, reference_role=idempotency_security_policy_id, security_policy_id=9, status=CANDIDATO)` | `(nuevo_id, regla_id=403)` | Regla 403 **CANDIDATO**, política CANDIDATO. Validar antes de activar |
| RATE_LIMIT | `(44, RATE_LIMIT, upload_rate_limit_policy_id, rate_limit_policy_id=2, CANDIDATO)` | `(nuevo_id,418)` | Política CANDIDATO; QA counters/tipo de recurso |
| SESSION | `(44, SESSION, b2b_session_policy_id, session_policy_id=1, CANDIDATO)` | `(nuevo_id,399)`, `(nuevo_id,400)` | Política VIGENTE, vínculo pantalla aún CANDIDATO |
| TIMEOUT_RETRY | `(44, TIMEOUT, upload_timeout_policy_id, timeout_policy_id=2, CANDIDATO)` | `(nuevo_id,417)` | Política CANDIDATO y existen suboperaciones de validación/procesamiento |

**Prohibido:** crear esas filas por SELECT de inspección, deducir que la política CANDIDATO es efectiva o anunciar familia COMPLETE solo por el vínculo.

## Casuística de camino 3

**BROWSER_PLATFORM** (no hay cobertura transversal suficiente para compatibilidad de archivos):
- Caso A: navegador desktop compatible → cargar archivo y validar; solución: pruebas reales Chrome/Edge y permisos.
- Caso B: iOS Safari con selector/restricciones → mantener capacidad o mostrar alternativa accesible; solución: prueba de file input y fallback.
- Caso C: API de navegador ausente → error seguro y recuperación visible; solución: detectar capacidad soportada, sin fingir éxito.
- **Candidato recomendado:** solo documentar contrato de compatibilidad si la matriz evidencia una semántica funcional que no exista ya; no crear regla de manera preventiva.

**TRANSITIONS** (usar candidato **581**, no duplicarlo):
- Archivo con verificaciones PASS → `TR_LOAD_CREATE`, BORRADOR → ARCHIVO_CARGADO; fuente server-side.
- Archivo con error/duplicado → conservar BORRADOR; reintentar/reemplazar o abrir carga previa sin estado arbitrario.
- Continuar validación → `TR_LOAD_VALIDATE_START`, permisos e idempotencia comprobados.
- Resultado con incidencias → `TR_LOAD_VALIDATE_OK`, `RESULT_WITH_ISSUES` en paso 3, **sin cuarto paso**.

**Owner (camino 4):** no emergió una **nueva** decisión cerrada que sea requisito previo para crear el mapeo. Hay **una decisión pendiente ya registrada** dentro de TESTING_OBLIGATIONS y otras brechas del run: no se atribuye al owner una respuesta que aún no consta. La ausencia de aprobación no detiene la ejecución; queda en hallazgos.

## Contrato reutilizable para el perfil

`programacion.input_family_reuse_map_v1` guarda **17 entradas** ancladas al run, su assessment, su hash de Curator, regla VIGENTE o política real y el hallazgo residual.

`public.lf_input_family_reuse_before_propose_v1(44, '<FAMILY_CODE>', 956)` retorna una respuesta **READ_ONLY**, con `automatic_rule_creation=false` y `continuation_allowed=true`. Verifica en tiempo de consulta que la regla continúe VIGENTE transversal o que la política siga existiendo con el mismo estado; si cambió, `SOURCE_DRIFT_REVIEW`.

**Integración pendiente a revisar:** disponer el llamado desde el perfil, antes de proponer `RULE_CREATE_APPLY`. El mapeo y su función por sí solos **no prueban** ese cableado. No hay nueva ruta independiente de Input Governance.

Requisitos de cierre: migración única por Train, PG17.6/18.7 BEGIN→ROLLBACK + pruebas negativas; SELECT de 17/11/4/2, 0 vínculos insertados, 47/30/17 run sin cambio, 127 transversales invariantes, 0 reglas promocionadas y revisiones específicas por Curator / UI / Ingeniería.

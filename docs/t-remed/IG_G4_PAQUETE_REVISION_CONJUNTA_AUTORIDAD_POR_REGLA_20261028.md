# LF IG — G4: paquete para revisión conjunta de autoridad de aplicabilidad por regla
Fecha: 2026-10-28 · PR #3269 draft · **PROPUESTA PARA DECISIÓN, NO RATIFICADA** · CERO escrituras a Supabase, sin Router, sin reclasificación G5.

## 1. Decisión que se debe tomar

Definir **quién autoriza el alcance de cada regla** sin inferir GLOBAL de `es_transversal`, sin atribuirlo a `created_by` ni usar `reglas_pantallas` como autoridad terminal, y **sin crear otro motor de aprobaciones**.

La arquitectura propuesta es:
**fuente de regla y política autoritativa → analizador de autoridad y dominios requeridos → expediente con hashes y evidencia → registro central `private.lf_human_decision_*` (por dominio, cuando corresponda) → verificador de todos los recibos → admisión de publicación técnica N-4**.

El matcher N-4 **solo resuelve coincidencia determinista**, nunca aprueba; Curator/Validator descubren/verifican, pero no se convierten en gerentes funcionales.

## 2. Evidencia viva verificada

- EKB `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`: usar selectores y contexto canónico, no inferir alcance por transversalidad o frecuencia. `INPUT-GOV-CONSUMER-BINDING-001`: consumer debe estar autorizado. `IG-TARGETED-EVIDENCE-BEFORE-HUMAN-ESCALATION-001`: buscar evidencia relevante antes de escalar. `CI-MIGRATION-SOURCE-PARITY-001`: cambios SQL solo source-first gobernados.
- `lf_ops.reglas` posee `codigo`, `categoria`, `origen`, `descripcion`, `valor_config`, `es_transversal`, `estado`, `pendiente_decision`, pero **no tiene `owner_role` canónico**. `origen` mezcla identificadores de handoff, `decision_producto`, `seguridad`, `legal` y referencias a decisiones: **evidencia de origen, NO autorización comprobada**.
- En `private.lf_human_decision_*` ya existen 7 clases ACTIVE, 11 clasificadores ACTIVE y 7 rutas PENDING_AUTHORITY, ninguna ACTIVE. Hay **0 políticas de canal de autoridad, 0 solicitudes y 0 recibos** en el corte actual; no se puede convertir en `ACTIVE` por diseño.
- Las 3 rutas IG vigentes tienen `subject_type='INPUT_GAP_PROPOSAL'`, **no** cambio de alcance de regla. `private.fn_lf_human_decision_open_ig_v3` exige un `input_gap_proposals.id` legítimo y admisión previa, no es adaptador general de scope.
- `private.fn_lf_human_decision_resolve_policy_v1` clasifica **una** clase por solicitud (regla más prioritaria), y su invocación read-only fue **denegada por ACL**. Su código fuente y las tablas pudieron inspeccionarse.
- `private.lf_human_decision_requests_v1` es única por `producer_code+subject_type+subject_key` cuando OPEN; `lf_human_decision_receipts_v1` tiene **UNIQUE(request_id)**. Para multiautoridad, no basta con colocar varios dominios en una sola solicitud.
- Los recibos técnicos verifican currentness, actor, política de autoridad y hashes, pero **la existencia de un recibo no demuestra por sí sola competencia de dominio**. Esta debe derivarse de fuente gobernada y verificarse antes y después.
- G3: el matcher candidato superó 28 vectores y 812 pares en PostgreSQL 17.6 aislado, pero la prueba ACL post-DDL e integración siguen pendientes.

## 3. Propuesta de selección de autoridad: dos pasos separados

**A. Descubrimiento verificable, sin decisión humana prematura**
1. Recuperar regla exacta, documentos de autoridad, política canónica, propietario de la fuente, alcance solicitado y contraejemplos.
2. Extraer las **obligaciones/effects** que la regla impone, sus sujetos y excepciones; comparar con políticas normativas de dominio. No usar `categoria`, `origen`, el texto de la regla ni modelos semánticos **como autorización final**.
3. Proponer dominios candidatos para aprobar (Producto, Software Security, Privacy, Legal, UX, Governance, Data Ops), con evidencia positiva/negativa y trazabilidad a autoridad real; si hay duda, `UNKNOWN_AUTHORITY`.
4. Validator independiente comprueba especialidades y alcance; no acepta como prueba la misma etiqueta que propuso Curator.
5. Si falta una fuente de autoridad, aplicar `ACQUIRE_EVIDENCE/HOLD` según el contrato existente, **no** abrir una cola gerencial automáticamente.

**B. Aprobación formal de ámbito (solo tras ratificación del contrato)**
6. Usar **el registro central de LF** con asunto específico de cambio de aplicabilidad (identificador de trabajo `RULE_APPLICABILITY_CHANGE`, **sin registrarlo todavía**) y ruta por dominio competente.
7. Cada solicitud liga `rule_ref`, `rule_sha256`, `selector_sha256`, `scope_diff_sha256`, `consumer`, `policy_revision`, `authority_domain`, `currentness_sha256`, pruebas negativas, restricciones y vigencia.
8. Para una regla que exige dos o más autoridades, usar solicitudes **por dominio** con `subject_key` inequívoco basado en `rule/version/scope/domain` y recibos individuales. La prueba agregada acepta publicación **solo si todos los dominios requeridos** tienen decisión válida, vigente y vinculada al mismo paquete. El modo exacto de almacenamiento del agregado sigue pendiente de evaluar; no crear tabla nueva por defecto.
9. Una excepción que degrade una regla superior **no delegable** recibe VETO, incluso con otro recibo positivo; si hay conflicto de autoridad, HOLD.
10. Tras aprobación funcional, publicación pasa **por otra frontera técnica** (CI/source parity/PASE/Train/READBACK). N-4 ejecuta coincidencias automáticamente dentro del ámbito ya autorizado; **no** hace una aprobación por pantalla.

## 4. Ejemplos para probar juntos antes de decidir

| Regla real | Hipótesis de competencia, NO aprobación | Riesgo de scope | Evidencia que falta |
|---|---|---|---|
| `REG_SES_001` — onboarding OTP 30 min | Producto LF; revisar Software Security si la expiración tiene dependencia de autenticación | Derivarse a login B2B aunque la regla diga onboarding | Identificación de propietario de política OTP/sesión y versión; pruebas negativas en B2B |
| `REG_ABT_004` — experimentación de campos, OTP y copy | Producto LF; Privacy/Security **solo si el experimento toca sus obligaciones** | A/B del cliente heredado en login B2B | Contrato de experimentos, datos tratados y decisiones registradas |
| `B2B-RULE-AUTH-001` — autorización server-side | Software Security; posible dueño de control operativo B2B | Degradación de guardia o aplicación a flujo pre-auth | Política superior y constancia de veto/alcance post-auth |
| `B2B-RULE-DESIGN-001` — design system | UX/UI; revisar Governance sobre control técnico del design system | Confundir estándar de tokens LF con todas las pantallas y excepciones | Fuente canónica, owner del design system, selector actual/impacto |
| `B2B-RULE-STORY-READINESS-001` — readiness del Backoffice | Software Governance | Confundir **selector de familias** con ejecutar 47 familias por defecto | Pipeline del selector previo y contrato de `Story Ready` |

**Importante:** los cinco dominios son **hipótesis de calificación**, no decisiones de titularidad. `es_transversal`, `origen` y comentarios de Git no pueden aprobar nada.

## 5. Cuatro decisiones para discutir antes de implementar

| Tema | Recomendación para debate | Estado |
|---|---|---|
| 1. Registro | Reutilizar `private.lf_human_decision_*`, sin segundo motor | Arquitectura propuesta; falta ratificar el tipo de asunto y la ruta |
| 2. Fuente de competencia | Un catálogo/contrato gobernado **existente o una extensión mínima de fuente**, no un mapeo `categoria→owner` codificado en la función | **Sin fuente canónica identificada por regla** |
| 3. Varias autoridades | Un expediente versionado, **solicitud y recibo por dominio**, aprobación agregada `AND`, veto no delegable | Propuesta; validar integridad, duplicados y revocación |
| 4. Fase de activación | Diseñar y probar en sandbox antes de publicar; no exigir recibos reales para aprobar la **construcción técnica**, sí para **cualquier cambio operativo** | Separación obligatoria por EKB |

## 6. Gate y validaciones pendientes

**G4 no está aprobado.** Para cerrarlo: identificación real del owner/delegación por regla, fuente de policy/currentness, clasificador que no acepte autoridad autoprovista, rutas/recibos auténticos en canal autorizado, casos de multiautoridad, excepciones y veto, hash exacto del paquete, pruebas del resolvedor accesible por su caller legítimo, y readback. No extender roles, estados ni tablas por inferencia.

**G5 bloqueado:** no iniciar reclasificación, no retirar vínculos `DERIVED_GLOBAL`, no aprobar de forma masiva, no alterar Router ni Supabase.

### Conclusión preparada para revisión conjunta

Hay **mecanismo de decisión** pero **falta la fuente vinculante de competencia por regla** y la formalización del caso multidominio. Son las dos decisiones que cambian el diseño; corregirlas primero evita un motor paralelo, heurísticas en duro y autorizaciones falsas.

# LF IG — G4: integración al registro central de decisiones humanas (contrato de alcance)

**Fecha:** 28-oct-2026. **Estado:** ESTUDIO DE CONTRATO, `G4_NO_VERIFICADO`, `G5_NO_RECLASSIFY`. **Origen:** EKB + funciones/tablas vivas en solo lectura + registro de decisiones existente. Sin Router, sin SQL DDL y sin permiso de publicación.

## 1. Hallazgo arquitectónico: reutilizar la autoridad correcta

LF ya dispone en el esquema `private` de un registro de decisiones humanas con:

- `lf_human_decision_classes_v1`: **7 clases activas** (Producto LF, Privacidad, Legal, UX/UI, Software Security, Software Governance, Data Operations).
- `lf_human_decision_classification_rules_v1`: **11 reglas activas** de clasificación por productor, tipo de asunto y condición.
- `lf_human_decision_route_policies_v1`: **7 políticas, cero ACTIVE**; las tres de Input Governance están `PENDING_AUTHORITY` y aplican al asunto `INPUT_GAP_PROPOSAL`.
- `lf_human_decision_authority_policies_v1`: **cero registros** activos o pendientes en el corte consultado.
- `lf_human_decision_requests_v1` y `lf_human_decision_receipts_v1`: **cero registros** cada una.
- `private.fn_lf_human_decision_resolve_policy_v1(text,text,jsonb)`: función `STABLE SECURITY DEFINER` que selecciona una clase, comprueba política `ACTIVE`, identidad del reviewer y política de canal de autoridad activa. La llamada directa read-only por la conexión disponible fue **denegada por permisos**; su semántica se revisó por definición fuente, no se declaró una ejecución exitosa del resolvedor.
- `private.fn_lf_human_decision_assert_authority_receipt_v1`: valida recibo de procedencia con SHA, asunto, rol, decisión, fuente/currentness y política de canal. Se inspeccionó definición, no se invocó ni fabricó un recibo.
- `private.fn_lf_human_decision_open_ig_v3`: **específica para `input_gap_proposals`** con `HUMAN_DECISION_REQUIRED` y admisión previa `HUMAN_ELIGIBLE`; no admite arbitrariamente una regla N-4. No se debe enviar un `rule_ref` fingiendo ser un `proposal_id`.

**Conclusión:** el patrón central de clasificación, enrutamiento y recibo **sí existe** y debe reutilizarse. Pero **ninguna ruta demostrada autoriza hoy cambios de aplicabilidad por regla**. No equivale a un G4 PASS.

## 2. Cinco negativas comprobadas en lectura

Se ejecutó `sandbox/lf_contract_gate_test/input_governance/ig_g4_human_decision_registry_readonly_20261028.sql` con `WITH ... AS MATERIALIZED`. Es una **proyección equivalente de los primeros gates del registro**, no una llamada al resolvedor protegido.

| Entrada de prueba | Salida de proyección read-only | Por qué |
|---|---|---|
| IG, `INPUT_GAP_PROPOSAL`, `PRIVACY_PII` | `BLOCKED_ROUTE_NOT_ACTIVE` | Clase PRIVACY reconocida, política `HDR_ROUTE_IG_PRIVACY` pendiente |
| IG, `INPUT_GAP_PROPOSAL`, `RUNTIME_CONFIG` | `BLOCKED_ROUTE_NOT_ACTIVE` | Clase SOFTWARE_GOVERNANCE reconocida; política pendiente |
| IG, propuesta de `RULE_APPLICABILITY_CHANGE` | `BLOCKED_NO_CLASSIFICATION` | No existe clasificador para ese tipo de asunto |
| IG, familia inexistente | `BLOCKED_NO_CLASSIFICATION` | No se admite un caso nuevo por parecido semántico |
| Contexto JSON no objeto | `BLOCKED_INVALID_CONTEXT` | Rechazo de formato |

**No se concluye** que alguna solicitud humana pudiera tramitarse hoy por la función restringida; se comprobó la configuración de los objetos y se confirmó ausencia de políticas activas/recibos.

## 3. Contrato mínimo propuesto sin inventar tablas ni roles

**Propuesta para revisión de owner, NO aplicable todavía:** reutilizar el registro actual con un tipo de asunto diferenciado para cambio de alcance de regla (`RULE_APPLICABILITY_CHANGE` como identificador de trabajo propuesto, no nuevo enum autorizado):

1. Fuente canónica identifica `rule_ref`, versión/hash, efecto/obligación, políticas superiores, sujeto, trigger y atributos mínimos de contexto. `lf_ops.reglas` no tiene columna `owner` ni una competencia aprobatoria por regla: **`created_by` y `es_transversal` no bastan**.
2. Curator describe alternativas, positivos, negativos, `UNKNOWN`, alcance esperado/exclusiones, fuentes EKB/policy y riesgo bidireccional; Validator independiente comprueba las hipótesis y el diff de cobertura, sin autoaprobar.
3. El **dominio de autoridad se deriva de fuentes gobernadas** y se comprueba antes de construir el `p_context` del resolvedor; el proponente no puede elegir `family_code`, `required_reviewer_role` o clase para obtener un aprobador fácil.
4. Registrar **clasificación y ruta de decisión para el nuevo asunto** mediante el mecanismo existente, con owner competente, versión de política, identidad y recibo vigente. Los registros actuales `INPUT_GAP_PROPOSAL` permanecen sin cambios. `ANY` como fallback a un solo aprobador genérico está prohibido para reglas multidominio.
5. Si una regla afecta más de una potestad (ej. privacidad + control de seguridad), exigir **las autorizaciones de todos los dominios pertinentes**. El resolvedor actual da una sola `decision_class` por solicitud: dividir en solicitudes por dominio con trazabilidad y agregación independiente o proponer extensión mínima gobernada. No declarar que el resolvedor actual resuelve multiautoridad.
6. Publicación posterior comprueba recibo auténtico por `rule_sha + selector_sha + scope_diff_sha + consumer + currentness` y todos los vetos. Solo entonces el selector ACTIVE podrá ser consumido por N-4. No pedir una aprobación por cada pantalla nueva **dentro del scope aprobado**.
7. La decisión funcional **no reemplaza** autorización técnica de migración, PR, CI exact-head, PASE/Train y readback. No publicar ni registrar recibos durante este diseño.

### Limitación concreta del clasificador v1

Su campo `attribute_name` admite `ANY`, `FAMILY_CODE` o `REQUIRED_REVIEWER_ROLE`; no consume aún una **clase de autoridad verificada contra la fuente de la regla**. `FAMILY_CODE` está pensado para brechas IG y no determina por sí solo autoridad normativa; `REQUIRED_REVIEWER_ROLE` viene del contexto del solicitante si ningún adaptador lo comprueba. **Necesidad puntual:** definir un adaptador gobernado de fuente de autoridad, o una extensión de atributos verificados por datos, antes de registrar enrutamiento de reglas. No crear un segundo motor de decisiones.

## 4. Pruebas de aceptación obligatorias para G4

| ID | Prueba negativa/positiva | Esperado |
|---|---|---|
| G4-A | Solicitud de scope sin clasificación registrada | BLOCKED |
| G4-B | Clasificación existente, ruta `PENDING_AUTHORITY` | BLOCKED |
| G4-C | Ruta `ACTIVE` sin autoridad de canal activa | BLOCKED |
| G4-D | Clase/rol suministrados por usuario, sin source binding verificado | BLOCKED |
| G4-E | Recibo de otra regla/selector/consumer/version | BLOCKED |
| G4-F | Regla con Privacy + Security, aprobación de solo uno | HOLD |
| G4-G | Excepción intenta debilitar prohibición superior no delegable | VETO |
| G4-H | Fuente/política revocada o currentness alterada | HOLD |
| G4-I | Decisiones auténticas de todos los dominios pertinentes y hashes exactos | Candidato a publicación; NO cambio operativo inmediato |
| G4-J | Pantalla futura compatible con selector ya autorizado | N-4 MATCH, sin segunda aprobación por pantalla |

Todos los positivos que requieren firma permanecen **NO_VERIFICADOS**. No falsificar atestaciones ni probar con escrituras en `private`.

## 5. G3: control de permisos vigente verificado, nueva función pendiente

Se ejecutó `sandbox/lf_contract_gate_test/input_governance/ig_g3_n4_acl_baseline_readonly_20261028.sql` contra catalog `pg_roles` + `has_schema_privilege`/`has_function_privilege`:

| Control | Observado |
|---|---:|
| Roles comparados | 9 |
| Roles públicos sin acceso efectivo al esquema | 3/3 |
| Roles técnicos del ámbito con uso de esquema y matcher | 6/6 |
| Accesos efectivos públicos inesperados | 0 |
| Roles técnicos previstos sin acceso | 0 |
| Nuevo helper de validación desplegado en Supabase | NO (correcto) |

**Esto certifica únicamente ACL basales por catálogo**. Faltan permisos efectivos **después del candidato** y negativos de ejecución por rol en PostgreSQL aislado, además de validación independiente de la integración con el consumidor real.

## 6. Estado de continuidad

- **G3-PG aislado 28/28, 812/812, rollback:** PASS histórico verificado en run GitHub `40741198646`, job `123002927376`.
- **G3 ACL baseline:** PASS en catálogo; **G3 ACL candidato:** PENDING.
- **G4 registro/funciones:** ENCONTRADOS y su bloqueo de autoridad demostrado en tablas; **G4 approvals reales:** NO_VERIFICADO.
- **G5 reclasificación:** NO_RECLASSIFY. Nada en este documento autoriza tocar `DERIVED_GLOBAL`, crear reglas/policies o activar `human_decisions`.

Próxima dependencia concreta: ratificar **qué fuente canónica expresa la competencia por regla** y cómo se proyecta al clasificador central sin aceptar entradas autoprovistas; solo después propuesta de actualización controlada del registro de políticas, con tests del resolver en ambiente autorizado y política de multiautoridad.

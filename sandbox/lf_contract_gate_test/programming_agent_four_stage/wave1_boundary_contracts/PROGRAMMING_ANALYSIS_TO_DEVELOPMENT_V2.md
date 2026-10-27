# Programación: retorno tipado de A9 y admisión V2 — propuesta (26-oct-2026)

## Flujo

1. El último perfil de Análisis, **aún no registrado**, puede proponer `output_type=PROGRAMMING_ANALYSIS_PACKAGE_READY` con `programming_handoff` (6 claves: `context_id`, `context_sha256`, `target_ref`, `requested_scope_ids`, `producer_execution_ref`, `entry_contract_digest_sha256`). El perfil no puede elegir `target_profile`; si falta información, continúa con `NEEDS_INPUT` o `BLOCKED`.
2. `lf_profile_result_router_return_classify_v1` detecta este tipo y emite `ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION` sin reingresar a Stage1. Otros tipos conservan el flujo anterior.
3. `lf_profile_result_router_return_prepare_v1` comprueba `PROGRAMACION` y obtiene el binding desde `manifest.router_profile_handoff.semantic_request.router_action_binding`. **Solo devuelve** `programming_admission_request`, nunca invoca la admisión. Las funciones de retorno son SECURITY DEFINER, y llamar allí al gate SECURITY INVOKER ejecutaría la comprobación con autoridad `postgres`, eludiendo la frontera de identidad elegida por el dueño.
4. Un **orquestador gobernado todavía por determinar** invoca la entrada de #3176 `public.lf_programming_development_admission_v1` con el binding y el handoff, como llamador no privilegiado. Esta integración se mantiene fuera de ambos PR.
5. La compuerta de #3176 deberá conectarse por separado a `private.fn_lf_programming_context_handoff_receipt_resolve_v2`; el lector nuevo comprueba exactamente el binding D7, su recibo, el sobre, el juez, los scopes, la vigencia, las revocaciones y la vigencia de la definición de Producto. `resolve_v1` permanece intacto y siempre cerrado.
6. Solo después de que el contrato V2 sea verificable, exista escritor runtime gobernado y `DESARROLLO_CODIGO_AGENTE_LF` esté `ACTIVE`, podrá plantearse un pase a la operación. **Ninguna migración de estos PR da permiso de ejecución.**

## Inercia hoy

El proveedor `private.fn_lf_programming_definition_currentness_v1` siempre responde `verified=false` con `DEFINITION_CURRENTNESS_PROVIDER_NOT_RELEASED`; el ledger D7 tiene cero filas verificadas a la fecha de referencia; no hay escritor runtime; la operación sigue en `CANDIDATO_READ_ONLY`; no hay perfiles de Análisis registrados. Incluso una fila hipotética íntegra no autoriza efectos. No se modifica el Router ACT-0001.

## Resultados y códigos

| Condición | Código | Consecuencia |
|---|---|---|
| Salida de análisis sin handoff mínimo | `PROFILE_RESULT_PROGRAMMING_HANDOFF_INVALID` | BLOCKED |
| Salida "lista" que también se declara bloqueada o incompleta (`status` BLOCKED/NEEDS_INPUT/NEEDS_REPAIR, `self_verdict` de ajuste, `blocked=true` o `missing_inputs`) | `PROFILE_RESULT_PROGRAMMING_ANALYSIS_CONTRADICTORY` | BLOCKED |
| Salida tipada válida | `PROFILE_RESULT_PROGRAMMING_ANALYSIS_READY` | Solicitud preparada, no ejecución |
| Canal distinto | `PROFILE_RESULT_PROGRAMMING_CHANNEL_MISMATCH` | BLOCKED |
| Binding no disponible | `PROFILE_RESULT_ROUTER_BINDING_NOT_AVAILABLE` | BLOCKED |
| Recibo no encontrado | `PG01_V2_RECEIPT_NOT_FOUND` | No admisible |
| Hash o veredicto incorrecto | `PG01_V2_HASH_MISMATCH` / `PG01_V2_RECEIPT_NOT_ACCEPT` | No admisible |
| Sobre inválido o distinto de contexto/contrato | `PG01_V2_ENVELOPE_INVALID` / `PG01_V2_CONTEXT_OR_CONTRACT_MISMATCH` | No admisible |
| Juez inválido o sin los pasos | `PG01_V2_JUDGE_INVALID` / `PG01_V2_JUDGE_STEPS_INVALID` | No admisible |
| Scope no admitido | `PG01_V2_SCOPE_NOT_ADMITTED` | No admisible |
| Plazo inválido, futuro o vencido | `PG01_V2_VALIDITY_INVALID` / `PG01_V2_NOT_YET_VALID` / `PG01_V2_EXPIRED` | No admisible |
| Revocado | `PG01_V2_REVOKED` | No admisible |
| Vigencia de definición sin verificar | `PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED` | No admisible |

**Propuesta de política temporal:** máximo 24 horas desde `valid_from` hasta `valid_until`, sujeto a la confirmación de Cristhian. El contrato del paquete V1 se conserva con su digest congelado; el sobre V2 es adicional. El hash del snapshot as-of no se reinterpreta. Las revocaciones son append-only, sin conceder acceso a ningún consumidor.

## Decisiones pendientes para Cristhian

1. ¿Qué orquestador invoca la entrada de desarrollo usando `programming_admission_request`?
2. ¿Qué perfiles pueden emitir `PROGRAMMING_ANALYSIS_PACKAGE_READY` y cómo se prueba ese derecho?
3. ¿Qué fuente oficial y función actualizan/atestiguan la vigencia de definiciones de Producto?
4. ¿Se aprueba el máximo propuesto de 24 horas?
5. ¿Qué operación y autoridad emiten revocaciones?
6. ¿Es correcta la ruta del binding en el manifest? El simple hash del binding no demuestra procedencia.

## Limitaciones

No se implementa un registro runtime de recibos, no se concede EXECUTE en lectores ni se activa ninguna operación. La prueba PostgreSQL debe ejecutarse sobre una instancia 17 desechable. El validador JSON Schema se entrega como contrato, no como una afirmación de que el runtime lo haya certificado.

## Verificación (Claude, 26-oct-2026, PostgreSQL 16 local desechable; CI usa 17)

**Punto 3** (`test_programming_analysis_return_to_development_v1.sql`, 9/9). La prueba no usa imitaciones de las funciones de retorno: las reconstruye desde sus migraciones del repo (`20261025014719` + parches `20261026180000` y `20261026180500` para `classify_v1`; `20261025004001` para `prepare_v1`) y comprueba que su md5 coincide con producción (`7517e452…` y `8bf503bf…`), así que la migración se aplica sin tocar sus precondiciones. Incluye la regresión del retorno positivo real (`routing.via=ORCHESTRATOR` → `REENTER_ROUTER_STAGE1`), que sigue igual.

**Punto 4** (`test_programming_admission_envelope_v2_v1.sql`, 14/14). Carga el ledger D7 real (`20261026173901`) y escribe los recibos con el escritor real. Cubre: rol restringido sin acceso; recibo inexistente; proveedor cerrado; admisión completa con proveedor de prueba; `resolve_v1` sigue cerrado; ACCEPT/BLOCK; seis variantes de sobre inválido; contexto distinto; seis variantes de juez inválido (inexistente, en curso, otra operación, otro sujeto, revisión FAIL, juez de otro paquete); partes no admitidas; plazo futuro, vencido, mayor a 24 h y mal formado; revocación por binding (sin afectar otros) y por contexto (afecta a todos); inmutabilidad de revocaciones; permisos. Un sobre válido de las pruebas cumple el JSON Schema del contrato y cuatro variantes inválidas lo incumplen.

**Correcciones de Claude sobre la entrega de GPT:**
- `resolve_v2`: con el recibo inexistente, la siguiente comprobación sobrescribía el motivo (`PG01_V2_ENVELOPE_INVALID` en vez de `PG01_V2_RECEIPT_NOT_FOUND`), y la respuesta decía siempre `found=true` y `hashes_verified=true`. Ahora se detiene en el recibo, informa los valores reales y marca qué comprobaciones no llegaron a evaluarse (`evaluated=false`).
- `classify_v1`: una salida `PROGRAMMING_ANALYSIS_PACKAGE_READY` que a la vez se declaraba bloqueada o incompleta pasaba a desarrollo. Ahora se bloquea con `PROFILE_RESULT_PROGRAMMING_ANALYSIS_CONTRADICTORY`.
- Las pruebas de GPT cubrían 7 y 5 casos con funciones simplificadas; se reemplazaron por las de arriba. Con las migraciones originales de GPT, las pruebas nuevas fallan justo en esos dos defectos.

## Decisiones V2 confirmadas (26-oct-2026)

Paulo confirmó que el contrato V2 se agrega al paquete V1, con **vigencia máxima de 24 horas**. La vigencia de Producto se verifica exclusivamente mediante `lf_ops.fn_screen_contract_v1`, con referencias `lf-screen-contract://<APP_SHELL_CODE>/<MODULE_CODE>/<SCREEN_CODE>` y estado obligatorio `VIGENTE`. La huella canónica es SHA-256 de `(contract #- '{metadata,generated_at}')::text` en UTF-8: se excluye solo la fecha de generación, no otros campos del contrato. El emisor futuro debe utilizar `private.fn_lf_programming_definition_ref_sha256_v1` para evitar divergencias. Las revocaciones se insertan únicamente por una ejecución `ACTUALIZACION_DB_LF` del Merge Train en estado `IN_PROGRESS`. La entrada a desarrollo la invoca el agente de Programación al arrancar como `service_role`, y el binding del Router se coteja con el que quedó guardado en la ejecución terminada del perfil. La decisión sobre qué perfiles pueden emitir `PROGRAMMING_ANALYSIS_PACKAGE_READY` queda para Cristhian. En el estado consultado (27-oct), solo dos pantallas están `VIGENTE` (`HOME_APRENDA_ANTES_DECIDIR` y `HOME_FAQ`) y **ninguna tiene módulo asignado**, así que `fn_screen_contract_v1` no las encuentra: **hoy ninguna pantalla puede pasar el proveedor**. Login B2B (`B2B-AUTH-001`) figura como `CANDIDATO` y no puede admitirse hasta que Producto lo pase a `VIGENTE`.

Verificación (Claude, 27-oct, PostgreSQL 16 local): `test_programming_admission_envelope_v2_v1.sql` 19/19. La huella canónica se comprobó en vivo (solo lectura) contra el contrato real de `B2B-AUTH-001`: con `generated_at` la huella cambia en cada consulta; sin él se mantiene (`3493902a…`). Ajustes sobre la entrega de GPT: la función de huella llamaba dos veces al contrato de pantalla (~300 KB cada vez); ahora una sola. La prueba de "dos objetivos" usaba una ejecución que el nuevo filtro del Train rechaza antes de la validación de la tabla; ahora usa la ejecución del Train de prueba.


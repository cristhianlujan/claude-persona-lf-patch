# Entrada de admisión para DESARROLLO_CODIGO_AGENTE_LF — propuesta

## Decisión y límites

Tras el PR #3177, el Router ACT-0001 **deriva** hacia selección de perfil en modo `DERIVATION_ONLY`: no aplica ni autoriza efectos de Programación. La admisión PG-01 se comprueba en la entrada de la operación `DESARROLLO_CODIGO_AGENTE_LF`, separada del Router. La migración no altera ninguna función del Router, no escribe recibos ni activa la operación.

Los dos componentes nuevos son `public.lf_programming_admission_gate_v1(jsonb)` y `public.lf_programming_development_admission_v1(jsonb,jsonb)`. Ambos son `SECURITY INVOKER`, `STABLE`, sin DML. Solo `service_role` y `supabase_read_only_user` reciben EXECUTE sobre estas funciones; **no** se concede EXECUTE sobre el lector privado D7 ni acceso a la tabla de recibos. La compuerta pública solo proyecta `schema_version`, `found`, `admissible`, `reason` y nunca expone recibos o envelopes.

## Tabla de decisiones

| Primera condición | `paso` | `codigo` o contenido |
| --- | --- | --- |
| Binding no objeto | `PROGRAMACION_BINDING_INVALIDO` | `PG01_ROUTER_BINDING_NOT_OBJECT` |
| Huella ausente o alterada | `PROGRAMACION_BINDING_INVALIDO` | `PG01_ROUTER_BINDING_SHA_MISMATCH` |
| Canal incorrecto | `PROGRAMACION_BINDING_INVALIDO` | `PG01_ROUTER_BINDING_CHANNEL_MISMATCH` |
| Autoridad de efecto diferente de false | `PROGRAMACION_BINDING_INVALIDO` | `PG01_ROUTER_BINDING_EFFECT_AUTHORITY_UNEXPECTED` |
| Precondición no coincide | `PROGRAMACION_BINDING_INVALIDO` | `PG01_ROUTER_BINDING_PRECONDITION_MISMATCH` |
| Handoff inválido | `PROGRAMACION_HANDOFF_INVALIDO` | `PG01_GATE_BINDING_INVALID` |
| Recibo inexistente | `PROGRAMACION_ADMISION_BLOQUEADA` | `PG01_RECEIPT_NOT_FOUND`; `RETURN_TO_ANALYSIS_NO_CODE` |
| Lector sin permiso o fallo / recibo no admisible | `PROGRAMACION_ADMISION_BLOQUEADA` | Motivo de gate; `BLOCK_NO_CODE` |
| Gate admisible, operación no ACTIVE | `PROGRAMACION_OPERACION_NO_ACTIVA` | `operation_status` |
| Gate admisible, operación ACTIVE | `PROGRAMACION_DESARROLLO_ADMITIDO` | `admision`, pero `downstream_execution_allowed=false` |

Toda respuesta tiene `schema_version`, `operation_code`, `downstream_execution_allowed=false`, `paso`, `motivo_es`, `siguiente_paso_es`; los códigos externos se presentan en `codigo` y no en `reason`.

## Por qué hoy es inerte

1. El lector D7, en fase 1, nunca devuelve admisión verdadera.
2. La operación registrada continúa `CANDIDATO_READ_ONLY`, `write_allowed=false`.
3. Los llamadores `service_role` y `supabase_read_only_user` no poseen EXECUTE sobre el lector D7: por el diseño `SECURITY INVOKER`, obtienen `PG01_GATE_READER_NOT_GRANTED`.
4. Incluso en la rama hipotética positiva, `downstream_execution_allowed=false`. **Admitir no equivale a ejecutar.**

La huella `binding_sha256` se recalcula mediante la convención `sha256:` + digest del JSONB excluyendo la propia huella. Esta huella comprueba integridad relativa, **no autenticidad** del emisor: quien pueda modificar el binding también puede recalcularla.

## Pendientes para abrir la compuerta

- Aprobar el **sobre V2 adicional a V1**: juez independiente A9, scopes admitidos, vigencia, revocación y vigencia actual de la definición de Producto (referencia y huella usadas frente a las vigentes). No se diseña V2 aquí.
- Autorizar una migración separada para conceder EXECUTE del lector D7 al actor que lo requiera, tras revisión de seguridad.
- Implementar el escritor runtime de recibos bajo operación gobernada.
- Activar la operación en I1 con autoridad específica, separada de este PR.

## Preguntas para Cristhian

1. ¿Existe un registro persistido del `router_action_binding` emitido para verificar autenticidad, o se propone solo comparar su huella?
2. ¿Esta entrada la invoca el perfil al finalizar la administración, o una fase gobernada posterior a Gate2?
3. ¿Debe incluirse el `context_id` elegido por el perfil en el binding del Router?

## Pruebas

Desde la raíz del repo, contra PostgreSQL 17 desechable: `psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/test_programming_development_admission_gate_v1.sql`. El script abre una transacción, crea stubs, carga la migración desde disco y hace `ROLLBACK`.

## Verificación (Claude, 26-oct-2026)

- `test_programming_development_admission_gate_v1.sql`: `PROGRAMMING_DEVELOPMENT_ADMISSION_TESTS_PASSED:16` en PostgreSQL 16 local desechable (CI usa 17). Correcciones sobre el borrador: las comparaciones usan `IS DISTINCT FROM` (con `<>`, un campo ausente hacía pasar la prueba sin comprobar nada) y el entorno de prueba otorga `USAGE` sobre `extensions` a `service_role` y `supabase_read_only_user`, igual que en Supabase vivo (verificado en solo lectura).
- `test_programming_development_admission_real_d7_v1.sql`: la compuerta contra el **lector D7 real** (migración `20261026173901`), no un stub. `service_role` recibe `PG01_GATE_READER_NOT_GRANTED`; el dueño recibe `PG01_RECEIPT_NOT_FOUND`; un `context_id` en mayúsculas se detiene como `PG01_GATE_BINDING_INVALID` sin llegar al lector.
- Hallazgo de prueba: dentro de una misma transacción, PL/pgSQL reutiliza una llamada ya inicializada y no vuelve a comprobar `EXECUTE` después de un cambio de rol. Las pruebas de privilegios deben hacer la llamada con el rol restringido antes de cualquier llamada como dueño. En producción cada llamada corre en su propia transacción con su propio rol, así que no afecta al comportamiento real.


## Ajuste de entrada gobernada (#3176, 26-oct-2026)

La firma de entrada pasa a `public.lf_programming_development_admission_v1(jsonb,jsonb,text)`, siendo el tercer argumento `p_source_execution_id`. Tras validar los campos y la huella local del `router_action_binding`, consulta la ejecución de perfil: exige `EJECUCION_PERFIL_LF`, tipo `PERFIL`, estado `COMPLETED`, canal `PROGRAMACION`, e igualdad `jsonb` exacta con `manifest.router_profile_handoff.semantic_request.router_action_binding`. Ante discrepancias responde `PROGRAMACION_BINDING_INVALIDO` y `PG01_ROUTER_BINDING_NOT_ISSUED_BY_EXECUTION`. La compuerta `SECURITY INVOKER` ahora usa `resolve_v2`; se concede `EXECUTE` en ese lector exclusivamente a `service_role`, nunca a `supabase_read_only_user`, `anon` ni `authenticated`. La admisión válida incluye `source_execution_id`, pero mantiene **`downstream_execution_allowed=false`**. Esta migración no modifica el Router ni activa desarrollo.

## Verificación del ajuste (Claude, 27-oct-2026)

Reemplaza a la verificación del 26-oct en lo que respecta a lectores y privilegios.

- Corrección sobre el borrador: la función de entrada usaba `v_execution` sin declararla y no compilaba; se añadió `v_execution public.lf_operation_execution%ROWTYPE;`.
- `test_programming_development_admission_gate_v1.sql`: `PROGRAMMING_DEVELOPMENT_ADMISSION_TESTS_PASSED:20` en PostgreSQL 16 local desechable (CI usa 17).
- `test_programming_development_admission_real_d7_v1.sql` (reescrita): carga las migraciones reales de D7, de #3181 (`resolve_v2` y proveedor de vigencia) y de esta compuerta. Resultados: `supabase_read_only_user` → `PG01_GATE_READER_NOT_GRANTED`; `service_role` → `PG01_V2_RECEIPT_NOT_FOUND` con las cuatro claves de respuesta; dueño → no encontrado; `context_id` en mayúsculas → `PG01_GATE_BINDING_INVALID` sin llegar al lector; ACL de `resolve_v2` limitada a `service_role`. Emite `PROGRAMMING_DEVELOPMENT_ADMISSION_REAL_READERS_OK`.
- Dependencia: esta rama se apila sobre `lf/pg01-admission-envelope-v2-v1` (#3181) porque la compuerta llama a `resolve_v2`. Se fusiona después de #3181.

## Corrección del retorno V2 — 27-oct-2026

El lector V2 devuelve PG01_V2_RECEIPT_NOT_FOUND. La entrada comprobaba el
código V1 PG01_RECEIPT_NOT_FOUND, por lo que clasificaba la ausencia como
BLOCK_NO_CODE en vez de RETURN_TO_ANALYSIS_NO_CODE. Se alinea el código
exacto con V2; no se cambia el lector, los grants ni la decisión de admisión.
La prueba con lectores reales ahora invoca también la entrada completa sobre
una ejecución de perfil explícitamente sintética y exige retorno a Análisis,
PROGRAMACION_ADMISION_BLOQUEADA y downstream_execution_allowed=false.
También conserva el rechazo de una ejecución origen inexistente.

La validación local usa una BD desechable; no constituye un caso positivo real
ni habilita la aplicación de esta migración. El PR permanece draft.

Validación de este incremento: PostgreSQL 14.24 local extraído en directorio
aislado, sin instalación global, Docker ni TCP. Pasan los 20 casos existentes
y la integración con lectores reales ampliada. La prueba nueva falla con el
código anterior (REAL_FAIL:4_full_entry_missing_receipt) y pasa con la corrección.
La versión 17 objetivo sigue pendiente de CI/revisión; no se atribuye esta
corrida a CI ni se declara un positivo operacional.

## Cross-execution handoff audit (2026-10-27)

The entry now requires `producer_execution_ref = source_execution_id` after
validating the handoff shape. A completed origin with an identical valid Router
binding cannot reuse another execution's handoff/receipt. Mismatch returns
`PROGRAMACION_HANDOFF_INVALIDO / PG01_HANDOFF_SOURCE_EXECUTION_MISMATCH` with
`downstream_execution_allowed=false`.

The new negative test reproduced an incorrect `PROGRAMACION_DESARROLLO_ADMITIDO`
on the previous candidate (ACTIVE is only a rollback-owned test fixture). The
corrected suite has 21 cases. Valid fixtures now use matching producer/source
identities instead of silently exercising the old gap. No hosted change.

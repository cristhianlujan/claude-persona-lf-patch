# SALY — Preflight de política y evidencia de entrega V1 (candidato)

**Estado: CÓDIGO LOCAL VERIFICADO, NO INTEGRADO / SIN MERGE / SIN GRANTS / SIN RENDER.**

## Fuentes revisadas antes de programar
- Fuente anclada al proyecto: `LF_resguardos_construccion.md` (B1 esquema primero, B6 procedencia vs calidad, B11 prueba negativa, B13 configuración, B25 error específico y B30 registro no equivale a publicación).
- GitHub `main`: `AGENTS.md`, `CLAUDE.md` (writes solo por ruta Router/PR/PASE/Merge Train), `skills/creative_factory/SKILL.md` v0.12 (`PLAN_ONLY/REVIEW_ONLY`), `sandbox/creative_factory/native_transport_capture_v1.py` (`validate_provider_ack` no disponible).
- SQL live read-only: tabla `saly.config_global` y función `saly.creative_execution_policy_v1`.
- Candidato en PR #4616, `sandbox/creative_factory/queue_v02/001_saly_queue_serial_candidate.sql`.

## Evidencia encontrada
- 25 filas en `saly.config_global`; **ninguna** con `scope='CREATIVE_FACTORY'`. No hay política de cola autorizada hoy.
- La función actual requiere cuatro variables **REAL/INTEGER**: `QUEUE_MAX`, `MAX_ATTEMPTS`, `QUEUE_TIMEOUT_SECONDS`, `LEASE_SECONDS`. Valores no definidos, no fijar números a partir del fixture.
- El transporte Native oficial es solo revisión. Su validador de proveedor falla cerrado con `NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE`.
- El candidato de DB acepta `delivery_channel` y `delivery_receipt` de texto; eso NO prueba por sí solo entrega real de imagen. **No desplegar hasta vincularlo con un adapter/attestor de confianza.**

## Contrato preparado (lectura y verificación únicamente)
1. `check_creative_config(rows, asof)`: valida las cuatro claves y sus versiones desde una lectura autorizada; responde bloqueantes específicos. Aun con fixture válida no concede autorización operativa.
2. `verify_delivered_image(...)`: exige **dos readbacks independientes**, con conectores confiables inyectados por el ejecutor (no por el pedido):
   - Proveedor de imagen: `generation_status=GENERATED` y coincidencia de RUN, claim, ítem, artefacto y hash.
   - Canal de entrega: `delivery_status=DELIVERED`, `message_id` del host y mismas claves, incluyendo superficie destinataria.
   - Lectura binaria del artefacto real para comprobar `sha256` antes de devolver un recibo estructural.
3. Conector de proveedor ausente, host no disponible, correlación distinta o bytes alterados => **rechazo**. La función nunca da `production_authorized=true`.

## Pruebas
- `python3 -m unittest -v test_activation_preflight_v1.py` → **21/21 PASS** local.
- El caso positivo usa dobles de prueba, no constituye evidencia de un proveedor real.

## Bloqueos / siguiente lote
- **Configuración:** falta la decisión y publicación de los cuatro valores operativos mediante ruta gobernada. No inventarlos ni migrarlos desde fixture.
- **Generación:** no existe aún adaptador verificado Native con recibo auténtico y artefacto recuperable.
- **Entrega:** no existe aún API/recibo de host ChatGPT comprobado para certificar un `message_id` mostrado al usuario. No confundir archivo creado con archivo entregado.
- **Integración:** el código es una interfaz candidata, no está conectado a la RPC ni a la skill. Asegurar independencia de los readers y permisos antes de integrar.
- **Gobernanza:** PR/PASE/Train y readback solo tras tests con esquema fiel, sin modificar pedidos existentes.

## Lote siguiente — coordinador verificable de entrega (candidato, 2026-11-22)

Se añadieron:
- `delivery_completion_guard_v1.py`: secuencia de puertos tipados `claim_readback → provider_readback → host_readback → artifact_readback → receipt_readback → record_delivery → receipt_readback → release_done`.
- `test_delivery_completion_guard_v1.py`: **18/18 PASS local** (dobles de prueba), con rechazos específicos y ausencia de `release_done` ante fallo. El recibo ya existente que coincide evita una escritura duplicada; un recibo ajeno se rechaza.
- `completion_unit_results.txt`: evidencia del resultado local y límites.

**Alcance estricto:** el coordinador NO genera ni envía imágenes. No crea autoridad ni concede GRANT. Solo puede operar cuando un runtime confiable le inyecte puertos reales. Nunca aceptar readers, `claim_token` ni recibos fabricados desde el pedido. `production_authorized=false` incluso en el caso positivo sintético.

### Puertos faltantes que impiden cierre real

| Puerto | Autoridad exigida | Estado |
|---|---|---|
| `claim_readback(run_id)` | SQL autorizado sobre saly.creative_runs + claims + items, con hash y lease reales | SIN CONECTOR |
| `provider_readback(artifact_ref)` | Recibo auténtico Native ligado a RUN/claim/item/hash | NO DISPONIBLE |
| `host_readback(message_id)` | Confirmación real de mensaje DELIVERED en chat destinatario | NO DISPONIBLE |
| `artifact_readback(artifact_ref)` | Bytes reales del artefacto del proveedor | NO DISPONIBLE |
| `receipt_readback(run_id)` | SQL de solo lectura sobre receipt canónico | SIN CONECTOR |
| `record_delivery(...)` | RPC saly.creative_queue_record_delivery_v1, SOLO identidad verificada del attestor | SIN GRANT |
| `release_done(token)` | RPC saly.creative_queue_release_v1('DONE'), después de QA + receipt verificado | SIN GRANT |

**Riesgo que permanece:** SQL candidato v0.2 sigue aceptando `delivery_channel` y `delivery_receipt` textuales; una llamada fuera del coordinador podría fabricar evidencia si se conceden permisos. Por ello, **NO MERGE, NO GRANT, NO DESPLIEGUE** hasta que la capa SQL obligue a verificar procedencia del attestor y se pruebe la denegación de accesos alternos. El coordinador Python por sí solo NO soluciona este riesgo estructural.

### Política CREATIVE_FACTORY

Las cuatro claves siguen sin valor operativo acreditado; cifras en fixtures y migraciones con ROLLBACK son solo pruebas. Se intentó releer Supabase en este lote, pero la conexión de solo lectura devolvió `Connection terminated due to connection timeout`; no declarar como evidencia actual el conteo previo de 0. No se creó ninguna migración ni se escribieron parámetros.

### Próximo lote técnicamente admisible

1. Recuperar lectura actual de `saly.config_global` / `creative_execution_policy_v1` y fijar fuente de aprobación para las cuatro claves.
2. Revisar posibilidad real de receipts Native + host y credenciales/identidades de los conectores autorizados. Si no existe API host confiable, mantener `DONE` bloqueado.
3. Diseñar puerta exclusiva de attestor en DB (incluyendo rechazo al worker y al canal textual alterno), con PG17 negativo, mutación y ROLLBACK sobre un esquema fiel.
4. Solo entonces: Router → PR no Draft → PASE → Merge Train → readback.

**Resultado del lote:** contrato de secuenciación añadido y 18/18 PASS sintéticos; integración externa y operativa NO verificada.

## Corrección de arquitectura: GPT_NATIVE y CLAUDE_NATIVE (22/11/2026)

### Fuentes reales empleadas

- `CLAUDE.md` y `AGENTS.md` de `main`: owner nativo actúa en la **conversación vigente**; GitHub Actions no llama por sí solo un modelo Native. Una continuación no es un RUN nuevo.
- `supabase/migrations/20261029140000_lf_profile_native_executor_claude_parity_v1.sql`: los pares canónicos son `GPT_NATIVE/OPENAI_CHATGPT_NATIVE` y `CLAUDE_NATIVE/ANTHROPIC_CLAUDE_NATIVE`. **Este contrato es para perfiles LF**, no es por sí solo una activación creativa.
- `skills/creative_factory/SKILL.md` v0.12: `PLAN_ONLY/REVIEW_ONLY`; no invoca modelos, Router, perfiles ni genera imágenes.
- `supabase/migrations/20261121154917_lf_saly_native_canonical_wire_v1.sql`: canon `SALY_CANONICAL_NATIVE_WIRE_V1`, `CANONICAL_WIRE_REVIEW_ONLY`, bytes, hash, y `native_transmitted=false`.
- `sandbox/creative_factory/native_transport_capture_v1.py`: `archive_pre_dispatch` conserva prompt y recursos **antes** del envío, sin declarar recepción ni proveedor.
- `docs/programming-agent/ANALYSIS_C2C3_GPT_NATIVE_APPROVED_EQUIVALENT_V1.md`: una captura en chat puede ser evidencia local equivalente acotada, `provider_attested=false`, **no** `REAL_EXECUTION_RECEIPT`. Es otro alcance, no transferir la autorización a SALY.
- `LF_resguardos_construccion.md`: B1, B6, B11, B13, B19, B25, B30 y B32.

### Solución candidata entregada

`native_session_bridge_v1.py` reconoce explícitamente ambos modos Native, rechaza una pareja modo/proveedor incorrecta y los falsos transportes (API, nueva sesión, fallback remoto). Consume bytes de `creative_native_canonical_wire_v1`, el hash del prompt y el recibo estructural de `archive_pre_dispatch`; conserva `order_id + item_id`. En **PLAN_ONLY** exige que `run_id` y `claim_id` sean nulos: no crear una cola operativa para revisar un plan. Devuelve un cursor hacia el **chat dueño actual**, no dispara imagen.

`classify_native_chat_artifact` solo verifica hash de bytes locales y separación de identidades. Su nivel es `NATIVE_CHAT_LOCAL_EQUIVALENT_NOT_PROVIDER_ATTESTED` y **jamás habilita `DONE`**. Un reporte del modelo no es un comprobante del proveedor ni del host.

`test_native_session_bridge_v1.py`: **21/21 PASS en Python local** para GPT/Claude, hash correcto, mezcla de proveedores, wire alterado, Base64, JSON duplicado, fake RUN, falsos receipts, entre otros. Los blobs del repositorio se releyeron y cotejaron exactamente con `git hash-object` local:
- `native_session_bridge_v1.py`: `7b9206529ebc4dcf0c674bc014a4d19860c2dc65`.
- `test_native_session_bridge_v1.py`: `c97a8af7d6c27eed8ef8c85d94a4e865529ac4d2`.

### Integración que **aún debe implementarse** (sin APIs ficticias)

1. Preparación Native `PLAN_ONLY` con `saly.creative_skill_prepare_v1` (lectura autorizada) → prompt canónico → `archive_pre_dispatch` → cursor del mismo chat. **Sin RUN** en esta fase.
2. Crear contrato aparte `RENDER_READY` para la operación creativa solo con autoridad vigente, parámetros `CREATIVE_FACTORY`, claims, RUN e ítems, una vez que las fuentes sean verificadas. No transformar la salida `REVIEW_ONLY` existente en un permiso de generación.
3. Ejecución en la sesión nativa propietaria con el modelo disponible. **No suponer** que el GitHub workflow o Python invocan `GPT_NATIVE` o `CLAUDE_NATIVE` en segundo plano, ni que los dos tienen el mismo proveedor gráfico.
4. Recibir evidencia de artefacto/entrega desde un transporte realmente existente; distinguir `LOCAL_NATIVE_CHAT_EQUIVALENT` de `PROVIDER_ATTESTED` y del `DELIVERED` del host. No elevar la evidencia local a atestación.
5. Asegurar una puerta SQL única con identidad autenticada, QA interno, hash de bytes y fencing token antes de `creative_queue_release_v1(DONE)`. Las RPC de texto de `queue_v02` siguen siendo inseguras para apertura de permisos.
6. Pruebas fieles PG17/ROLLBACK, PASE, autorización de cambio oficial, Train y readback tras integrar. No modificar ni cerrar los 2 pedidos anteriores.

**Estado:** desarrollo estructural Native **candidato**, no implementación operativa; **NO MERGE / NO DEPLOY / NO GRANT / NO RENDER**. La lectura Supabase RO en esta sesión sigue fallando por timeout: el recuento previo de configuración no es un readback actual.

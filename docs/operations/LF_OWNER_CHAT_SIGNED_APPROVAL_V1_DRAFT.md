# LF — Aprobación humana oficial por chat de orquestación (V2, DRAFT)

**Decisión del dueño 16/11/2026, 20:35 Lima:** la orden literal del dueño enviada como mensaje de usuario en el chat de orquestación es la **aprobación humana oficial y final** de todo PR de gobernanza y todo lote de promociones MANUAL, presente y futuro. No se exige clic de GitHub, web, correo, SMS, firma del proveedor ni servicio externo. Esta política no constituye una excepción: es contrato general. Esta fuente revoca el requisito de firma externa de la versión candidata anterior de #4063.

## Regla base y frontera de identidad

proponente -> contrato/snapshot cerrado -> render(scope) -> el dueño escribe APRUEBO <scope_hash corto> <alcance> en el chat -> orquestador toma el evento USER original -> recibo -> gate de consumo único -> decide HUMAN o Merge Train.

El hash (12 hex en orden visible, SHA-256 completo en receipt) vincula alcance y detecta manipulación; **no prueba identidad por sí mismo**. La identidad procede del **rol de emisor del evento original del transporte de orquestación**, con el actor_subject previamente vinculado al dueño. Un texto introducido por el modelo, un parámetro actor_subject escrito por el proponente o una captura de pantalla no equivalen al evento USER original. El registrador del mensaje se identifica separadamente del proponente: proposer_subject != registrar_subject y owner_subject != registrar_subject. El orquestador solo debe escribir a través del transporte oficial admitido; nunca dar capacidad de registro a los perfiles/LLM. Sin readback del evento USER original, el gate bloquea, **no por firma externa**, sino por falta de procedencia interna.

## Catálogo reutilizable; alcance individual cerrado

Tabla private.lf_owner_chat_action_catalog_v1: acciones habilitadas, claves obligatorias exactas, TTL máximo 900 segundos, versión. Dos entradas iniciales:

- MERGE_GOVERNANCE_PR: {action,repository,pr_number,head_sha}. Alcance único PR+HEAD. Si el Train cambia HEAD al sincronizar/retimestamp, exigir **nueva orden por chat**.
- PROMOTE_RULE_BATCH: {action,repository,execution_id,rule_codes,rule_snapshots_sha256}. Lista ordenada y sin duplicados + RUN + snapshot del lote. Una autorización no expande la cohorte ni implica GO de producción.

Para otras familias futuras, PR de gobernanza agrega entrada y validador de alcance al catálogo; no se crea otro canal. Prohibido habilitar una acción nueva sin validación y controles de alcance equivalentes.

Formato exacto de mensaje humano:

APRUEBO <primeros_12_hex_SHA256_UTF8_JSON_CANONICO_ALCANCE> <JSON_CANONICO_ALCANCE>

No hay contraseñas ni códigos remitidos fuera del chat; el hash corto se calcula localmente del alcance y no es un factor de autenticación. El recorte solo sirve para identificar la orden; el gate verifica además SHA completo y **JSON completo**. El literal es una instrucción *futura e individual*: la decisión general actual por chat no se convierte retroactivamente en autorización de merge o promoción de un alcance no expresado.

## Registro oficial propuesto

private.lf_owner_chat_orders_v1: source_chat_id, source_message_id único, source_kind=CHAT_ORCHESTRATOR_USER_TURN, actor_subject, proposer_subject, registrar_subject, acción, scope JSONB, scope_sha256, **texto literal**, literal_sha256, sent_at, recorded_at, expires_at, consumed_at, consumed_by. Fecha Lima en readback sent_at_lima, zona America/Lima. TTL 15 minutos desde el mensaje original. private.lf_owner_chat_revocations_v1 registra anulación antes del consumo. Tabla/fns en esquema private, sin GRANT EXECUTE a roles nuevos; PUBLIC/anon/authenticated/service_role revocados.

Funciones propuestas, source-only:
- private.fn_lf_owner_chat_register_v1: valida orden, tipo de evento, catálogo, alcance, SHA y separación de actores, registra recibo; solo autorizada desde registrador del orquestador, no desde el proponente.
- private.fn_lf_owner_chat_consume_v1: operación atómica FOR UPDATE; sin orden, otro scope/HEAD/snapshots, caducidad, revocación, reutilización, alteración o actores no separados retorna BLOCKED. Consume una sola vez bajo transacción del gate.
- private.fn_lf_owner_chat_revoke_v1: anula recibo no consumido, requiere otro mensaje original del dueño por el canal de orquestación.

## Integración con gates existentes (futuro cutover gobernado)

**HUMAN public.lf_rule_promotion_decide_v1:** exigir resultado CONSUMED del recibo PROMOTE_RULE_BATCH asociado a RUN y lista exactos; el lote gobierna llamadas existentes request/decide/apply y readback en una sola transacción. Mantener score, hard blocks, validaciones y AUTO_SCORE_V1. La cadena HUMAN:<nombre> nunca sustituye el receipt.

**Merge Train:** en el camino de main confiable, después del sync y PASE verde sobre HEAD exacto, pero antes del efecto, exigir recibo MERGE_GOVERNANCE_PR consumido atómicamente para ese pr_number+head_sha. La UI de GitHub no decide la autoridad humana. Conservar cola, locks, source parity, commit checks y políticas del Train.

**PASE:** validar arquitectura de canal y fixtures; un check SUCCESS no representa aprobación humana. PASE no genera orden ni consume recibo.

**Sin bypass:** este PR #4063 introduce la infraestructura candidata, NO cambia la función HUMAN en vivo, ni el Merge Train, ni PASE, ni los PR #4061/#4062. Falta el puente de transporte del evento USER original del orquestador a escritor autorizado y un readback de ese puente. No se exige firmante de proveedor. El mecanismo está **aceptado como política general**; la implantación operacional sigue **NO VERIFICADA** hasta integración y PG17/18.

## Evidencia de pruebas del candidato

Se corrieron 16 tests de verificador Python y 9 tests transaccionales SQLite con BEGIN/ROLLBACK: ausente, otro scope, caducado, reutilizado, revocado, actor incorrecto y autoaprobación, además de alcance PR y lote y catálogo de acción futura. 25/25 PASS en el ambiente local. Hashes, actor y origen del evento en estos tests son **datos sintéticos**.

**Límites:** SQL DDL/fns PG17/PG18 no ejecutadas en PostgreSQL local; no se ha introducido evento auténtico de orquestación ni activado el consumidor material HUMAN/Train. CI exact-head mide admisión/código del PR, no prueba integración material de este contrato.

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

private.lf_owner_chat_orders_v1: source_chat_id, source_message_id único, source_kind=canal de origen USER configurado, actor_subject, proposer_subject, registrar_subject, acción, scope JSONB, scope_sha256, **texto literal**, literal_sha256, sent_at, recorded_at, expires_at, consumed_at, consumed_by. Fecha Lima en readback sent_at_lima, zona America/Lima. TTL 15 minutos desde el mensaje original. private.lf_owner_chat_revocations_v1 registra anulación antes del consumo. Tabla/fns en esquema private, sin GRANT EXECUTE a roles nuevos; PUBLIC/anon/authenticated/service_role revocados.

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


## Lote IG 20:55 — implementación source-only + prueba PG17/18

- **HUMAN:** `private.fn_lf_owner_chat_promote_batch_v1` acepta un único order_id para un lote de promotion_ids existentes, bloquea cohorte/snapshot/RUN distintos y consume en la misma transacción. `public.lf_rule_promotion_decide_v1` se redefine mediante DO guardado por MD5 de la fuente actual `98f1be74469c91d577e5eca66b81cba5`, para que la ruta `HUMAN:*` APPROVE requiera un lease de la transacción exacta. `AUTO_SCORE_V1` permanece sin alteración intencional. Si la función fuente cambia, la migración falla cerrada. Ninguna aprobación/promoción real ha sido ejecutada.
- **Train:** `private.fn_lf_owner_chat_train_merge_gate_v1` consume una orden `MERGE_GOVERNANCE_PR` solo para PR+HEAD exactos; retorna `AUTHORIZED_FOR_TRAIN_ONLY` sin aplicar ni mergear. **Todavía NO hay invocación efectiva desde el workflow del Merge Train para migraciones y PRs code-only**. No se añadió gate paralelo ni se alteró el workflow que recibe credenciales DB. No se puede afirmar integración de producción; el siguiente cutover debe usar el transporte de escritura ya autorizado y comprobar el evento USER real.
- **Pruebas PG reales:** `sandbox/lf_contract_gate_test/owner_chat_approval/test_lf_owner_chat_pgdual_rollback_v1.py` ejecuta un fixture PostgreSQL 17.6 y otro PostgreSQL 18.7 con DDL de funciones de consumo, `BEGIN/ROLLBACK`, cero residuos en las tablas nuevas, caso de PR HEAD exacto, lote sintético de 22 reglas y negativos (sin orden, HEAD cambiado, vencida, repetida, revocada, autoaprobación). El fixture sustituye `decide_v1/apply_v1` por dobles y **omite el DO de pin MD5 de la función live**, porque no tiene el esquema productivo. Por tanto acredita el wrapper y consumo en PG17/18, **no** una promoción contra los contratos vivos.
- **Evidencia red→green:** primer job PG17/18 falló porque PostgreSQL puro no trae roles Supabase; después se corrigieron roles en setup, sincronización de arranque PostgreSQL y tres literales SQL dañados. La ejecución <https://github.com/repositorio LF configurado/actions/runs/44000026845> terminó SUCCESS (PG17/PG18). PASE, PASE Merge Gate, paridad, clasificación y admisión sobre HEAD anterior `23a93b8388188d1de327f01cc2faf12dc379a88d`: SUCCESS.
- **Cierre del lote:** código candidato DRAFT, no merge, no ejecución de perfiles, no promoción, no permisos EXECUTE nuevos, sin tocar PR #4061/#4062 ni producción. Falta readback del origen USER y el enlace efectivo al Merge Train antes de habilitar efectos.


## Lote IG 21:50 — dueño fijo, Train y prueba B2B-AUTH-002

Configuración de autoridad única en private.lf_owner_chat_identity_v1: nombre fijo **titular canónico LF**, canal fijo **canal de origen USER configurado**. No se parametriza por regla, pantalla, PR u orden. El transporte del orquestador aún debe acreditar de modo independiente que el USER turn original pertenece a esa identidad; no se infiere a partir del texto firmado por el propio modelo.

Fuente Supabase SELECT: lf_ops.pantallas id **52**, código **B2B-AUTH-002**, nombre **Recuperar acceso**, flujo **BACKOFFICE_B2B**, paso **RECOVERY_REQUEST**. Tiene 32 reglas vinculadas (25 VIGENTE, 7 CANDIDATO). Seis candidatas sin decisión pendiente: B2B-RULE-AUTH-027, B2B-RULE-AUTH-028, B2B-RULE-AUTH-042, B2B-RULE-AUTH-044, B2B-RULE-AUTH-045, B2B-RULE-COMPAT-001. B2B-RULE-THEME-002 tiene pendiente_decision=true: excluir de promociones mientras siga pendiente.

El test owner_chat_approval/test_lf_owner_chat_pgdual_rollback_v1.py usa el código real de request_v1, decide_v1 y apply_v1 del fixture de fuente LF más la migración IG0815 vigente, seguido por el parche MD5-protegido de decide_v1 en #4063. No tiene dobles de decide/apply; sí usa un RUN, mensajes y registros sintéticos exclusivamente en PostgreSQL 17/18 local con BEGIN/ROLLBACK. Esta prueba NO registra un evento auténtico del orquestador, no demuestra independencia del juez sintético y no escribe en Supabase.

El workflow lf-migration-merge-train.yml comprueba, desde main confiable, que existe exactamente un recibo no revocado/no consumido con el dueño fijo, PR y HEAD finales. Invoca fn_lf_owner_chat_train_merge_gate_v1 mediante el rol postgres del Train **antes** de aplicar, con bloqueo si el recibo o la función no existen. El job de merge exige output autorizado+HEAD exacto antes del merge. El flujo de bootstrap requiere atención: GitHub pull_request_target ejecuta el workflow del main previo hasta que estos cambios estén fusionados; no declarar el guard activo en producción mientras no haya readback de cutover.

### Necesidades consolidadas para futura activación

| Necesito | Para qué | Quién | Asumo si no hay respuesta |
|---|---|---|---|
| Evento USER original con conversation_id, message_id e identidad autenticada vinculada al dueño | Probar procedencia real del mandato por chat; no admitir textos de perfiles o modelos | Orquestador / plataforma | BLOCKED: ningún recibo real acreditado |
| Vinculación estable de identidad ChatGPT a titular canónico LF mediante el transporte existente | Autoridad fija comprobable sin pedirla por cada orden | Administrador de orquestación | Solo configuración nominal; no autenticación material |
| Ruta de ingesta del mensaje USER a la función registradora con permisos existentes | Crear recibos reales para HUMAN y Train sin nuevos roles | Operaciones LF | Fail-closed sin nuevos EXECUTE |
| Secuencia de bootstrap gobernado de SQL + workflow en main confiable | Evitar ventana de bypass/bloqueo irreversible del propio Train | Dueño / gobernanza LF | PR DRAFT, sin instalación ni merge |
| RUN real de pantalla B2B-AUTH-002 con once pasos y hashes/source_refs vigentes | Probar posteriormente contra un caso real sin inventar RUN | Router / orquestador | Solo fixtures sintéticos PG17/18; no promoción real |
| Resolver B2B-RULE-THEME-002 pendiente | Delimitar cohorte susceptible de promoción | Dueño / perfil competente | Excluir THEME-002; cohorte de 6 no pendientes |
| Orden APRUEBO con alcance literal cerrado tras fijar HEAD, RUN y snapshots | Validar consumo único y TTL 15 min para una orden REAL | Dueño, en el chat | No asumir la instrucción general como orden específica |
| Evidencia readback de la primera invocación material del Train y cierre de los checks | Verificar conexión real a la BD y al mecanismo, sin autoaprobaciones | Operaciones LF | Estado no verificado, sin activación |


## Lote IG 22:10 — normalización de autoridad y consumidor

Fuente operativa **única**: fila LF_OWNER de private.lf_owner_chat_identity_v1.
owner_sub se siembra por SELECT de public.lf_ig_project_owner_v2 (project_code LF)
y se vuelve a comprobar por JOIN; owner_name se obtiene solo por ese JOIN,
sin almacenamiento ni comparaciones por texto. repository_full_name,
channel_code y authority_role_code (SUPER_ADMIN) pertenecen a la misma fila,
no a cada regla ni pantalla ni orden.

La declaración de fuente pública sigue etiquetada UNVERIFIED_CHAT_DECLARATION
y usa un identificador UUID documental: leer una fila UUID **no** acredita
identidad de usuario ante la plataforma. La prueba de USER turn original
permanece pendiente, no crear un recibo real o autorizar acciones por mera
coincidencia de texto. La asignación SUPER_ADMIN en este contrato no concede
ningún rol SQL ni sustituye el control de identidad de Supabase Auth.

Firmas consumidoras usan UUID: register_v1 recibe p_actor_sub desde evento
USER autenticado; consume_v1/promote_batch_v1/train_merge_gate_v1 derivan
la identidad de la fila configurada, sin parámetro del dueño por orden.
El campo de auditoría decided_by de HUMAN contiene identificador UUID,
no nombre. El workflow conserva su allowlist histórica paulozterra,
cristhianlujan: es una admisión de actor de GitHub distinta de autoridad
de la orden chat, no normalizarla sin un cambio separado gobernado.


## Lote IG 23:05 — ACCOUNT_SESSION dual-channel

**Fuente única:** la fila LF_OWNER de private.lf_owner_chat_identity_v1 conserva
el owner_sub canónico unido a public.lf_ig_project_owner_v2. La tabla hija
private.lf_ig_parameters_v1 es la TABLA ÚNICA de parámetros. El dominio
OWNER_CHAT contiene solamente SHA-256 hexadecimal de lower(trim(correo))
para cada canal activo; la vista de compatibilidad
private.lf_owner_chat_authorized_accounts_v1 no duplica almacenamiento.
No existe dependencia de correo externo ni un valor claro persistente.
**No se interpreta el simple conocimiento del correo como prueba de sesión.**

**Regla de autoridad:** el registrador únicamente acepta una sesión si
owner_sub, canal, session_account_sha256 y activo coinciden exactamente
con una fila vigente de esa tabla. identity_mode del RECIBO se deriva a
ACCOUNT_SESSION solo en ese caso, nunca se recibe de un modelo ni de la orden.
No se altera por ello identity_mode de public.lf_ig_project_owner_v2;
conservar UNVERIFIED_CHAT_DECLARATION allí es correcto hasta una operación
oficial y distinta, además de que su constraint actual la requiere.
Si no hay sesión autorizada se lanza error, no se crea recibo y el estado
no evoluciona. Los recibos guardan canal, hash, literal y sent_at_lima;
el consumidor Train vuelve a comprobar que la cuenta permanece activa.
La revocación exige canal/hash igualmente.

**Límite material:** ACCOUNT_SESSION acredita coincidencia de cuenta/canal
según transporte protegido, más fuerte que una declaración del modelo,
pero NO equivale a una firma por mensaje por parte de ChatGPT o Claude.
Un hash conocido, incluso el del dueño, tampoco es prueba de sesión
si lo aporta un modelo o un archivo manipulable. Falta readback autorizado
de la sesión real en cada plataforma y la vinculación segura con el evento
USER original, sin aceptar metadatos declarados por el agente.

**Permisos/cutover:** no se añaden grants, no se ejecutan migraciones
ni Train sobre un PR productivo. La ruta pull_request_target sigue usando
main confiable y requiere bootstrap oficial de forma separada.


## Lote IG 23:25 — Correo único externo, dos canales activos (candidato)

- Decisión posterior del dueño: la huella de la cuenta solo se almacena en
  una tabla de parámetros gobernada, nunca como variable de instalación;
  los consumidores reciben únicamente un readback protegido. No publicar
  el correo en claro en documentación, migraciones, fixtures, tests o logs.
- El SHA256(lower(trim(email))) entregado coincide exactamente con la huella
  previa de Claude. La misma huella se siembra para `canal Claude configurado`
  y `canal ChatGPT configurado` a partir de una sola constante SQL, uniendo al
  `owner_sub` canónico. Nunca se incluye el correo real en claro.
- El registrador PostgreSQL recibe el correo únicamente desde metadatos de
  una cuenta de sesión previamente validada por el transporte protegido,
  calcula internamente SHA256(lower(trim(email))) y compara con la fila activa
  del canal. No persiste ni devuelve el texto del correo; el recibo conserva
  solo SHA, canal, identidad derivada, fecha Lima y orden literal.
  La revocación aplica exactamente la misma normalización.
- El validador Python exige un readback protegido de la configuración,
  incluida la lista de cuentas y canales activos. Compara el hash de sesión
  proveniente del transporte autorizado con la tabla canónica; si no
  existe fila activa, bloquea. La ausencia de credenciales de sesión
  acreditadas sigue siendo un bloqueo distinto de la coincidencia de hash.
- Tests aislados PG17.6/PG18.7: una cuenta **ficticia** ensamblada en
  memoria permite probar minúsculas, mayúsculas y espacios sin depositar el
  correo real en CI; primero se comprueba el seed real para los dos canales,
  luego se reemplaza la huella por el hash de la cuenta de prueba dentro de
  la transacción que se revierte. Un segundo guard inspecciona todos los
  archivos versionados y compara hashes de correos literales.
- Hallazgo de privacidad durante la guardia: el ledger histórico de
  migraciones tenía el correo del dueño en la columna `created_by`.
  Se redactaron esos valores con su hash y se dejó nota explícita;
  se conservaron nombres y versiones. No se alteró la base de datos.
- ACCOUNT_SESSION continúa sin equivaler a una firma verificable por
  mensaje ni acredita por sí solo el ingreso autenticado de ChatGPT/Claude.
  **No realizar promociones reales ni merge por la coincidencia de este
  hash:** se exige evento de sesión protegido y readback de autoría.


## IG 07:08 — parámetros únicos, gobernanza de cambios y mantenimiento (propuesta)

**Decisión fuente:** la tabla hija especializada no permite administrar
parámetros generales de IG y notificaciones. Se usa una sola tabla canónica
`private.lf_ig_parameters_v1` con clave (namespace, parameter_code, channel_code),
`value_kind`, valor tipado SHA256/JSONB, `activo`, `revision`,
`updated_at` y `last_approved_order_id`. Para OWNER_CHAT solo admite
SESSION_EMAIL_SHA256 por canal, vinculado a owner_sub canónico.
El hash del correo existente se sembró una única vez en SQL, en ambas filas.
Una vista de lectura mantiene las consultas de consumidores ya existentes;
no hay segundo almacén. No crear keys/notificaciones reales en este lote.

**Escritura controlada (candidato no desplegado):**
1. Solicitud de cambio con namespace, código, canal, valor hash objetivo,
   activo y revisión esperada; pantalla solo muestra propuesta.
2. Se congela alcance JSON + SHA. Dueño confirma literal `APRUEBO`
   en este chat como evento USER de sesión autenticado, distinto del
   productor. No se confunde esta autorización general de desarrollo con
   una orden futura para un cambio de fila concreto.
3. Registrador autorizado y diferente del proponente crea recibo único,
   `UPDATE_IG_PARAMETER` con TTL y alcance cerrado. El modelo no puede
   escribir recibos ni decidir su propio `identity_mode`.
4. `private.fn_lf_ig_parameter_update_v1` consume el recibo de forma
   transaccional, verifica versión/estado/alcance, y el trigger
   `lf_ig_parameter_governed_write_v1` rechaza INSERT/DELETE y UPDATE
   sin recibo consumido en esa misma transacción.
5. Una fila inmutable de `private.lf_ig_parameter_change_audit_v1`
   registra valor anterior/nuevo (solo hash), versiones, actor UUID,
   referencia del mensaje, hash de alcance y hora. Se exige readback
   posterior para considerar el cambio realizado.
6. Sin grants EXECUTE ni modificación en BD de producción. El escritor
   candidato por ahora admite solo cambio de cuenta OWNER_CHAT; futuros
   parámetros IG y NOTIFICATIONS necesitarán política/contratos propios.

**Pantalla de mantenimiento — DISEÑO/PROPUESTA, NO IMPLEMENTADA:**

`Mantenimiento > Parámetros` (uso exclusivo de operador autorizado).
Listado compacto con filtros por dominio, estado y código; columnas
`Parámetro | Canal/ámbito | Valor protegido (SHA abreviado) | Activo |
Revisión | Última aprobación | Última modificación`. Detalle muestra
definición del parámetro, versión vigente, historial de auditoría y
formulario de propuesta. Para correo, el valor en claro se ingresa solo de
forma transitoria (no persistir en frontend, telemetría, URL ni logs),
se normaliza a lowercase/trim, se transforma a SHA-256 y se descarta.
Acción `Solicitar aprobación` genera solicitud de alcance inmutable,
no actualiza la base. `Aplicar` se habilitará exclusivamente cuando
exista recibo autenticado, independiente, vigente, idéntico y sin consumir;
toda confirmación muestra readback. Proteger contra autoaprobación de modelos,
replay, version drift y bloqueo de ambos canales simultáneamente.

**Límites:** es propuesta de UI sin rutas, componentes ni permisos creados.
El hash de email es identificador de cuenta configurada, no autenticación
de proveedor ni firma individual del mensaje. Antes de activar cambios
en producción se requiere enlace efectivo del USER turn del orquestador
con un sujeto de cuenta validado, bootstrap gobernado y verificación de
permisos, incluido un mecanismo de recuperación si se rota el único
correo registrado en ambos canales. No hay cambios en PR #4061/#4062.

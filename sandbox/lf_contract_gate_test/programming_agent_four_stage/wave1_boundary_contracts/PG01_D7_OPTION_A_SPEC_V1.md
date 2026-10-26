# PG01_D7_OPTION_A_SPEC_V1

26-oct-2026 · Solo especificación, sin DDL, migración, cambios de ACL, writes, ejecución o activación. Es la posición propuesta de Paulo para D7-A, pendiente de confirmar en reunión. Base main ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267 y #3135 1bb2ca2.

## Objetivo y frontera de almacenamiento

Satisfacer PERSISTED_PROGRAMMING_CONTEXT_RECEIPT mediante un registro append-only del recibo PG-01 y su envelope verificable. El snapshot continúa exclusivamente en private.lf_decision_context_asof_v1, mediante public.fn_lf_decision_context_asof_record_v1 y resolve_v1. No crear otra tabla de snapshots, duplicar payloads de contexto o reemplazar su autoridad.

La tabla nueva de esta opción sería solo un ledger de recibos/admisiones enlazados al contexto existente. Nombre lógico propuesto: private.lf_programming_context_handoff_receipts_v1; no existe en el readback de catálogo de esta tarea. No es un objeto creado ni un nombre ya aprobado. Si se elige persistir el envelope en el almacén as-of existente, deberá acordarse su contrato y consumer/decision_ref específicos: eso es una variante futura, no una segunda copia del snapshot.

El patrón record_v1 es reutilizable para identidad, hash, replay/conflicto, append-only y recibo de escritura. No se puede invocar sin más para «persistir PG-01»: su entrada exige el contexto LF_DECISION_CONTEXT_ASOF_INPUT_V1, sus authority_refs y reglas; no valida los siete campos PG-01, el envelope A9 ni el scope admitido.

## Dos objetos distintos y un vínculo exacto

1. Recibo de frontera intacto: schema_version=PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 más siete campos de negocio: context_id, context_sha256, snapshot_schema_digest_sha256, receiver_schema_digest_sha256, material_projection_sha256, validated_material_paths y verdict ACCEPT/BLOCK.
2. Envelope de admisión y persistencia separado: referencias exactas de paquete/ejecución/pedido/target, resultado registrado del juez gobernado, scope solicitado/admitido y su procedencia, currentness material, versión de entrada y vínculo al hash del recibo.
3. Identidad del registro: binding de ambos a un mismo contexto y decisión, con autoría real de la operación escritora.

Los nombres de atributos de la tabla/envelope que siguen son requisitos lógicos propuestos, no campos ya emitidos por el Router ni columnas existentes. El contrato final se acuerda junto a PROGRAMMING_ENTRY_CONTRACT_V2. No se añade un octavo campo al recibo V1 ni se cambian sus bytes para insertar procedencia.

### Esquema lógico propuesto, no SQL ejecutable

| Elemento del registro | Contenido / regla |
|---|---|
| Identificador de registro | Inmutable; identificador asignado por la escritura gobernada, fuera del recibo de siete campos |
| Clave del binding | Hash de la identidad estable descrita abajo; única y cotejada por el lector |
| Referencia de contexto | context_id y context_sha256 exactos contra el snapshot as-of existente; sin copiar su payload |
| Recibo | Objeto exacto con schema_version y siete campos; validación de forma, digests, verdict y paths materiales |
| Hash del recibo | Digest recalculado independientemente por el escritor; algoritmo/representación explícitos |
| Envelope separado | Binding de admisión A9/juicio/paquete/ejecución/pedido/target/scopes/currentness/versiones al mismo recibo/contexto |
| Hash del envelope y del registro lógico | Recalculados sin incluir sus propios hashes ni metadatos volátiles; reglas versionadas |
| Autoría | Ejecución/operación real del escritor, referencia de autoridad y política vigentes; nunca p_actor libre del caller |
| Tiempos de auditoría | Momento de registro independiente de los times as-of del snapshot; no se usa para resolver latest |
| Vínculo de revisión, si aplica | Nueva decisión/juez/revisión se enlaza a registro anterior sin UPDATE o sustitución implícita |

## Idempotencia y conflictos

La clave estable de binding incluye contexto id/hash, identidad/hash del paquete, identidad exacta de target/revisión, scope solicitado ordenado y delimitado, identidad de ejecución A1–A9/pedido, identidad/versionado del juicio registrado y digest/versión del contrato de entrada. La composición exacta y sus tipos se congelan en el contrato futuro.

No incluir el hash del resultado/recibo como parte que cambie libremente la clave: permitiría insertar otro resultado para la misma identidad sin detectar conflicto. Tampoco incluir UUID/hora de inserción o ID de reintento del Train: son auditoría, no identidad semántica.

El request digest compara recibo y envelope completos bajo ese binding, excluyendo solo campos de transporte/auditoría definidos. Se propone reutilizar el algoritmo del patrón record_v1 para la representación JSONB: SHA256 de UTF-8 del jsonb::text calculado por Postgres. No usar json.dumps del cliente como si fuera equivalente; cualquier hash externo diferente debe estar nombrado y versionado por separado. No se cambia el cálculo existente de context_sha256.

| Situación | Comportamiento propuesto |
|---|---|
| Mismo binding, mismo request digest y mismos bytes lógicos | Devolver exactamente el registro original; conservar autor/tiempos/resultado; no insertar ni actualizar |
| Mismo binding, digest o contenido diferentes | BLOCK por conflicto de replay; comparar contenido además de clave/hash |
| Nuevo juicio/versión legítimos | Nueva identidad y fila enlazada, con evidencia de nueva admisión; no mutar anterior |
| Mismo context_id con otro context_sha256 | BLOCK; no reparar historial ni copiar snapshot |
| Scope/target/ejecución/pedido distintos | No reutilizar recibo; requerir binding y admisión exactos para el nuevo destino |
| Dos writers concurrentes del mismo binding | Restricción única y manejo transaccional de carrera; gana un registro, segundo coteja y devuelve replay o conflicto |
| Estado BLOCK que se quiere convertir en ACCEPT | No UPDATE ni promoción por overwrite: requiere un nuevo juicio/identidad y registro explícitos |

Las reglas de ACL y el escritor autorizado deben validar la identidad del juicio, no permitir que el caller invente otro judge_id para eludir un conflicto. Ninguna «última fila ACCEPT» es la autoridad del lector.

## Escritor gobernado y secuencia

El receptor PG-01 permanece lector y emisor puro del resultado: no tiene INSERT/UPDATE/DELETE, no llama record_v1 ni crea ejecuciones o reservas de Train.

Mientras rija el alcance autorizado de esta propuesta, cualquier escritura futura de schema o recibo sigue Router→ACTUALIZACION_DB_LF→PR→Merge Train, después de la decisión D7 y GO correspondiente. Train abre la ejecución real previa a apply y registra autoría/readback; no se fabrican IDs ni receipts retroactivos. La introducción de un writer runtime de mayor frecuencia exigiría otra autorización/contrato expreso: esta spec no lo habilita ni convierte un INSERT directo en runtime aprobado.

Secuencia propuesta:
1. A9 de Paulo ensambla los artefactos A1–A8 fuera del modelo.
2. Escritor autorizado persiste el snapshot único con record_v1 y coteja readback as-of/id/hash. Esta escritura no equivale a admisión semántica.
3. Juez gobernado independiente evalúa el snapshot y paquete exactos; operación gobernada registra su resultado y procedencia READY por scope.
4. Se construye el envelope A9 ligado al contexto y juicio registrados. No se modifica el snapshot inmutable para añadir resultados posteriores.
5. La futura frontera V2 de PG-01 consume esa evidencia y emite el recibo de siete campos, sin efectos.
6. Escritor D7-A valida binding/recibo/envelope, inserta o devuelve replay exacto y produce evidencia de registro.
7. Lector independiente hace readback; una futura compuerta SQL del Router comprueba PERSISTED_PROGRAMMING_CONTEXT_RECEIPT por clave exacta antes de autorizar el flujo de código.

Hay que acordar la separación entre generación del recibo de frontera y admisión operacional que exige su persistencia, para evitar un ciclo «necesito recibo persistido para producir el mismo recibo». No se implementa esa secuencia ni el adaptador Router aquí. La política actual la exige nominalmente, pero la ruta PROGRAMACION no tiene todavía este lector/dispatch conectado.

## Lector SQL por clave exacta

API lógica propuesta, sin crear función: recibir binding esperado, context_id/hash, target/revisión, scope solicitado, referencia del juicio admitido y digest/versión de entrada, provenientes de autoridad gobernada independiente del receptor. Resolver una fila exacta y verificar:
- Identidad completa, unicidad, hashes de recibo/envelope y concordancia con el contexto as-of existente.
- Juicio registrado, admisor/juez autorizado, scopes admitidos con procedencia y cierre material.
- Recibo verdict=ACCEPT; registros BLOCK son auditables, no autorizan.
- Currentness material vigente, dependencias y validez de autoridad/contrato; un registro histórico no queda vigente para siempre.
- Ausencia de revoke/conflicto/supersesión aplicables según la política futura de autoridad.
- Runtime y operación autorizados en compuertas separadas. Persistencia/ACCEPT no conceden ejecución.

La implementación futura debe tener búsquedas indexadas por la identidad exacta, sin ORDER BY latest ni fallback a otra fila. Si la autoridad independiente no entrega binding esperado o juicio verificable, bloquear. No basta que el caller aporte un receipt_id existente.

resolve_v1(consumer,subject,as_of) puede recuperar un contexto histórico para cotejar; no reemplaza el lookup exacto del ledger PG-01. Comparar siempre id y hash esperados y recalcular, pues resolve_v1 no toma esos parámetros ni verifica currentness semántica.

## ACL y separación de responsabilidades propuestas

| Actor | Permisos previstos |
|---|---|
| Operación escritora vía Train | Entrada restringida y transaccional; validar autoridad/ejecución/binding del escritor; INSERT controlado y SELECT necesario para replay/readback |
| Receptor PG-01 | Solo lectura por interfaz exacta; ningún permiso de escritura o capacidad de firmarse una admisión |
| Router | Solo lector SQL acotado, sin acceso a credenciales o autorización de insertar; no confiar en bool supplied por caller |
| Juez gobernado | Evalúa con fuentes independientes; su resultado se registra por la operación autorizada, no por un UPDATE a la fila del receptor |
| Verificador independiente | Readback mínimo y trazable de contexto/recibo/envelope/juez; sin privilegios para completar evidencia ausente |
| PUBLIC / anon / authenticated | Sin INSERT/UPDATE/DELETE ni EXECUTE del futuro writer; sin lectura amplia de envelopes si contienen evidencia sensible |

SECURITY DEFINER, si se elige, requiere search_path fijo, ownership/grants mínimos y validación de ejecución efectiva; no basta un string p_actor_execution_id ni una variable libre. RLS no sustituye restricciones, control del writer ni guardia append-only; evaluar su necesidad según roles de backend y política admitida.

La función viva record_v1 tiene ACL observada con EXECUTE para PUBLIC/anon/authenticated/service_role y solo comprueba actor no vacío en su cuerpo; la validación privada es estructural. No copiar esa accesibilidad como autorización D7. No se modifican sus grants en esta tarea; cualquier endurecimiento compartido necesita scope/revisión propio.

Append-only: proteger UPDATE/DELETE también por trigger, siguiendo private.fn_lf_decision_context_asof_immutable_v1, sin impedir las nuevas filas legítimas. El bypass administrativo no es ruta operativa. Auditoría de nuevas versiones, ausencia de sobrescritura y retención deben quedar en el contrato futuro.

## Readback independiente y patrón record_v1

| Patrón vivo reutilizable | Adaptación pendiente para D7-A |
|---|---|
| record_v1 devuelve id/hash/decision_ref y NEW_CONTEXT o IDEMPOTENT_REPLAY | Diseñar recibo de registro D7 propio, sin cambiar los siete campos del recibo de frontera |
| UNIQUE decision_ref/context_sha256 y conflicto de digest | Clave de binding de admisión/scope y comparación de payloads; no reutilizar decision_ref sin contrato |
| Trigger as-of bloquea UPDATE/DELETE | Mismo principio para ledger de recibos, sin duplicar snapshots |
| Hash del JSONB persistido | Algoritmo y normalización explícitos del recibo/envelope, con readback recalculado |
| Resolve histórico con identidad y payload | Lector D7 exacto más cotejo contra snapshot único; nunca asumir que as_of es lookup por id |
| Dependencies/currentness de capacidades y typed_evidence | Añadir validación del juicio A9, procedencia READY, currentness material y permisos reales del escritor |

El verificador lee desde destino, recalcula hashes y compara binding, campos, identidad del juez y snapshot; no consume solo el resultado «insertado» del writer. Si falta readback independiente, PERSISTED_PROGRAMMING_CONTEXT_RECEIPT no se satisface.

Negativos a diseñar/ejecutar en tarea futura: actor no autorizado, envelope/juez faltante o alterado, scope ajeno/replay, id/hash de contexto distintos, contrato desalineado, stale/unknown, BLOCK persistido, duplicados concurrentes y conflictos, pérdida de material, intento UPDATE/DELETE y readback ausente. No se ejecutan ni se declara resultado sobre ellos aquí.

## Decisiones abiertas

Confirmar D7-A, contrato V2/envelope, identidad del juez/operación registradora y lector SQL, composición exacta de claves, política de supersesión/currentness, ACL y manejo futuro de frecuencia de escrituras. D8 #3167 permanece intacto y draft; no es el permiso para escribir D7. Referencias: A9_ASSEMBLER_SOURCES_V1.md y PG01_A9_ADMISSION_ENVELOPE_DESIGN_V1.md.

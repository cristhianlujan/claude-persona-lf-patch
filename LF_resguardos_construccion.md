# LF — Resguardos de construcción (concurrencia, transporte y cierre)

Versión 1 · 2026-11-20 · Alcance: núcleo de reglas, IG, T_REMED, perfiles, colas y Train.
Cada resguardo se probó en un sandbox (Postgres 16 local y Python 3), con un caso que provoca el problema y su protección. LF usa Postgres 17; los mecanismos citados son iguales en ambas versiones.

Regla general: **ningún PR entra si toca un punto de esta lista y no trae la prueba que provoca el problema.**

El documento tiene dos partes:
- **Parte A:** problemas generales de concurrencia y transporte (1 a 14).
- **Parte B:** problemas que ya ocurrieron en LF, tomados de la EKB (1.468 errores registrados, 370 recurrentes), de mediciones hechas hoy en Supabase y de lo vivido en el proyecto (B1 a B24).

---

# Parte A — Concurrencia y transporte

## 1. Contratos
**Problema en LF:** llegan campos de transporte vacíos y contratos con restos de versiones anteriores.
**Regla:**
- Toda función pública valida su contrato de entrada **antes** de hacer cualquier cosa.
- Si falta un campo o llega vacío, la llamada se rechaza con un código claro. No se adivina un valor por defecto.
- Los contratos tienen versión. Un cambio incompatible crea `_v2`, no edita `_v1`.
- Contrato de salida: nunca se emite un campo obligatorio vacío.

**Prueba:** `encolar` con `regla=""` devolvió `RECHAZO CONTRATO: campo regla vacío` sin escribir nada.

## 2. Jueces
**Problema en LF:** el contenido cambia después de que el juez lo evaluó y el veredicto se sigue usando.
**Regla:**
- El veredicto guarda el hash del objeto que evaluó.
- Antes de usarse, se recalcula el hash. Si no coincide, el veredicto queda **inválido** y hay que juzgar de nuevo.
- El juez recibe una **copia profunda** (ver 11) y no puede modificar lo que evalúa.

**Prueba:** el veredicto era válido. Se cambió el texto de la regla y quedó `INVÁLIDO, rejuzgar`.

## 3. Sincronización y condición de carrera
**Problema:** dos procesos leen la misma regla y escriben encima uno del otro (el último gana sin enterarse).
**Regla:**
- Concurrencia optimista: toda escritura lleva la versión leída (`WHERE version = :leida`). Si no actualiza nada, devuelve `CONFLICTO` y el llamante relee.
- Los contadores y límites compartidos se serializan con `pg_advisory_xact_lock` o `SELECT … FOR UPDATE`.
- Nunca hacer leer → decidir → escribir en transacciones separadas.

**Prueba:** A y B leyeron la versión 1. A escribió (`OK`) y B recibió `CONFLICTO`. Quedó solo el cambio de A, en versión 2.

## 4. Colas
**Problema en LF:** el mismo trabajo se toma dos veces (PR duplicados) o queda tomado por un proceso que murió.
**Regla:** la cola es una tabla en Postgres con estas protecciones:
- `FOR UPDATE SKIP LOCKED` al tomar, para que dos trabajadores nunca tomen el mismo ítem.
- **Lease** (préstamo con vencimiento): `lease_hasta`. Si vence, otro trabajador lo puede recuperar.
- `intentos` con un máximo. Al superarlo, el ítem pasa a una cola de fallidos y no se reintenta más.
- **Clave de idempotencia** única: si llega dos veces el mismo pedido, solo se procesa una vez.

**Prueba:** 3 trabajadores concurrentes tomaron ítems distintos (1, 3 y 4). El duplicado `cb-1` fue `DUPLICADO ignorado`.

## 5. Bounded queues (colas acotadas)
**Problema:** una cola sin límite crece hasta saturar la base o los chats.
**Regla:**
- El tamaño máximo es un parámetro de configuración (`cola_max`), no un número en el código.
- Al llegar al límite se rechaza el pedido explícitamente (presión hacia atrás, *backpressure*).
- El conteo y la inserción ocurren bajo un mismo bloqueo. Sin bloqueo, la carrera rompe el límite.

**Prueba:** 10 pedidos simultáneos con `cola_max=5` dieron 5 `ENCOLADO` y 5 `cola llena`. En la cola quedaron exactamente 5.

## 6. Starvation (inanición)
**Problema:** un trabajo de baja prioridad nunca se atiende porque siempre llega algo más urgente.
**Regla:**
- Prioridad con **envejecimiento** (*aging*): la prioridad efectiva mejora con el tiempo de espera.
- La tasa de envejecimiento es un parámetro (`aging_seg`) y se calibra con datos reales.

**Prueba:** sin envejecimiento, la tarea lenta no salió en 10 rondas. Con `aging_seg=1`, salió en la ronda 9. Con `aging_seg=2` tampoco salió en 10 rondas: un valor mal calibrado equivale a no tener envejecimiento.

## 7. Join (esperar a todos los hijos)
**Problema en LF:** un RUN padre se cierra antes que sus hijos, o nunca se cierra.
**Regla:**
- Cada hijo, al terminar, bloquea la fila del padre (`FOR UPDATE`) y verifica si quedan hijos abiertos.
- Solo el último hijo cierra al padre.
- Así, dos hijos que terminan a la vez no pueden cerrarlo los dos ni dejarlo abierto.

**Prueba:** 3 hijos terminaron en simultáneo. H1 y H2 respondieron `padre espera`, H3 `padre cerrado`, y el padre quedó `COMPLETADO`.

## 8. Async y callbacks
**Problema:** un callback llega dos veces, nunca llega o llega tarde.
**Regla:**
- Todo callback lleva una clave de idempotencia (ver 4).
- Toda espera tiene timeout (ver 13).
- El emisor no supone éxito: el estado queda `ESPERANDO_CALLBACK` hasta recibir la confirmación.

**Prueba:** el callback rápido respondió. El lento cayó por timeout a los 0,5 s y quedó marcado para reintento.

## 9. Productor–consumidor: BlockingQueue y thread-safe
**Problema:** dentro de un script o agente, varios hilos comparten una lista sin protección y se pierden datos.
**Regla:**
- Entre hilos, solo se transportan datos por una cola segura para hilos: `queue.Queue(maxsize)` en Python, `BlockingQueue` en Java.
- Nunca listas ni diccionarios compartidos sin bloqueo.
- Para terminar, se envía una marca de fin (*sentinel*) por cada consumidor.

**Prueba:** 4 productores × 500 ítems, con 3 consumidores y una cola de 10, dieron 2000 recibidos, 2000 únicos y 0 perdidos. Control sin protección: se esperaban 800 000 y se obtuvieron 201 646.

## 10. Out-of-order execution (eventos fuera de orden)
**Problema:** el paso 3 llega antes que el 1 y se aplica sobre un estado equivocado.
**Regla:**
- Cada evento lleva un número de secuencia por entidad.
- Se aplica solo el `último + 1`. Los adelantados esperan y los repetidos se ignoran.
- Al aplicar uno, se drenan los que esperaban.

**Prueba:** llegaron 3, 1, 2, 2. El 3 esperó, el 1 se aplicó, el 2 se aplicó y drenó al 3, y el segundo 2 se ignoró.

## 11. Deep copy
**Problema:** un paso modifica un objeto que otro paso (o el juez) ya había tomado como referencia.
**Regla:**
- Al pasar datos entre pasos se entrega una **copia profunda** (`copy.deepcopy`) o el dato serializado (JSON), nunca la referencia viva.
- En SQL, `jsonb` ya se maneja por valor.
- El riesgo está en el código de los agentes y scripts.

**Prueba:** se cambió `monto_max` después de copiar. La copia superficial vio 99 999 (corrupta) y la profunda conservó 8 000.

## 12. Bloqueos: deadlock y bloqueo animado (livelock)
**Problema:** dos procesos se esperan mutuamente (deadlock), o reintentan a la vez una y otra vez sin avanzar (livelock).
**Regla:**
- Bloquear siempre en el **mismo orden**: ordenar por clave antes de `FOR UPDATE`.
- Los reintentos usan **espera exponencial con aleatoriedad** (*backoff con jitter*), nunca un intervalo fijo, y tienen un máximo de intentos.

**Prueba:**
- Con orden de bloqueo opuesto, Postgres detectó `deadlock detected`. Ordenando por código, hubo 0 deadlocks.
- Livelock (simulación): con reintento fijo, el choque siguió sin resolverse tras 50 rondas; con jitter se resolvió en la primera.

## 13. Timeouts
**Problema en LF:** procesos y chats que esperan para siempre.
**Regla:**
- Toda operación tiene timeout, configurado como parámetro.
- En Postgres: `lock_timeout` y `statement_timeout` por función o por rol.
- En colas: el lease (ver 4).
- En agentes: `wait_for` y límites de tiempo por paso.
- Si se vence el tiempo: estado `FALLIDO` con motivo `TIMEOUT`, y se reintenta o se reporta.

**Prueba:**
- Con un bloqueo retenido 3 s y `lock_timeout=500ms`: `canceling statement due to lock timeout`.
- Un lease vencido de 1 s fue recuperado por otro trabajador, con `intentos=2`.

## 14. try…finally (cierre garantizado)
**Problema en LF:** RUN que quedan `IN_PROGRESS` para siempre después de un error.
**Regla:**
- Todo paso que abre un estado lo cierra pase lo que pase.
- En PL/pgSQL: un bloque `BEGIN … EXCEPTION WHEN others THEN <marcar FALLIDO>` dentro de la función.
- En Python: `try/finally` o un gestor de contexto (`with`).
- Prohibido dejar un estado intermedio sin salida.

**Prueba:** el paso falló a la mitad (división por cero) y el RUN quedó `FALLIDO`, no `EN_PROCESO`.

---

# Parte B — Resguardos propios de LF (problemas que ya tuvimos)

Cómo leer la evidencia de cada punto:
- **EKB:** código y frecuencia registrados en `lf_error_knowledge`.
- **Medido hoy:** consulta de solo lectura en Supabase del 2026-11-20.
- **Probado:** reproducido en el sandbox local.
- **Proyecto:** ocurrido en el trabajo de IG, sin volver a medirlo hoy.

## B1. Suponer el esquema en vez de leerlo
**Qué pasó:** consultas y handoffs con nombres de columnas que no existen o no coinciden con la tabla real.
**Evidencia:** es el error más frecuente de la EKB.
- DB-001: 245 veces
- SQL-017: 47
- DB-SCHEMA-FIRST-COLUMN-ASSUMPTION-001: 29
- GOV-READBACK-SCHEMA-ASSUMPTION-001: 15

**Regla:** antes de leer o escribir un objeto que no se inspeccionó en el mismo lote, consultar `information_schema.columns` y `pg_constraint` en una sentencia aparte. El contrato del handoff se construye desde el esquema real, no desde la memoria.

## B2. Migraciones aplicadas sin fuente en Git o fuera del Train
**Evidencia:** EKB.
- Fallo de paridad entre migración y fuente: 235 veces
- CI-MIGRATION-SOURCE-PARITY-001: 37
- SRC-001: 24
- GOV-CI-MIGRATION-SOURCE-PARITY-20260829: 22
- CI-MIG-001: 12

**Regla:**
- Toda migración entra solo por PR y Train, con un archivo por PR.
- El nombre debe estar clasificado en `main` antes de ponerle la etiqueta.
- Nunca usar `apply_migration` ni DDL por `execute_sql`.

## B3. Merge por fuera del Train mientras otro corre
**Qué pasó:** `main` se movió debajo del Train. En el incidente #2484 de octubre se fusionó directo mientras corría el #2485.
**Evidencia:** EKB CI-014 y la regla del repositorio.
**Regla:**
- Todo merge se hace con `ready-to-merge`, y nunca hay dos PR propios en el Train al mismo tiempo.
- Si `main` avanzó, se actualiza la rama sin force-push y se reetiqueta.

## B4. Varias consultas en una sola llamada esconden resultados
**Evidencia:** EKB DB-002, 23 veces.
**Regla:** una consulta por llamada, o todo combinado en un único `SELECT` (con `UNION` o JSON).

## B5. Un identificador consumido no prueba que se escribió algo
**Evidencia:** EKB SQL-009, 20 veces. **Probado:** se insertaron 2 filas, se hizo ROLLBACK, y la siguiente fila recibió el id 3.
**Regla:** nunca usar el valor de una secuencia como evidencia de escritura ni de ausencia de escritura. Se verifica leyendo la fila.

## B6. Recibo válido no es calidad
**Evidencia:** EKB GOV-032 (16 veces) y AB-PROFILE-QUALITY-GATE-001 (14).
**Regla:** separar siempre dos controles:
- El de procedencia: quién lo hizo, el hash y el recibo.
- El de calidad: si el contenido es correcto.

Un recibo auténtico no autoriza nada por sí solo.

## B7. Pruebas de concurrencia de mentira
**Evidencia:** EKB AUD24-F01, 16 veces.
**Regla:**
- Una prueba de concurrencia lanza **al menos dos invocaciones reales en competencia**, con la misma clave, y comprueba que el efecto ocurrió una sola vez.
- Los resguardos 3, 4, 5 y 7 de la Parte A se hicieron así.

## B8. Validadores y listas permitidas que no se actualizan junto con el cambio
**Evidencia:** EKB CI-003, 17 veces.
**Regla:** si cambia un archivo gobernado, en el mismo PR se actualizan sus listas permitidas, pines de hash y pruebas.

## B9. Ampliar el timeout como "solución"
**Evidencia:** EKB PROFILE-ROUTER-INPUT-GOV-CURRENTNESS-TIMEOUT-001, 10 veces.
**Regla:**
- No se amplía un timeout para que algo pase.
- Primero se mide qué se repite, y se reutiliza un resultado reciente (caché con control de vigencia).

## B10. RUN abiertos para siempre
**Medido hoy:** 36 ejecuciones en `IN_PROGRESS`, 33 de ellas con más de un día.
**Regla:**
- Cierre garantizado (resguardo 14 de la Parte A).
- Además, un barrido periódico que pase a `FALLIDO` con motivo `ABANDONADO` toda ejecución cuyo lease venció. Así ningún tablero cuenta como "en curso" algo que está muerto.

## B11. Controles que solo repiten lo que reciben (controles formales)
**Proyecto:** en la ruta de creación de IG, `classify` devolvía la categoría recibida y `existing_check` solo contaba el código.
**Probado:** con un texto de sesión etiquetado como UX, el control formal devolvió `UX`, y el control real lo rechazó como de SESIÓN.
**Regla:** todo control trae una **prueba negativa**, un caso malo que demuestre que lo rechaza. Un control que nunca ha rechazado nada no cuenta como control.

## B12. Varias puertas con validaciones distintas
**Proyecto y medido:**
- Hay dos puertas para crear reglas: la directa y la de IG V2.
- Hay 10 funciones que escriben `lf_ops.reglas` cada una con sus propias validaciones.

**Regla:** una sola puerta de escritura por entidad; las demás la llaman. Es el plan de acople.

## B13. Datos fijos en reglas y en funciones
**Medido:** 85 reglas con una cifra sin variable (auditoría del 19 de noviembre). Hoy, además, la función de puntaje de promoción tiene el umbral 85 escrito en el código y no lee `lf_global_config`.
**Regla:**
- Todo umbral, límite o ventana vive en `lf_global_config`, en un solo lugar.
- Esto aplica también a los umbrales de los propios controles.

## B14. La misma relación guardada dos veces
**Medido hoy:**
- `public.lf_prevention_rules` y `transversal.prevention_rules` son idénticas: 280 filas con el mismo hash de contenido.
- Hay 6.177 enlaces regla–pantalla copiados a mano.

**Regla:** si una relación se puede derivar, se calcula con una vista o función. Nunca se copia en otra tabla.

## B15. Una regla vigente que cita una candidata
**Medido hoy:** 13 reglas VIGENTE citan una regla CANDIDATO.
**Regla (invariante):** una regla VIGENTE solo puede citar reglas VIGENTE. Se valida al promover y al cambiar una regla.

## B16. Borrar una regla viva rompe sus relaciones
**Proyecto:**
- Seis claves foráneas impedían borrar.
- No existía un estado "retirada".

**Regla:**
- Se reemplaza con un **código nuevo**, se re-enlaza y se retira la vieja con el motivo `REEMPLAZADA_POR:<código>`.
- Nunca se reutiliza el código ni queda un momento sin regla. Así se hizo en el piloto del 19 de noviembre.

## B17. Un criterio pensado para una clase bloquea a otra
**Proyecto:** el mínimo de 5 pantallas para promover bloqueaba las reglas de backend, que no tienen pantallas.
**Regla:** todo umbral nuevo se prueba contra todas las clases de regla (pantalla, backend y transversal) antes de activarlo.

## B18. Bloquear el flujo por el contenido
**Proyecto:** pasos de IG que detenían la corrida porque una regla tenía defectos.
**Regla:**
- Un paso solo se bloquea por un error del propio flujo.
- Los defectos de contenido se reportan y la corrida sigue.
- Las dependencias no son de arrastre: basta con que la unidad anterior haya terminado y esté habilitada.

## B19. Restricciones que nadie aprobó
**Proyecto:** etiquetas como "solo sandbox", `no_promotion` y "producción NO-GO" fueron agregadas por un agente sin aprobación del dueño.
**Regla:** toda restricción registra quién la definió y cuándo. Si no tiene origen aprobado, no se aplica.

## B20. Trabajo duplicado entre agentes o chats
**Proyecto:** se abrieron PR duplicados para la misma regla (se cerraron duplicados del #4332).
**Regla:**
- Cada tarea tiene una clave única y un solo dueño.
- Antes de crear un PR o un issue se busca si ya existe uno para esa clave (idempotencia, resguardo 4).

## B21. EKB que se lee pero no se escribe
**Proyecto:** los chats consultaban la EKB y no registraban lo aprendido.
**Regla:** ningún bloque se cierra sin registrar en la EKB el error nuevo o sumar la recurrencia de uno conocido.

## B22. Chats que llegan a su límite y traspasos incompletos
**Proyecto:** el chat 12 se llenó a mitad de la familia B.
**Regla:**
- Se cambia de chat antes de que se llene.
- El traspaso lleva los campos mínimos de la sección 15.9 del protocolo del repositorio: PR, rama, SHA, ejecución, estado y próximo paso.

## B23. Pruebas de punta a punta contaminadas por el pedido
**Proyecto:** los pedidos largos, o con códigos de familia, le daban pistas al agente.
**Regla:** las pruebas de punta a punta usan un pedido mínimo y sin pistas, y reglas reales.

## B24. Una función con efectos usada como filtro
**Probado (encontrado durante estas pruebas):** una función que cambia datos, usada dentro de un `WHERE` (`… where id = tomar('w')`), se ejecuta **una vez por fila** y toma varios ítems a la vez.
**Regla:** una función con efectos se llama sola, en una CTE (`with t as (select tomar(...))`) o en una sentencia aparte, nunca como filtro.

## B25. Una prueba negativa que pasa por el control equivocado
**Probado (bloque C del núcleo, EKB `LF-AUTOTEST-MASKED-CONTROL-20261120-001`):** la prueba de código repetido solo exigía «rechazada»; el control de duplicado también rechazaba, así que con el control de código anulado la prueba seguía pasando. Cuatro mutantes sobrevivieron por esto.
**Regla:** cada prueba negativa comprueba que falló **el control que prueba** (por número o nombre), no solo el resultado final, y se confirma con una mutación de ese control.

## B26. Estructura sin validar antes de inspeccionarla
**Probado (bloque C, EKB `LF-NUCLEO-CONDITION-AS-STRING-BYPASS-20261120-001`):** una condición enviada como texto en vez de objeto no tenía hojas que revisar; los controles de vocabulario, datos fijos y parámetros pasaban vacíos y el evaluador entró en recursión infinita.
**Regla:** validar primero la forma completa de una estructura (árbol, JSON, contrato) y solo después su contenido; todo recorrido recursivo falla de inmediato ante un nodo inválido.

## B27. Dos relojes en la misma operación
**Probado (bloque C, EKB `LF-NUCLEO-CLOCK-TIMESTAMP-VS-NOW-20261120-001`):** se publicó con `clock_timestamp()` y el resolvedor filtraba con `now()` (inicio de la transacción): la regla recién creada no era visible en la misma transacción.
**Regla:** una operación usa un solo reloj; las fechas de vigencia que otro proceso lee usan `now()`; `clock_timestamp()` solo para trazas.

## B28. Un mutante muerto por error de sintaxis no es evidencia
**Probado (bloque D, EKB `LF-MUTANT-KILLED-BY-SYNTAX-NOT-EVIDENCE-20261121-001`):** dos mutantes «murieron» por error de sintaxis o por una construcción no soportada, y una mutación que anulaba solo un operando de un `OR` parecía sobrevivir aunque el resto de la condición seguía detectando el caso.
**Regla:** un mutante cuenta como muerto solo si falla con el mensaje de la aserción esperada; cada mutación anula el comportamiento completo (por ejemplo, el `RAISE`), no un operando.

## B29. Cambiar una función con llamadores sin medir la equivalencia
**Probado (promoción legada, PR #4477):** antes de reemplazar `lf_rule_promotion_score_v1` se comparó la versión vieja con la nueva en 6.655 combinaciones sintéticas que recorren todas las ramas, y la migración compara la huella de producción antes y después y se revierte si difiere.
**Regla:** toda función con llamadores se cambia con una prueba de equivalencia (o con la diferencia esperada declarada) y una verificación antes/después dentro de la misma migración.

## B30. Registrar no es publicar
**Probado (bloque E, EKB `LF-NUCLEO-VERSION-INSERT-EQUALS-PUBLISH-20261121-001`):** insertar una versión la dejaba vigente en el acto; una versión 2 de una regla VIGENTE habría entrado en efecto sin evaluación ni juicio. Se detectó al diseñar la ruta de cambio, con las tablas aún vacías.
**Regla:** todo objeto con ciclo de vida separa el registro de la entrada en efecto, y la entrada en efecto pasa por la promoción. Cada fase nueva se revisa contra el ciclo completo (registrar, evaluar, publicar, implementar) antes de construirla.

## B31. Esperar el Train por identidad, no por posición
**Probado (instancia SALY, EKB `LF-TRAIN-POLL-LATEST-RUN-MISSES-OWN-20261121-001`):** la espera miraba la corrida más reciente del Train; otra rama encoló la suya justo después y la espera siguió hasta su límite aunque el PR propio ya estaba fusionado.
**Regla:** esperar por el estado `merged` del propio PR o por la corrida filtrada por rama o título; nunca por la posición en la lista.

## B32. Un motor compartido no lleva datos de una instancia
**Probado (PR #4483 y #4484, EKB `LF-NUCLEO-ENGINE-PRODUCT-CONSTANTS-20261121-001`):** el control 19 tenía escritos los ámbitos de LF y las autopruebas usaban datos reales de LF, lo que impedía reutilizar el motor en SALY.
**Regla:** los valores de producto van en la configuración de cada instancia; las pruebas crean sus propios datos; una prueba conjunta verifica la paridad entre instancias.

## B33. Base de datos de solo lectura
**Regla:** La base de datos es solo lectura. Todo cambio (migración, DDL y DML de migración) va exclusivamente por PR → Merge Train con la etiqueta `ready-to-merge`. Nunca utilizar `apply_migration` ni realizar escrituras por `execute_sql`. Un rechazo por permiso es intencional: no buscar otra vía.

## B34. Rigor proporcional
**Regla:** No agregar candados (SHA, firmas, hashes o bloqueos) a algo que aún no se demostró que funciona. Primero demostrar funcionamiento de punta a punta, luego calidad y al final seguridad. Respetar los controles ya vigentes y obligatorios de la ruta gobernada.

## B35. Foco y hallazgos en la EKB
**Regla:** Las sugerencias laterales del operador se acumulan como HALLAZGO, se registran en la EKB y se atienden después del foco principal, salvo urgencia. Antes de comenzar cada lote, consultar la EKB. Todo hallazgo debe registrarse allí.

## Lista de revisión para cada PR
- [ ] El contrato de entrada se valida al inicio y no puede salir ningún campo obligatorio vacío.
- [ ] Cada escritura compartida usa versión leída o un bloqueo.
- [ ] Las colas usan `SKIP LOCKED`, lease, límite de intentos e idempotencia.
- [ ] El tamaño de cola, el envejecimiento y los timeouts vienen de configuración.
- [ ] El cierre del padre lo hace el último hijo, con bloqueo.
- [ ] Los eventos traen número de secuencia.
- [ ] Los datos entre pasos se pasan por copia profunda.
- [ ] Los bloqueos se toman en orden fijo y los reintentos usan jitter.
- [ ] Todo estado abierto tiene `EXCEPTION`/`finally` que lo cierra.
- [ ] Ninguna función con efectos se usa como filtro en un `WHERE`.
- [ ] El PR trae la prueba que provoca el problema y muestra la protección.
- [ ] Se leyó el esquema real antes de consultar o escribir (B1).
- [ ] La migración va sola, con nombre clasificado y por el Train (B2, B3).
- [ ] Los controles de procedencia y de calidad están separados (B6).
- [ ] Cada control nuevo trae una prueba negativa (B11).
- [ ] Se escribe por la puerta única, no directo a la tabla (B12).
- [ ] Ningún umbral queda escrito en el código: se lee de `lf_global_config` (B13).
- [ ] No se copia una relación que se puede derivar (B14).
- [ ] Una regla VIGENTE no queda citando una CANDIDATO (B15).
- [ ] El criterio nuevo se probó con reglas de pantalla, de backend y transversales (B17).
- [ ] Toda restricción nueva tiene un origen aprobado (B19).
- [ ] El bloque se cierra con su registro en la EKB (B21).
- [ ] Cada prueba negativa verifica el control específico y sobrevive a su mutación (B25).
- [ ] La forma de toda estructura se valida antes que su contenido (B26).
- [ ] Un solo reloj por operación (B27).
- [ ] Los mutantes cuentan solo si mueren por la aserción esperada (B28).
- [ ] Una función con llamadores se cambia con prueba de equivalencia y verificación antes/después (B29).
- [ ] Lo que se registra no entra en efecto sin pasar por la promoción (B30).
- [ ] La espera del Train se hace por el propio PR (B31).
- [ ] El motor compartido no tiene valores ni datos de una instancia; la paridad está probada (B32).
- [ ] Toda migración, DDL o DML de migración va por PR → Merge Train con `ready-to-merge`; un rechazo de permisos no se elude (B33).
- [ ] Primero se demuestra funcionamiento E2E, después calidad y finalmente seguridad proporcional, respetando controles vigentes (B34).
- [ ] Se consulta la EKB antes del lote y se registran los hallazgos laterales para atención posterior, salvo urgencia (B35).

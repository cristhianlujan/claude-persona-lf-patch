# PR #93 · LOTE-E · Guardas CA-N56 a CA-N73

## Alcance

Este lote corrige la migración `180530` antes de cualquier despliegue. No autoriza
conexión a Supabase, ejecución SQL, instalación de claves, despliegue Edge, merge ni
regeneración de baseline.

## CA-N49 · grants bajo el owner correcto

La migración obtiene temporalmente las membresías de:

- `lf_writer_verifier_v7`;
- `lf_governance_owner_v3`.

Las dos membresías se obtienen antes de cualquier `ALTER TABLE`, `CREATE TRIGGER` o
concesión de funciones. `fn_writer_preimage_scope_v7(text)` concede `EXECUTE` a
`postgres` bajo `lf_writer_verifier_v7`; los helpers de canonicalización, framing y
preimage lo hacen bajo `lf_governance_owner_v3`. Ambas membresías se revocan antes
del `COMMIT`.

## CA-N50 · DDL del trigger

La función del trigger se crea bajo `lf_governance_owner_v3`, pero el `DROP TRIGGER`,
`CREATE TRIGGER` y `ENABLE ALWAYS` se ejecutan nuevamente en el contexto del ejecutor
de la migración, siguiendo el patrón de `180315`.

El preflight confirma que el ejecutor puede administrar la tabla
`private.lf_gate_test_runs_v3`.

## CA-N51 · corte explícito

V7 continúa sin desplegarse, por lo que el estado esperado es cero gates V7 previos.

La migración no invalida filas silenciosamente. Si encuentra un gate V7 anterior sin
`writer_nonce_sha256`, aborta con SQLSTATE `55000` y exige un backfill explícito antes
de continuar. Una reaplicación después de insertar gates con el contrato nuevo sigue
siendo válida.

## CA-N52 · alineación fila-evento

El nonce ya no se añade dentro de `persisted_effects`.

Se agrega la columna privada:

`private.lf_gate_test_runs_v3.writer_nonce_sha256`

El trigger `trg_05_bind_gate_writer_nonce_v7` se ejecuta `BEFORE INSERT OR UPDATE` y
`ENABLE ALWAYS`. Para filas V7:

- obtiene el nonce desde el evento de evidencia creado por el writer;
- exige el mismo `signed_preimage_sha256`;
- exige igualdad completa de `persisted_effects`;
- exige igualdad de `persisted_effects_sha256`;
- recalcula el digest de la fila para comprobarlo;
- persiste el nonce únicamente en la columna privada;
- bloquea cambios posteriores de evento, efectos, hash o nonce.

El evento y la fila conservan exactamente los mismos `persisted_effects` firmados.

## CA-N53 y CA-N54 · preflight y readback

El preflight incluye `fn_frame_component_v7(text)`.

El readback comprueba:

- owners de binder, validador e invariante;
- owner de la tabla;
- columna y constraint del nonce;
- seis grants de helpers para `postgres`;
- denegación de roles API;
- trigger `BEFORE INSERT OR UPDATE` y `ENABLE ALWAYS`;
- uso de la columna privada por el validador;
- alineación fila-evento;
- membresías y privilegios `CREATE` residuales.

## CA-N55 · batería concluyente

`PR93_WRITER_V7_ADVERSARIAL_TESTS.sql` añade:

- bytes sobrantes después de tres frames válidos;
- `RESET ROLE` garantizado ante cualquier SQLSTATE;
- verificación del `key_id` registrado por clave `RETIRING` y `ACTIVE`;
- ventana de rotación exacta de diez minutos;
- rechazo de retiro antes del fin del overlap;
- rechazo de una tercera promoción mientras existe una clave `RETIRING`;
- prueba conductual de exclusión de claves `RETIRING` expiradas (bloque
  `$expired_retiring_key$`, conservada);
- igualdad de nonce, `persisted_effects` y `persisted_effects_sha256` entre fila y evento.

La batería termina con `ROLLBACK`.

## CA-N56 · downgrade de autenticación

El binder bloquea cualquier `UPDATE` que intente cambiar una fila V7 hacia otro modo
de autenticación. La batería ejecuta el downgrade y exige SQLSTATE `55000`, conservando
la fila como `GITHUB_OIDC_HMAC_NONCE_V7`.

## CA-N57 · readback normalizado

Las inspecciones de literal exacto sobre `pg_get_functiondef` eliminan whitespace con
`regexp_replace(...,'\s','','g')`. La comprobación negativa cubre tanto
`persisted_effects` como `persisted_effects_sha256`, y el readback verifica además el
guard de downgrade. La detección de mutación del binder usa una normalización distinta
descrita en CA-N62.

## CA-N58 · control positivo del framing manual

El vector manual de tres frames debe ser aceptado antes de añadir el byte sobrante.
Así, el rechazo del vector con sufijo queda atribuido a bytes residuales y no a un
preimage base inválido.

## CA-N59 · dependencias completas

El preflight valida `extensions.digest(bytea,text)` y todas las funciones externas
referenciadas por el invariante de separación. El binder, creado por esta misma
migración, se comprueba inmediatamente después de su instalación.

## CA-N60 · privilegio temporal del trigger

PostgreSQL exige `EXECUTE` sobre la trigger function al crear el trigger. La migración
concede ese privilegio a `postgres` únicamente durante `CREATE TRIGGER` y lo revoca
después de `ENABLE ALWAYS`. El readback exige que no quede ACL residual.

## CA-N61 · `proacl IS NULL` no es ACL vacío

`proacl IS NULL` significa ACL por defecto, no ausencia de privilegios: para funciones
implica `EXECUTE` a `PUBLIC`. La versión anterior aplicaba
`coalesce(p.proacl,'{}'::aclitem[])` y por tanto devolvía `true` en ese estado.

`temporary_creator_acl_removed` ahora exige ACL explícito:

| Estado de `proacl` | Resultado |
|---|---|
| `NULL` | `false` |
| explícito con entrada `postgres` / `EXECUTE` | `false` |
| explícito sin entrada `postgres` / `EXECUTE` | `true` |

La comprobación no usa `has_function_privilege('postgres',...)`, porque un superusuario
responde `true` aunque no exista ninguna concesión explícita. Si la fila de `pg_proc`
no aparece, `coalesce(...,false)` fuerza fallo.

## CA-N62 · detección de mutación del binder

`binder_preserves_persisted_effects` combina tres controles fail-closed:

1. el SHA-256 exacto de `pg_proc.prosrc` debe coincidir con el cuerpo versionado por
   la migración `180530`;
2. la inspección textual no debe detectar una mutación de los efectos firmados;
3. todos los vectores autocontenidos deben producir el resultado esperado.

El pin del cuerpo esperado es:

`3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293`

Cualquier cambio del cuerpo del binder, incluso mediante una sintaxis no contemplada
por los patrones, hace que el readback falle hasta que el nuevo cuerpo sea auditado y
el digest esperado se actualice expresamente.

La normalización común elimina comentarios `-- ...` y `/* ... */`, colapsa whitespace
y convierte el texto a minúsculas. Se aplica exactamente igual al binder real y a
todos los vectores.

Se declara mutación textual cuando se detecta cualquiera de estas familias:

- asignación directa a `NEW.persisted_effects` o
  `NEW.persisted_effects_sha256` mediante `:=` o `=`;
- asignación directa al registro completo `NEW`;
- targets `NEW` o `NEW.campo` en `SELECT ... INTO`;
- targets equivalentes en `EXECUTE ... INTO`;
- targets equivalentes en cláusulas `RETURNING ... INTO`;
- targets equivalentes en `FETCH ... INTO`.

La lista autocontenida contiene 23 casos positivos y negativos. Incluye comentarios,
mayúsculas, saltos de línea, punto espaciado, targets posteriores, lecturas, casts,
comparaciones, JSON, `INSERT INTO`, `EXECUTE` sin target y DML cuyo `RETURNING` escribe
en otra variable.

El readback publica:

- `definition_checks.binder_definition_digest.expected`;
- `definition_checks.binder_definition_digest.actual`;
- `definition_checks.binder_definition_digest.matches`;
- `definition_checks.binder_mutation_pattern_controls.all_pass`;
- por cada vector: `expected`, `detected` y `pass`.

## CA-N63 · separación entre prueba conductual e inspección de definición

El bloque runtime `$rotation_overlap$` ya no inspecciona el texto
`retiring_until > clock_timestamp()`. Una prueba de ejecución no debe depender de la
redacción de la definición.

La cobertura conductual permanece intacta en `$expired_retiring_key$`, que instala una
clave `RETIRING` vencida y exige que el verificador la rechace.

La inspección estática se conserva, movida al readback estructural como
`definition_checks.verifier_definition_excludes_expired_retiring_keys_definition_only`,
cuyo nombre declara que es una comprobación de definición y no una prueba de runtime.

## CA-N64 · comentarios antes de la asignación

La definición y los vectores pasan por la misma eliminación de comentarios antes de
colapsar whitespace. Por ello, una asignación precedida por `-- ...` o `/* ... */`
conserva la frontera de sentencia y se detecta.

Además, el pin exacto de `pg_proc.prosrc` impide que una variante de comentario no
reconocida por el normalizador pueda producir un PASS: cualquier modificación del
cuerpo cambia el digest y falla cerrado.

## CA-N65 · `EXECUTE ... INTO`

El patrón de asignación por `INTO` acepta como origen `SELECT`, `EXECUTE`, `RETURNING`
o `FETCH`. Los vectores incluyen `EXECUTE ... INTO NEW.campo` como primer target y
como target posterior, con terminación antes de `USING`.

## CA-N66 · `RETURNING ... INTO`

Las cláusulas DML `RETURNING ... INTO` se inspeccionan con la misma lista de targets.
Los vectores incluyen primer target y target posterior para los dos campos firmados.

## CA-N67 · normalización ejercitada por los vectores

`normalized_sources` recibe mediante `UNION ALL` el cuerpo real y los vectores. Una
única expresión elimina comentarios, colapsa whitespace y aplica `lower()`. Los
patrones nunca se ejecutan contra el `source_text` crudo.

## CA-N68 · evidencia direccional por vector

`cases` ya no publica únicamente un booleano de acierto. Para cada vector entrega:

- `expected`;
- `detected`;
- `pass`.

Esto permite distinguir de inmediato un falso positivo de un falso negativo.

## CA-N69 · batería de patrones nuevamente satisfacible

La expresión ARE para sentencias con `INTO` usa el prefijo no voraz
`\m[a-z]*?(?:select|execute|returning|fetch)\M`. Esta forma conserva la captura corta
de la lista de targets hasta `FROM`, `USING` o `;`, evitando que el texto terminador
forme parte del target. Los vectores heredados de `SELECT ... INTO`,
`EXECUTE ... INTO` y `SELECT ... INTO NEW` vuelven a producir el resultado esperado.

La condición `binder_preserves_persisted_effects` sigue exigiendo simultáneamente:

1. digest exacto del cuerpo;
2. ausencia de mutación detectada en el binder real;
3. `all_pass=true` para todos los vectores.

## CA-N70 · enlace del trigger a la función fijada

`gate_trigger.binds_pinned_function` exige que `pg_trigger.tgfoid` sea exactamente
`private.fn_bind_gate_writer_nonce_v7()`. Un trigger homónimo que invoque otra función
ya no puede satisfacer el readback aunque el binder fijado conserve su digest.

## CA-N71 · límite conocido del normalizador de comentarios

La eliminación de comentarios es una defensa textual en profundidad y no es un lexer
PL/pgSQL completo: secuencias `--` o `/*` dentro de literales pueden alterar la vista
normalizada. Esta limitación no puede producir PASS sobre un cuerpo modificado porque
el digest exacto se calcula sobre `pg_proc.prosrc` crudo antes de cualquier
normalización. Un cambio legítimo del binder exige auditoría y actualización expresa
del digest esperado.

## CA-N72 · identificadores entrecomillados

Los patrones de asignación directa y de targets `INTO` aceptan tanto
`NEW.persisted_effects` como `NEW."persisted_effects"`, incluyendo la variante
`persisted_effects_sha256`. Dos vectores adicionales verifican ambas familias.

## CA-N73 · documentación sincronizada

Este documento incorpora CA-N64 a CA-N73, el pin exacto del binder, la regla de
rotación del digest, la comprobación del enlace del trigger y las limitaciones
conocidas de la capa textual.

## Evidencia pendiente

Todo permanece únicamente versionado. Siguen pendientes:

1. auditoría estática independiente del nuevo head;
2. aplicación de migraciones en un entorno Supabase aislado;
3. ejecución completa de baterías y readbacks;
4. test Edge y comparación Edge/PostgreSQL;
5. controles administrativos externos previos al merge.

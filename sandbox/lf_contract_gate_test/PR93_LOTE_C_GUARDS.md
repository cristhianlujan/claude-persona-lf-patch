# PR #93 · LOTE-D · Guardas CA-N49 a CA-N55

## Alcance

Este lote corrige la migración `180530` antes de cualquier despliegue. No autoriza
conexión a Supabase, ejecución SQL, instalación de claves, despliegue Edge, merge ni
regeneración de baseline.

## CA-N49 · grants bajo el owner correcto

La migración obtiene temporalmente las membresías de:

- `lf_writer_verifier_v7`;
- `lf_governance_owner_v3`.

`fn_writer_preimage_scope_v7(text)` concede `EXECUTE` a `postgres` bajo
`lf_writer_verifier_v7`. Los helpers de canonicalización, framing y preimage lo hacen
bajo `lf_governance_owner_v3`. Las dos membresías se revocan antes del `COMMIT`.

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
- comprobación estática de exclusión de claves `RETIRING` expiradas;
- igualdad de nonce, `persisted_effects` y `persisted_effects_sha256` entre fila y evento.

La batería termina con `ROLLBACK`.

## Evidencia pendiente

Todo permanece únicamente versionado. Siguen pendientes:

1. auditoría estática independiente del nuevo head;
2. aplicación de migraciones en un entorno Supabase aislado;
3. ejecución completa de baterías y readbacks;
4. test Edge y comparación Edge/PostgreSQL;
5. controles administrativos externos previos al merge.

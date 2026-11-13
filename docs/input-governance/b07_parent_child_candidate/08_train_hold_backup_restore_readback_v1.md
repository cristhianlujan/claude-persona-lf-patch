# B07 Padre/Hija — HOLD DDL, backup/restauración y readback (corte posterior a #3831)

**Estado: DRAFT / NO-GO PARA MERGE TRAIN.** El dueño pidió confirmación explícita NUEVA antes de cualquier DDL B07 en Supabase temporal. Este documento NO es esa confirmación. NO aplicar SQL, invocar writers V2 ni etiquetar `ready-to-merge` en PR #3818. Producción del motor mantiene bloqueos ajenos a B07.

## Autoridad documental verificada
- #3830 (documento 12 original) y #3831 (enmienda literal B07 padre/hija) integrados por Train **documental**, sin DDL de B07. Readback del documento 12: Git blob `56b6df52de545465a12459351a0cf1b8bba7be8f`, SHA-256 `84e56f4127c1be3f06bf45a5c733befef7e956a969e4c2577cfe1d6246889a7a`; preimagen SHA-256 `7a2ef3f621462dd9f79df9d6c36d2ae913b7661f2bae518230c39228dd3cdb40`.
- #3821 confirma decisión documental `DEC-B07-PADRE-HIJA-001` sin firma humana autenticada: `identity_verified=false`.
- #3832 es PR DRAFT **preparatorio** de operación y owner SALY, no alta efectiva. No se autoriza registrar SALY por INSERT directo ni reutilizar placeholder LF como credencial SALY.

## Preimagen observada en Supabase temporal por SELECT durante este lote
- `lf_ops.reglas` = 578; `estado=CANDIDATO` = 166, `VIGENTE` = 412.
- `saly.reglas` = 14; `estado=VALIDADO` = 14.
- `to_regclass('lf_ops.reglas_versiones_b07')` y `to_regclass('saly.reglas_versiones_b07')` = NULL.
- Son valores del instante de lectura, NO garantías para la futura aplicación. Repetir inmediatamente antes del Train; si difieren, revisar delta y bloquear hasta resolverlo.

## Gate de autorización ANTES de etiqueta ready-to-merge
1. Dueño confirma explícitamente este DDL B07 específico y la base temporal, con alcance, riesgos de nueva historia y backup; registrar recibo en ruta oficial. Sin confirmación, `HOLD_B07_OWNER_DDL_CONFIRMATION_MISSING` (**código propuesto del checklist, no emitido por backend**).
2. Alta gobernada SALY efectiva (operación `ACTUALIZACION_REGLA_SALY` y owner SALY con procedencia), más binding Router/perfil y pruebas negativas, por PR/Train **separado**. Sin ello `B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED` / `B07_SALY_OWNER_REGISTRY_MISSING` siguen abiertos.
3. Validar la **migración NUEVA y atómica empaquetada** `supabase/migrations/20261113180000_lf_ig_b07_parent_child_atomic_v1.sql` para padre/hija + backfill baseline + triggers/ACL/RLS + integración LF V2 + finalizador SALY; DOWN fail-closed conserva historia, sin editar migraciones ya desplegadas. Archivo CANDIDATO, NO recibido en base viva. Falta alta SALY gobernada, tests del archivo integrado, backup/restauración pre/post y OK explícito DDL del dueño.
4. 3 CI R17/PASE/clasificación PASS en el **HEAD exacto** posterior al último rebase; evidencia de versiones PG17.6/18.7 y hash de todos los archivos; Merge Gate debe pasar antes del Train.

## Backup preaplicación — solo procedimiento, NO ejecutado
1. Tomar snapshot/restauración de TODA la base del entorno de destino por operador autorizado; anotar ID de backup, hora UTC, retention, WAL/PITR o equivalente, checksum, permisos y custodio. No copiar claves al repositorio.
2. Guardar SELECT de `pg_catalog`, migraciones y definición `pg_get_functiondef` del escritor LF V2, SHA-256 de cada padre LF/SALY y totales por estado, y conteo de RUN existentes. Preimagen con recibo oficial y `execution_id` del Train.
3. Restaurar ANTES del despliegue una copia aislada para certificar recuperabilidad del backup; comparar esquema, conteos y hashes. Si falta evidencia de restauración: STOP.

## Aplicación oficial futura, SI Y SOLO SI se autoriza
- Ingresar como PR gobernado a Merge Train OIDC. Una transacción: crear historias, baseline `BASELINE_CURRENT_ONLY` (sin falsificar versiones antiguas), controles padre = última hija en COMMIT, hash encadenado, ACL/RLS, LF V2 + SALY. No dejar ventana de escrituras del padre sin historia hija. No usar escritores desde este chat.
- No modificar RUN históricos ni promover CANDIDATO. No mapear SALY VALIDADO a LF VIGENTE; conservar `vigente`, `decision_id` y toda la imagen original.

## Readback SELECT postaplicación (pendiente y NO acreditado)
```sql
SELECT estado,count(*) FROM lf_ops.reglas GROUP BY estado ORDER BY estado;
SELECT estado,count(*) FROM saly.reglas GROUP BY estado ORDER BY estado;
SELECT to_regclass('lf_ops.reglas_versiones_b07'),to_regclass('saly.reglas_versiones_b07');
SELECT count(*) FROM lf_ops.reglas_versiones_b07;
SELECT count(*) FROM saly.reglas_versiones_b07;
SELECT count(*) FROM lf_ops.reglas p WHERE to_jsonb(p) IS DISTINCT FROM
 (SELECT h.snapshot FROM lf_ops.reglas_versiones_b07 h WHERE h.rule_id=p.id ORDER BY h.version_no DESC LIMIT 1);
SELECT count(*) FROM saly.reglas p WHERE to_jsonb(p) IS DISTINCT FROM
 (SELECT h.snapshot FROM saly.reglas_versiones_b07 h WHERE h.rule_id=p.id ORDER BY h.version_no DESC LIMIT 1);
SELECT pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure);
SELECT has_function_privilege('service_role','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');
SELECT has_function_privilege('authenticated','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');
```
- Exigir cero divergencias padre/hija; 578 y 14 baselines **solo si** la nueva preimagen coincide con los conteos documentados; versión 1 inicial por regla, hash SHA-256 de `snapshot`, `previous_sha256` y chain, índices, RLS/ACL, replay idempotente, prueba de rechazo de DML directo/autor no elegible/hash obsoleto. Audit Trail y recibo del Train.
- Tomar backup **después de COMMIT confirmado** con historial, restaurarlo en otra PostgreSQL, comparar bit a bit datos padre/hija, SHA, metadatos de funciones y permisos y recibos. Verificar que DOWN no destruye historia. Si hay falla: marcar NO-GO y ejecutar restauración aprobada, nunca borrar historial a ciegas.

## Cierre
B07 **ABIERTO** hasta recibo de decisión DDL, op+owner SALY, archivo migración oficial, backup restaurable, 3 CI, Train exitoso, SELECT post real, restauración posdatos y firma de cierre de gobernanza. No atribuir PASS a acciones futuras.

## Lote complementario — respaldo verificable y restauración (plan, NO ejecutado)
1. **Identidad del paquete:** fijar `main_sha`, `pr_head_sha`, SHA-256 de la migración versionada real (el Train puede reasignar timestamp), clasificación, `execution_id` y `train_run_id`. Dos firmas/controles distintos: autorización específica del dueño para DDL y ejecución OIDC del Train; ninguno se infiere de #3821.
2. **Captura consistente antes de Train:** en lectura transaccional/snapshot, registrar (a) conteos de `lf_ops.reglas` por `estado`; (b) conteos de `saly.reglas` por `estado`; (c) SHA-256 determinista sobre `jsonb_agg(to_jsonb(r) ORDER BY r.id)` en ambas tablas; (d) `COUNT(*)` y digest verificable de los RUN existentes; (e) definiciones de funciones y triggers `pg_get_functiondef` y ACL/RLS previos; (f) estado actual de migraciones, operación y owner SALY. No persistir datos personales, claves o credenciales dentro del PR.
3. **Backup físico/lógico gobernado:** operador con permisos de backup del Supabase temporal obtiene backup completo con roles, esquemas, datos, secuencias y metadatos de políticas; almacena `backup_id`, timestamp UTC, caducidad, checksum y ubicación custodiada fuera del repositorio. Si el backup administrado no incluye roles/grants/WAL, aportar copia complementaria y declarar limitaciones; no asumir que una exportación CSV basta.
4. **Ensayo previo de recuperación:** restaurar ese backup en **instancia aislada**, sin tráfico ni conexión a producción; demostrar mismo conteo, SHA de padres, objetos, extensiones, roles/grants y RUN históricos. Registrar `restore_id`, código/resultado y SHA de verificación. La falta de esta evidencia bloquea la etiqueta del Train.
5. **Aplicación futura, si se autoriza:** conferir preimagen, que SALY operación+owner+perfil existen con procedencia oficial, que no hay otro Train activo, CI 3/3 y PG17.6/18.7 en HEAD exacto; proceder **solo** por `ready-to-merge` a Train. El SQL oficial exige una sola transacción y `B07_SALY_OFFICIAL_OPERATION_NOT_REGISTERED` / `B07_SALY_OWNER_AND_PROFILE_GOVERNED_REQUIRED` ante datos faltantes. Ningún bypass.
6. **Readback posterior al COMMIT:** comparar hashes de los 578/14 padres (o conteos de preimagen nuevamente observados) contra snapshot previo; exigir mismo estado, cantidad y datos. Hija: exactamente una `BASELINE_CURRENT_ONLY` por cada regla previamente existente, `version_no=1`, `previous_sha256 IS NULL`, `snapshot_sha256=SHA256(snapshot::text)`, latest=padre, sin salidas huérfanas; conteos y hash de RUN existentes idénticos. Comprobar ACL/RLS, writer LF V2, writer SALY, historial inmutable y prueba de rechazo de escrituras directas.
7. **Restauración con datos pos-commit:** generar backup posterior, restaurarlo en una **segunda** instancia aislada y comparar bajo el mismo snapshot los SHA de padres, historial completo (orden estable por `rule_id,version_no`), `previous_sha256`, recibos, permisos, índices y funciones; registrar comando/recibo y digest exactos. Nunca afirmar restauración real con un test de fixtures sintéticos.
8. **Condiciones STOP:** cualquier drift de preimagen, RUN alterado, ausencia de SALY/owner/autoridad, fallo CI, backup no restaurable, mismatch de padre-hija, discrepancia de historia o ACL => no cierre; activar exclusivamente restauración autorizada con datos y auditoría, no ejecutar DOWN destructivo. Publicar código exacto del fallo y recibos faltantes.

**Campos de recibo (VACÍOS hasta ejecución real):** `owner_ddl_approval_ref=[PENDIENTE]`; `op_saly_train_ref=[PENDIENTE]`; `backup_pre_id=[PENDIENTE]`; `backup_pre_sha256=[PENDIENTE]`; `restore_pre_id=[PENDIENTE]`; `b07_train_execution_id=[PENDIENTE]`; `post_readback_ref=[PENDIENTE]`; `backup_post_id=[PENDIENTE]`; `restore_post_id=[PENDIENTE]`; `terminal_receipt=[PENDIENTE]`.

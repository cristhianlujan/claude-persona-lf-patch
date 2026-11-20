# LF — Retención de registros durante 10 años (DRAFT, NO-GO operativo)

## Autoridad y límites
- Dueño, decisión literal por chat 17/11/2026 08:17 Lima: «Estandariza todo a 10 anios».
- Encargo IG 08:48: **PR DRAFT + SELECT**, sin aplicar SQL, sin merge ni promoción, sin tocar #4040/#4044/#4061/#4062/#4063/#4064; sin modificar reglas VIGENTE ni TIMEOUT-001/RATE-001/AUTH-047/049.
- No sustituye autorizaciones gobernadas de ACT-0001 / LF Migration Merge Train ni habilita nuevos EXECUTE.
- **El alcance de 10 años es REGISTRO LF**, no las credenciales ni materiales efímeros. No extender sobre esquemas Supabase administrados ni SALY/Overall sin una decisión de alcance.
- 3650 días es **el valor inicial del dueño**, distinto de diez aniversarios civiles: con años bisiestos puede diferir. Confirmar tratamiento regulatorio antes de activar.

## SELECT — origen e impacto
- `programacion.credential_custody`: 2 filas, **2/2 purged_at no nulo y secret vacío (0 bytes)**; 0 textos secretos no vacíos. Solo se hicieron agregados; ningún valor `secret` salió del servidor.
- Columna `secret text NOT NULL` **permite** contenido en claro técnicamente. No se puede demostrar si existió contenido previo ni identificar su formato histórico; no hay evidencia de secreto en claro **actual**.
- Owner tabla `postgres`, ACL de tabla solo postgres, RLS=ON, FORCE=OFF, 0 políticas RLS; `anon`, `authenticated`, `service_role`, PUBLIC: sin SELECT; 0 triggers de negocio, 0 dependientes de funciones indexados por `pg_depend`/búsqueda de `pg_proc.prosrc`. **Uso activo y razón histórica exacta sin acreditar.** Inferencia: estructura de custodia histórica por rol, con señal de purga; no afirmar que sea un almacén actual ni que su borrado sea seguro.
- Purga propuesta, NO ejecutada: prohibir nueva escritura de secreto reversible; verificar lectores no detectables por dependencias (Edge/scripts y accesos externos), probar rotación/revocación en vault y remover/restringir la columna `secret` mediante operación autorizada con backup, reversible cuando corresponda. Los valores actuales ya están vacíos; **no ejecutar UPDATE/DELETE**.
- `lf_proto.proto_onboarding.otp_code`: columna literal de OTP, **0 filas**. `auth.mfa_challenges.otp_code`: columna literal, **0 filas**, esquema administrado. Brecha estructural; no afirmar códigos actuales guardados. No conservar códigos OTP ni contraseñas crudas: el proveedor OTP debe mantener desafío/estado sin almacenar el código en tablas LF; un verificador unidireccional de contraseña no equivale a contraseña en claro, queda bajo la política de identidad del proveedor. Retirar columnas tras revisión aprobada, no en este PR.
- `REG_AUD_003` **VIGENTE** contiene 730 días (completadas) y 90 días (abandonadas/bloqueadas/expiradas). `LEGAL-RECLAMOS-04` **CANDIDATO** contiene 2 años. No modificar estas filas. Su **lectura operativa** debe migrar a `private.fn_lf_ig_record_retention_for_rule_v1`, que resuelve `LF_RECORD_RETENTION_DAYS` en BD **sin fallback a los literales históricos**. Hasta vincular y probar consumidores, estos dos flujos **NO ESTÁN ESTANDARIZADOS**.
- `private.fn_operational_retention_snapshot_v1` y `private.fn_operational_retention_v1` conservan 30 días para cron, monitor, outbox PG_NOTIFY y cola procesada; `fn_lf_p0_evidence_retention_guard_v1` usa lifecycle 1/14 días. Son **TEMPORAL_OPERATIVO**, no sustituir por 3650 días ni tocar sin análisis del lifecycle.
- `private.lf_ig_parameters_v1` no existía al SELECT. `private.lf_reusable_policy_registry_v1` es catálogo de reglas de política, no de valores; `public.lf_policy_versions` no cumple el contrato completo de versión/edición/aprobación por parámetro.

## Catálogo central (migración candidata)
- **ÚNICO parámetro de retención de REGISTRO**: `LF_RECORD_RETENTION_DAYS`, inicial **3650** `DAYS`, editable solamente mediante nueva versión y operación con evidencia verificable.
- Parámetro auxiliar del mismo catálogo, **no duplica los diez años**: `LF_RETENTION_HOT_MONTHS`, inicial **12** `MONTHS`, editable gobernadamente.
- `private.lf_ig_parameters_v1` propone `parameter_code`, `parameter_version`, `value_integer`, `value_unit`, `lifecycle_status`, `effective_from`, `source_decision_literal`, `proposed_by`, `owner_approval_ref`, `approved_by_role`, `approved_at`, `authorized_execution_id`, `change_reason`, `correlation_id`, `recorded_at`.
- Filas iniciales en **CANDIDATO** (no ACTIVE); no atribuir recibo firmado de autorización a un texto de chat. `APPEND_ONLY`: UPDATE/DELETE bloqueados; una futura versión reemplaza lógicamente la anterior por `effective_from`, sin alterar historia.
- RLS FORCED y sin permisos para `anon`, `authenticated`, `service_role` ni PUBLIC. Lectura solo por resolver gobernado; **no se conceden EXECUTE nuevos**.
- `lf_ops.auditoria_eventos` registra inserción del candidato con `parameter_code`, versión, unidad, valor, `correlation_id`, fuente del chat como literal, `owner_approval_verified=false`. La activación de versiones está **bloqueada** hasta implementar validador de operación oficial y autorización del dueño por chat; no hay pantalla de mantenimiento ni escritor de ACTIVE.
- No insertar valores de 3650/12 en reglas o código. Los números solo aparecen en la **semilla de datos de la tabla de parámetros** y en pruebas/esta descripción, nunca como fallback de runtime.
- Riesgo: reglas existentes conservan literales por restricción del dueño. El runtime solo se considerará unificado tras demostrar que los consumidores leen el parámetro; **0 reglas reescritas y 0 consumidores migrados en este PR**.

## Cobertura tabla por tabla
- Inventario `docs/ig/retention_10y_table_inventory_v1.csv`: **576 tablas base, 21 esquemas** por SELECT de `information_schema`. Una clase provisional por tabla: `REGISTRO`, `SECRETO`, `TEMPORAL_OPERATIVO`. Solo nombres de tabla/columna y marcadores, no datos, contraseñas ni tokens.
- Clasificación **heurística, propuesta**, no verificación semántica del contenido de cada tabla. La columna `review_flag` exige readback del dominio, sobre todo tablas mixtas con columnas sensibles. **Ninguna clase autoriza borrado.**
- `LF_CANDIDATE_SCOPE` significa revisión dentro del producto LF, no aceptación global; `PLATFORM_MANAGED_REVIEW` no permite cambios a `auth`, `storage`, `cron`, `vault`; `OTHER_PRODUCT_OUT_OF_SCOPE` resguarda SALY/Overall; `SHARED_OR_BENCHMARK_REVIEW` requiere delimitar propietario.
- Un registro con campo de clave/OTP se marca riesgo de **columna mixta**: conservar datos de negocio/auditoría no justifica retener el secreto. Revisar a nivel de columna y operación antes de asignar retención.
- `REGISTRO`: historial, decisiones, auditorías, eventos confirmados, evidencias, reclamos y configuración; conservar **3650 días** desde fecha contractual por tabla previa validación legal y finalidad. Si no existe timestamp confiable, **bloquear mover/purgar**, no inferir.
- `SECRETO`: claves HMAC, tokens/credenciales reversibles, challenges de autenticación y material de firma; **no conservar histórico del secreto**; solo metadatos redacted como `REGISTRO`, rotación/revocación y purga gobernada por ciclo de vida. No destruir clave activa antes de sustituirla; no almacenamiento de OTP/password.
- `TEMPORAL_OPERATIVO`: colas, tickets, transferencias de chunks, lotes efímeros y trabajos; usar TTL/estado de consumo **específico y parametrizable**, no 3650. Mantener recibo de ejecución/auditoría separado como REGISTRO cuando corresponda.

## Traslado a histórico (PROPUESTA, sin implementador)
1. Hot: desde creación hasta **12 meses**, tomados de `LF_RETENTION_HOT_MONTHS`. Parentesco por claves y sello de tiempo explícito por tabla, pendiente de aprobación; proteger casos abiertos / legal hold.
2. Histórico: desde >hot hasta el vencimiento del plazo **3650 días** del registro, en particiones temporales de **solo lectura** y controles de acceso; no trasladar secretos ni materiales OTP.
3. Crear **copia primero** con manifest por lote: tabla/partición, rango, fuente/HEAD/schema SHA, total de filas y checksum criptográfico de registros ordenados por clave estable. Comparar **conteo y checksum** en fuente y destino, hashes y FK antes de retirar hot; si falla algo: **no borrar ni cerrar**.
4. Registrar atestación independiente de copia y readback, aprobación de integridad y estado inmutable de la partición. La verificación no acredita automáticamente cierre ni autorización destructiva.
5. Al expirar, **borrado o anonimización solo previa aprobación explícita del dueño POR CHAT**, con recibo asociado, lote, alcance, filas/bytes estimados y evidencia retenida; sin aprobación: mantener bloqueado, documentar conflicto de minimización/legal.
6. No confundir expiración de retención de registro con limpieza técnica de SECRETO o TEMPORAL_OPERATIVO; esas políticas requieren configuración específica, controles de seguridad y revisión separada. Tampoco convertir automáticamente backups, objetos externos o réplicas en histórico verificado.
7. Evitar asumir que la tabla es particionable: verificar índices, FK, triggers, políticas RLS, dependencias, volumen, PII y coste antes de elegir estrategia. No ejecutar `DETACH`/`DROP` ni alterar particiones en este PR.

## Verificaciones y límites
- SELECT acredita el catálogo y los hechos actuales; `test_lf_ig_retention_10y_candidate_v1.py` comprueba solo texto/contratos.
- `sandbox/lf_contract_gate_test/input_governance/retention_10y_candidate_rollback_v1.sql` requiere PostgreSQL de pruebas con schema LF equivalente. La prueba ejecutable debe **eliminar BEGIN/COMMIT internos de la migración al componer un único BEGIN/ROLLBACK**, o usar driver de migración transaccional; no correr la inclusión directa con un COMMIT interno.
- PG rollback, pruebas de reglas consumidoras, autorización ACTIVE, particiones, 576 contenidos/columnas y ruta destructiva: **NO EJECUTADOS**. Cualquier CI PASE verde no reemplaza esos ensayos.
- Estado: **DRAFT / NO-GO funcional**, sin escritura en Supabase, sin merge, sin promociones ni nuevos EXECUTE.

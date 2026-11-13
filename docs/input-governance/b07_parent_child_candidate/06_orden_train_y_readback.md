# B07 PADRE/HIJA — secuencia Train y readback esperado

**NO EJECUTABLE EN PRODUCCIÓN.** Propuesta para aprobación por ruta EKB. Decisión documental del dueño confirmada en conversación 2026-11-13 08:31 Lima; `identity_verified=false`; recibo autenticado por registrador no acreditado.

## Orden permitido — una sola ventana gobernada, sin brecha entre escritor y triggers
1. **Cambio normativo primero:** aplicar por ruta oficial únicamente la enmienda B07 del archivo `05_enmienda_literal_para_documento_12.md` sobre `12_criterios_cierre_motor_7.md`, con preimagen, hash, autoría documental y readback; **no** cambiar B04 ni B12. Si el documento 12 continúa exigiendo literalmente 9 columnas, **NO-GO**.
2. **Gate de preparación:** 3 CI PASS en HEAD exacto y revisión de consumidores, ACL, funciones V2 y escritor oficial SALY. **BLOQUEO actual: NO existe escritor SALY nativo conectado; no autorizar promoción de este diseño como ciclo completo**. La `service_role` no recibe escritura directa de historia.
3. **Backup previo:** captura restaurable de la base a la que se migraría, SHA del esquema y filas `lf_ops.reglas`/`saly.reglas`, ledger migraciones, WAL/PITR y prueba de restauración fuera de producción. No tocar RUN históricos. Debe existir plan de custodia de historia después del despliegue; DOWN nunca hace DROP de datos históricos sin resguardo.
4. **Train oficial único y atómico:** desde Router/PR habilitado → Merge Train OIDC → escritor oficial de migraciones; en una única transacción gobernada: crear ambas hijas + FK/índices/constraints, **backfill 1 imagen por cada padre** y sus hashes, instalar control padre=última hija y vista/ACL/RLS, integrar **V2 LF** y **escritor SALY real** en la misma ventana **sin** intervalo operativo en que el padre pueda mutar sin HIJA. No se reutiliza `supabase/migrations/20261113030000...` desplegada como fuente para reescribirla; se requiere migración NUEVA, versionada, con rollback certificado.
5. **Readback posaplicación SELECT real:** comparar `lf_ops.reglas=578`, `CANDIDATO=166`, `VIGENTE=412`, `saly.reglas=14`, `VALIDADO=14` contra preimagen **ajustando únicamente por escrituras nuevas autorizadas y recibidas**. No presentar valores históricos como actuales sin relectura; ver `to_regclass` de hijas, 578 y 14 versiones baseline de salida, `min/max(version_no)`, hashes fuente/catálogo, `row_number()` por regla y `identity_verified=false`.
6. **Invariantes y seguridad:** `SELECT` de cada padre vs última hija sin diferencias, hash real del JSONB, hash anterior encadenado, FK e índices, RLS activo, `service_role` solo SELECT sobre HIJA, `anon/authenticated` sin acceso, escritor oficial V2 modificado y función auxiliar privada no invocable por service_role; vistas consumen solo LF `estado=VIGENTE` y SALY `estado=VALIDADO AND vigente`.
7. **Pruebas posteriores:** modificación gobernada documental LF → append en la misma transacción, CREATE → v1, CANDIDATO nuevo → promoción controlada, replay sin duplicados, fallos de hash antiguo/evidencia incompleta/autor ausente, SALY por **su propio escritor oficial**, sin mapear VALIDADO→VIGENTE. Verificar no alteración de RUN históricos, baseline B12 y contrato B04.
8. **Restauración posdatos y cierre:** respaldo completo **después** de historia confirmada, restauración en otra base PostgreSQL y comparación SHA padre+hija/objetos/funciones/recibos/consulta final; si DOWN detecta historia, bloquear DROP y usar procedimiento de custodia aprobado. Solo después del readback de Train, registrar recibo y evaluar B07 para cierre. Producción NO-GO hasta resolver otros bloqueos del motor.

## Consultas de readback esperadas (solo SELECT)
```sql
SELECT estado,count(*) FROM lf_ops.reglas GROUP BY estado ORDER BY estado;
SELECT estado,count(*) FROM saly.reglas GROUP BY estado ORDER BY estado;
SELECT to_regclass('lf_ops.reglas_versiones_b07'),to_regclass('saly.reglas_versiones_b07');
SELECT count(*) FROM lf_ops.reglas_versiones_b07;
SELECT count(*) FROM saly.reglas_versiones_b07;
SELECT count(*) FROM lf_ops.reglas r WHERE to_jsonb(r) IS DISTINCT FROM (SELECT h.snapshot FROM lf_ops.reglas_versiones_b07 h WHERE h.rule_id=r.id ORDER BY h.version_no DESC LIMIT 1);
SELECT count(*) FROM saly.reglas r WHERE to_jsonb(r) IS DISTINCT FROM (SELECT h.snapshot FROM saly.reglas_versiones_b07 h WHERE h.rule_id=r.id ORDER BY h.version_no DESC LIMIT 1);
SELECT n.nspname,c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relname IN ('reglas_versiones_b07');
SELECT pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure);
```

**Lectura actual anterior al despliegue (SELECT 2026-11-13T13:58:16.975Z):** 578 LF, 166 CANDIDATO, 412 VIGENTE, 14 SALY VALIDADO, 0 columnas lifecycle_* y ambas HIJAS inexistentes. Es evidencia de **cero despliegue**, no de eficacia en vivo.


## Actualización SALY B07 — orden gobernado posterior al diseño

1. **Enmienda documental:** primero integrar PR #3824 DRAFT sobre rama L28 por el escritor de documentos autorizado; fuente B07 del documento 12 no existe aún en main. Preimagen SHA256 `7a2ef3f621462dd9f79df9d6c36d2ae913b7661f2bae518230c39228dd3cdb40`, postimagen `84e56f4127c1be3f06bf45a5c733befef7e956a969e4c2577cfe1d6246889a7a`. Fuente de decisión #3821 DEC-B07-PADRE-HIJA-001, identity_verified=false.
2. **Dependencia de autoridad SALY (NO existente en vivo):** registrar por ruta EKB la operación `ACTUALIZACION_REGLA_SALY` en `lf_operation_registry` mediante provenance/bootstrap oficial; registrar owner `project_code='SALY'` en `lf_ig_project_owner_v2`. Sin ambos, el escritor candidato queda bloqueado. No reutilizar credencial LF como firma SALY.
3. **Migración oficial nueva:** backup preimagen con hash; Merge Train OIDC; aplicar dentro de una ventana atómica UP de hijas + baseline, RLS/ACL, puente finalizador LF V2 y escritor SALY de `sandbox/lf_contract_gate_test/input_governance_lifecycle/b07_saly_official_writer_candidate_v1.sql` (blob Git `ff6d47c70f42f5fb2ad6f8b132caf278ec16c79d`). No sustituir la migración desplegada. No permitir intervalo con padre mutable sin historia.
4. **Escritor SALY exclusivo:** invocar únicamente `public.lf_ig_saly_rule_finalize_b07_v1(child_execution_id)` con child `ACTUALIZACION_REGLA_SALY COMPLETED` y 7 PASS_CLEAN, parent gobernado con contexto SALY, decisión `lf_ig_owner_decision_v2` para SALY, owner registrado, SHA fuente/patch y referencia válida `saly.decisiones`. Solo cambios documentales título/razón/fuente; conserva `VALIDADO`, `vigente`, `decision_id` y contenidos funcionales. Direct DML/función no autorizada bloqueados. Replay es idempotente.
5. **Readback y restauración:** SELECT pre/post sobre 578 LF (166 CANDIDATO y 412 VIGENTE en preimagen) y 14 SALY VALIDADO, verificar hash padre/hija último, recibos `lf_b07_saly_finalization_receipt_v1`, permisos, operación/owner SALY, y copia restaurada con datos confirmados (hash previo y posterior iguales). DOWN con historia no borra: custodia y restauración oficial antes de revertir.
6. **No ejecutar Train todavía:** R17 global del HEAD `2e938da` falló por fuentes B09 desalineadas ajenas a B07; aunque B07 PG17/18 pasó, se requieren las tres CI PASS sobre el HEAD definitivo, además del readback del PR de enmienda y autorización de ruta oficial.

### SELECT de readback SALY — pendiente de aplicación oficial
```sql
SELECT operation_code,status,created_by_execution_id FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_REGLA_SALY';
SELECT project_code,owner_name,identity_mode,status FROM public.lf_ig_project_owner_v2 WHERE project_code='SALY';
SELECT to_regprocedure('public.lf_ig_saly_rule_finalize_b07_v1(text)');
SELECT has_function_privilege('service_role','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');
SELECT has_function_privilege('authenticated','public.lf_ig_saly_rule_finalize_b07_v1(text)','EXECUTE');
SELECT count(*) FROM public.lf_b07_saly_finalization_receipt_v1;
SELECT count(*) FROM saly.reglas WHERE estado='VALIDADO' AND vigente;
SELECT count(*) FROM saly.reglas r WHERE to_jsonb(r) IS DISTINCT FROM (SELECT h.snapshot FROM saly.reglas_versiones_b07 h WHERE h.rule_id=r.id ORDER BY h.version_no DESC LIMIT 1);
```

**Readback vivo previo al Train:** el registro/owner SALY, el escritor y las hijas no están instalados; ninguna escritura a Supabase se ejecutó en este lote.
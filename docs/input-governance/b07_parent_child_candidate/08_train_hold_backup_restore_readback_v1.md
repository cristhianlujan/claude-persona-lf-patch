# B07 LF — HOLD DDL | Backup restaurable (plan, NO ejecutado)

**PR #3818 DRAFT / SIN ready-to-merge / SIN Train**. Alcance: LF exclusivamente.
Decisión documental del dueño #3821 y #3831: **identity_verified=false**, no equivale a autorización de DDL. SALY queda fuera de este PR. El SQL no toca RUN existentes.

## Preimagen real (SELECT 2026-11-13)
- `lf_ops.reglas`: 578 filas (412 VIGENTE, 166 CANDIDATO).
- Operaciones `ACTUALIZACION_REGLA_LF` y `CREACION_REGLA_LF`: `SANDBOX_ACTIVE` / `OP_CANDIDATE`; ambas con procedencia.
- Owner LF: `TEMP_DOCUMENTARY_ACTIVE`, identidad `UNVERIFIED_CHAT_DECLARATION`, recibo SHA-256 y perfil PERFiL válido.
- `lf_ops.reglas_versiones_b07`: NO EXISTE. Estos números son lectura histórica, repetir antes del Train.

## Procedimiento de backup pre-Train (NO ejecutado)
1. Recibo explícito nuevo del dueño autorizando exactamente DDL LF B07 en Supabase temporal. Guardar `owner_ddl_approval_ref`. Sin esto STOP.
2. Operador autorizado captura backup consistente de base completa (esquemas/roles/grants/secuencias/datos), `backup_pre_id`, UTC, SHA-256, custodio, retención, PITR/WAL si existe. Nunca publicar credenciales ni datos personales.
3. Bajo mismo snapshot SQL registrar lista de migraciones, `pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure)`, hashes deterministas y estados de los 578 padres, estado del catálogo proyecto, cantidad+SHA ordenado de RUN históricos, RLS/ACL previas.
4. Restaurar backup pre-Train en otra instancia PostgreSQL aislada y sin tráfico. Releer roles, extensiones, funciones, tablas, estados, conteos, hashes, RUN; guardar `restore_pre_id` y evidencia. Si restauración falla o está incompleta: STOP.
5. Confirmar HEAD exacto con R17, PASE y clasificación PASS y test PG17.6/18.7; asegurar que main no avanzó y no hay Train concurrente. El Merge Gate se relee; no etiquetar sin OK DDL.
6. Solo tras cumplimiento, migración oficial única por Merge Train OIDC (nunca DML/DDL manual), con etiqueta `ready-to-merge` autorizada específicamente. No se autoriza aquí.
7. Readback post-commit: una versión baseline por padre preexistente, hashes encadenados, latest=padre, 166 candidatas sin promover, ACL/RLS, solo LF, función V2 con append, RUN históricos sin mutación, receipts reales.
8. Backup poscommit y RESTORE en segunda instancia aislada con toda historia; verificar SHA padres/hijas, funciones, índices, permisos y roles, RUN; `backup_post_id` y `restore_post_id`. No confundir restauración sintética de CI con backup vivo.

## SELECT exacto posterior a instalación (PENDIENTE)
```sql
SELECT
 (SELECT count(*) FROM lf_ops.reglas_versiones_b07) AS versiones_lf,
 (SELECT count(*) FROM lf_ops.reglas p WHERE NOT EXISTS (
   SELECT 1 FROM lf_ops.reglas_versiones_b07 h
   WHERE h.rule_id=p.id
     AND h.version_no=(SELECT max(z.version_no)
                       FROM lf_ops.reglas_versiones_b07 z WHERE z.rule_id=p.id)
     AND h.snapshot=to_jsonb(p)
     AND h.snapshot_sha256=encode(extensions.digest(convert_to(h.snapshot::text,'UTF8'),'sha256'),'hex')
 )) AS divergencias;
```
Exigir `divergencias=0`; `versiones_lf>=578` solo si preimagen futura confirma 578 padres. Añadir consultas ACL/RLS, owner, operaciones, histórico RUN y recibos.

**Recibos pendientes:** `owner_ddl_approval_ref`, `backup_pre_id`, `restore_pre_id`, `b07_train_execution_id`, `post_readback_ref`, `backup_post_id`, `restore_post_id`, `terminal_receipt`. Sin recibos, B07 no cierra.

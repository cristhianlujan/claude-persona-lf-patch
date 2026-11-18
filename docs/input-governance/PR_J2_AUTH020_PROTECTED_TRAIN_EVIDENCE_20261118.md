# PR-J2 — Recibo técnico AUTH-020 sujeto al Train completado #4085

| Hecho | Evidencia real (readback SELECT) |
|---|---|
| Train productor | `44330090597`, RUN `EXEC-DB-TRAIN-PR4085-20261118100000-R44330090597`, COMPLETED |
| Evento | `lf_eventos.id=21937`, `MIGRATION_TRAIN_RECEIPT_RECORDED` |
| HEAD fuente | `367f5fa03875348cfe0114e24be7e34ded72c761` |
| SHA del recibo Train | `91851a194d944d17a24fe21af265c4efc011099991496cecfd80ce953ed46970`, digest recalculado = PASS |
| Ejecutado | GitHub Actions `44329868870`, 16/16 `RULE_CONTRACT_LEVEL` PASS, PG17 rollback y segunda conexión |
| SHA reporte PG | `2595d1a15fe61945ff59e0cd87a32068b1e1e80975e2dd64767b2ba249045ec5` |
| SHA readback PG | `c01aae41970c82bf5dd053e38e12db702c65602b85f063bc185e7dc6e4994362` |
| SHA manifiesto de checks | `fb9dc4bd53b8ff63e91edc514b3b5f9111106151976607552b681e8b595aee10` |
| SHA parche JSONB | `adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02` |
| SHA candidato | `16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061` |

## Antes/después

| Objeto | Antes | Después esperado de PR-J2 |
|---|---|---|
| Evidencia AUTH-020 PR-H | 0 | 1 fila fuente-vinculada y evento auténtico |
| AUTH-020 MD5 | `7588d5a7de4d94a864fca9e63cd10ebe` | Mismo: la regla aún NO se aplica |
| Regla candidata MD5 proyectado | — | `9d558e62bd85cefe6dbe0f4147e59056` (para decisión V2 posterior) |
| Reglas totales | 579 | 579 |
| Permiso38 VIGENTE | 0 | 0 |
| Política20 | CANDIDATO | CANDIDATO |
| Decisiones/cambios V2 | 0/0 | 0/0 |

**Importante:** `functional_checks_status='PASS'` y `negative_checks_status='PASS'` significan **RULE_CONTRACT_LEVEL en SQL modelo temporal**, tal como se definió explícitamente para esta etapa. `login_backend_e2e=NOT_TESTED`; no simular evidencias de producción. El reporte de CI guarda ese nivel de alcance.

La migración J2 valida el evento y HEAD reales **antes** de insertar. El fixture PG17 de CI usa un evento sintético solo para validar ejecución/rollback de SQL; no lo confunde con el recibo de la base. Solo la migración normal del Merge Train registra en Supabase.

**Siguiente tramo, no autorizado por este recibo automáticamente:** obtener RUN legítimo Product Director con Step50 y Step70 independiente, luego usuario dueño `Cristhian Lujan` en `lf_ig_rule_owner_decide_v2`, ejecutar finalización oficial V2, readback hashes; política20 por ACTUALIZACION_DB_LF con provenance renovada. No tocar permiso38 ni AUTH-018/019.

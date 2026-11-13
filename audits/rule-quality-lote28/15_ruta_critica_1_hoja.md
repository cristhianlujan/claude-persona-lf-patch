# Ruta crítica LF para usar Input Governance de punta a punta — una hoja

**Hoy:** Motor **0/7 bloqueos cerrados (NO-GO)**. Ya están en Supabase las migraciones V2, guard y backfill: `LF_GOVERNANCE` 238/238 activos y 155 recibos `APPLIED`. Eso demuestra ejecución, **no firma ni cierre**. B07 pasó una reversión parcial en PG17.6/18.7, pero falta el esquema definitivo.

**Flujo:** Definir RUN (B02) → reconciliar efectos (B03) → verificar owner/decisiones documentales (B06/B08) + proteger funciones existentes (B12) → terminar ciclo LF4/SALY5 (B07) → ejecutar juez nativo y cerrar RUN 11/11 (B09) → revisar siete recibos y resolver G15.

| Lo que falta | Lo hace ingeniería / operaciones | Decisión que sí depende del dueño |
|---|---|---|
| **B02/B03** RUN abiertos y efectos | Ops/DBA: inventario, hashes, leases, heartbeat, idempotencia y efectos por RUN | Fijar cohorte oficial y aceptar el alcance |
| **B12** funciones legacy | Arquitectura/DBA: compatibilidad, MD5, negativos y readback post-migración | Solo si hay excepción o cambio de política |
| **B07** ciclo LF4/SALY5 | Arquitectura/DBA: SQL UP/DOWN completo, pruebas PG17/18 con datos, índices/RLS/consumidores, readback | Definir nombres y semántica exacta de 4 campos LF y 5 SALY, sin cambiar significado de VALIDADO |
| **B06/B08** owners/decisiones | Gobernanza/Ingeniería: verificar 155 recibos, guard y archivados; registrar decisión documental y negativos | Ratificar atribución a Cristhian Luján con `identity_verified=false` y el riesgo temporal |
| **B09 + G15** flujo completo | Plataforma/QA: proveedor nativo/juez independiente, Step70, Step80, 11/11, terminal READY, siete evidencias | Revisar/autorizar GO técnico cuando existan todos los recibos |

**En paralelo:** 5 bloqueos de Contenido se tramitan por IG sin vetar GO del Motor; backup/PITR/restauración B13/B14 se exigen en la base final. Sin fechas comprometidas. Migraciones por **Merge Train**, nunca SQL directo ni cambio de RUN históricos.

**Próximo paso:** Ingeniería entrega la matriz completa LF4/SALY5 para decisión del dueño y la reconciliación de RUN. Después prueba y registra, sin nuevas microaprobaciones. **B07 sigue NO-GO**; ningún bloqueo se cierra por declaración.

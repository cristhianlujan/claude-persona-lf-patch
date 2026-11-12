# Lote 19 — UNA propuesta de procedimiento de reconciliación (NO EJECUTADA)

**Estado:** PROPUESTA DOCUMENTAL — NO-GO / UNVERIFIED. No incluye DML/DDL ni comandos para cambiar estados. No autoriza cierre, reintento, rollback, reactivación o promoción. Requiere un lote posterior autorizado explícitamente por el dueño.

## Datos del diagnóstico
- **OBJETIVO R01:** 232 RUN `IN_PROGRESS`, frente a los **32** informados; la cohorte de 32 no queda determinada por una condición de filtro aportada. El informe `03_32_prioritarios.md` selecciona **32 prioritarios nuevos**, todos respaldados por `01_runs_232_readback.csv`, NO la supuesta cohorte original.
- **OBJETIVO H2:** 8 propietarios de lease con vencimiento pasado, 0 leases vigentes; los otros 224 carecen de expiry. **H1:** no se identificó columna explícita de heartbeat en `public.lf_operation_execution` ni en el catálogo examinado; `updated_at` o `observed_at` NO certifican heartbeat.
- **Clasificación REQUIERE_REVISION_SEMANTICA R01:** A=6, B=56, C=4, D=166. Los casos B son señales de efecto (`effect_guard.SUCCEEDED`, `github_write`, write-like step o registros relacionados); no se certifica cumplimiento de la intención de escritura.

## Procedimiento único sujeto a futura autorización

| Fase | Acción humana/técnica propuesta | Recibo que debería quedar | Gate |
|---|---|---|---|
| P0 — Definir cohorte | Dueño confirma si el alcance son los 232 o entrega identificadores exactos de sus 32. Congelar fecha/corte y pertenencia. | `RECON_SCOPE_RECEIPT`: lista exacta, fuente, consulta, SHA-256, hora UTC, identidad del autorizador | NO-GO sin definición |
| P1 — Congelar evidencia | Exportar snapshot de cada RUN, contrato/versión, último paso, leases/fence/checkpoint, guardas y matrices de sinks; conservar RAW y SHA-256 por RUN. | `RUN_PREIMAGE_RECEIPT`: run_id, estado, contrato, filas/pasos, sellos, SHA, corte | No modificar RUN |
| P2 — Conciliar efectos | Por cada efecto referido (GitHub SHA/PR, migración, captura, homologación, regla, ledger, registro), validar readback en destino real, correlación de ejecución e idempotencia; documentar efectos ausentes o desconocidos. | `EFFECT_RECON_RECEIPT`: ref + hash pre/post, commit, id destino, idempotency key, reconciliado sí/no | NO-GO si destino no consultable |
| P3 — Probar vitalidad | Verificar señal independiente del worker, expiración/fence, reclamación de lease, RUN padre/hijo y flujo de orquestación. No usar timestamp como heartbeat. | `LIVENESS_RECEIPT`: último heartbeat real (si existe), autoridad worker, lease/fence, evidencia externa | No tocar si C o sin certeza |
| P4 — Dictamen por clase | Clasificación preliminar A/B/C/D se somete a control semántico y operativo: B no se reintenta antes de idempotencia; C se preserva; D se investiga; A exige ausencia demostrable dentro de fronteras completas. | `TRIAGE_VERDICT_RECEIPT`: hechos OBJETIVO, inferencias, fuentes faltantes, juez, identidad, firma y conflictos | Bloqueo ante insuficiencia |
| P5 — Dueño decide | Actor autenticado, perfil owner del proyecto (no SUPER_ADMIN), alcance por operación/familia, separación de funciones; decide una acción por RUN. `projects/actors/category_family_map` L13/L17 son laboratorio, no autoridad desplegada. | `OWNER_DECISION_RECEIPT`: run_id, acción explícita, perfil, sub/actor verificado, proyecto, motivo, plazo, snapshot_sha | Requiere operación futura autorizada |
| P6 — Ejecución futura gobernada | SOLO en otro lote, usar contrato/operación oficial y escritor autorizado, nunca SQL manual sobre registros ni bypass Router; verificar precondiciones, compensación, saga/rollback si existen efectos. | `GOVERNED_ACTION_RECEIPT`: execution_id nuevo, permiso, contrato, outcome, evidencia RAW, logs, rechazo y controles negativos | No está autorizado aquí |
| P7 — Readback y cierre | Consultar estado final, efectos reconciliados, recibos por paso, ausencia de duplicados y terminal READY si aplica el contrato; permitir bloqueado si evidencia falta. | `TERMINAL_RECON_RECEIPT`: estado/versión/hash + resultado antes/después + autoridad y auditoría | No declarar PASS sin terminal |

### Tratamiento condicionado por clase (NO es permiso para mutar)
- **A (6):** NO equivale a "nunca hubo efecto"; antes de considerar cierre sin compensación, ampliar inventario de sinks y comprobar ausencia de efectos y de worker vivo.
- **B (56):** mayor riesgo. Si el trabajo ya escribió, reintento ciego podría generar duplicados o reversión errónea; la acción futura depende de recibo destino, idempotencia y relación al RUN.
- **C (4):** preservar; una actividad reciente sin lease vigente no garantiza vida, pero tampoco autoriza matar el proceso.
- **D (166):** falta evidencia; no masificar ni declarar huérfanos. Requerir inventario de contratos, worker y efectos.

### Control de owners transversal
El modelo L13 requiere `project_code+owner_profile_code+actors` y familia por proyecto; L17 exige JWT verificable, rol efectivo y actor mapeado, rechaza SUPER_ADMIN y limita `session_user`. No están desplegados como registro de owners acreditado en este Supabase (véanse SELECT O1–O4). Cualquier iniciativa futura requiere decisión de quién gobierna LF/SALY, readback de fuentes oficiales, pruebas PG18, y operación de adopción **separada** de la reconciliación de RUN.

**Riesgos de aplicar fuera del proceso:** doble ejecución irreversible; promover una regla no aprobada; inventar un owner; bypass de aislamiento por proyecto; falsificar terminal; perder auditabilidad.

**Fuentes y SHA-256:**
- R01 SELECT y SHA-256 `b8f0cd33b2c288aff482619ec4873e64c119b6c9121e7a4c2c478db10d4b65e0` (`02_runs_diagnostic_select.sql`).
- H1 `89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385`; H2 `5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40` (`08_heartbeat_lease_select.sql`).
- O1–O4 (`05_owners_select.sql`); referencia L13/L17 documentada con Git blob en `04_owners_real_registry.md`.

**Juez:** GPT-6, el mismo modelo; NO independiente. Todos los recibos P0–P7 son **campos propuestos no emitidos**.

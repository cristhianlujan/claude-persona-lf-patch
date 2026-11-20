# L34 · B02/G01 + B03/G02 — plan de recibos por RUN (SIN EMITIR)

## Contexto verificable
- Universo inmutable: **235 RUN L33**, HEAD `978c1c203a324cb6fe76e461d94ab47a65df6ab5`; SHA membresía `92655adfadaa16478f3fcd14daae78a7b614907444d176ae26c04fbc431dbdb3`, as_of `2026-11-13 08:36:22.461152+00`.
- SELECT de contraste en Supabase temporal: `2026-11-13 13:51:06.935579+00`, rol `supabase_read_only_user`. No hay DML/DDL, no cambios de RUN, no reintentos.
- Archivo RAW L34 `01_b02_b03_235_run_effects_readback_raw.json`; 235 filas con preimagen congelada, readback actual, pasos, guard, lease e idempotencia.
- Se requieren **235 EFFECT_RECON_RECEIPT y 235 LIVENESS_RECEIPT**, uno por RUN; propuestas sin firma en `04_b02_b03_235_receipts_unissued.json`. Ninguna se ha emitido por escritor oficial.
- **Clasificación por datos** 235/235 preliminar; **clasificación final G02 segura para cerrar o reintentar con solo SELECT** 0/235; **requieren custodia/acción humana** 235/235. Clase propuesta **no es veredicto**.

## Resultado de la lectura actual
| Control | Conteo |
|---|---:|
| Membresía histórica L33 encontrada | 235/235 |
| IN_PROGRESS en lectura posterior | 234 |
| COMPLETED posterior (PR3807) | 1 |
| Leases vencidos | 8 |
| Sin lease | 227 |
| Con clave de idempotencia | 205 |
| RUN con duplicación de idempotencia observada | 0 |
| RUN con registros de guard | 7 |
| Guard SUCCEEDED | 9 |
| Guard RESERVED | 10 |
| Guard ABANDONED | 0 |
| RUN con referencias de paso | 80 |
| RUN con indicios locales de GitHub | 152 |

**Clases provisionales**, no normativas: `B` indicio local de efecto o tipo DB sin cotejo externo, `C` sin indicio local (no prueba ausencia), `D` excepción (lease vencido, transición posterior, duplicado, guard sin resolver). `A` exige evidencia externa independiente y custodia; no se asigna automáticamente. 
`A=0; B=183; C=43; D=9`.

## Plan por tipo de RUN (25 grupos)
| Tipo RUN | N | B | C | D | Leases vencidos | Revisiones obligatorias |
|---|---:|---:|---:|---:|---:|---|
| `ORQUESTACION_PIPELINE_LF` | 99 | 87 | 12 | 0 | 0 | Worker/scheduler/queue: ack, heartbeat, lease fence; DB/Edge/GitHub: per-step external effects |
| `ACTUALIZACION_DB_LF` | 30 | 26 | 0 | 4 | 3 | DB: supabase_migrations.schema_migrations + objeto/version/statement SHA; GitHub: PR exact HEAD/merge + official Train RUN |
| `ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF` | 21 | 20 | 1 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `EJECUCION_PERFIL_LF` | 12 | 12 | 0 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `VULNERABILITY_COVERAGE_REPAIR_LF` | 12 | 1 | 11 | 0 | 0 | DB: efecto/ledger/objeto/PK; GitHub o proveedor si aplica: evidencia externa |
| `GITHUB_CONTRACT_GATE_LF` | 10 | 8 | 2 | 0 | 0 | GitHub: workflow/check-runs/status SHA and job logs; DB: effect guard receipt if any |
| `ACTUALIZACION_SKILL_LF` | 8 | 7 | 1 | 0 | 0 | DB: KB/catálogo/ejecuciones hijas; Storage/external worker: payload/version/ack |
| `EJECUCION_ESTRATEGIA_LF` | 7 | 0 | 2 | 5 | 5 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `ACTUALIZACION_PERFIL_LF` | 6 | 6 | 0 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `ESCRITURA_BASE_CONOCIMIENTO_LF` | 6 | 3 | 3 | 0 | 0 | DB: KB/catálogo/ejecuciones hijas; Storage/external worker: payload/version/ack |
| `ACTUALIZACION_CARD_LF` | 4 | 1 | 3 | 0 | 0 | DB: activos, reglas, dependencias; GitHub: artefacto/commit, rollout |
| `ACTUALIZACION_ESTRATEGIA_LF` | 4 | 4 | 0 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `ACTUALIZACION_ADAPTER_LF` | 2 | 1 | 1 | 0 | 0 | DB: activos, reglas, dependencias; GitHub: artefacto/commit, rollout |
| `CREACION_PERFIL_LF` | 2 | 2 | 0 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `EJECUCION_ROUTER_LF` | 2 | 1 | 1 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `ACTUALIZACION_ROUTER_LF` | 1 | 0 | 1 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `BUILD_INTEGRAL_STORY_CREATOR_LF` | 1 | 1 | 0 | 0 | 0 | DB: efecto/ledger/objeto/PK; GitHub o proveedor si aplica: evidencia externa |
| `CREACION_ADAPTER_LF` | 1 | 0 | 1 | 0 | 0 | DB: activos, reglas, dependencias; GitHub: artefacto/commit, rollout |
| `CREACION_CARD_LF` | 1 | 1 | 0 | 0 | 0 | DB: activos, reglas, dependencias; GitHub: artefacto/commit, rollout |
| `CREACION_ESTRATEGIA_LF` | 1 | 0 | 1 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |
| `EJECUCION_SKILL_LF` | 1 | 1 | 0 | 0 | 0 | DB: KB/catálogo/ejecuciones hijas; Storage/external worker: payload/version/ack |
| `EXTRACCION_FUENTES_DIGITALES_LF` | 1 | 0 | 1 | 0 | 0 | Proveedor web/Google Maps/HTTPS: acceso, cuotas y resultado; DB/KB: writes, snapshots SHA |
| `HOMOLOGACION_FUENTES_DIGITALES_LF` | 1 | 0 | 1 | 0 | 0 | Proveedor web/Google Maps/HTTPS: acceso, cuotas y resultado; DB/KB: writes, snapshots SHA |
| `LEARNING_BRIDGE_KB_CARD_LF` | 1 | 0 | 1 | 0 | 0 | DB: KB/catálogo/ejecuciones hijas; Storage/external worker: payload/version/ack |
| `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` | 1 | 1 | 0 | 0 | 0 | DB: pasos y ejecución hija/parent; GitHub: versiones de perfiles/rules + tests |

## Prioridad de conciliación (no autoriza operación)
1. **Excepciones D**: ocho leases vencidos y RUN PR3807 cambiado de estado; Operaciones + responsable de worker deben leer heartbeat, fence, job, acks y efecto antes de cualquier conclusión.
2. **Escrituras DB**: cada `ACTUALIZACION_DB_LF` requiere ledger/version/commit/Train, y causalidad exacta del RUN. #3807 tiene recibo específico en 05.
3. **Indicios GitHub/worker/servicio**: verificar run id, SHA, objeto de destino, before/after, recibo escritor, deduplicación, guard SUCCEEDED/RESERVED y posibles efectos no registrados.
4. **Clase C**: exigir negativa externa y declaración verificable de ausencia de efectos; no tratar logs vacíos como ausencia.
5. **Recibos**: para cada RUN, completar inventario de efectos, destino, identidad de custodio, evidencia RAW, auditor independiente, firma y resolución G01 → G02.

## Responsables
- **Operaciones**: custodio de 235, confirmar delta PR3807, 235 liveness; firmas/ACK de workers.
- **DBA**: hashes de filas/steps/guard, reconstrucción ledger y PK/tx reales, validación de lecturas y credenciales.
- **GitHub/Merge Train/servicios externos**: readback independiente de cada side effect, commits exactos, acks y idempotencia.
- **Auditor independiente**: readback y negativos, control de consistencia, aceptar/rechazar evidencia; no autocertificación.
- **Dueño**: firma/decisión G01-G02 por canal oficial, sin confundir autorización documental con identidad autenticada.

**Estado B02/G01: ABIERTO. Estado B03/G02: ABIERTO. safe_to_retry=false, safe_to_close=false para 235/235.**

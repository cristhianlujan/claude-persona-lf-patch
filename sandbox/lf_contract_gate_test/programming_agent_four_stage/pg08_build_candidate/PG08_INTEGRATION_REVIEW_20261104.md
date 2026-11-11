# Revisión de integración PG-08 C1–C8 — 2026-11-04

**Alcance:** lectura del código candidato de C1–C8 en PR draft #3528 y contraste con el contrato de la ruta crítica. Se aplicaron dos correcciones de fuente al mismo PR; no se realizaron pruebas Python, E2E, CI de calificación ni ejecución de herramientas reales. **La revisión estática no equivale a calificación independiente.**

## Dictamen
`SOURCE_REVIEW_WITH_FIXES / INTEGRATION_NOT_QUALIFIED / OFFICIAL_PENDING`

Se confirma existencia de ocho productores candidatos. Comparten por contrato `solution_id`, `target_repo`, `base_head_sha`, `candidate_head_sha_reported`, `diff_sha256_reported` y `executor_mode_reported`; los sobres enlazan `candidate_sha256` y rechazan autoridad prematura.

No existe evidencia en este examen de que las ocho piezas hayan sido consumidas en una ejecución encadenada real. Las referencias y resultados provienen del invocador y no son recibos autenticados.

## Correcciones aplicadas
1. **INTEGRATION-01 C2→C6: pérdida de datos**. C2 validaba `command_ref`, `stdout_sha256` y `stderr_sha256` en la observación, pero no los conservaba en `checks_reported`. C6, por tanto, registraba carencias imposibles de solucionar desde su entrada. Se reparó `pg08_c2_format_lint_delta_candidate_v1.py` para preservar esos tres campos sin inventar valores. C6 ya admite los nombres de campo directos y no requiere reescritura.
2. **INTEGRATION-02 C8: secuencia Compose/healthchecks inconsistente**. Se añadió bloqueo si se declara `CONTAINER_HEALTHCHECK=PASS` sin `DOCKER_COMPOSE_UP=PASS`; además se rechaza `DOCKER_COMPOSE_UP=PASS` con `CONTAINER_BUILD=FAIL/BLOCKED` cuando build está declarado REQUIRED. No significa que las herramientas se ejecutaran.

## Revisión de enlaces por checkpoint

| Checkpoint | Productor | Fuente vinculada | Condición no probada |
|---|---|---|---|
| C1 | Build/compilación | PG-07_C6 | HEAD/compilación/recibos reales |
| C2 | Formato/lint | PG-06_C4 + C1 | Línea base, equivalencia de hallazgos, CI exacto |
| C3 | Typecheck | C1 + C2 | Toolchains aplicables y ejecución real |
| C4 | Unit/smoke/Flyway | C1 + C3 | PostgreSQL local y ciclo efectivo |
| C5 | Spectral/oasdiff/BD | C1 + C4 | Aplicabilidad, contrato base/candidato, catálogo migrado |
| C6 | Recibos de checks | C1–C5 | Autenticación y completitud real |
| C7 | Fronteras de arquitectura | C1 + C6 | Cobertura real de módulos y pruebas |
| C8 | IaC/contenedores | C1 + C7 | Red aislada, Floci, Docker y cloud bloqueada |

## Riesgos y trabajo pendiente antes de un GO
- **R1 — Fuente, no ejecución**: todos los sobres garantizan `pass=false`, `admitted=false`; se necesita prueba de punta a punta con HEAD exacto, patches verdaderos, recibos reales y calificador independiente.
- **R2 — Veracidad externa**: los hashes de manifiesto solo prueban coherencia del objeto serializado; no autentican la existencia del recibo ni la ejecución que se declara.
- **R3 — Autoridad del híbrido**: GPT_NATIVE/CLAUDE_NATIVE/WORKER_API son etiquetas no verificadas hasta que el ejecutor autorizado produzca una atestación vinculada al patch.
- **R4 — C6 ocurre antes que C7 y C8**: su manifiesto incluye únicamente checks C1–C5. Los recibos adicionales de arquitectura e infraestructura están en C7 y C8, y tendrán que ser incorporados por la verificación/manifest final; no debe afirmarse que C6 ya cubre los ocho checkpoints.
- **R5 — Aplicabilidad**: valores NOT_APPLICABLE de C4/C5/C7/C8 están declarados por el invocador, no demostrados por el perfil de tecnología/CI.
- **R6 — Aislamiento real**: el campo `execution_target_type=LOCAL_ISOLATED/FLOCI_EMULATOR` no impide por sí solo conexiones externas ni asegura que un comando no use credenciales cloud.
- **R7 — Pruebas pendientes**: las dos correcciones y el conjunto C1–C8 requieren suites unitarias, negativas y una corrida integrada. No declarar `TESTED` ni `QUALIFIED` mientras sigan pausadas.

## Ruta crítica registrada
Consulta read-only del 2026-11-04 a `programacion.engineering_plan_units` y `engineering_work_checkpoints`:
- PG-08: Feedback técnico local de construcción — 8 checkpoints PENDING.
- PG-09: Gobernador de iteraciones — 5 checkpoints PENDING.
- PG-10: Manejo de conflicto de contrato o scope — 5 checkpoints PENDING.
- PG-11: Revisión de integridad del cambio — 5 checkpoints PENDING.
- PG-12: Manifest y provenance del candidato — 4 checkpoints PENDING.

**Restan 4 etapas posteriores a PG-08; contando la integración y calificación inconclusas de PG-08, 5 etapas abiertas (27 checkpoints oficiales PENDING en total).**

## Próxima acción segura
No reabrir PG-00 ni Análisis. Si la pausa de pruebas continúa, el siguiente desarrollo de fuente es PG-09_C1, pero **sin declarar PG-08 cerrada**. Para una decisión de integración más confiable se recomienda una corrida local adversarial y un E2E con paquete de prueba (sin tocar reglas de Análisis productivas), seguida de revisión independiente exact-HEAD.

**Límites de ejecución:** sin cambios a Supabase, main, Análisis ni producto. PR #3528 permanece en draft.

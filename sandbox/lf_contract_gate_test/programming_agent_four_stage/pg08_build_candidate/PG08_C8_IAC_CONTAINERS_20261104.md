# PG-08_C8 — IaC y contenedores aislados (candidato fuente, 2026-11-04)

## Contrato oficial
La migración `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql` define:

- **PG-08_C8**: “IaC y contenedores (D14, STD-IAC/CONT): terraform fmt/validate, lint de IaC, plan/apply contra Floci; build de imágenes y docker compose up con healthchecks verdes”.
- **Criterio de salida**: **PASS sin tocar la nube**.

No se ejecutó Terraform, Floci, Docker ni una llamada a infraestructura. El artefacto es un **productor de evidencia declarada, no autenticada**, y no representa una ejecución ni un PASS del checkpoint.

## Reutilización
- `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1`: identidad del repo, base HEAD, candidato HEAD, digest del diff y procedencia del generador.
- `PG08_C7_ARCH_BOUNDARY_CANDIDATE_V1`: enlace a PG-08_C6 y sus dependencias, con procedencia de checks de arquitectura. C8 exige huellas SHA-256 y relación C7→C1.
- No se crea ningún Worker, orquestador, runner de CI, proxy Terraform ni contenedor adicional.

## Nuevo componente
`tools/pg08_c8_iac_container_candidate_v1.py` implementa:

`prepare_pg08_c8(pg08_c1, pg08_c7, infrastructure_observations)`

Cada solución registra obligatoriamente la aplicabilidad de ocho controles:

1. `TERRAFORM_FMT`
2. `TERRAFORM_VALIDATE`
3. `IAC_LINT`
4. `FLOCI_PLAN`
5. `FLOCI_APPLY`
6. `CONTAINER_BUILD`
7. `DOCKER_COMPOSE_UP`
8. `CONTAINER_HEALTHCHECK`

Cada control declara `REQUIRED` o `NOT_APPLICABLE`, con referencia de aplicabilidad. Las exenciones se registran como `NOT_RUN` y **no se toman como PASS**; la aplicabilidad real debe verificarse contra el target y su configuración.

Para los `REQUIRED`, se exige herramienta y versión, comando y referencia, SHA-256 de configuración, stdout/stderr, referencia de recibo, resultado, código de salida, hallazgos y referencia al entorno de ejecución declarado.

El sobre rechaza duplicados, coverage parcial, identidades inconsistentes, fuentes alteradas, PASS con exit code incorrecto o hallazgos, y contradicciones entre plan/apply de Floci. Un `FLOCI_APPLY` reportado requiere `FLOCI_PLAN` también requerido, marcado PASS y referenciado al mismo destino Floci. Un healthcheck declarado exige la presencia del control de Compose.

## Restricciones de aislamiento y nube
El campo `execution_target_type` permite exclusivamente:
- `LOCAL_ISOLATED` para Terraform local, lint, build, Compose y healthcheck.
- `FLOCI_EMULATOR` para plan/apply simulado.

Se rechazan los tipos declarados `CLOUD`, `REMOTE`, `PRODUCTION`, `PUBLIC`, `UNKNOWN` y todos los no reconocidos. **Esto no garantiza aislamiento real**: una referencia al emulador puede ser falsa y los comandos podrían contener endpoints remotos. El consumidor de ejecución necesita, además, sandbox efectivo sin salida a nube, allowlist de comandos/proveedores, comprobación del endpoint Floci y recibos verificables.

Un perfil que declara `NOT_APPLICABLE` para todos los controles **no queda aprobado**. Debe acreditarse que el proyecto realmente no requiere esos checks, o mantener el checkpoint pendiente.

## Límites y criterios pendientes de calificación
Faltan:
1. Confirmación del perfil técnico y aplicabilidad desde el repositorio de producto y su CI exactos.
2. Readback de base SHA, candidate HEAD y digest real del diff.
3. Aislamiento de red efectivo y bloqueo de credenciales/proveedores cloud reales.
4. Ejecución de Terraform fmt/validate, lint IaC, plan/apply contra Floci y Docker/Compose/healthchecks cuando apliquen.
5. Recibos auténticos de versiones, configuración, ejecución y resultados.
6. Calificación independiente y demostración de **PASS sin tocar nube**, incluyendo controles adversariales.

Incluso si las observaciones reportan PASS, el resultado conserva:
`iac_containers_executed_by_this_component=false`,
`target_isolation_verified=false`,
`cloud_access_prevented_by_runtime=false`,
`exact_head_readback_verified=false`,
`receipts_authenticated=false`,
`pg08_c8_pass=false`,
`pg08_c8_admitted=false`,
`handoff_allowed=false`,
`production_authority=false`.

## Estado y frontera posterior
**`PG08_C8_SOURCE_PREPARED / TOOLS_NOT_EXECUTED / CLOUD_ISOLATION_UNVERIFIED / OFFICIAL_PENDING`**.

Con esto existen componentes candidatos para PG-08_C1–C8. **No significa que PG-08 esté cerrado**. Antes de calificar el bloque se necesita revisar interoperabilidad y completar ejecución/recibos reales, incluyendo el hueco de transporte de evidencias en C2→C6. El siguiente bloque de ruta crítica es PG-09, pero PG-08 permanece pendiente de integración y calificación.

Sin cambios a Análisis, Supabase, main o el producto. Las pruebas oficiales permanecen pausadas; fuente aislada en PR draft #3528.

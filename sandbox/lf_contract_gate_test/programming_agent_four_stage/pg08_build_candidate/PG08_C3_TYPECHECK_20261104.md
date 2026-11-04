# PG-08_C3 — Typecheck por lenguaje (candidato fuente, 2026-11-04)

## Contrato y ubicación
- **Checkpoint oficial:** PG-08_C3.
- **Definición:** Typecheck (tsc strict, javac, mypy en la plataforma).
- **Salida exigida:** PASS.
- **Fuente:** `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

## Reutilización
El nuevo componente no reimplementa PG-07 ni ejecuta un segundo motor. Reutiliza `PG08_C1_BUILD_COMPILATION_CANDIDATE_V1` para la identidad del target, base, HEAD candidato, diff y procedencia; reutiliza `PG08_C2_FORMAT_LINT_DELTA_CANDIDATE_V1` como cadena de procedencia de la revisión posterior. Exige SHA-256 exacto de ambas fuentes y el enlace PG-08_C2 → PG-08_C1.

## Implementación fuente
`tools/pg08_c3_typecheck_candidate_v1.py` expone `prepare_pg08_c3(pg08_c1, pg08_c2, typecheck_observations)`.

Para cada solución debe recibirse exactamente una observación con:
- repositorio, base SHA, candidate HEAD, diff SHA, identidad del ejecutor;
- `required_profiles`: conjunto explícito no vacío entre `TSC_STRICT`, `JAVAC`, `MYPY`;
- un check por perfil requerido con comando, herramienta, versión, configuración SHA-256, stdout/stderr SHA-256, referencia del recibo, estado y exit code, y diagnósticos.

Rechaza: campos faltantes, valores fuera de contrato, duplicación de soluciones/checks, cobertura incompleta, hashes fuente alterados, desalineación de base/HEAD/diff/ejecutor, PASS con exit code distinto de cero, FAIL con exit code cero, BLOCKED con proceso supuestamente ejecutado, y PASS con diagnósticos.

## Adaptación híbrida
Los resultados tipo GPT_NATIVE, CLAUDE_NATIVE y WORKER_API se vinculan al mismo candidato de código, **sin convertir la declaración de procedencia en prueba autenticada**.

La selección de herramientas depende del target real y de la configuración gobernada de CI; nunca se infiere solo por la extensión del archivo. Una entrada que marque un único lenguaje no prueba que sea el conjunto completo de herramientas exigidas.

## Límite de autoridad
Este componente **no** ejecuta `tsc --strict`, `javac`, `mypy`, build ni llamadas a un modelo. Tampoco confirma que los perfiles técnicos, comandos y versiones informados sean los utilizados por CI.

Un lote cuyos checks declaran PASS genera `REPORTED_TYPECHECK_PASS_UNVERIFIED`, nunca PASS oficial. La salida conserva:
`typecheck_executed_by_this_component=false`,
`toolchain_selection_verified=false`,
`diff_readback_verified=false`,
`configuration_verified=false`,
`receipts_authenticated=false`,
`pg08_c3_pass=false`,
`pg08_c3_admitted=false`,
`handoff_allowed=false`,
`production_authority=false`.

## Para la validación posterior
1. Verificar el conjunto de herramientas aplicables desde el perfil del target y CI vigente.
2. Obtener código realmente generado por un ejecutor autorizado, HEAD candidato y diff exactos.
3. Ejecutar en aislamiento typecheck real de cada lenguaje aplicable.
4. Autenticar comandos, hashes, versiones y recibos por check.
5. Registrar dictamen independiente para PG-08_C3.

**Estado:** `PG08_C3_SOURCE_PREPARED / TYPECHECK_NOT_EXECUTED / OFFICIAL_PENDING`.

La calificación y las pruebas oficiales permanecen pausadas. No se modificó Análisis, Supabase, el código de producto ni main. Documento y código quedan aislados en PR draft #3528.

# PG-12_C2 — Inputs, entorno, consumo y glosario (2026-11-04)

## Criterio oficial consultado (solo lectura)
**PG-12_C2:** «Inputs: context_id, versión del catálogo, versiones de skills, stack_profile, proveedor/modelo, foto de la EKB, versiones de toolchain y digest de la configuración de linters; consumo total y por etapa (tokens, caché, costo, gasto desperdiciado) y modo de optimización usado; registro de consultas extra (cada una con su motivo tipado y su resolver); mapa identificador → term_id de los identificadores de dominio nuevos».

Criterio de salida PG-12: «La identidad del candidato puede reconstruirse sin inferencias posteriores». Estado oficial `PENDING`.

## Fuente candidata
`tools/pg12_c2_execution_inputs_usage_candidate_v1.py` expone `prepare_pg12_c2`. Reutiliza C1 mediante esquema, digest SHA-256 y comprobación de estado no admitido, sin inventar identidad de ejecución.

El sobre incluye:
- `context_id`, catálogo, lista versionada de Skills, `stack_profile`, proveedor, modelo y snapshot EKB.
- Herramientas y versiones; digest SHA-256 declarado de la configuración de linters.
- Modo de optimización tipado.
- Totales y desglose por etapa de tokens de entrada/salida y tokens en caché; costos y gasto desperdiciado como cadenas decimales, más moneda.
- Consultas extra con `query_id`, motivo tipado, resolver y referencia a la consulta exacta.
- Identificadores de dominio y sus `term_id` declarados.

Validaciones **solo estructurales**: duplicados, referencias vacías, costos negativos, caché superior al input, gasto desperdiciado superior al costo, tipos inválidos y sumas por etapa que no coinciden con el total. Para evitar errores de coma flotante, las comprobaciones monetarias usan `Decimal`.

## Límites
Los importes y cantidades son **reportados**, no contrastados con recibos de proveedor/modelo ni con el worker. Tampoco se autenticaron snapshots de contexto, catálogo, skills, EKB, toolchain, ni cobertura real de identificadores del diff. El digest de la configuración de linters se comprueba solo por formato.

Incluso con sumas correctas, la salida fija `cost_accuracy_verified=false`, `glossary_coverage_verified=false`, `real_run_receipt_verified=false`, `pg12_c2_pass=false`, `handoff_allowed=false` y `production_authority=false`.

## Validación diferida
1. Leer de fuentes auténticas versiones y fingerprints de inputs, registros de consultas extra y perfil del stack.
2. Contrastar uso/costos/caché con recibos del proveedor o del worker, incluidas monedas y gasto desperdiciado.
3. Extraer del diff real identificadores de dominio y validar su cobertura y `term_id` en glosario auténtico.
4. Ejecutar pruebas adversariales exact-HEAD e integración con C1 y revisión independiente, con trazabilidad de cada resultado.

**Estado:** `PG12_C2_SOURCE_PREPARED / NOT_TESTED / NOT_QUALIFIED / OFFICIAL_PENDING`.

**Siguiente:** PG-12_C3, enlace de resultados de checks PG-08 y PG-11. El PR #3528 permanece draft, sin escrituras en Análisis, Supabase, `main` ni código productivo.

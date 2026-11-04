# LF — Consolidación de pila PG-01 → PG-14 (04-11-2026)

**Estatus:** TECHNICAL_CANDIDATES_QUALIFIED_BY_INDEPENDENT_REVIEW / NOT_PRODUCTION_ADMITTED.
**Mandato:** solo lectura/registro documental. Este documento NO fusiona PR, NO enciende workflows, NO altera Supabase, NO registra Análisis READY, NO habilita Worker/Testing.

## 1. Pila efectiva verificada en GitHub

Los PR siguientes están **abiertos, en draft y sin fusionar**. Cada PR desde #3535 tiene como base la rama del anterior, y su `base_sha` es el HEAD aprobado correspondiente.

| Etapa | PR | HEAD exacto | Resultado externo informado |
|---|---:|---|---|
| PG-04 integración | #3534 | `44b95d89e173ccc4b5e5b0632b9439f7a2f29e4e` | 146/146 pruebas (incluyendo suite PG-04 anterior) |
| PG-05 | #3535 | `417a1e0ee6afe51ba2409d6f081c7714d0ec8d76` | 13/13 |
| PG-06 | #3536 | `0eccf3e34aae34d225f0c74696708744abca8098` | 15/15 |
| PG-07 | #3537 | `715046cfe6030b17878331193d4115696fafcadd` | 15/15 |
| PG-08 | #3539 | `ec516d2abbc225a5e2bdcaf48718b1719a34be8b` | 14/14 |
| PG-09 | #3540 | `2fa6b19b60a324aa0abe4197014250dac849331c` | 14/14 (C5 estructural, no ejecutado) |
| PG-10 | #3541 | `e6bc017fc45b1f587ae80ace5c0b9467bd804b83` | 15/15 (C5 estructural, no ejecutado) |
| PG-11 | #3542 | `837b188d5d33f8fc597f2ac03789d9e5ce182293` | 26/26 |
| PG-12 | #3546 | `26e09c08c2a70ab06d778166652c0577850b3d06` | 12/12 + readback PostgreSQL 16.15 desechable |
| PG-13 | #3548 | `2cdac92fee2d588efc5d85393dbc7a2f6e0bbeb1` | 12/12 + 8 variantes de ataque Git aislado BLOCK |
| PG-14 | #3550 | `d675a7248ac686049623c7f2c0906504bdfb6f34` | 13/13 + respuestas locales ACCEPT/BLOCK releídas de PostgreSQL |
| Consolidación actual | nuevo PR derivado de #3550 | consultar HEAD de este PR | solo auditoría documental |

El PR fuente #3528 (`bfd118c6705eecefbab952ab22b579909165806e`) sigue draft respecto de `main`; NO se incluye como antecesor directo de #3550, sino como fuente de módulos históricos portados. PG-01→PG-03 procede de su propia pila anterior a #3534. No sustituirla ni reconciliarla por inferencia.

**Ancestría verificada con `compare_commits`:**
- #3534 HEAD → #3550 HEAD: 144 commits delante, 0 atrás; 131 archivos.
- Base de #3534 (`b1957859d1872574417a345cf9b307a1500d9167`) → #3550 HEAD: 184 commits delante, 0 atrás; 171 archivos; todas las modificaciones categorizadas por directorios de etapa. Esto NO prueba admisión productiva.

## 2. Diagnóstico CI / política de merge

**#3550 HEAD exacto `d675a7248ac686049623c7f2c0906504bdfb6f34`**
- Workflow PASE: `SUCCESS`, run `41909335478`, job `PASE` SUCCESS.
- Job `PASE / MIGRATION_SOURCE_PARITY`: `SKIPPED` en el mismo run. Archivo actual `.github/workflows/pase.yml` contiene literalmente `migration-source-parity: if: ${{ false }}`.
- El job `pase-merge-gate` vive en `.github/workflows/pase-merge-gate.yml`, separado del run PASE. **No se pudo verificar su resultado exacto en el HEAD #3550** con la información del conector; no traducir automáticamente `UNKNOWN` a `FAIL` ni a `PASS`.
- El archivo `sandbox/lf_contract_gate_test/pase_temporary_disable/README.md` es una referencia histórica a congelamiento temporal; no reemplaza el análisis del YAML de la rama actual.
- Se requiere evidencia específica antes de diagnosticar «rojo»: PR/HEAD, nombre exacto de check, conclusión, run/job ID, paso fallido y código de error. No modificar `.github/workflows/` ni permisos para «pintar verde» un gate.

**Decisiones pendientes de autoridad:** levantar `if: false` de paridad, restaurar requerido de `pase-merge-gate`, aportar qualifications de control, conceder permiso de merge/firma; son cambios gobernados fuera de este PR. `PASE SUCCESS` solo acredita el workflow propio y no sustituye los otros checks.

## 3. Estado de checkpoints de ruta crítica

Estados informados por la auditoría independiente y tablero LF v3.3o:
- PG-01 6/7; PG-02 5/5; PG-03 9/10; PG-04 6/7.
- PG-05 4/5; PG-06 4/5; PG-07 6/6; PG-08 8/8.
- PG-09 4/5; PG-10 4/5; PG-11 5/5; PG-12 4/4; PG-13 3/3; PG-14 3/3.
- Los **89/89 checkpoints en Supabase continúan PENDING** según último tablero reportado; aquí NO se envían actualizaciones.

Los verdes son **calificación técnica del candidato** o ensayos locales; no equivalen a un Worker con facturación real, ejecución real de linters/builds, jueces semánticos admitidos, registro de estado productivo o handoff real de Testing.

## 4. Qué significa preparar Análisis READY

El contrato canónico `programming_entry_contract_v1.json` requiere paquete `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`, snapshot `PROGRAMMING_CONTEXT_SNAPSHOT_V1` preparado por A9, fuente material completa, `context_id`, `context_sha256`, `source_snapshot_sha256`, `authority_fingerprint_sha256`, digest de esquema, persistencia as-of y recibo de paridad A9→PG-01. Se exigen validez de fuente, clasificación de autoridad/implementación, cobertura de frentes materiales, stop rule A8, decisiones, compatibilidad del scope y currentness. Solo pueden admitirse scopes READY limpios, aislando scopes bloqueados en PARTIAL_READY.

El validador `profiles/programming_analysis_lf/validators/runtime_validate.py` de Análisis **solo comprueba coherencia estructural de propuestas**, y su salida conserva `independent_semantic_judge=NOT_EXECUTED`, `pg01_consumer_verified=false`, `downstream_authorized=false`.

Para Testing, `testing_admission_contract_v1.json` modo `EXECUTION` exige el `analysis_package_ref`, el `analysis_package_sha256`, `source_currentness_ref`, `frozen_candidate_ref` y `frozen_candidate_sha256`. Sin paquete Análisis **READY actual y atestado**, no se permite invocar Testing real aunque PG-14 haya respondido localmente ACCEPT.

**Paquete intake preparado:** `ANALYSIS_READY_INTAKE_BLOCKED_20261104.json`. Sus campos nulos NO son hashes ficticios; están intencionalmente pendientes. Debe rellenarse *solo* desde el productor A9/ledger/recibos autorizados y luego pasar juez independiente y admission real. No forzar `READY` desde un chat.

## 5. Secuencia de liberación propuesta — sin ejecución en este mandato

1. Registrar evidencia de los checks exactos de cada PR, en especial `pase-merge-gate` y `migration-source-parity`, incluyendo sus estados `SKIPPED` y causes. Confirmar policy actual antes de intentar merge.
2. Resolver cualquier calificación/autoridad de control por la vía del dueño. **NO** habilitar workflows ni fusionar toda la pila desde este dossier.
3. Solicitar al dueño de Análisis un único sujeto real A1–A9, con target y snapshots exactos, para elaborar `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`; verificar ausencia de decisiones pendientes/material desconocido y currentness. Mantener Análisis estrictamente read-only desde nuestro carril.
4. Obtener veredicto del juez independiente, recibo canónico de contexto y paridad A9→PG-01. Devolver BLOCKED/NEEDS_INPUT si falta cualquier fuente.
5. Solo tras lo anterior, programar una prueba gobernada pequeña (una sola solución/scope READY) con Worker real, costos medidos y checks de build reproducidos; nunca extrapolar los fixtures.
6. Antes del handoff productivo a Testing: confirmar `EXECUTION`, SHA congelado del mismo candidato, obligaciones, blind-test, copy y autoridad SUPER_ADMIN requerida; Testing debe producir su propio recibo ACCEPT/BLOCK y readback.

## 6. Principios de no-go

- No se ha emitido la firma única de SUPER_ADMIN del Bloque F.
- No hay paquete Análisis READY que pueda verificarse con los recibos accesibles en esta auditoría.
- Ningún merge ni actualización a Supabase por esta consolidación.
- No corregir `migration-source-parity` creando falsos ledgers, retimestamping SQL, activando workflows sin aprobación o elevando privilegios de base de datos.
- Si la evidencia real no existe: `REQUIRES_DECISION / BLOCKED`; no presentar `PASS` sintético como operativo.

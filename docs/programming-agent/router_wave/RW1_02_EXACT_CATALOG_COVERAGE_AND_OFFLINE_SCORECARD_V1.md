# RW1-02 — Intersección exacta del catálogo y comparador de evidencia A/B/C/D

**Tipo:** PREWORK técnico reproducible; **no inicia ni cierra RW1-02_C1/C2/C3** y no sustituye `RW1-01_C3=PENDING`.  
**Fuente observada:** Supabase LF read-only, 2026-10-18, `public.lf_activos` no archivados, `public.lf_router_action_registry` (solo filas `status='ACTIVE'`). EKB consultado: `GOV-ROUTER-OVERHYDRATION-JIT-001`, `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`, `...PREWRITE-INTENT-GATE...`, `...UNSTRUCTURED-MUTATION-FALSE-READY...` y `ENGINEERING-FOUR-CAPABILITY-ROUTER-001`.

## 1. Intersección exacta: no confundir un nombre sin ruta con capacidad ausente

Existen **22** valores distintos de `lf_activos.tipo_activo` no archivados. **8** coinciden exactamente (después de `upper(btrim)`) con por lo menos una fila `ACTIVE` de `lf_router_action_registry.asset_type`, **14** no coinciden.

| Tipo no archivado sin ruta ACTIVE exacta | Activos existentes |
|---|---:|
| CONTRACT | 7 |
| DB_TABLE | 7 |
| SHEET | 6 |
| AUDIT | 3 |
| HANDOFF | 3 |
| IMAGE_ASSET | 3 |
| TABLE | 2 |
| CARRIER | 1 |
| DB_SCHEMA | 1 |
| ORCHESTRATOR | 1 |
| PDF | 1 |
| ROUTER | 1 |
| TEST_SUITE | 1 |
| UI_PACKAGE | 1 |

Los ocho tipos con coincidencia exacta son `CAPABILITY` (113 activos, 2 rutas), `DOC` (26, 2), `SKILL` (14, 4), `REGLA` (12, 3), `PERFIL` (11, 5), `CARD` (5, 1), `ADAPTER` (4, 3), `FUNCTION` (1, 1).

**Advertencia causal:** una ruta `ACTIVE` declarada no prueba responsabilidad competente ni permiso de efecto; un tipo sin ruta exacta puede ser manejado por `DB`, `MIGRATION`, `TRIGGER`, `APP_SHELL`, relaciones, perfiles, operaciones u otro consumidor. Estas seis denominaciones aparecen en el registro pero no en los 22 tipos no archivados; por tanto la resta no indica «14 funciones faltantes». La unidad a descubrir es **responsabilidad/capacidad/rol/operación**, no un diccionario cerrado de palabras. No llenar automáticamente 14 filas con mapping inventado.

## 2. Evidencia reproducible

```sql
WITH asset_types AS (
 SELECT tipo_activo, count(*) AS asset_count
 FROM public.lf_activos WHERE archived_at IS NULL GROUP BY tipo_activo
),
route_types AS (
 SELECT asset_type, count(*) route_rows, count(*) FILTER(WHERE write_allowed) routes_write
 FROM public.lf_router_action_registry WHERE status='ACTIVE' GROUP BY asset_type
)
SELECT a.tipo_activo,a.asset_count,coalesce(r.route_rows,0) active_route_rows,
       coalesce(r.routes_write,0) configured_write_rows,
       CASE WHEN r.asset_type IS NULL THEN 'NO_EXACT_ACTIVE_TYPE_ROUTE'
            ELSE 'EXACT_ACTIVE_TYPE_ROUTE' END match
FROM asset_types a
LEFT JOIN route_types r ON upper(btrim(a.tipo_activo))=upper(btrim(r.asset_type))
ORDER BY active_route_rows, a.asset_count DESC, a.tipo_activo;
```

**Dos mediciones separadas:** 35 filas `ACTIVE` en Router action registry, con 16 tipos y 26 filas marcadas `write_allowed`; esas 26 son banderas de configuración, **no operaciones de escritura ejecutadas ni autorizadas**. El Router operativo es `STABLE` y su código vivo medido tiene 39.602 caracteres en la lectura previa; el tamaño fuente no cuantifica complejidad ni latencia por solicitud.

## 3. Instrumento offline A/B/C/D: misma entrada, dimensiones no confundidas

Archivo: `sandbox/lf_contract_gate_test/router_wave/compare_rw102_candidate_traces_v1.py`. Identidad congelada del corpus C2: Git blob `58884d37d74f1c784dfb5920ed2ac548781bfe18`, 30 solicitudes, 12 necesidades y 9 familias.

```bash
python3 sandbox/lf_contract_gate_test/router_wave/compare_rw102_candidate_traces_v1.py
python3 sandbox/lf_contract_gate_test/router_wave/compare_rw102_candidate_traces_v1.py --self-test
python3 sandbox/lf_contract_gate_test/router_wave/compare_rw102_candidate_traces_v1.py \
  --candidate A=/tmp/A.json --candidate B=/tmp/B.json \
  --candidate C=/tmp/C.json --candidate D=/tmp/D.json
```

Cada archivo de candidato, cuando realmente exista, debe ser un array JSON de respuestas para **los mismos 30 IDs**, siguiendo el contrato actual `check_result()` del validador RW1-01_C2. El comparador:
- Rechaza alteración del corpus congelado, identifica faltantes/duplicados y muestra violaciones de forma y seguridad declarada por candidato.
- Mantiene la salida `architectural_verdict=NOT_DETERMINABLE_FROM_SHAPE` aunque tenga 30/30 respuestas de forma aceptable. Ni `fixture://` ni `authority_evidence_ref` autodeclarada prueban responsable registrado.
- Nunca certifica consumidor real, autorización, tiempos, costos, determinismo de dos ejecuciones independientes, ni calidad del juez. Esos requieren recibos **del proveedor**, mediciones de mismo snapshot y holdouts protegidos.
- Sin los cuatro archivos responde `NOT_EXECUTED`; no rellena variantes A/B/C/D a partir de expectativas del productor.
- Su `--self-test` busca cinco propiedades: una referencia de fixture no puede acreditarse como autoridad, un shape PASS no elige ganador, y se detectan SHA incorrecto, duplicado y caso ausente.

**No usar la salida del comparador como cierre de C3, ejecución E2E de Router ni selección de arquitectura.** Las formas aceptables son solo el primer nivel; se necesitan evidencias materiales para continuidad, seguridad real y costo.

## 4. Qué podría falsificar realmente cada diseño

| Brazo | Falsificador en prueba futura | Evidencia distinta de forma necesaria |
|---|---|---|
| A / semántica central | Un tipo añadido mediante registro obliga cambiar el código del núcleo; o la ruta inspección/Train se degrada | Git diff de núcleo, readback catálogo, canario Train + captura de tiempos |
| B / catálogo mínimo | «regla+skill» pierde objetivo antes de llegar al competente, o el responsable no existe en catálogo | Identidades de responsables y consumidores registradas, recibo multiobjetivo del mismo SHA |
| C / sobre mínimo | Negación contextual fuerza regex por término, o hints pasan a permisos de efecto | Lista de reglas añadidas, decisión de derivación, scope+prewrite realmente verificados |
| D / coordinador | Requiere quinta capacidad de ejecución, introduce ciclo o actúa sobre objetivo excluido | DAG del handoff, comprobación de cuatro capacidades, recibos sin bucle y sin mutación excluida |

**Criterios uniformes:** tasa de forma, falso permiso de efecto, continuidad comprobada, pérdida de objetivos, falso rechazo de trabajo read-only, costo real del recorrido, fuente/versión y compatibilidad. No imputar pesos ni ganador sin pactar medición; evitar convertir una sola métrica en decisión.

## 5. Ausencias deliberadas

- Los holdouts de C3 independiente y RW1-02 **no se generan ni publican en este prework**, para no contaminar al juez.
- Ninguna variante A/B/C/D se ha ejecutado. `NOT_EXECUTED` es el único estado justificable por falta de sus trazas.
- No se crean perfiles, adapters, operaciones, una quinta capability ni migraciones de producción.
- La fuente de la cobertura actual debe reconfirmarse antes de cualquier decisión de implementación; lo aquí medido es corte de catálogo.

**Dependencia formal:** `RW1-01_C3` continúa pendiente; el PR de pretrabajo queda DRAFT, no `ready-to-merge` hasta que se satisfaga la independencia material.

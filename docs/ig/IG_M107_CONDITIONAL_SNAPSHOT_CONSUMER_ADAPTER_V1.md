# IG M10.7 — lector transversal condicional del snapshot (candidato, no activo)

## Cambio solicitado
Se prepara un **único lector de datos** para consumidores como Curator y Validator, sin duplicar la lógica de extracción ni intervenir en sus decisiones. La elección del origen se realiza solo cuando el paquete es completo y corresponde al consumidor, ejecución y etapa.

- Código: `supabase/functions/_shared/ig_snapshot_reader_v1.mjs`.
- Pruebas: `sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_snapshot_reader_v1.mjs`.
- Prueba previa: `node --test` 11/11 PASS. Revisión V2: 21 casos incluidos, pendiente comprobación de CI en el PR.
- EKB previo leído: `IG-M107-RUN-CONTEXT-CANDIDATE-G1-010`, `IG-M107-INMEM-SNAPSHOT-PILOT-022`, `IG-M107-SQL-MATERIALIZATION-BENCHMARK-023`.
- Autoridad: contrato `docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md`, G3 no activo.

## Política de selección

| Consumidor | Etapa | Paquete y lectura |
|---|---|---|
| Curator | `CURATING` | Si existe paquete V2 íntegro, con identidad correcta y de fuente interna confiable: leer snapshot; si no existe, continuar con su contexto canónico actual |
| Validator | `VALIDATING` | Si existe paquete V2 íntegro, con identidad y Validator independiente: leer snapshot; si no existe, continuar con su lectura canónica actual |
| Cualquiera | Etapa distinta | No solicitar el paquete: seguir ruta actual |
| Cualquiera | Proveedor V1 `RUN_PINNED_FIELDS_ONLY` | No es un snapshot completo: mantener lectura actual |
| Cualquiera | Paquete V2 incorrecto o adulterado | FAIL_CLOSED: nunca usar el paquete ni esconder el fallo mediante fallback |

El lector valida identidad `run_id`, pantalla, versión, contrato, fuente y etapa, y SHA-256 canónico del conjunto entregado. Ahora permite acceder selectivamente por sección/ID/ruta, sin copiar todo por lectura. No comparte veredictos ni permisos de Validator.

**Frontera de confianza:** el argumento `loadTrustedSnapshot` debe conectarse exclusivamente a un proveedor de autoridad de backend; se prohíbe alimentarlo de JSON, request body, header o parámetro suministrado por un cliente.

## Revisión V2 — acceso selectivo, sin cargas/copies innecesarias

El lector candidato **ya no entrega `data` completo por defecto**. Al abrir una ejecución elegible, obtiene el paquete interno confiable una sola vez, verifica identidad/etapa, calcula y compara SHA-256 **una sola vez** y congela su contenido JSON. Devuelve un método `read(selection)` que no efectúa RPC, hash ni `structuredClone` en cada lectura. No guarda snapshots entre ejecuciones.

Cada consumidor pide solo lo necesario, sin requerir las demás secciones:
```js
const bound = await selectSnapshotReadV1({consumer, run, loadTrustedSnapshot});
if (bound.mode === 'SHARED_SNAPSHOT') {
  const curatorInputs = bound.read({
    rules: [7, 8],
    contracts: ['INPUT_READINESS_CONTRACT'],
    families: ['ACTIONS'],
    graph: ['canonical_contract.visual.design_bindings']
  });
}
```
Los identificadores son ilustrativos. En ejecución real se derivan de las reglas/familias aplicables, nunca se codifican por pantalla. Las secciones `rules`, `contracts`, `families` son índices por ID/código **perezosos**: solo se construye un índice al consultar esa sección. `graph` selecciona campos por ruta; `true` permite obtener una sección íntegra únicamente cuando el consumidor de verdad la necesita. Las vistas y registros se entregan inmutables sin clonaciones sucesivas.

Un paquete V2 auténtico puede contener solo las secciones relevantes al alcance solicitado; el lector rechaza **únicamente** secciones/identificadores que un consumidor solicite y que estén ausentes. No obliga a contener las 47 familias, todos los contratos o todos los grafos para una operación de cinco familias. Se conserva validación inicial del hash de **los datos realmente entregados**, identidad, etapa e independencia del Validator.

No hay caché global, permisos adicionales ni un segundo motor: se usa el mismo lector transversal y sus controles esenciales. Una etapa no aplicable o G1 solo referencial usa ruta vigente; un V2 falso, identidad errada o campo solicitado ausente falla cerrado. **No comparte veredictos ni autoridad.**

**Límite comprobable:** esta revisión optimiza las lecturas **dentro del proceso que ya recibió los datos**. La primera carga y la verificación SHA todavía acceden al paquete entregado; el proveedor V2 real aún no existe y no está probado el ahorro de transferir selecciones entre procesos. Para ese caso, la futura implementación del proveedor debe proyectar y agrupar valores del snapshot en el origen, sin transmitir el dataset entero por cada consumidor y conservando prueba de integridad. No simular una ganancia de red con el lector local.

**Pruebas candidatas:** 21 casos para selección exacta, reutilización por referencia, carga única, índices perezosos, vista inmutable, G1/fallback, etapa, SHA/identidad, independencia y negativos. Ninguna prueba activa los consumidores productivos ni sustituye el benchmark completo.

## Estado comprobado y limitación

El proveedor real `programacion.fn_input_governance_run_context_packet_v1(bigint)` hoy requiere `VALIDATING`, es candidato sin permiso de consumo activo y retorna `IG_EXECUTION_SOURCE_CONTEXT_V1 / RUN_PINNED_FIELDS_ONLY`: aporta identidades y referencias, **no el contenido completo** de reglas, contratos y grafo. Curator ya posee un contexto/grafo local por solicitud, pero el proveedor G1 no corresponde a su etapa.

Por ello, el nuevo lector está **preparado y probado como componente candidato**, **no importado ni invocado aún desde Edge productivo**. No se hizo pasar al paquete G1 por un snapshot V2. No se cambian el Curator SQL, Validator SQL, 21 triggers, reglas, grants, políticas ni tiempos. Un fichero bajo `_shared` que todavía no se importa no activa runtime.

**Paso posterior necesario antes de conectar los consumidores:** proveedor V2 verificable que entregue las secciones/variables necesarias por etapa y ejecución, conexión del lector a las rutas reales y prueba end-to-end de equivalencia + benchmark versus run 933. No declarar G3/CP3 por haber pasado 11 pruebas unitarias.

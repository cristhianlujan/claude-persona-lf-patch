# M10.7 — Proveedor transversal de proyección por ejecución (V2 candidato)

## Alcance

Objetivo: cargar una vez los **datos de entrada congelados** de la ejecución y
entregar solamente las variables necesarias para cada consulta de Curator o
Validator. El proveedor reutiliza el lector autorizado
`supabase/functions/_shared/ig_snapshot_reader_v1.mjs`. No crea motor de
decisiones, caché global, tabla nueva ni reglas por pantalla.

- Código: `supabase/functions/_shared/ig_snapshot_projection_provider_v2.mjs`.
- Tests: `sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_projection_provider_v2.mjs`.
- CI aislado, sin secretos o DB:
  `.github/workflows/ig-m107-projection-candidate-ci.yml`.
- EKB leído: `IG-M107-RUN-CONTEXT-CANDIDATE-G1-010`, `IG-M107-INMEM-SNAPSHOT-PILOT-022`,
  `IG-M107-SQL-MATERIALIZATION-BENCHMARK-023`,
  `IG-M107-SELECTIVE-SNAPSHOT-READER-CANDIDATE-025`.

## Comportamiento efectivo del candidato

```js
const provider=createRunScopedProjectionProviderV2({
  loadTrustedRunData: async pinned => /* fuente backend de datos congelados */
});
const x=await provider.select({
  consumer:'INPUT_VALIDATOR',run,
  selection:{rules:[7],contracts:['C1'],families:['ACTIONS']}
});
```

`loadTrustedRunData` es una dependencia **interna de confianza**: recibe
la identidad de la ejecución y devuelve `{identity,data}`, con identidad
idéntica y datos congelados, nunca el cuerpo de una solicitud HTTP. La primera
lectura elegible invoca la fuente exactamente una vez; llamadas concurrentes
comparten la misma promesa. Se reutilizan las proyecciones e índices lazy del
lector V1, sin `structuredClone` ni consultas por cada `read`.

La instancia mantiene **un único run**. Cambiar run/pantalla/versión/hash
rechaza reutilizar la instancia; el siguiente run usa otra instancia. Cada
consumidor conserva etapa e identidad propias. La etapa no aplicable deja
la ruta canónica sin cargar datos. Curator en CURATING puede usar la selección
únicamente si ya existe una fuente congelada válida; en caso contrario conserva
su grafo/contexto canónico actual.

`projectForTransfer` envía un objeto con **solamente las secciones e IDs
solicitados** y SHA-256 calculado sobre esa proyección. El receptor usa el
mismo `selectSnapshotReadV1` para verificar identidad/etapa/hash y acceder a
sus valores. Las rutas de grafo mantienen su estructura JSON para que también
puedan leerse tras pasar de un proceso a otro.

Las decisiones de Curator y Validator siguen siendo independientes. No se
comparten PASS ni evidencias de autoridad, no se eluden currentness,
restricciones de ingreso o los 21 triggers vigentes.

## Medición real de volumen SQL (Supabase, read-only)

Pantalla 43, run histórico 933. Consulta SQL de comparación, con
`fn_input_effective_rule_links_v1` en CTE `MATERIALIZED` utilizada una vez
por ámbito, y lectura por índices existentes:

| Indicador | Todas las entradas | Selección de ejemplo |
|---|---:|---:|
| Reglas efectivas | 246 | 5 |
| Contratos definidos/fail-closed | 10 | 2 |
| Familias | 47 | 5 |
| JSON serializado | 242017 bytes | 71116 bytes |

Disminución de bytes: **70.6% para esta selección concreta**.
El `EXPLAIN (ANALYZE, BUFFERS)` conjunto se ejecutó en **66.032 ms**
(planificación **3.331 ms**); **no mide tiempos comparables full vs select**
ni una ejecución real de Curator/Validator. La selección de cinco reglas fue
solo un fixture; los selectores productivos se derivan de la necesidad de cada
consumidor, no de los IDs del caso. Los contratos representan gran parte del
payload: la siguiente optimización del loader puede elegir rutas dentro de
ellos cuando no sea necesario enviar el documento completo.

## Frontera y siguiente condición operativa

Este PR entrega el **proveedor en memoria, proyecciones transportables,
tests y evidencia**, pero todavía **no integra un extractor SQL backend real**
como `loadTrustedRunData`: el proveedor G1 vigente retorna referencias
`RUN_PINNED_FIELDS_ONLY`, no un dataset de autoridad completo. Por lo
tanto, NO se importan estos módulos en Edge Curator/Validator ni se despliegan
ni se otorgan GRANT. No se hacen pasar los datos SQL históricos por un
snapshot transaccional operativo.

Para probar el sistema completo después: enlazar el loader con el origen
canónico congelado durante la ejecución, instrumentar una carga por run y
transporte de secciones, comparar paridad de resultados y tiempo por fase
contra el baseline de run 933. No declarar G3 o CP3 sin esa evidencia.

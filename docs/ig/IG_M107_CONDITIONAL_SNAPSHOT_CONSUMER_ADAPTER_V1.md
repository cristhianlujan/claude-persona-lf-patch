# IG M10.7 — lector transversal condicional del snapshot (candidato, no activo)

## Cambio solicitado
Se prepara un **único lector de datos** para consumidores como Curator y Validator, sin duplicar la lógica de extracción ni intervenir en sus decisiones. La elección del origen se realiza solo cuando el paquete es completo y corresponde al consumidor, ejecución y etapa.

- Código: `supabase/functions/_shared/ig_snapshot_reader_v1.mjs`.
- Pruebas: `sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_snapshot_reader_v1.mjs`.
- Prueba local: `node --test` 11/11 PASS.
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

El lector valida identidad `run_id`, pantalla, versión, contrato, fuente y etapa, y SHA-256 de JSON canónico de los datos. Congela en memoria reglas, contratos, familias y grafo. No comparte veredictos ni permisos de Validator.

**Frontera de confianza:** el argumento `loadTrustedSnapshot` debe conectarse exclusivamente a un proveedor de autoridad de backend; se prohíbe alimentarlo de JSON, request body, header o parámetro suministrado por un cliente.

## Estado comprobado y limitación

El proveedor real `programacion.fn_input_governance_run_context_packet_v1(bigint)` hoy requiere `VALIDATING`, es candidato sin permiso de consumo activo y retorna `IG_EXECUTION_SOURCE_CONTEXT_V1 / RUN_PINNED_FIELDS_ONLY`: aporta identidades y referencias, **no el contenido completo** de reglas, contratos y grafo. Curator ya posee un contexto/grafo local por solicitud, pero el proveedor G1 no corresponde a su etapa.

Por ello, el nuevo lector está **preparado y probado como componente candidato**, **no importado ni invocado aún desde Edge productivo**. No se hizo pasar al paquete G1 por un snapshot V2. No se cambian el Curator SQL, Validator SQL, 21 triggers, reglas, grants, políticas ni tiempos. Un fichero bajo `_shared` que todavía no se importa no activa runtime.

**Paso posterior necesario antes de conectar los consumidores:** proveedor V2 completo y con autoridad verificable para la etapa correspondiente, conexión del lector a las rutas reales y prueba end-to-end de equivalencia + benchmark versus run 933. No declarar G3/CP3 por haber pasado 11 pruebas unitarias.

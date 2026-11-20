# Matriz de cobertura Carril D → núcleo aislado

| Diseño | Elemento implementado | Prueba | Estado |
|---|---|---|---|
| D-01 Identidad/versiones/pins | `RunContract`, `Pins`, `fingerprint()` | T06, T09, T12 | Implementado experimental |
| D-01 Evidence/receipts | `Receipt.valid()` y `Outcome` | T06, T11, T14 | Parcial: coherencia de identidad, no verificación de proveedor |
| D-02 Loader dinámico | `load_inventory()` desde JSON real o fixture | T01, T12, T13, T15 | Implementado; **pendiente ejecutar con bytes reales #3220** |
| D-02 Conteos 108/22 | `load_inventory()` | T01, T02 | Implementado sobre fixture equivalente en topología |
| D-02 DAG/ciclos/referencias | `topo_layers()`, validadores | T02, T03 | Implementado |
| D-02 Dependencias | `eligible()` | T04 | Implementado a nivel PG/CP |
| D-03 Estados | `State`, `ALLOWED`, `transition()` | T07, T08 | Implementado puro |
| D-03 Evidencia actual | `Receipt.valid()` | T06, T14 | Parcial: no se recomputa digest del contenido del recibo |
| D-03 Invalidación | `material_drift`, `invalidated_descendants` | T09 | Parcial: cálculo puro, sin event log ni persistencia |
| D-03 Closure | `verify_closure()` | T05, T10, T11 | Implementado sintético, fail-closed para N/A |
| Governance | `authority_status` candidato solamente | T12 | Implementado: nunca concede GO |
| PG-00 externo | `pg00` leído pero no certificado | T01 | Parcial intencional |
| PASE/Train | no integrada | — | Fuera de alcance |
| Recorder/Ledger/Worker/Runner | sin adapters | — | Fuera de alcance |

**Nota sobre recibos:** `Receipt.valid()` valida coincidencia exacta y forma del hash, no autenticidad criptográfica ni verificación independiente del proveedor. No considerar el PASS local como prueba operacional. El motor en este lote es una referencia experimental, no un gate de producción.

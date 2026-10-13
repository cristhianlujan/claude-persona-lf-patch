# EXECUTION_CONTINUITY — RECOVER / RECONCILE / RESUME

**Estado: CANDIDATE_SOURCE_ONLY. No instalado, no promocionado, no consumer admitido.**
El núcleo v0.1.0 es reusable por proyecto. El Merge Train es un adaptador candidato, no propietario de la capacidad. Ningún cambio de código confiere autoridad de base, ledger, Git o producción.

## Entrada única gobernada
```
caller (cualquier proyecto)
    -> ACT-0001 / Router [ejecución válida + operation_code + scope + owner]
    -> EKB / contrato + política vigente / inventario / currentness
    -> EXECUTION_CONTINUITY.decide(mode, request)
       | BLOCK -> sin efectos y evidencia de causa raíz
       | SKIP  -> no reejecutar efecto durable
       | ADMIT -> adaptador autorizado por operación/proyecto
    -> readback independiente -> recibo -> veredicto/cierre gobernado
```

El núcleo **no ejecuta** comandos, no crea otro Router, no guarda estados, no modifica registros, ni administra identidades de otros proyectos. Entrada/output: `LF_EXECUTION_CONTINUITY_REQUEST_V1` / `LF_EXECUTION_CONTINUITY_DECISION_V1`. La implementación es `continuity_core_v1.py` y su manifest versionado es `manifest_v1.json`.

## Semántica invariante

| Modo | Admite únicamente si | Nunca hace |
|---|---|---|
| RECOVER | fuente/blob original, versión original, owner approval, no efecto equivalente ya materializado, rollback compatible, dependencias y conflictos verificados | retimestamp, replay implícito, DDL fuera de transporte autorizado |
| RECONCILE | identidad y contenido del ledger leídos, Git rename-only de bytes exactos, scope Git-only | DB apply, ledger DML, modificación de SQL |
| RESUME | checkpoint y effect guard persistidos; reserva nueva solo con autorización; SUCCEEDED -> SKIP | repetir SUCCEEDED ni suponer resultado de RESERVED |

`RESERVED` sin recibo **BLOCK** y exige reconciliación durable; no se interpreta como efecto ausente. Fecha futura superior a UTC+10m **BLOCK**. `production_allowed=false` no admite excepciones tácitas.

## Protocolo de creación y activación (NO ejecutado)

1. **Inventario / descubrimiento:** verificar que no haya capability equivalente o código duplicado; registrar relación con `DB_WRITE_TRANSPORT` y Saga, sin sustituir sus contratos.
2. **Contrato versionado:** congelar fuente, manifest y hashes; revisión independiente, positivos/negativos, rollback sin residuos y análisis de consumidores actuales.
3. **Registro gobernado:** por operación `ACTUALIZACION_DB_LF` y Train, crear/admitir `lf_capability_registry` + `lf_capability_version_registry` y `lf_activos.transversal_inventory` mediante migración source-first posterior y aprobada, con readback real.
4. **Currentness:** promocionar `lf_capability_current` solo mediante `fn_lf_capability_promote_v1` y entry guard `fn_lf_capability_preflight_v1`. Sin ese paso, los adapters deben rechazar en runtime.
5. **Consumer por consumer:** declarar operation_code + autoridad Router + scopes + contrato/policy + adaptador + pruebas negativas para cada proyecto; `consumers_known` es inventario, nunca wildcard de permisos.
6. **Validación terminal:** correr CI sobre SHA exacto, readback de base/catálogo, pruebas rollback y rechazo de replay; emitir recibo y cierre solo con evidencia; activación/producción requieren autorización propia.

## Propuesta de adaptadores

- `ACTUALIZACION_DB_LF` / Merge Train: traducir contexto de Git+ledger a request canónico. Scripts específicos `lf_migration_*` permanecen privados al adaptador; no son la API transversal.
- Otros proyectos: integrar por **nuevo adaptador declarado** con autorización y transportes propios. No hay consumo automático ni whitelist global.
- `RECOVER` de #2349: superseded por PR #2354; no intentar apply del blob anterior. El readback indica efecto equivalente y el núcleo debe recibir `replay_equivalent_absent=false`.

## Trazabilidad y límites

PR candidato: #2358. Evidencia disponible: tests estáticos del Train. Pendiente para capacidad formal: registro DB, pointer/currentness, contrato operativo, readback positivo/negativo por consumidor y aceptación del owner. No marcar READY/ACTIVE ni aplicar por solo merge del código.

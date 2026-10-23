# PG-01 · Base SQL aislada del receptor

Estado: candidato de fuente, PR draft. No es cierre P1/I0 ni ejecución PG-01 real.
La revisión de Claude previa al código fue dispensada por Paulo en la conversación del 23/10/2026. La revisión independiente sigue pendiente.

## Alcance

Una única migración crea las tres funciones de contexto de #1912 y reemplaza la guardia existente con la versión de #2306. Los cuerpos de las cuatro funciones conservan las fuentes exactas. Se excluye el resto de ambos PRs. Se añaden REVOKE EXECUTE FROM PUBLIC a las tres funciones nuevas para mantenerlas owner-only, sin habilitar llamadores. La ACL de la guardia existente se conserva.

Fuentes:
- #1912 @ 78030d6b8ea51f61807b8bc005ee9386a901a82a, migración 20261007183500_programming_context_snapshot_runtime_guard_v1.sql; blob eae0d12e2d93f7d6e65be977c3c54541029c3ae6.
- #2306 @ cb7f1564d48a01448589b04b8c1bb040e7fee291, migración 20261012094600_analysis_a9_pg01_receipt_digest_guard_fix_v1.sql; blob 1aaabfe817cccdbff6e025af0f1c3c648ffa295f.
- Contratos main: programming_entry_contract_v1.json (SHA-256 d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8) y analysis_programming_handoff_parity_contract_v1.json.

La migración usa MANAGED_PREFIXES: programming_context_snapshot_runtime_guard_. Los paths están en las familias fijas MIGRATION y PROGRAMMING_AGENT_TESTS; confirmar con PASE sobre cada HEAD antes del push.

No cambia contracts SOURCE_ONLY_CANDIDATE, registry, Router, workflows, reglas de merge, paquete PG00 ni repositorio programming-agent. No instala emisor ni nueva persistencia. El wrapper record es para el productor A9; el consumidor de lectura no debe usarlo para guardar su recibo.

## Recorrido que la base permite probar

Contexto A9 → record canónico (solo prueba local) → resolve por consumidor/sujeto/as-of → validación del snapshot → guardia exacta contra id/hash/schema ESPERADOS DEL HANDOFF.

Resolve no recibe context_id: un resultado RESOLVED no autoriza aceptar otra identidad. La guardia verifica contexto inmutable, schema exterior LF_DECISION_CONTEXT_ASOF_INPUT_V1, schema interior de Programación, digest declarado y SHA-256 recalculado por PostgreSQL.

## Reproducción local

Desde la raíz del repo:

```bash
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/run_programming_pg01_receiver_base_v1.py --allow-local-docker
```

Añadir --sudo-docker únicamente cuando los permisos de Docker del host lo requieren. Usa la imagen existente postgres:17.6 en un contenedor único desechable, sin red externa ni puertos publicados, con datos tmpfs. No acepta URL ni credenciales de Supabase. El contenedor se elimina en finally.

Reutiliza cuerpos SQL canónicos de DECISION_CONTEXT_ASOF desde la migración de main 20261004144500_t_decctx_decision_context_asof_v1.sql. El catálogo de dependencias es sintético local. La rama de typed_evidence no está implementada en el entorno de prueba: su doble falla explícitamente si se invoca. No se declara integración con las autoridades vivas.

Prueba el rollback de las cuatro definiciones en la instancia local y comprueba restauración del cuerpo original de la guardia y ausencia de wrappers. Luego aplica la fuente completa en ese entorno desechable y prueba validación, errores, rechazo antes de record, readback, replay idempotente, ACL y hash. No retira COMMIT por regex: extrae la envoltura transaccional exterior exacta. BEGIN/ROLLBACK de DDL en Supabase sigue prohibido.

El archivo pg01_receiver_base_local_20261023.json conserva resultados locales y hashes de la migración y dependencias. Sus IDs son fixtures, no recibos operativos. El hash del runner se registra junto a esa evidencia.

## Ocho familias del plan: alcance real de esta entrega

| Familia | Evidencia de esta base | Pendiente del receptor |
|---|---|---|
| N1: seis campos faltantes / 06-oct | Fixture sintético con campo obligatorio omitido y record rechazado | Recuperar los bytes históricos y ejecutar la variante exacta; no se atribuye procedencia histórica al fixture |
| N2: matriz vacía / 07-oct | Fixture sintético, PROGRAMMING_SCOPE_FRONT_MATRIX_INCOMPLETE | Variante histórica exacta |
| N3: cero READY / 09-oct | Caracterización: un snapshot NEED_MORE_EVIDENCE sin READY puede ser VALID en forma | Gate de admisión ≥1 READY; no tratar VALID como ACCEPT |
| N4: recibo esperado ausente | Id, hash o schema esperado nulo → guardia false | Rechazo externo del emisor |
| N5: stale | Canonical record rechaza dependency drift del catálogo local; guardia histórica puede seguir true | Consumir decisión de CURRENTNESS_AUTHORITY en admisión; no sustituirla por fecha antigua |
| N6: autoridad alterada | Contexto alterado conservando hash → guardia false | Autoridad/fingerprint autoconsistente pero vencido requiere comprobación independiente |
| N7: scope equivocado | Validador verifica matriz/depencias y preserva PARTIAL_READY válido | Gate del scope SOLICITADO, ausente de firmas SQL extraídas |
| N8: pérdida / recibo distinto | Id/hash/schema distintos y latest mutable → guardia false | Proyección lossless y digest de la proyección |

No se declara «8/8 del receptor». Los resultados de pruebas de forma/guardia no cierran las familias pendientes. Tampoco se consume un snapshot positivo real ni se persiste un recibo PG-01. Los prints PASS de las regresiones preexistentes, si se ejecutan, solo describen esas pruebas locales.

## Emisor: diseño pendiente de implementación (2A.c)

Un emisor de lectura debe consumir esta base junto con currentness, scope solicitado, paridad, C4 y suficiencia C7. ACCEPT solo después de todas las verificaciones; repetir con entradas y decisiones pinneadas debe conservar el recibo sin redescubrir.

Siete campos requeridos de PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1:

| Campo | Fuente |
|---|---|
| context_id | Resultado que coincide con el handoff exacto |
| context_sha256 | Hash canónico del contexto completo, recomputado y cotejado |
| snapshot_schema_digest_sha256 | Contrato pinneado por el productor |
| receiver_schema_digest_sha256 | La misma versión contractual consumida por receptor; paridad obligatoria |
| material_projection_sha256 | Proyección efectivamente validada y serialización reproducible |
| validated_material_paths | Array de rutas realmente verificadas |
| verdict | ACCEPT o BLOCK |

schema_version identifica la envoltura; no es un octavo campo de negocio agregado. El marco técnico y la evidencia por scope requieren una envoltura revisada compatible, sin modificar silenciosamente el contrato de siete campos. No completar rechazos tempranos con hashes ficticios o null no autorizados; devolver diagnóstico tipado sin recibo completo cuando no pueda construirse legítimamente.

D7 decide persistencia de I0. No crear otro almacén ni usar record_v1 como si guardara el recibo del consumidor: guarda snapshot A9.

## Límites de gobernanza y siguiente paso

Sin hosted apply, activación, ready-to-merge o merge. La consulta de encaminamiento de la futura operación DB devolvió BLOCK_SCOPE_SEMANTICS_UNATTESTED; no se ejecutó ninguna escritura DB ni se usó esa respuesta como admisión. El trabajo actual es preparación local y PR draft autorizado, admitido expresamente como desarrollo local por CLAUDE.md. Cualquier ejecución operativa posterior necesita la ruta canónica y sus gates.

Próximo paso: implementar emisor y gates de admisión; C4, C6 y C7 siguen sin cerrar. Revisión independiente pendiente. No declarar P1/I0 ni PG01_CONSUMED_AND_RECONCILED por este PR.

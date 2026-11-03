# PG-01 · Base SQL y emisor de lectura candidato

Estado: candidato de fuente, PR draft #3135. Sin apply, merge o activación.
Paulo autorizó continuar sin Claude el 23/10/2026. Revisión independiente pendiente.

## Estado del plan

| Paso | Estado de esta entrega |
|---|---|
| 2A.a | Implementado como fuente: tres funciones #1912 y guardia corregida #2306 en una migración; no instaladas |
| 2A.b | Ocho familias probadas con casos sintéticos locales; tres históricos exactos también rechazados. No acredita calificación operativa |
| 2A.c | Emisor de lectura implementado; siete campos ACCEPT/BLOCK, sin persistencia |
| 2A.d | Paridad del digest comprobada en el emisor; no sustituye el acuerdo C1 con el productor |
| 2A.g | Positivo sintético ACCEPT de frontera; execution_allowed=false |
| 2A.h | Resultado y recibo idénticos al repetir inputs/decisiones exactos, sin redescubrimiento |
| C4 / 2A.e | Validador integrado al resultado/proyección local; admisión operativa pendiente |
| C7 / 2A.f | Validador integrado al resultado/proyección local; acuerdo A9/readback pendientes |
| C6 persistencia / I0 | Pendiente: D7 y positivo real admitido de PR2 |

ACCEPT aquí significa únicamente SOURCE_ONLY_READ_ONLY_BOUNDARY. El resultado exterior conserva execution_allowed=false y pending_gates con C4, C7 y persistencia C6. No equivale a P1, autorización de programación, PG01_CONSUMED_AND_RECONCILED ni recibo operativo admitido.

## Base SQL

Una única migración extrae las tres funciones de contexto de #1912 y reemplaza la guardia con #2306. Conserva sus cuerpos exactos. REVOKE EXECUTE FROM PUBLIC sobre las tres funciones nuevas las mantiene owner-only. No añade llamadores; conserva ACL del guard original.

Fuentes:
- #1912 @ 78030d6b8ea51f61807b8bc005ee9386a901a82a: 20261007183500_programming_context_snapshot_runtime_guard_v1.sql, blob eae0d12e2d93f7d6e65be977c3c54541029c3ae6.
- #2306 @ cb7f1564d48a01448589b04b8c1bb040e7fee291: 20261012094600_analysis_a9_pg01_receipt_digest_guard_fix_v1.sql, blob 1aaabfe817cccdbff6e025af0f1c3c648ffa295f.

Nombre con prefijo MANAGED_PREFIXES programming_context_snapshot_runtime_guard_. Paths con familias fijas MIGRATION y PROGRAMMING_AGENT_TESTS. No changeset manifest mientras el diff permanezca así.

El wrapper record pertenece al productor A9 y no es llamado por el emisor. No hay nuevo almacén, snapshot runtime, Router ni cambio de contracts SOURCE_ONLY_CANDIDATE.

## Emisor y puertos de lectura

programming_pg01_receiver_v1.py agrega ReadOnlyReceiver, SqlReadPort y CanonicalCurrentnessPort sobre las piezas existentes. No abre conexiones ni acepta credenciales/URL de DB. No activa un consumidor ni una operación.

SqlReadPort ejecuta una única SELECT fija parametrizada. El adaptador de DB debe usar conexión/transacción de solo lectura. La SELECT une resolve, validación y guardia en una sola lectura. No hay referencia a record como operación ejecutable del emisor.

El handoff esperado es independiente del readback: id, hash, digest del contrato, consumidor, sujeto y as-of. Resolve consulta por consumidor/sujeto/fecha, por lo que RESOLVED solo se usa después de la guardia y el cotejo de identidad exacta. Contextos ausentes, hash/schema distintos, campos desconocidos y payload inválido bloquean antes de emitir ACCEPT.

El emisor:
1. Carga una vez los bytes del contrato y conserva el digest de esos mismos bytes.
2. Resuelve y verifica el contexto exacto mediante la guardia SQL corregida, incluido digest PostgreSQL del contexto completo.
3. Reutiliza validadores SQL y validate_programming_snapshot_payload_v1 de main.
4. Verifica package READY/PARTIAL_READY, al menos un READY, scope SOLICITADO READY, dependencias READY y frentes limpios. Nunca sustituye un scope solicitado bloqueado por otro disponible.
5. Delega vigencia a evaluate_authority de CURRENTNESS_AUTHORITY existente. El proveedor debe hidratar evidencia por contexto/scope desde fuentes confiables; no se acepta una decisión CURRENT escrita por quien llama.
6. Exige raíces completas para contexto, esquema, autoridad y fuente. Autoridad/esquema/contexto cambiados requieren reconstrucción; bounded_validation_required bloquea. Un cambio de revisión Git por sí solo no causa stale.
7. Produce una proyección conservadora con scope_id y el snapshot completo. Compara cualquier proyección propuesta contra esa representación exacta mediante el serializador/hash canónico existente; quitar una obligación o introducir cambios bloquea.
8. Emite resultado determinista, con gates aún pendientes y sin permisos de ejecución.

La proyección completa evita pérdida en esta versión; no es todavía la proyección mínima con presupuesto para el Worker. El proveedor operativo de currentness, su procedencia y wiring siguen pendientes: las pruebas usan el evaluador real con un proveedor de materiales sintéticos.

## Recibo de siete campos

schema_version identifica PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1. Los siete campos de negocio son:

| Campo | Origen |
|---|---|
| context_id | Contexto que coincide con handoff A9 esperado |
| context_sha256 | Hash completo comprobado/recomputado por SQL |
| snapshot_schema_digest_sha256 | Digest del productor, cotejado contra bytes del contrato |
| receiver_schema_digest_sha256 | Digest de la misma versión del contrato consumida |
| material_projection_sha256 | Proyección completa validada con canonical_sha256 existente |
| validated_material_paths | Rutas materiales realmente comprobadas |
| verdict | ACCEPT o BLOCK |

Digest de programming_entry_contract_v1.json: d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8. No es el hash del subobjeto JSON ni el del contexto persistido.

Scope, diagnóstico, currentness, nivel de admisión y gates pendientes están en la envoltura separada PG01_READ_ONLY_BOUNDARY_RESULT_V1. El emisor no modifica el contrato de recibo de main.

Un fallo temprano que impida identificar y validar el contexto devuelve BLOCK con receipt=null, sin hashes ficticios. Un fallo posterior sobre un contexto/proyección identificados produce un recibo BLOCK completo; su hash siempre identifica la proyección completa retenida, no una propuesta con pérdida. Ni la envoltura ni el recibo se persisten en BD.

## Ocho familias negativas

| Familia | Comprobación local |
|---|---|
| N1: campos obligatorios ausentes | Sintético con seis campos omitidos; histórico exacto del 06-oct también BLOCK |
| N2: matriz vacía | Sintético aislado con matriz vacía BLOCK; histórico del 07-oct BLOCK en un control anterior |
| N3: cero READY | Sintético de forma válida pero cero READY recibe NO_READY_SCOPE; histórico del 09-oct BLOCK en un control anterior |
| N4: recibo esperado ausente | Id/hash/schema ausente o malformado bloquea; sin consulta si el esperado no es válido |
| N5: stale | Evaluador canónico produce STALE_AFFECTED; UNKNOWN_FAIL_CLOSED y prueba compatible con validación acotada pendiente también bloquean |
| N6: autoridad alterada | Hash esperado incompatible y fingerprint de autoridad cambiado (incluso compatibilidad declarada) bloquean |
| N7: scope equivocado | Scope ajeno o S2 BLOCKED de un PARTIAL_READY no se acepta ni se sustituye por S1 |
| N8: pérdida / recibo distinto | Proyección con obligación eliminada, id/hash/schema distinto o resolución mutable bloquean |

Los tres históricos fueron obtenidos por Supabase RO y reproducidos exclusivamente en Postgres local. Sus context_sha256 originales se recomputaron y coincidieron antes del replay. Los tres fallan primero con PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING; no se atribuye al histórico 07-oct una ejecución aislada del guard de matriz ni al 09-oct la del guard cero READY. Esos controles se aíslan con sintéticos.

Los bytes históricos no se incorporan al repo. La evidencia guarda id/hash/fecha/código; el export temporal es solo input externo de pruebas y se retira después de la ejecución.

## Reproducir

```bash
python3 sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/run_programming_pg01_receiver_base_v1.py --allow-local-docker
```

Agregar --sudo-docker solo si el host lo necesita. Para replay histórico, agregar --historical-input /ruta/export-ro.json con las filas exactas id/hash/decided_at/context_payload obtenidas por RO. Sin export se ejecuta la base y las ocho familias sintéticas; no se afirma replay histórico.

Contenedor postgres:17.6 único, desechable, sin red externa ni puertos, datos tmpfs, eliminado en finally. Las SELECT del emisor se ejecutan bajo BEGIN READ ONLY. La preparación de fixtures y record se ejecutan solo en ese Postgres local.

Reutiliza cuerpos canónicos de DECISION_CONTEXT_ASOF de 20261004144500_t_decctx_decision_context_asof_v1.sql. El catálogo de autoridades es sintético. La rama typed_evidence no está soportada por el bootstrap y su doble falla explícitamente si se llama. Ninguna prueba califica el proveedor operativo de currentness.

pg01_receiver_base_local_20261023.json contiene resultados y hashes de migración, runner, emisor, pruebas, fixture y dependencias. Los IDs sintéticos de pruebas no son recibos operativos. Las regresiones main se ejecutan aparte y no acreditan activación.

## Gobernanza

Solo desarrollo local y PR draft autorizados; no hosted apply, ready-to-merge, merge o activación. La ruta de la futura operación DB previamente devolvió BLOCK_SCOPE_SEMANTICS_UNATTESTED; no se usó como admisión y no se ejecutó ninguna escritura Supabase. Cualquier operación posterior necesita Router → ACTUALIZACION_DB_LF → PR → PASE → Merge Train.

Siguiente paso: C4 y C7, proveedor operativo admitido de currentness y persistencia según D7. Revisión independiente pendiente; no cierre P1/I0.

## Revisión posterior local

PG01_C4_C7_LOCAL_REVIEW_V1.md documenta la corrección de currentness malformado y los validadores estructurales puros de C4/C7. No están conectados para quitar pending_gates. La nueva evidencia local es independiente del archivo previo de 97 comprobaciones. No se publicó este incremento ni se aplicó en Supabase.

## Integración local posterior de C4/C7

PG01_PREPLANNING_INTEGRATION_V1.md describe SourcePreplanningReceiver: marco y suficiencia ligados al contexto, preservados en la proyección y en su hash, sin ampliar el recibo de siete campos. Se mantiene el consumidor base para la frontera de lectura. 41 tests unitarios y 101 comprobaciones SQL locales; sin CI del incremento ni gates operativos cerrados.

## Currentness técnico posterior

PG01_TECHNICAL_CURRENTNESS_V1.md documenta TechnicalCurrentnessPort y el enlace al evaluador canónico para los pins C4/C7. Mantiene las restricciones operativas; sin proveedor calificado, presupuesto real, acuerdo A9 ni readback. La regresión actual es 60 tests unitarios y 106 comprobaciones SQL locales.

## Lector exacto de fuentes

PG01_EXACT_ARTIFACT_READER_V1.md describe el lector Git/RO por identidad exacta, integrado a C4 en pruebas, y el readback de fuentes reales. 76 tests unitarios y 111 comprobaciones SQL locales. La lectura verificada no acredita admisión del proveedor ni sustituye los inputs operativos faltantes.

# PASE — alcance local, solución de reglas y validación transversal tardía V1

Estado: **CANDIDATO / PR, sin activación**. Alcance: plan 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1'; no cambia fases ya DONE, workflows, required checks, deploy ni producción.

Autoridad de ejecución: plan y decisiones vigentes en Supabase; este documento establece un criterio de adopción que debe ligarse al plan bajo su mecanismo gobernado antes de llamarse vigente. Tarea de integración: [F09-X17 (#2049)](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/2049).

## Regla fundamental: nunca una validación obligatoria sin solución

Para cada condición **obligatoria** debe existir un binding comprobable:

| Campo | Exigencia |
|---|---|
| Identidad | `rule_code`, unidad propietaria y capa `LOCAL` o `INTEGRATION_LATE` |
| Implementación | `validation_code`/capability existente, handler verificable y `validation_input` explícito; no inferencia por título |
| Veredicto | Expectativa `PASS`/`FAIL` tipada; `UNKNOWN` no es `PASS` |
| Solución | Una ruta concreta `AUTO_RESOLVE`, `HUMAN_DECISION` o `BLOCK` con causa raíz y owner; `CHECK_ONLY` no basta para un requisito |
| Evidencia | Positivo y negativo del procedimiento + recibo **nuevo** de la ejecución exacta, head/source/currentness |
| Cierre | Solo juez de su propio dominio marca el control local. Resolver ejecutado ≠ PASS: exige revalidación |

La ausencia de handler, input, prueba negativa, currentness, ruta de resolución o capacidad actual genera `UNBOUND_REQUIRED_RULE` y **no admite DONE**. Si falta la capacidad, crear un ítem atómico por **procedimiento distinto**: especificación de inputs/PASS/FAIL, implementación, pruebas positivas y negativas, prueba de fallo, calificación y binding. Nunca un validador nuevo para otro path/tabla/versión con el mismo procedimiento. **No inventar un resolver automático**: en el catálogo de Programación no hay ninguno ACTIVE al emitir este documento.

Se reutilizan procedimientos, NO resultados. Un PASS de una unidad o ejecución anterior no es evidencia del checkpoint actual. Las decisiones previas se consideran solo si son vigentes por identidad y momento `as-of`, nunca por simple herencia.

## Fronteras de evaluación

| Momento | Owner y responsabilidad | Se evalúa | No se evalúa |
|---|---|---|---|
| A. Unidad local F04–F09 | El control/unidad que produce un efecto | Su contrato funcional, entradas propias, expected result, evidencia exacta, pruebas negativas de su lógica | Estado de otras unidades, coordinación, arrastres, transformación del transporte, seguimiento de recibos en receptores |
| B. Orquestador | PASE/POST-PASE existente | Elegibilidad para iniciar, dependencias como **precondiciones de agenda**, dispatch y autorización de invocación | Reejecutar pruebas de dependencias o declarar PASS de controles |
| C. Integración tardía **F09-X17** | Una unidad de verificación transversal, no un nuevo orquestador | Bordes entre unidades, handoff, versiones y decisiones `as-of`, identidad de run/head, causalidad, idempotencia, duplicados, transporte y receipts de receptores | Recalcular el dominio funcional, repetir DDL o tests locales |
| D. Agregación F09-016 y cierre F10 | Jueces existentes | Consumir veredictos locales + veredicto de integración y cerrar solo con fuentes current | Activar checks ni producir pruebas faltantes |

La dependencia A -> B **solo** habilita que B empiece cuando A tenga estado admisible; no obliga a B a inspeccionar las validaciones internas de A. La integridad del borde A -> B se prueba únicamente en F09-X17, con recibos de ambos extremos.

## Reutilización concreta, sin fork semántico

- `programacion.programming_validation_registry`: `PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1` para invariantes textuales; `PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1` para integridad de bytes; `PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1` para estructura/catalogo. Cada uno requiere nuevo input y nuevo receipt por ejecución. Catalog y pruebas: `docs/programming/PROGRAMMING_VALIDATORS_AND_RESOLVERS_GUIDE_V1.md`.
- Para controles funcionales usar las capacidades **propias**: `MIGRATION_SOURCE_PARITY` para paridad, `RUNTIME_DEPLOY_VERIFICATION` para runtime, checks específicos de contratos/observabilidad que ya tengan owner y ruta; los tres validadores de Programación **no sustituyen** sus jueces.
- Para F09-X17 reutilizar `CONSUMER_ADMISSION` (admisión y receiver receipt), `CAUSAL_EFFECT_LINEAGE` (causalidad a efecto receptor), `DECISION_CONTEXT_ASOF` (condición/decisión temporal), `CURRENTNESS_AUTHORITY` (frescura), `EVIDENCE_LEDGER` y `FINAL_EVIDENCE` (recibos y manifest). Resolver capabilities y versiones **dinámicamente** por registro, verificar readback. No crear copias de estas semánticas.
- `F09-013` mide tiempos y coste de transporte; `F09-015` provee observabilidad y reutiliza fuentes nativas bajo su F09-X15. F09-X17 se limita a **consistencia entre capas**, no duplica métricas ni crea tablas.

## Criterios de separación de las unidades pendientes

1. **F07-X01**: valida solo secuencia funcional del Train, autorización sobre final head, checks pre-apply y emisión del recibo; no comprueba el consumo transversal del recibo (F09-X17). D1–D3 mandan sobre textos antiguos del work item hasta que haya binding canónico de la nueva versión.
2. **F07-X02**: valida la **revalidación única del main actual** de D5 y cierre de D6; no regresa a auditoría commit-por-commit. R01 runtime es precondición propia. R02–R05 siguen deuda clasificada, no se importan como fallo de un control ajeno. Paridad PASS se exige en F09-X16 según D6.
3. **F07-X03**: valida contrato de operación separada para deploy del worker según D4; no reutiliza el refresco del perfil como si fuera deploy.
4. **F09-X16**: comprueba su propia secuencia de reactivación por control, en shadow primero; F09-X17 verifica la coherencia de los handoffs, sin invadir la autorización.

## Unidad tardía F09-X17 (nueva tarea, sin nuevo engine)

**Posición:** después del cierre local de F07-X01/X02/X03 y evidencia F09-013/014/015; inmediatamente antes de F09-016 y los jueces F10. Debe incorporarse como work item y plan unit gobernados tras verificar que el plan mantiene su DAG y su presupuesto. No tocar units DONE.

**Inputs obligatorios:** snapshot de plan exacto; lista de cruces *realmente aplicables* (productor, receptor, capacidad, versión, requiredness); recibos actuales y sus identificadores `run_id`, `exact_head_sha`, digest; temporalidad `as-of`; salida de admission y causal lineage; taxonomía de fallo y owner.

**PASS:** para todo borde requerido, dispatch y receptor comparten ejecución/versión/plan/head permitido; decisión temporal vigente y compatible; no duplicación, omisión ni cambio semántico en transporte; recibo receptor verificable; ningún `REQUIRED` queda `BLOCK`, `HOLD` o `UNKNOWN`. Para bordo no aplicable existe evidencia explícita de no aplicabilidad.

**FAIL/BLOCKED:** unión inconsistente, old-condition no vigente, receptor sin receipt, transporte alterado, duplicado o versión stale. Abrir **un ítem de remediación por causa raíz**, asignado a su owner. No rerun masivo ni pasar a DONE por contar artefactos.

**Salida:** un veredicto tipado de integración `PASS|BLOCKED|UNKNOWN` con un manifest de bordes y referencias de evidencia. `F09-016` exige `PASS` para declarar `PRE_ACTIVATION_QUALIFIED`; F10 hace lectura terminal separada.

## Prueba de adopción antes de habilitar esta política

1. Inventory de **todas** las reglas obligatorias de unidades pendientes y mapping `rule -> owner -> handler/current version -> input -> positive/negative proof -> fail route -> fresh receipt`.
2. Negativa de regla sin solución => `BLOCK`; negativa de validador con PASS histórico sin fresh receipt => `BLOCK`.
3. Negativa de intentar evaluar arrastre/transporte dentro de un juez LOCAL => rechazado por alcance.
4. Positivo local: solo cambia el estado de su unidad; ninguna dependencia se revalida en cascada.
5. Positivo/negativo F09-X17: interfaces requeridas con 2 extremos; versión vieja o handoff ausente => `BLOCKED`.
6. Prueba DAG/orden: F09-X17 precede F09-016 y F10; ninguna unidad DONE cambia.
7. Revisión de activación independiente: `if:false`, ruleset, deploy, DDL y producción **sin cambios**.

**Estado del presente PR:** materializa el contrato candidato y su trazabilidad; **no** prueba que las 150 unidades ya estén binded, que F09-X17 exista en Supabase ni que PASE esté autorizado para reactivación. El alta canónica y las pruebas con evidencias de ejecución actual son trabajo posterior con owner y readback.

# LF Input Governance — G4 contrato verificable de autorización del alcance de reglas v1

> **ADENDA G4 (28-10-2026) — REGISTRO EXISTENTE IDENTIFICADO:** La gobernanza central de decisiones humanas **ya existe** en `private.lf_human_decision_classes_v1`, `...classification_rules_v1`, `...route_policies_v1`, `...authority_policies_v1`, requests y receipts. Inventario: 7 clases ACTIVE, 11 clasificadores ACTIVE, 7 rutas PENDING_AUTHORITY (0 ACTIVE), 0 políticas de autoridad y 0 requests/receipts. Específico IG: las tres rutas actuales son para `INPUT_GAP_PROPOSAL`, no para cambio de scope de regla N-4. **NO crear tabla/motor paralelo**. Contrato y cinco ensayos read-only en [auditoría de registro real G4](./IG_G4_REGISTRY_REUSE_REAL_AUTHORITY_GAP_20261028.md). La anterior afirmación de que faltaba un circuito de decisiones debe interpretarse como que **falta vinculación y autorización de scope por regla**, no que falte el registro central. G4 sigue NO_VERIFICADO.

**Fecha:** 2026-10-28. **Naturaleza:** especificación de integración con contratos existentes, no un motor nuevo, no autorización concedida. **Estado:** `G4_NO_VERIFICADO`, `G5_NO_RECLASSIFY`. Dev branch PR #3269; EKB consultado; sin Router, escrituras a Supabase ni merge.

## 1. Evidencia primaria actual: quién puede decidir y qué no está probado

- `public.lf_capability_registry` reconoce la capacidad `INPUT_GOVERNANCE` como `ACTIVE`, `owner_scope='LF_GOVERNANCE'`, `entry_guard_required=true`. Eso gobierna la **capacidad**, pero **no identifica por sí solo al aprobador competente de una regla de sesión, seguridad, marketing, etc.**
- Existe rol SQL `lf_governance_owner_v3` de tipo `NOLOGIN`, pero no se verificó un recibo de ese rol para un selector. La etiqueta `LF_GOVERNANCE` no equivale automáticamente al nombre de dicho rol.
- `programacion.fn_guard_human_decision` verifica ejecución, `head_sha`, `actor_identity` y `approval_ref`. Es una verificación de integridad y procedencia; **no basta para asegurar competencia de negocio**.
- `programacion.fn_guard_human_decision_authority_receipt` ata `HUMAN_DECISION` a un recibo con `execution_id/head_sha/subject_ref/subject_sha256` mediante `fn_assert_provenance_receipt`.
- `programacion.fn_guard_authority_attestation_insert` exige challenge vigente, rol requerido, nonce, head coincidente y una sesión externa de mínimo privilegio; esa ruta **no concede automáticamente ámbito sobre una regla**.
- `programacion.authority_challenges`: 7 desafíos históricos, ninguno vigente en el corte; ninguno requiere `LF_GOVERNANCE` o `programacion_human_authority`. `authority_attestations`: **0**. `human_decisions`: **0**; recibos `HUMAN_DECISION`: **0**.
- Los 14 selectores N-4 ACTIVE apuntan a eventos 19948/19951; ambos tienen `acceptance_declared=false`, `production_authorized=false`. Evento 19962 demuestra cierre **técnico** pero no aprobación de scope. No presumir revocación de selectores históricos por esta carencia de metadatos.

## 2. Contrato mínimo: paquete de decisión por regla y versión

| Campo del paquete | Fuente obligatoria | Control |
|---|---|---|
| `rule_ref`, `rule_definition_sha256` | Catálogo gobernado `lf_ops.reglas` (lectura canónica) | Debe existir versión vigente o candidata, según etapa; no aceptar hash autorreportado |
| `selector_sha256`, `scope_diff_sha256` | Selector propuesto, análisis de impacto independiente | Hashes verificables, alcance derivado de datos, no indicador `is_broad` del proponente |
| `consumer_code`, `target_context_contract` | Consumer binding IG y N-4 | Denegar consumidores no autorizados; no confundir consumer externo con `consumer_role` |
| `source_policy_refs`, `risks`, `negative_cases_sha256` | Curator + pruebas del Validator independiente | Mínimo prueba positiva, negativa y dato desconocido según naturaleza |
| `functional_owner_ref`, `competence_scope` | Autoridad existente, delegación rastreable | El owner de la capacidad NO reemplaza al dueño especializado; no inventar rol |
| `veto_refs`, `exception_conditions` | Seguridad/Legal si corresponde | Veto vinculante para restricciones no delegables |
| `decision`, `actor_attestation_ref` | Decisión humana y atestación legítima | Autoriza **solo** operación/alcance/versión vinculados |
| `authority_receipt_ref`, `head_sha`, `execution_id` | `provenance_receipts` + ledger de ejecución | Enlace exacto del recibo a contenido y actor |
| `effective_from`, `expires_at`, `revocation_ref` | Política de vigencia autorizada | Expirada/revocada = HOLD de nuevo alcance |

**El paquete es conceptual y puede residir en un contrato existente que admita esos datos de forma gobernada.** No crear nuevo ledger, tabla ni enum hasta comprobar exhaustivamente que no hay formato/canal compatible.

## 3. Estados y transiciones propuestas (fuera de BD por ahora)

1. `PROPOSED`: hay descripción/selector nuevo; **no operativo**.
2. `EVIDENCE_REVIEWED`: Curator+Validator independientes y scope diff actualizados; todavía no aprobado.
3. `HOLD_AUTHORITY`: no se demuestra competencia, reto externo/recibo o vínculo exacto; no se expande.
4. `HOLD_CONFLICT`: reglas incompatibles, veto o excepción no competente; no se expande.
5. `APPROVED_FOR_GOVERNED_PUBLICATION`: consta decisión funcional válida vinculada a hashes, consumer, pruebas, límites y vigencia; se admite solicitar publicación.
6. `PUBLISHED`: solo cuando owner de migraciones/Router del carril posterior cumpla permisos, CI, source parity y readback en otra fase.

**Estos son nombres del documento, NO nuevos estados DB.** La coincidencia runtime N-4 nunca crea aprobaciones, y no llama LLM ni gerencia por pantalla.

## 4. Fichas de responsabilidad y precedencia sin enum cerrado

| Obligación | Actor competente | Restricción de separación |
|---|---|---|
| Investigar alcance y contraejemplos | Curator | No aprobar sus propias hipótesis |
| Verificar alcance y cobertura calculada | Validator independiente | No reutilizar resultado del Curator como PASS propio |
| Aprobar interpretación funcional, alcance y excepciones | Dueño de la regla con delegación válida; gerencia dentro de su competencia | No asumir rol desde nombre de capability |
| Vetar degradación de controles normativos | Seguridad/Legal o autoridad normativa pertinente | El veto no se supera con score alto ni rol técnico |
| Registrar/validar recibos | Mecanismo de `authority_attestations`, `human_decisions`, `provenance_receipts`, sujeto a homologación | El recibo técnico no demuestra competencia de negocio sin vínculo |
| Publicar selector y comparar readback | Autoridad técnica gobernada, **fase posterior** | No ejecutar por esta rama de diseño |

**Precedencia:** una relación de autoridad exige referencia y delegación observables. Si dos fuentes son incomparables, HOLD; no escoger pantalla sobre shell, último evento, mejor puntuación o primera fila SQL.

## 5. Admisión fail-closed: 12 pruebas concretas

| ID | Prueba | Salida aceptable |
|---|---|---|
| A01 | Regla conocida, selector hash correcto y aprobador competente con recibo | `APPROVED_FOR_GOVERNED_PUBLICATION` (aún no publicado) |
| A02 | `provenance.authority` en JSON sin recibo | HOLD |
| A03 | Referencia a evento 19948/19951/19962 sin aprobación expresa del scope | HOLD |
| A04 | `human_decisions` con actor_identity pero sin competencia de la regla | HOLD |
| A05 | Recibo atado a HEAD antiguo o a otro selector | HOLD |
| A06 | Regla CANDIDATO o selector UNRESOLVED para consumo operativo | HOLD |
| A07 | Alcance amplio autoetiquetado como local por productor | HOLD hasta cobertura independiente |
| A08 | Expansión realmente amplia, firma competente solo para un módulo | HOLD |
| A09 | Veto de política superior no delegable | HOLD/VETO |
| A10 | Aprobación condicionada, condición ausente, expirada o revocada | HOLD |
| A11 | Nueva pantalla compatible **dentro del selector ya autorizado** | MATCH automático sin nueva gerencia por pantalla |
| A12 | Cambio de fuente, consumer, regla o selector sin nuevo recibo aplicable | HOLD de la ampliación |

La implementación existente de JS con test doubles cubre parte de A01–A12 **a nivel de referencia**; no sustituye pruebas reales de autoridad y revocación.

## 6. Gate G4 de cierre

**NO-GO hasta** identificar exactamente: (a) fuente/owner de cada regla y delegación, (b) canal externo válido de actor, (c) decisión/recibo exactos, (d) alcance derivado independientemente, (e) veto y vigencia, (f) prueba real positiva y negativa, (g) integración con publicación del selector sin rutas paralelas.

G4 **no se resuelve** copiando el valor `OWNER_AUTHORIZED_GOVERNED_MIGRATION`, usando `lf_governance_owner_v3` por su nombre ni registrando un recibo ficticio. Dejar `NO_VERIFICADO` hasta contar con evidencia.

## 7. Estado G3 en paralelo

Verificador Python ajustado para exigir socket Unix privado y data directory local desechable, 27 vectores, baseline 14 × 58, comprobación de 52 matches y lectura independiente post-ROLLBACK. **NO EJECUTADO** en PostgreSQL porque el contenedor no tiene `psql`/`postgres`; `apt-get update` falló resolución de `deb.debian.org`. No suplantar PostgreSQL con motores distintos.

**Evidencia referenciada:** `IG_G4_AUTORIDAD_SCOPE_FUENTES_Y_BRECHA_CONTRATO_V2_20261028.md`, `ig_n4_scope_authority_readonly_audit_20261028.sql`, `ig_n4_isolated_pg_verifier_20261028.py`, EKB transversal y contrato N-4 vigente.

## 8. Decisión arquitectónica posterior: una ejecución lógica de extremo a extremo

**Dirección del owner — 28/10/2026.** Se simplifica el contrato anterior. Este apartado rige la **orquestación** G4 de nuevos cambios, sin alterar ACL, políticas actuales, SQL vivo, ni redefinir el Validator de IG. **Diseño aceptado; runtime aún no integrado.**

- **Un solo run lógico por solicitud**: Router, resolución de canal/ruta y selección determinista, selección semántica cuando proceda, Input Governance, Curator, Validator y resultado pertenecen a la **misma ejecución raíz**. Usar la identidad canónica de ejecución y su `run_id` de IG asociado mediante correlación verificable; no afirmar que un `execution_id` texto de Router y un `run_id` bigint de IG tengan idéntico tipo o valor. No crear otro run raíz para G4, Curator, Validator, cada pantalla o cada familia.
- **Pasos secuenciales, tiempos flexibles**: cada paso avanza a partir de la salida admitida del anterior; persistir checkpoint/idempotencia en contratos existentes. Una espera externa no reinicia el Router ni duplica fases: se conserva el run y se reanuda **en el paso pendiente**. No confundir un solo run con una única transacción SQL larga, locks durante esperas, un proceso en ejecución constante o un polling periódico.
- **Identidad al ingresar**: reutilizar la identidad y contexto admitidos por el Router; Curator y Validator mantienen sus identidades/roles diferenciados y evidencia del trabajo que efectivamente realizan, **sin reautenticar cada paso**. En acciones privilegiadas o cuando cambia el contexto relevante, los guards canónicos verifican vigencia, permisos y recibo exacto, sin inventar una cadena de identidades duplicadas.
- **G4 es una condición del mismo run, no otro pipeline**: solo si el Validator entrega un **cambio nuevo de selector/alcance** que requiere autorización funcional, el mismo orquestador aplica el gate G4 por fuente y ámbito verificados. Para evaluación normal o pantalla nueva dentro del selector ya aprobado, G4 es `NOT_APPLICABLE` y se continúa sin aprobación humana. Ausencia de competencia → mismo run en espera/bloqueo tipado; no transformar esa ausencia en PASS.
- **Reanudación segura**: al recibir autorización tardía, comprobar que corresponde a esa misma regla, operación, selector y versión vigente; si cambian los materiales, invalidar únicamente las etapas afectadas según el contrato existente y recalcular sin lanzar un nuevo run raíz. No copiar recibos entre ejecuciones.
- **Fronteras y resultado**: validación de contenido pertenece al Validator vigente; autorización funcional al registro humano existente solo cuando corresponda; publicación por su guard técnico autorizado. Retornar un estado/resultante único del run que distinga `EVALUADO`, `PENDIENTE_DE_AUTORIDAD`, `BLOQUEADO` o `PUBLICACIÓN_ADMITIDA` **solo como descripciones del contrato, no enums nuevos de BD**. No publicar automáticamente por pasar tests sandbox.
- **Fuera de alcance de esta actualización**: no activar `RULE_APPLICABILITY_CHANGE` ni rutas `PENDING_AUTHORITY`; no cambiar reglas, permisos o selectores históricos; no hacer G5; no ejecutar Story Creator en el procesamiento de reglas; no imponer segunda revisión PG P10, nuevas colas o workers.

**Criterios de integración del run único (a comprobar antes de activarlo):** (1) identidad/correlación raíz estable en todas las fases; (2) Curator y Validator distintos, sin autoaprobación; (3) G4 omitido explícitamente cuando no hay cambio de alcance; (4) suspensión y continuación sin nuevo run ni tareas duplicadas; (5) actualización del selector bloqueada sin competencia; (6) readback del estado/resultante raíz sin convertir aprobación funcional en deploy. Son seis escenarios del mismo flujo, no seis nuevas aprobaciones ni checkpoints.

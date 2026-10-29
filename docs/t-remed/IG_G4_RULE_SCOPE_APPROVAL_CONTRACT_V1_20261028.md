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
| `authority_receipt_ref`, `head_sha`, `ig_run_id` (solo trazabilidad) | Recibo de autoridad canónico y run IG vigente | Autorización exacta por contenido y competencia; no atar al perfil ni exigir recibo por cada run |
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

## 8. Contrato ratificado: el run nace en Input Governance

**Corrección owner, 28/10/2026.** El Router resuelve el destino y entrega el contexto; **no crea el run de Input Governance**. El run IG se materializa en `programacion.input_readiness_runs` al iniciar el trabajo de IG, mediante el Curator gobernado, y el `run_id` devuelto identifica su ciclo hasta el resultado.

```text
Router (solo enruta, fuera del run IG)
  -> entrada Input Governance
     -> crear/reutilizar run_id en input_readiness_runs
        -> Curator (mismo run_id)
        -> Validator (mismo run_id)
        -> G4 solo si hay un cambio nuevo de alcance (mismo run_id)
        -> resultado/continuación del mismo run_id
```

**No hay ejecución padre obligatoria.** Un `execution_id` de `EJECUCION_PERFIL_LF` o del Router es identidad de su propio consumidor; no es la raíz del run IG ni se requiere para autorizar el alcance de una regla. El registro `public.lf_operation_execution_steps/input_validate` puede contener evidencia de qué `run_id` consumió el perfil, pero es correlación del **consumidor**, no autoridad ni prerrequisito de G4.

- **Creación y reanudación.** `fn_input_governance_curator_materialize_v1` selecciona estrategia; `BOOTSTRAP/REBIND/RECURATE` crean un run IG y `NOOP` recupera el run actual sin duplicación. El Validator recibe `p_run_id bigint`. Si un paso queda pendiente, continúa el mismo run; si la política actual exige un run nuevo por cambios materiales, se conserva la filiación histórica por `supersedes_run_id`. No equiparar un run lógico con una única transacción SQL o un worker permanente.
- **Identidad y controles.** La admisión existente de IG comprueba consumidor, identidad propia de Curator/Validator y currentness donde corresponda; G4 **no reautentica esas etapas ni repite el control de identidad**. Solo revisa la autorización funcional de la nueva ampliación antes de publicar. Si no hay cambio de alcance, G4 es NOT_APPLICABLE.
- **Autorización reutilizable por ámbito.** Una decisión válida sobre una regla+versión+selector+consumidor puede seguir aplicando en evaluaciones posteriores durante su vigencia. No exigir que el recibo de autoridad posea el mismo `run_id` que la evaluación ni un `execution_id` de perfil. El recibo se comprueba contra los materiales y la fuente competente, no contra una ejecución externa. Nuevas ampliaciones sin competencia probada permanecen HOLD.
- **Sin motores paralelos.** Reutilizar funciones IG, Validator, registro de autoridad y estado/continuación existentes. No crear tabla de correlación, nuevo run de G4, cola, estado DB ni aprobación humana por pantalla.

### Evidencia y cambios acotados

La definición vigente de `programacion.fn_input_governance_bootstrap_materialize_v2` inserta en `programacion.input_readiness_runs` con `status='CURATING'` y retorna `v_run` como `run_id`. `programacion.fn_input_governance_curator_materialize_v1` comprueba ese run y puede devolver un run reutilizado en estrategia NOOP. `programacion.fn_input_governance_validator_validate_v1` recibe el mismo `p_run_id`. Esas fuentes establecen el origen real del run; el readback histórico de un perfil que consumió run 949 no demuestra relación padre/hijo.

El probe `sandbox/lf_contract_gate_test/input_governance/ig_g4_authority_contract_probe_v1.py` dejó de exigir `execution_id`, `verify_run_binding` y coincidencia recibo↔run. Recibe `ig_run_id` positivo para identificar el contexto IG y valida **únicamente** fuente, selector, dominio competente, veto y recibo de autoridad por el ámbito solicitado. Su suite `test_ig_g4_authority_contract_probe_v1.py` pasó **24/24 pruebas sintéticas** en Python 3.13, con blobs exactos `199692ad7278d53924935de485b8061f205f4aae` y `ac7d63b0448e320397c2fe45b544ddd4ded716f8`. No se han conectado los verificadores reales de fuente y recibo; por tanto esto **no** certifica integración ni autoriza producción.

**Siguiente integración:** conectar la verificación de autoridad **solo en la frontera de cambio de alcance**, dentro del run IG existente, con los verificadores canónicos y sin crear otra ejecución. Mantener G5 sin reclasificación y EKB vivo pendiente de escritura gobernada.

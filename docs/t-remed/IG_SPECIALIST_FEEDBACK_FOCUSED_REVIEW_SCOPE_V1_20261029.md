# LF Input Governance — Revisión focalizada de observaciones de perfiles
**Fecha:** 2026-10-29 · **Estado:** diseño/evidencia DRAFT; **NO** habilitado en vivo.
**PR:** #3269 · **Owner de ruta:** Router ACT-0001 / EJECUCION_PERFIL_LF; IG mantiene autoridad de evaluación, no de promoción.

## 1. Decisión: dos operaciones que NO deben confundirse

**A. Revisión focalizada del hallazgo (READ / JUDGMENT):**
Un perfil especialista cuestiona una evaluación IG y adjunta run, pantalla,
familia, hash del snapshot y fuentes/razones. El Router recibe el resultado
del perfil y encamina una revisión autorizada a la especialidad competente.
El revisor consume el *run* ya existente, inspecciona la familia y sus
evidencias, y emite una de estas conclusiones propuestas:
- `MAINTAINED_WITH_REASON`: la evaluación previa se mantiene, con evidencia.
- `CORRECTION_CANDIDATE`: la objeción está sustentada y requiere resolución
  de autoridad/fuente antes de cambiar el resultado.
- `NEEDS_MORE_EVIDENCE`: aún no se puede probar la discrepancia.
- `OWNER_DECISION_REQUIRED`: se trata de una nueva regla material, no de
  una fuente ya existente que IG omitió.

Esta revisión **no crea run**, no ejecuta todas las familias, no invalida
el run anterior, no modifica reglas ni aplica permisos. El juicio no es una
evaluación canónica nueva. Debe volver al perfil que originó la objeción a
través del Router; conservar fuente, conclusión, razones y pendientes en
los artefactos/receipts existentes, sin inventar un segundo motor ni tabla.

**B. Recalculación y sucesión de un run (WRITE / VALIDATE):**
Solo si existe evidencia gobernada de cambio de fuente, corrección
canónica autorizada o invalidez demostrada, se entra por el runtime IG
autorizado con preflight EKB, Curator y Validator independientes.
El plan de afectación puede ser `SELECTIVE` **solo** cuando las dependencias
del cambio están resueltas con granularidad suficiente. Si no, no se
simula selectividad: resolver dependencias o usar la ruta completa existente
cuando esté expresamente autorizada. No publicar un PASS parcial.
La nueva evaluación debe conservar las 47 familias/universo vigente, las
fuentes versionadas, snapshot/hash, identidad del Curator, evidencias del
Validator y linaje `supersedes_run_id`. No sobrescribir filas del padre.
Cualquier familia reutilizada en un nuevo run necesita identidad/hash
apropiados para el hijo, prueba de vigencia y validación independiente:
**prohibido copiar un PASS o hash del padre como aprobación del sucesor**.

## 2. Proceso de decisión sin bucles

1. **Perfil:** emite hallazgo de su propia disciplina y feedback tipado
   `IG_PROFILE_FEEDBACK_V1`; no se salta el Router ni llama directo a IG.
2. **Router:** reentra Stage1 y selecciona a la competencia de revisión
   gobernada; los hints del perfil son asesoría, no autoridad de routing.
3. **Binding:** validar que el perfil realmente consumió el IG run en
   `EJECUCION_PERFIL_LF/input_validate` y que pantalla, familia y
   `source_snapshot_sha256` coinciden. Rechazar hash obsoleto,
   perfil/ejecución equivocados o permisos inventados.
4. **Triaging:** `UNSUPPORTED_DISAGREEMENT` no reabre IG;
   `NONCANONICAL_RULE_PROPOSAL` se encamina a dueño competente y
   queda `PROPOSED_NOT_CANONICAL`;
   `EVIDENCE_CHALLENGE` con referencias verificables activa
   `FOCAL_REVIEW_ONLY`, nunca `FULL_RECURATE` por sí solo.
5. **Juicio focal:** comparar evaluación específica con fuentes canónicas
   y contraevidencias, documentando si mantiene, propone corregir,
   requiere más evidencia o necesita aprobación. No confundir
   "familia COMPLETE" con decisión de negocio necesariamente correcta.
6. **Solo si hay cambio admitido:** obtener impacto por procedencia
   exacta en el grafo canónico. Resolver también dependencias aguas
   abajo y efectos transversales según selectores gobernados. No
   seleccionar familias por nombre del perfil ni enumeraciones hardcoded.
7. **Recuration:** conservar el contrato existente, ejecutor autorizado,
   validator independiente, trazabilidad de run padre/hijo y postchecks
   13×47. Si el impacto no puede demostrarse, `FAIL_CLOSED`, nunca
   una recuración ficticiamente selectiva.
8. **Retorno:** informar al perfil original la respuesta razonada, el
   estado y la evidencia. Si persiste un desacuerdo sin fuente nueva,
   registrar esa conclusión y detener el ciclo; no reabrir por insistencia.

## 3. Hallazgo comprobado en Supabase (run 949, pantalla 51)

Consulta exacta versionada en:
`sandbox/lf_contract_gate_test/input_governance/ig_specialist_focal_review_scope_readonly_20261029.sql`.

Resultado **12/12 PASS**, solo lectura:
- 47 evaluaciones; Validator PASS de las 47; 949 COMPLETED y no invalidado.
- 949 conserva vínculo histórico `supersedes_run_id=833`.
- `SESSION` posee una única fuente de tipo
  `SCREEN_CANONICAL_GRAPH` (pantalla 51).
- **38 familias** comparten esa fuente, incluyendo `SECURITY` y
  `MFA_OTP_SSO`; **37 familias** solo poseen esa referencia.
- Ello prueba que el source-ref a nivel de grafo completo **no tiene
  granularidad suficiente para concluir qué familias realmente cambiaron**.
  No se interpreta "38 comparten" como "38 necesariamente afectadas".
- `fn_input_freshness_delta` ya produce `family_impacts` por referencias
  de fuente, pero la referencia agregada del grafo se comparte.
- `fn_input_governance_recurate_source_stale_v1` itera todas las familias
  del universo para construir un sucesor y exige conteo de 47. Por ello
  **la recuración parcial aún NO existe como capacidad probada**.
- Los 12 PASS anteriores verifican baselines y límites existentes;
  **no son pruebas de recompilación ni de ejecución de nuevo algoritmo**.

## 4. Criterios exactos antes de habilitar recuración parcial

| Caso | Resultado exigido |
|---|---|
| Feedback sin run/familia/snapshot vinculado | BLOCKED |
| Discrepancia sin evidencia nueva | MAINTAINED/NEEDS_MORE_EVIDENCE, sin IG run nuevo |
| Nueva regla funcional propuesta | PROPOSED_NOT_CANONICAL, dueño/autoridad correspondiente |
| Objeción contra `SESSION` sin impacto probado | FOCAL_REVIEW_ONLY; no asumir afectadas solo `SESSION` |
| Cambio con dependencia material y fuente específica acreditada | Curator revisa foco+dependientes resueltos, Validator independiente |
| Cambio de fuente agregada `SCREEN_CANONICAL_GRAPH` sin subdependencias | BLOCKED_SELECTIVE_SCOPE_UNRESOLVED; resolución o recuración completa autorizada |
| Mismo run vigente + sin cambio material | Reutilización/NOOP |
| Cambio de versión/contrato/fuente/selección de autoridad | Fail closed y nuevo preflight; no copy/paste de PASS anterior |
| Nuevo run | 47 evaluaciones o universo contractual vigente, contexto y hashes coherentes, linaje histórico, validator nuevo |
| Repetición de objeción sin nuevos hechos | No abrir ciclo infinito |

## 5. Integración, alcance y gate

Este trabajo **no cambia** el diseño del Router: ya retorna resultados
tipados y continúa con nueva selección en ACT-0001. Tampoco modifica
`INPUT_GOVERNANCE_EXECUTION_CONTRACT.allowed_consumers`, selectores de
pantalla, semántica de GLOBAL, ACL, EKB, reglas canónicas o perfil.
Se conecta con
`docs/t-remed/IG_PROFILE_SPECIALIST_FEEDBACK_ROUTER_HANDOFF_V1_20261029.md`
y su SQL candidato aún no desplegado.

**Estado de ejecución:** diseño + baseline read-only PASS;
adaptación de runtime/Curator para persistencia verdaderamente parcial
**NO_IMPLEMENTADO / NO_VERIFICADO**;
revisión independiente de la nueva capacidad **NO_VERIFICADA**;
integración y G4/G5 **NO-GO**.
No fabricar una regla nueva ni una fuente granular ficticia para pasar
las pruebas.

**EKB vivo consultado antes de diseñar:**
`INPUT-GOV-CONSUMER-BINDING-001`;
`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`;
`CI-MIGRATION-SOURCE-PARITY-001`;
`IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001`.

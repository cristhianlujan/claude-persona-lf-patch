# PG-00 C3 · Contrato de publicación del catálogo STD (candidato)

Estado: **GOVERNANCE_SPEC_CANDIDATE / NO GO**. Este documento no constituye emisión, aprobación ni recibo de PASE/Train.

## Autoridad y procedencia

1. Fuente de decisiones: `transversal.decision_log`, 17 `ADR-PROG-STD-001..017` vigentes, lectura independiente exacta.
2. Fuente de criterios: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`, PG-00_C3 y PG-02_C1.
3. Fuente de A7: `analysis_material_front_coverage_contract_v1.json`; `EVIDENCE_DERIVED_OPEN_CATALOG`, nunca catálogo cerrado.
4. El owner de Fase 2 decide el contenido normativo y las correspondencias faltantes; el agente/programador prepara el candidato pero **no se autoautoriza**. El revisor independiente comprueba el readback y el mismo commit. El Merge Train aplica migraciones solo bajo PASE. Esta propuesta no asigna nuevos permisos.

## Artefactos necesarios para declarar una versión emitida

- Catálogo normativo de estándares **STD-*** legible por herramienta (JSON) y por humano/LLM (documento), ejemplos **OK/NO**, severidad, condiciones de activación por stack, versión y fuente por regla. Los ejemplos PG-02_C1 no sustituyen el catálogo.
- Mapa abierto frente→dominio separado, con reglas explícitas por clase A7, granularidad A2 y capas del stack; excepciones y `DATA_CONTRACT/AUD-02` resueltas por fuente; tipo A7 sin match **BLOCK** sin inferencia.
- Referencia y SHA-256 verificables del contenido canonizado, head commit exacto, versión de esquema, versión del catálogo, fuente ADR exacta, firma/decisión de owner y veredicto independiente. Sin digest o readback exacto **BLOCK**.
- Publicación coherente **en repositorio y esquema transversal de Supabase**, ejecutada exclusivamente mediante migración gobernada, PASE y Merge Train. Prohibido escribir directamente o marcar `PG-00_C3` terminado por existencia del draft.
- PG-02 consume solo una release con recibo del Train, lectura posterior y checks de integridad de esos dos lugares. Ningún campo `state=PG00_RELEASED` proporcionado por un llamador es prueba de autoridad.

## Máquina de estados de publicación

`DRAFT_NOT_RELEASED` → `REVIEWED_CANDIDATE` (readback, cobertura, aprobación explícita y revisión independiente) → `PASE_QUALIFIED` (evidencia exact-head) → `TRAIN_APPLIED` (recibo auténtico y migración) → `ACTIVE_READBACK_VERIFIED` (repo+BD idénticos, misma huella). La transición es **bloqueante** si se salta un estado o cambia la fuente. Revocación: `SUSPENDED` si hay drift, stale ADR, rechazo o fuente indeterminada; todos los consumidores dejan de autorizar.

## Checkpoints de salida

- **C3**: catálogo íntegro STD en dos formatos, versionado, digest estable, disponible en `transversal` y repo, lector PG-03/skills con huella, verificación de ejemplos OK/NO.
- **C1–C2 / C4–C11 PG-00**: seguirán independientes y pendientes hasta tener evidencias específicas.
- **PG-02_C1**: solo clasifica cuando existe mapa autorizado y cada scope/material front tiene regla y perfil; no reclasifica A2/A7.
- **PG-02_C5**: juicio independiente sobre salida exacta, distinto al autor del código.
- **Negativos obligatorios**: ADR faltante/stale/duplicada, mapeo desconocido, condición AUD-02 irresuelta, cambio A2, digest/head drift, recibo Train ausente, BD/repo divergentes, self-attestation, downgrade y replay.
 
## Registro de bloqueos actuales (29/10/2026)

El PR #3325 contiene solo ejemplos de mapeo, no un catálogo STD íntegro. No hay autorización publicada en `transversal` para ese mapa; tampoco existe evidencia de aprobación independiente, PASE, Train ni readback. Por tanto permanece en **draft y NO GO**. Nunca usar este documento como credencial de activación.

# SKILL_ANALISIS_RIESGO_CONTENIDO_LF — ACT-0056

**Estado:** CANDIDATO / READ_ONLY  
**Versión:** v0.1  
**Operation code:** ANALISIS_RIESGO_CONTENIDO_LF  
**Tabla de resultados:** lf_content_decisions  
**Alias legacy:** JUICIO_INTERPRETACION_ENGINE_V0_1_1

## Propósito

Evalúa si el contenido capturado de fuentes financieras peruanas es seguro para producción, requiere revisión humana (HITL) o debe bloquearse.

## Posición en el pipeline LF

```
ACT-0052/0054/0055 (Extracción)
  → ACT-0053 (Homologación)
    → ACT-0056 (Análisis Riesgo) ← AQUÍ
      → Generación de contenido
```

## Estructura

```
skills/analisis_riesgo_contenido_lf/
  SKILL.md
  README.md
  contracts/skill_run_contract.json
  schemas/decision_output.schema.json
  judges/mini_judges.md
  judges/final_skill_judge.md
  examples/good_bad_ambiguous.md
  evals/evals.json
  fixtures/corpus_eventos_198_201.json
  validators/validate_decision_output.py
  adapters/lf_content_decisions_adapter.md
  checklists/preflight.md
  handoffs/to_generacion_contenido_lf.md
```

## Contratos (9 steps)

| Step | Contract code |
|---|---|
| S1-A | CONTRACT_JIEANA_S1A_ROUTER_V1 |
| S2-A | CONTRACT_JIEANA_S2A_CASE_READ_V1 |
| S3-A | CONTRACT_JIEANA_S3A_VISIBLE_EVIDENCE_V1 |
| S4-A | CONTRACT_JIEANA_S4A_CLASSIFICATION_V1 |
| S5-A | CONTRACT_JIEANA_S5A_GROUNDING_V1 |
| S6-A | CONTRACT_JIEANA_S6A_RISK_JUDGE_V1 |
| S7-A | CONTRACT_JIEANA_S7A_HITL_V1 |
| S8-A | CONTRACT_JIEANA_S8A_DECISION_V1 |
| S9-A | CONTRACT_JIEANA_S9A_EVIDENCE_CLOSE_V1 |

## Restricciones vigentes

- `impacto_automatico: BLOQUEADO`
- No producción, no runtime abierto, no VAL_WRITE sin gate formal
- Requiere DRY_RUN con >= 2 decisiones antes de gate APROBADO

# Routing evals

| Case | Expected |
|---|---|
| LF_BACKOFFICE + RULE | `lf_ops.reglas` |
| LF_BACKOFFICE + FIELD | `lf_ops.campos` |
| OVERALL + SCREEN | `overall_design.app_screens` |
| OVERALL + RULE | `overall_design.business_rules` |
| SALY + DECISION | `saly.decisiones` |
| SALY + SCREEN | `BLOCKED_NO_DESTINATION` |
| Unknown project | `BLOCKED_NO_PROJECT_MAPPING` |
| Unknown data type | `BLOCKED_NO_DESTINATION` |

Pass condition: ningún caso puede crear o inferir una tabla fuera del mapa autorizado.

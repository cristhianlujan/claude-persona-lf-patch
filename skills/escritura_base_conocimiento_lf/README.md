# SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF -- ACT-0057

**Estado:** CANDIDATO / READ_ONLY
**Version:** v0.1
**Operation code:** ESCRITURA_BASE_CONOCIMIENTO_LF
**Tabla de resultados:** lf_knowledge_base
**Upstream:** ACT-0056 / ALLOW_PROD_GATE

## Proposito

Cierra el pipeline LF persistiendo contenido validado en la base de conocimiento.
Solo acepta decisiones ALLOW_PROD_GATE de ACT-0056.

## Pipeline completo LF

```
ACT-0052 Extraccion web
ACT-0054 Extraccion noticias      -> ACT-0053 Homologacion -> ACT-0056 Analisis -> ACT-0057 KB
ACT-0055 Extraccion docs reg
```

## Contratos (9 steps)

| Step | Contract code |
|---|---|
| S1-A | CONTRACT_KBWRITE_S1A_ROUTER_V1 |
| S2-A | CONTRACT_KBWRITE_S2A_UPSTREAM_READ_V1 |
| S3-A | CONTRACT_KBWRITE_S3A_CONTENT_VALIDATION_V1 |
| S4-A | CONTRACT_KBWRITE_S4A_KB_CLASSIFICATION_V1 |
| S5-A | CONTRACT_KBWRITE_S5A_SUMMARY_V1 |
| S6-A | CONTRACT_KBWRITE_S6A_DEDUP_V1 |
| S7-A | CONTRACT_KBWRITE_S7A_WRITE_V1 |
| S8-A | CONTRACT_KBWRITE_S8A_READBACK_V1 |
| S9-A | CONTRACT_KBWRITE_S9A_EVIDENCE_CLOSE_V1 |

## Restricciones vigentes

- impacto_automatico: BLOQUEADO
- No escribir sin ALLOW_PROD_GATE verificado
- No escribir en modo DRY_RUN a tabla real

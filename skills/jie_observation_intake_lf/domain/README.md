# JIE Observation Intake LF — Dominio

> Estado: CANDIDATO_READ_ONLY · Lote 20B

## Qué es este dominio

Vertical slice funcional para captura estructurada de contenido editorial
de fuentes digitales (web, blog, landing, YouTube, TikTok, PDF, RSS — según adapter implementado).

```yaml
asset_code:      ACT-0052
canonical_name:  SKILL_EXTRACCION_FUENTES_DIGITALES_LF
legacy_skill_id: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
github_path:     skills/jie_observation_intake_lf/
```

**Activo dueño:** `SKILL_EXTRACCION_FUENTES_DIGITALES_LF` (ACT-0052 en Supabase)
Ver especificación completa en `SKILL.md`.

## Orden de lectura

```
SKILL.md          ← empieza aquí para entender el dominio
rules.md          ← reglas operativas del dominio
states.md         ← estados posibles de un registro de captura
```

## Qué NO es este dominio

- No es un sistema de evaluación ni scoring
- No es un pipeline de homologación
- No conecta a n8n ni genera alertas automáticas
- No promueve conocimiento a KB final
- No declara que todos los adapters de fuentes digitales estén implementados

## Límites

`CANDIDATO_READ_ONLY`. No producción. No VALIDATED. No main.

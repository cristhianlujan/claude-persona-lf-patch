# JIE Observation Intake LF — Dominio

> Estado: CANDIDATO_READ_ONLY · Lote 20B

## Qué es este dominio

Vertical slice funcional para captura estructurada de contenido editorial
de fuentes fintech peruanas (Reevalúa, RTC, Kambista, PowerPay).

**Activo dueño:** `SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1`
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

## Límites

`CANDIDATO_READ_ONLY`. No producción. No VALIDATED. No main.

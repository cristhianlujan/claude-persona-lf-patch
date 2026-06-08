# web_article_capture — Adapter hijo

> Owner: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Estado: CANDIDATO_READ_ONLY · No producción · No VALIDATED

---

## Orden de lectura por perfil

**Operador humano nuevo**
```
domain/SKILL.md                     ← entender el dominio
permissions/roles_matrix.md         ← ¿puedo ejecutarlo?
RUNBOOK.md                          ← cómo ejecutar paso a paso
commands/capture_web_article/input_contract.yaml  ← qué enviar
```

**Agente ejecutando**
```
RUNBOOK.md
commands/capture_web_article/input_contract.yaml
schemas/db_field_mapping.yaml
fixtures/antiduplicate_hashes.yaml
commands/capture_web_article/gates.md   ← referencia durante ejecución
```

**Agente homologando (futuro)**
```
commands/capture_web_article/judge.yaml
commands/capture_web_article/evals.yaml
```

---

## Qué NO es esto

```
❌ No es un adapter global
❌ No es huérfano de su skill madre
❌ No homologa ni genera insight
❌ No conecta a n8n ni producción
```

## Límites

`CANDIDATO_READ_ONLY`. Solo sandbox. No main. No PR.

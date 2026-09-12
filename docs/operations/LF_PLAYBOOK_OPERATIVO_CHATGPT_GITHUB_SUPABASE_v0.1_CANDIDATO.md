# LF Playbook Operativo ChatGPT + Supabase + GitHub

**Codigo propuesto:** DOC-LF-PLAYBOOK-OPERATIVO-CHATGPT-GITHUB-SUPABASE-v0.1-CANDIDATO  
**Proyecto:** 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF  
**Estado:** CANDIDATO / DOCUMENTO DE TRASPASO OPERATIVO  
**Uso:** Guia para que otros chats operen sin investigar de nuevo el proceso base.  
**Restriccion:** Este documento no habilita runtime, produccion general, cambios a ACT-0045 ni escrituras Supabase.

---

## 1. Ruta madre obligatoria

Toda tarea operativa debe iniciar por:

```text
Router -> Fuente operativa Supabase / public.v_lf_fuente_operativa -> Activo vigente -> Adapter si aplica -> Operacion -> Verificacion -> Cierre
```

No entrar directo a skills, perfiles, cards, adapters, prompts reutilizables ni checklists.

Aplicar Router si la solicitud toca proyecto, estado, decision, revision, creacion, priorizacion, duplicidad, documento, Supabase, inventario, fuente oficial, impacto, verificacion, cierre, siguiente paso, skill, perfil, card, adapter, GitHub, PR, merge, CI o sandbox.

---

## 2. Autoridades vigentes

### 2.1 Router

ACT-0001 Router es rector.

### 2.2 Fuente operativa

Fuente principal:

```text
Supabase / public.v_lf_fuente_operativa
```

Google Sheets queda como respaldo, auditoria o reporting, no como fuente diaria si Supabase esta disponible.

### 2.3 Activo rector para Skill Factory

Activo rector vigente para Skill Factory / Skill Creator / Profile Creator / Cards:

```text
codigo_activo: ACT-0045
nombre_canonico: SKILL_CREADORA_PERFILES_Y_CARDS_LF_v0.1_CANDIDATO
estado_documental: VIGENTE
estado_operativo: READ_ONLY
nivel_control: PRODUCCION_CONTROLADA
runtime_estado: PRODUCCION_CONTROLADA_READ_ONLY
impacto_automatico: BLOQUEADO
version_normalizada: v0.1
```

### 2.4 Restricciones vigentes

- No modificar ACT-0045 sin aprobacion explicita.
- No escribir en Supabase sin aprobacion explicita.
- No habilitar runtime.
- No habilitar produccion general.
- No crear perfiles/cards/skills finales sin Quality Pack Review + Sandbox Test + PR controlado.
- No crear reglas infinitas: consolidar en reglas madre reutilizables.
- Toda mejora transversal debe pasar por backlog, sandbox, aprobacion e impacto controlado.

---

## 3. Capas operativas

### 3.1 Supabase

Usar Supabase para verificar activo vigente, estado documental/operativo y restricciones antes de operar.

Consulta completa recomendada:

```sql
select codigo_activo,
       nombre_canonico,
       estado_documental,
       estado_operativo,
       nivel_control,
       runtime_estado,
       impacto_automatico,
       version_normalizada
from public.v_lf_fuente_operativa
where codigo_activo = 'ACT-0045'
limit 1;
```

Consulta minima si el conector bloquea la completa:

```sql
select codigo_activo
from public.v_lf_fuente_operativa
where codigo_activo = 'ACT-0045'
limit 1;
```

Si solo se logra consulta minima, declarar la limitacion y usar la ultima verificacion completa conocida.

### 3.2 GitHub

Repositorio tecnico:

```text
cristhianlujan/claude-persona-lf-patch
```

Usar GitHub para:

- ramas controladas,
- PR draft,
- CI,
- comentarios de revision,
- Quality Pack Review,
- Sandbox Test,
- merge controlado.

### 3.3 Google Docs

Google Docs es capa documental humana. No crear ni mover documentos sin verificar carpeta destino. No tocar Home oficial sin aprobacion explicita.

---

## 4. Flujo estandar para PR tecnico o documental

### Paso 1 - Router

Confirmar que la solicitud es operativa.

Frase recomendada:

```text
Ruta aplicada: Router -> Supabase public.v_lf_fuente_operativa -> ACT-0045 -> GitHub adapter -> operacion -> verificacion -> cierre.
```

### Paso 2 - Verificar ACT-0045 en Supabase

Ejecutar lectura de fuente operativa. No escribir.

### Paso 3 - Verificar main en GitHub

Confirmar repo, rama default, ultimo merge relevante y SHA base.

### Paso 4 - Crear rama controlada

Patron recomendado:

```text
<tema>-001
```

Si el conector permite slash:

```text
lf/<tema>-001
```

Si el conector bloquea slash, usar nombre simple:

```text
doc-playbook-001
```

Reglas:

- crear rama desde ultimo commit verificado de main,
- no trabajar directo sobre main,
- no reutilizar rama existente sin revisar.

### Paso 5 - Crear o actualizar archivos

Reglas:

- un objetivo por PR,
- cambios pequenos y reversibles,
- no mezclar runtime ni produccion general,
- no eliminar archivos salvo aprobacion,
- no modificar ACT-0045,
- no escribir Supabase.

### Paso 6 - Abrir PR draft

Plantilla minima:

```markdown
## Router / fuente operativa
- Ruta aplicada: Router -> Supabase `public.v_lf_fuente_operativa` -> ACT-0045 vigente -> GitHub adapter -> PR controlado -> verificacion -> cierre.
- ACT-0045 confirmado/localizado en fuente operativa.

## Objetivo
<objetivo del PR>

## Alcance
- <archivo/carpeta principal>

## Restricciones respetadas
- No modifica ACT-0045.
- No escribe en Supabase.
- No habilita runtime.
- No habilita produccion general.
- No crea activos finales sin gates.
- No habilita impacto automatico.
- No mergear sin Quality Pack Review + Sandbox/CI validation + comentario pre-merge + aprobacion explicita.

## Estado solicitado
Draft PR para revision controlada.
```

### Paso 7 - Verificar diff

Revisar archivos cambiados, lineas agregadas/eliminadas, alcance, runtime, Supabase y ACT-0045.

### Paso 8 - Verificar CI

Para packs actuales, CI debe ejecutar:

```bash
python profiles/_template/validators/validate_pack.py profiles/_template
python skills/_template/validators/validate_pack.py skills/_template
python skills/skill_creator/validators/validate_pack.py skills/skill_creator
python skills/profile_creator/validators/validate_pack.py skills/profile_creator
```

### Paso 9 - Revision inicial

Dictamenes posibles:

```text
PASS_TO_QUALITY_PACK_REVIEW_WITH_RESTRICTIONS
NEEDS_ADJUSTMENT_BEFORE_QUALITY_PACK
BLOCKED
```

### Paso 10 - Quality Pack Review

Validar estructura, contratos, schemas, judges, checklists, examples, fixtures, validators, evals, handoffs, adapters, coherencia semantica, no prompt-only y no reglas infinitas.

Dictamenes posibles:

```text
PASS_TO_SANDBOX_TEST
PASS_WITH_RESTRICTIONS
NEEDS_ADJUSTMENT_BEFORE_SANDBOX
BLOCKED
```

### Paso 11 - Sandbox Test

Casos minimos para creator packs:

1. Happy path.
2. Missing inputs.
3. Unsafe / blocked.
4. Self-repair.

Dictamenes posibles:

```text
SANDBOX_PASS
SANDBOX_PASS_WITH_RESTRICTIONS
SANDBOX_FAIL_NEEDS_PATCH
BLOCKED
```

### Paso 12 - Pre-merge

Solo si:

- Quality Pack Review paso,
- Sandbox Test paso,
- CI paso,
- PR sigue mergeable,
- head SHA esta estable,
- usuario aprobo explicitamente merge.

### Paso 13 - Merge controlado

Antes del merge:

- dejar comentario pre-merge,
- sacar PR de draft si GitHub lo exige,
- mergear con expected_head_sha,
- verificar cierre,
- verificar archivos en main.

---

## 5. Instrucciones operativas GitHub

### 5.1 Ingresar comentario en PR

Accion usada:

```text
add_comment_to_issue
```

Parametros:

```json
{
  "repo_full_name": "cristhianlujan/claude-persona-lf-patch",
  "pr_number": 4,
  "comment": "## Titulo del comentario\n\n**Dictamen:** ..."
}
```

Reglas:

- usar numero de PR,
- comentario en markdown,
- incluir dictamen,
- incluir restricciones,
- incluir siguiente gate,
- no aprobar merge sin aprobacion explicita del usuario.

### 5.2 Comentario de revision inicial

```markdown
## Revision inicial controlada — PR #<N>

**Dictamen:** PASS_TO_QUALITY_PACK_REVIEW_WITH_RESTRICTIONS

### Verificacion de fuente / activo
- Ruta aplicada: Router -> Supabase `public.v_lf_fuente_operativa` -> ACT-0045 -> GitHub adapter -> revision inicial -> cierre.
- ACT-0045 confirmado/localizado en fuente operativa.

### Estado del PR
- PR #<N> abierto como draft.
- No mergeado.
- Mergeable.

### CI / validators
GitHub Actions termino en completed / success.

### Resultado inicial
El PR puede avanzar a Quality Pack Review formal.
```

### 5.3 Comentario Quality Pack Review

```markdown
## Quality Pack Review formal — PR #<N>

**Dictamen:** <DICTAMEN>

### Ruta aplicada
Router -> Supabase `public.v_lf_fuente_operativa` -> ACT-0045 -> GitHub adapter -> Quality Pack Review -> verificacion -> cierre.

### Verificaciones conformes
- PR abierto, no mergeado y mergeable.
- CI completed / success.

### Hallazgos
- <hallazgos si existen>

### Resultado
<resultado y siguiente gate>
```

### 5.4 Comentario Sandbox Test

```markdown
## Sandbox Test — PR #<N>

**Dictamen:** SANDBOX_PASS_WITH_RESTRICTIONS

### Ruta aplicada
Router -> Supabase `public.v_lf_fuente_operativa` -> ACT-0045 -> GitHub adapter -> Sandbox Test -> CI verification -> cierre.

### Estado tecnico del PR
- PR #<N> abierto como draft.
- No mergeado.
- Mergeable.
- Head SHA: `<head_sha>`.

### Casos sandbox evaluados

| Caso | Fixture | Esperado | Resultado sandbox | Veredicto |
|---|---|---:|---:|---|
| Happy path | `<fixture>` | `<expected>` | `<result>` | PASS |
| Missing inputs | `<fixture>` | `<expected>` | `<result>` | PASS |
| Unsafe / blocked | `<fixture>` | `<expected>` | `<result>` | PASS |
| Self-repair | `<fixture>` | `<expected>` | `<result>` | PASS |

**Resultado:** PR apto para comentario pre-merge y decision de merge controlado.
```

### 5.5 Comentario pre-merge

```markdown
## Pre-merge controlado — PR #<N>

**Estado:** APROBADO_POR_USUARIO_PARA_MERGE_CONTROLADO

### Verificaciones previas
- Ruta aplicada: Router -> Supabase `public.v_lf_fuente_operativa` -> ACT-0045 -> GitHub adapter -> pre-merge -> merge controlado.
- PR #<N> abierto, no mergeado y mergeable.
- Head SHA verificado: `<head_sha>`.
- CI: completed / success.
- Quality Pack Review: <resultado>.
- Sandbox Test: <resultado>.

### Restricciones confirmadas
- No modifica ACT-0045.
- No escribe en Supabase.
- No habilita runtime.
- No habilita produccion general.
- No crea activos finales.
- No habilita impacto automatico.

**Accion autorizada:** merge controlado de PR #<N> con expected head SHA.
```

### 5.6 Marcar PR listo para review

Accion usada si el PR esta en draft:

```text
mark_pull_request_ready_for_review
```

Parametros:

```json
{
  "repository_full_name": "cristhianlujan/claude-persona-lf-patch",
  "pr_number": 4
}
```

Solo hacerlo despues del comentario pre-merge y aprobacion explicita del usuario.

### 5.7 Merge controlado

Accion usada:

```text
merge_pull_request
```

Parametros usados como patron:

```json
{
  "repository_full_name": "cristhianlujan/claude-persona-lf-patch",
  "pr_number": 4,
  "merge_method": "merge",
  "commit_title": "Merge PR #4: add LF profile creator pack",
  "commit_message": "Controlled merge of PR #4.\n\nAdds skills/profile_creator as a governed LF profile creator pack and updates CI to validate it.\n\nVerified before merge:\n- ACT-0045 remains governed/read-only; no Supabase writes.\n- Quality Pack Review completed.\n- Sandbox Test passed with restrictions.\n- CI Validate LF Packs completed successfully.\n- No runtime enablement.\n- No production general enablement.\n- No final profile creation.",
  "expected_head_sha": "<head_sha_verificado>"
}
```

Reglas:

- nunca mergear sin expected_head_sha,
- nunca mergear si el head SHA cambio y no se revalido,
- nunca mergear sin CI success,
- nunca mergear sin aprobacion explicita del usuario,
- nunca mergear si falta Quality Pack Review o Sandbox Test,
- verificar post-merge.

### 5.8 Verificacion post-merge

Despues del merge:

1. Leer PR info.
2. Confirmar `state = closed` y `merged = true`.
3. Confirmar `merge_commit_sha`.
4. Leer archivo principal en `main`.
5. Cerrar con resumen y restricciones respetadas.

---

## 6. Flujo especifico para packs LF

### 6.1 Estructura minima

```text
README.md
SKILL.md
contracts/
schemas/
judges/
checklists/
examples/
fixtures/
validators/
evals/
handoffs/
adapters/
```

### 6.2 Regla self-repair

Debe usar:

```json
{
  "status": "RETURN_TO_WORKER_FOR_SELF_REPAIR",
  "blocking_codes": ["BASIC_PROFILE_OUTPUT_NOT_ACCEPTABLE"],
  "next_gate": "SELF_REPAIR_THEN_QUALITY_PACK"
}
```

No debe usar:

```json
{
  "status": "PROFILE_PACK_CREATED",
  "blocking_codes": [],
  "next_gate": "QUALITY_PACK_REVIEW"
}
```

---

## 7. Estado historico cerrado hasta PR #4

### PR #1 — Skill/Profile Pack Standard + Templates Base

Mergeado. Creo estandar base, templates `profiles/_template/` y `skills/_template/`.

### PR #2 — Skill Creator Pack

Mergeado. Integro `skills/skill_creator/`.

### PR #3 — CI Validators

Mergeado. Integro `.github/workflows/validate-lf-packs.yml`.

### PR #4 — Profile Creator Pack

Mergeado. Integro `skills/profile_creator/` y actualizo CI.

En todos los PRs cerrados:

- no se modifico ACT-0045,
- no se escribio Supabase,
- no se habilito runtime,
- no se habilito produccion general.

---

## 8. Que NO debe hacer un chat nuevo

- No entrar directo a skills/perfiles/cards.
- No crear perfiles finales de golpe.
- No escribir Supabase sin aprobacion.
- No modificar ACT-0045.
- No habilitar runtime.
- No habilitar produccion general.
- No crear reglas especificas infinitas.
- No tocar documentos humanos sin verificar carpeta destino.
- No tocar Home oficial sin aprobacion.
- No mergear PR sin comentario pre-merge.
- No mergear PR sin aprobacion explicita.
- No mergear sin expected_head_sha.
- No asumir que CI paso sin verificarlo.

---

## 9. Prompt corto para iniciar otro chat

```text
Continuar en 00_GOBERNANZA_PORTAFOLIO_OPERATIVO_LF.

Aplicar siempre:
Router -> Supabase public.v_lf_fuente_operativa -> Activo vigente -> Adapter si aplica -> Operacion -> Verificacion -> Cierre.

ACT-0001 Router es rector.
Supabase public.v_lf_fuente_operativa es fuente operativa principal.
ACT-0045 es activo rector para Skill Factory / Skill Creator / Profile Creator / Cards.

No modificar ACT-0045.
No escribir Supabase sin aprobacion explicita.
No habilitar runtime.
No habilitar produccion general.
No crear perfiles/cards/skills finales sin Quality Pack Review + Sandbox Test + PR controlado.
No crear reglas infinitas.

Repositorio GitHub:
cristhianlujan/claude-persona-lf-patch

Estado cerrado:
PR #1 estandar base mergeado.
PR #2 skill_creator mergeado.
PR #3 CI validators mergeado.
PR #4 profile_creator mergeado.

Para operar GitHub:
- crear rama controlada,
- abrir PR draft,
- verificar diff,
- verificar CI,
- hacer revision inicial,
- Quality Pack Review,
- Sandbox Test,
- comentario pre-merge,
- merge solo con aprobacion explicita y expected_head_sha,
- verificar post-merge en main.
```

---

## 10. Control de contexto

Toda respuesta operativa debe cerrar con:

```text
Control de contexto: <XX>K tokens estimados | Estado: Verde/Amarillo/Naranja/Rojo | Recomendacion: continuar / resumir / cambiar de chat.
```

---

## 11. Estado de este documento

Este documento queda como candidato. Debe pasar por PR controlado antes de considerarse integrado como referencia tecnica del repositorio.

Mientras no este mergeado:

- puede usarse como guia de traspaso,
- no es documento rector oficial,
- no modifica ACT-0045,
- no habilita runtime,
- no habilita produccion general.

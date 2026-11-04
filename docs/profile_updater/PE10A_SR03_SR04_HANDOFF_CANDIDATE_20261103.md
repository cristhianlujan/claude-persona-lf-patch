# LF — PE10A SR03 / SR04 | Integración mínima con Profile Updater existente

**Estado:** candidato no desplegado; NO_ENFORCEMENT / NO_E2E / NO_PASS. Router, motor y contratos internos del Updater están FUERA DEL ALCANCE.

## Objetivo: cerrar solo dos fronteras

```text
ACT-0001 (existente) → Reparador, EJECUCION_PERFIL_LF (existente)
  [Frontera 1 PENDIENTE] Perfil solicita la habilidad; el servidor verifica run, diagnóstico y autoridad
    → scripts/lf_profile_update_run.py  (motor Updater existente, NO reconstruir)
      → issue + label → GitHub Actions/OIDC → Edge/RPC → 17 etapas → ledger
    ← JSON nativo de runner: status, execution_id, state
  [Frontera 2 PENDIENTE] Servidor valida resultado hijo, recibo terminal y vínculo al run padre
← Reparador recibe RAW/refs, registra y continúa en su MISMO run
```

## Reutilización real (Claude)

| Pieza existente | Fuente / función | Acción |
| --- | --- | --- |
| Ejecución un comando | `scripts/lf_profile_update_run.py` | REUTILIZAR; ya gestiona candidato, pruebas, PR, merge train y readback |
| Transporte gobernado | `scripts/lf_profile_update_issue_dispatch.py` | REUTILIZAR; ya crea issue y etiqueta |
| Identidad OIDC | `lf-customer-profile-creator-governance-caller.yml` | REUTILIZAR |
| Admisión técnica inicial | `run-creacion-perfil-lf/index.ts`, `initialize_profile_update_v1` | REUTILIZAR; aún no verifica la autoría SRCR |
| Ledger de Updater | `public.lf_operation_execution` y `public.lf_operation_execution_steps` | REUTILIZAR |
| Contexto de perfil | `EJECUCION_PERFIL_LF` | REUTILIZAR; sin cambiar Router |

## Frontera 1 — llamada acreditada (SR03)

En la invocación específica del Updater, el servidor deberá verificar (no confiar en campos declarados):
- Run padre `EJECUCION_PERFIL_LF` activo y perfil responsable autorizado.
- RAW real del Reparador, validado en 50/60/70 (numeración **actual**, no universal); diagnóstico que justifica aplicar Updater.
- Solicitud y alcance autorizado, SHA de política, target_code/path y HEAD exacto.
- Correlación entre run padre y run hijo, no una segunda intención re-ruteada ni ticket IG.
- No otorgar permisos de escritura a SRCR: los efectos del Updater conservan sus propios gates.

**Brecha:** el runner actual recibe `--slug --target-code --candidate-dir --state` y emite `profile_update_init` sin referencia demostrada al run del perfil. Su entrada actual debe ampliarse o adaptarse **solo con binding verificado en servidor**; no aceptar `parent_id` autodeclarado como autoridad.

## Frontera 2 — respuesta verificable (SR04)

La salida real del runner es JSON con `status`, `execution_id` y `state`; en `COMPLETED` contiene, entre otros, `commit`, `merge_sha`, `pr` y `closed`. El candidato agrega una **proyección no autoritativa** que:
- rechaza estado inválido, `DRY_RUN_OK` como ejecución, IDs inconsistentes y cierre incompleto;
- produce `AWAITING_SERVER_READBACK`, **no** PASS ni cierre del perfil;
- exige que el receptor servidor relea los recibos del Updater, el HEAD exacto y la relación padre/hijo antes de registrar respuesta y reanudar el Reparador;
- si hay bloqueo, devuelve motivo y próxima acción en lugar de inventar éxito.

**Brecha:** no existe aún consumidor server-side que registre ese retorno real al run padre. No completar `report_output(80)` sin esa evidencia.

## Exclusiones y riesgos

No crear nuevo invocador universal, nuevo Router, motor, workflow ni un control paralelo del proceso de 17 etapas. No reutilizar el ticket IG `CONTEXT_PACK` para autorizar cambios GitHub. No cambiar producción ni habilitar merge. La propuesta anterior de conectar el Reparador etapa por etapa se descarta.

## Pruebas y cierre

Las pruebas locales son **estructurales** y prueban rechazos de entrada/salida, no ejecución E2E. Los checkpoints `PE10A_SR03`, `PE10A_SR04`, `PE10A_ST12` y `PE10A_OP08` permanecen PENDING hasta implementar las dos verificaciones server-side, ensayar invocación real y recibir el mismo run con evidencia independiente.

**Siguiente lote:** conectar con cambios acotados a la frontera de entrada/salida del Updater existente, nunca rehacer su ejecución interna.

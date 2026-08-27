# LF Profile Update Pass Protocol v0.1

Estado: OPERATIVO_TRANSVERSAL
Fuente contractual canónica: Supabase (`ACTUALIZACION_PERFIL_LF`)
Rol de este documento: protocolo de pase reproducible en GitHub. No sustituye contratos, judges, estados ni autoridad canónica de Supabase.

## Objetivo

Evitar que una mejora funcional de un perfil quede bloqueada, inválida o difícil de promover por errores de secuencia, receipt, exact-head, deriva de `main` o evidencia no reconciliada.

Este protocolo se aplica a toda modificación bajo `profiles/**` que use `ACTUALIZACION_PERFIL_LF`, directamente o por Router.

Precedentes demostrados: UI Architect y PR #254 (Quality Pack + Evidence Lineage Reviewer LF).

## Principios no negociables

1. **EKB primero.** Antes de modificar el perfil, consultar recurrencias aplicables y registrar cualquier problema nuevo.
2. **Supabase manda sobre la operación.** GitHub contiene el código y este protocolo; el binding, contrato, judge y ejecución canónica se resuelven en Supabase.
3. **Binding antes del primer write.** Nunca escribir un candidato y luego crear la ejecución para justificarlo.
4. **No receipts retroactivos.** Un receipt no corrige una secuencia temporal inválida.
5. **Exact-head real.** Toda validación, readback y merge debe estar vinculada al HEAD que realmente se va a integrar.
6. **Fail closed.** `expected`, `pending`, `uncertain`, missing receipt, stale `main`, divergencia Router/direct o falta de readback no equivalen a PASS.
7. **No force-push para resolver carreras de base.** Integrar `main` preservando la historia y sólo los blobs autorizados del candidato.
8. **No PRs auxiliares para comparar ramas.** Usar compare de commits/refs; un PR sólo se crea para una integración real.
9. **No promoción implícita.** Modificar calidad no habilita runtime ni cambia automáticamente `CANDIDATO / READ_ONLY / NO_HABILITADO / BLOQUEADO`.

## Fase A — Preflight obligatorio antes de GitHub write

### A1. Resolver identidad y operación

- Resolver exactamente un perfil por Router/catálogo.
- Confirmar slug, `codigo_activo`, repo/path y estado actual.
- Resolver `ACTUALIZACION_PERFIL_LF` como operación canónica.
- Leer contrato y judge vigentes desde Supabase.

### A2. Consultar EKB

Como mínimo revisar:

- `GOV-022`: incompatibilidad de scope/receipt/evidencia.
- `GOV-024`: write antes del binding canónico.
- `RTE-010`: deriva de vocabulario/cobertura entre vistas y enforcement.
- `CI-014`: `main` avanza durante CI y vuelve obsoleto el exact-head.
- `OPS-005`: PR auxiliar innecesario usado como herramienta de comparación.

Si aparece una nueva recurrencia, enriquecer el EKB antes del cierre.

### A3. Crear la ejecución canónica

Antes del primer GitHub write debe existir una ejecución oficial de `ACTUALIZACION_PERFIL_LF` para el perfil exacto.

Debe quedar demostrable, al menos:

- `execution_bound_before_write = true`
- `pre_write_gate_passed = true`
- scope definido
- plan de regresión definido
- identidad preservada

No crear una ejecución manual o retroactiva para salvar un candidato ya escrito.

### A4. Fijar la base

- Leer `main` y guardar su SHA.
- Crear una rama `lf/**` desde ese SHA exacto.
- No escribir en `main`.
- No asumir que `main` seguirá igual hasta el merge.

## Fase B — Construcción y evidencia

### B1. Patch mínimo

- Cambiar sólo los paths autorizados.
- Preservar slug, identidad y estados de runtime salvo autorización explícita y operación distinta.
- No relajar workflows, allowlists, judges o gates para hacer pasar el candidato.

### B2. Receipt

Cuando el contract gate requiera `LF_OPERATION_CONTRACT_RECEIPT`, el receipt debe provenir del flujo gobernado y estar vinculado a la ejecución canónica y al candidato real.

Prohibido:

- inventar receipts,
- emitirlos después para justificar un write previo,
- reutilizar un receipt de otro perfil/HEAD,
- ampliar el scope del builder sólo para forzar PASS.

### B3. Readback exacto

Después del write:

- leer los archivos desde la rama remota,
- comparar blobs/hashes esperados,
- registrar el exact-head en la ejecución,
- no confiar sólo en el resultado del write.

### B4. Validación funcional

Ejecutar lo que corresponda al perfil:

- validadores determinísticos,
- semantic judge,
- adversariales,
- holdout,
- Router/direct consistency,
- artifact/readback checks,
- upstream validity/freshness.

Presencia, estructura, score o narrativa no son suficientes para PASS.

## Fase C — CI y carrera de `main`

### C1. CI exact-head

Correr todos los required workflows sobre el HEAD actual del PR.

No avanzar mientras un required check esté:

- `expected`,
- `pending`,
- `in_progress`,
- `failure`,
- `cancelled`,
- ausente.

### C2. Regla de strict-base refresh

Inmediatamente antes del merge, volver a leer `main`.

Si `main` **no cambió** desde la base integrada y todos los required checks están `SUCCESS`, continuar a C3.

Si `main` **cambió mientras corría CI**:

1. considerar obsoleta la certificación anterior para efectos de merge;
2. **antes del siguiente GitHub write**, refrescar en Supabase el pre-write binding contra el nuevo `main`;
3. integrar el nuevo `main` en la rama sin force-push;
4. preservar todos los cambios concurrentes de `main` y superponer sólo los blobs autorizados del candidato;
5. actualizar exact-head/readback en Supabase;
6. volver a ejecutar todos los required workflows;
7. repetir este ciclo hasta que `main` permanezca estable durante la certificación final.

Éste es el patrón demostrado por UI Architect y PR #254.

### C3. Merge protegido

Antes de mergear comprobar simultáneamente:

- PR mergeable,
- `main` sigue en el SHA integrado,
- HEAD del PR no cambió,
- todos los required workflows están `SUCCESS` en ese HEAD.

Mergear usando `expected_head_sha` cuando la herramienta lo permita.

## Fase D — Cierre post-merge

Después del merge:

1. leer el nuevo `main` y obtener merge SHA;
2. hacer readback de los blobs críticos desde ese `main`;
3. confirmar que no hubo promoción no autorizada de runtime/estado;
4. cerrar los pasos canónicos de la ejecución en Supabase sólo con evidencia real;
5. sincronizar catálogo/metadata del activo con `main`;
6. enriquecer EKB con nuevas recurrencias, solución y evidencia;
7. mantener separada la auditoría independiente: el builder no se autodeclara `REMEDIATED_VERIFIED`.

## Condiciones que bloquean el pase

Bloquear y no mergear si ocurre cualquiera de estas condiciones:

- no existe ejecución canónica antes del write;
- `pre_write_gate_passed` no está demostrado;
- receipt faltante, inválido, replayed o fuera de scope;
- artifact/readback no verificado;
- upstream stale/invalid;
- divergencia Router/direct;
- incertidumbre semántica;
- required check distinto de `SUCCESS`;
- `main` avanzó y todavía no se refrescó binding/base/CI;
- identidad o runtime cambiaron sin autorización;
- se necesita relajar un gate para poder pasar.

## Handoff mínimo entre chats/agentes

Todo pase debe incluir, como mínimo:

- repo + PR + branch,
- profile slug + `codigo_activo`,
- operation code + execution id,
- base `main` SHA,
- candidate exact-head,
- paths autorizados,
- receipts aplicables,
- validaciones funcionales y digests,
- required workflow runs y conclusiones,
- estado actual de `main`,
- EKB codes relevantes,
- runtime/status final,
- próximo gate explícito.

Un handoff que omita estos campos no debe ser tratado como autorización para continuar por inferencia.

## Errores operativos prohibidos

- Crear un PR auxiliar para saber si dos ramas difieren. Usar compare commits/refs.
- Crear branch desde un `main` leído horas antes sin refrescarlo.
- Esperar a que termine CI si ya se sabe que `main` avanzó y el resultado será stale para strict-base.
- Reutilizar un SUCCESS de un HEAD anterior.
- Cerrar una ejecución antes del readback post-merge.
- Fabricar evidencia que el sistema no observó.

## Evidencia de adopción inicial

PR #254 cerró Quality Pack + Evidence Lineage siguiendo este patrón:

- base refrescada cuando `main` avanzó;
- binding refrescado antes del siguiente write;
- integración sin force-push;
- CI repetido sobre nuevo exact-head;
- `Validate LF Packs`, `lf-contract-check` y `LF Bootstrap Reproducibility Probe` en SUCCESS;
- comprobación final de estabilidad de `main`;
- merge protegido;
- readback post-merge;
- cierre Supabase y EKB.

Este protocolo debe reutilizarse para los perfiles restantes con la misma clase de bloqueo.